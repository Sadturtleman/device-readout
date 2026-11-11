using System.Runtime.InteropServices;

namespace DeviceReadout.Windows;

[UnmanagedFunctionPointer(CallingConvention.StdCall)]
internal delegate int WinRtNoArguments(nint self);
[UnmanagedFunctionPointer(CallingConvention.StdCall)]
internal delegate int WinRtCellularEventInvoke(nint self, nint sender, nint args);

internal sealed class WindowsCellularWatcher(IWindowsConnectivityRuntime runtime)
{
    private sealed class Listener(Action<WindowsCellularAccountChange> changed, Action<Exception> fail)
    {
        private Action<WindowsCellularAccountChange>? changed = changed;
        private Action<Exception>? fail = fail;
        internal void Change(WindowsCellularAccountChange value) {try {Volatile.Read(ref changed)?.Invoke(value);} catch (Exception error) {Fail(error);}}
        internal void Fail(Exception error) {try {Volatile.Read(ref fail)?.Invoke(error);} catch (Exception) { /* Do not unwind into WinRT. */ }}
        internal void Stop() {Interlocked.Exchange(ref changed, null);Interlocked.Exchange(ref fail, null);}
    }
    private sealed class Lease(Action release) : IDisposable
    {
        private Action? release = release;
        public void Dispose() => Interlocked.Exchange(ref release, null)?.Invoke();
    }
    // Native calls use controlGate; callbacks never acquire it or execute under eventsGate.
    private readonly object controlGate = new(), eventsGate = new();
    private readonly HashSet<Listener> listeners = [];
    private readonly List<(int RemoveSlot, long Token, WindowsCellularEventHandler Handler)> registrations = [];
    private nint watcher;
    private long sourceEpoch;
    private bool started, unavailable;
    private Exception? sourceFailure, cleanupFailure;
    internal IDisposable? Subscribe(Action<WindowsCellularAccountChange> changed, Action<Exception> fail)
    {
        lock (controlGate) {
            if (cleanupFailure is { } cleanupError) throw cleanupError;
            if (unavailable) return null;
            var listener = new Listener(changed, fail);
            if (watcher != 0) {
                lock (eventsGate) {
                    if (sourceFailure is { } sourceError) throw sourceError;
                    listeners.Add(listener);
                }
                return new Lease(() => Remove(listener));
            }
            watcher = runtime.CreateCellularWatcher();
            if (watcher == 0) {unavailable = true;return null;}
            long epoch;
            lock (eventsGate) {epoch = checked(++sourceEpoch);sourceFailure = null;listeners.Add(listener);}
            try {
                Register(6, new("423cc41e-fe8c-5a7d-9fee-aae04ef85700"), args => Account(args, WindowsCellularAccountChangeKind.Added, epoch), epoch);
                Register(8, new("0e865096-1ffa-5792-8d4f-8623e3c77f56"), args => Account(args, WindowsCellularAccountChangeKind.Updated, epoch), epoch);
                Register(10, new("423cc41e-fe8c-5a7d-9fee-aae04ef85700"), args => Account(args, WindowsCellularAccountChangeKind.Removed, epoch), epoch);
                Register(12, new("e4dc9cfc-f462-5afd-856d-04ace229d00e"), _ => { }, epoch);
                Register(14, new("e4dc9cfc-f462-5afd-856d-04ace229d00e"), _ => Failed(new DeviceReadoutException(ErrorCode.ReadFailed, "Cellular account observation stopped; continuity was lost."), epoch), epoch);
                started = true;Check(Method<WinRtNoArguments>(watcher, 17)(watcher), "AccountWatcher.Start", supportsFallback: true);
                lock (eventsGate) if (sourceFailure is { } error) throw error;
                return new Lease(() => Remove(listener));
            } catch (Exception error) {
                listener.Stop();lock (eventsGate) listeners.Remove(listener);
                try {CloseSource();} catch (Exception releaseError) {cleanupFailure = releaseError;}
                if (error is DeviceReadoutException {Code: ErrorCode.UnsupportedEntity} && cleanupFailure is null) {unavailable = true;return null;}
                throw;
            }
        }
    }
    private void Register(int slot, Guid iid, Action<nint> invoke, long epoch)
    {
        var handler = new WindowsCellularEventHandler(iid, invoke, error => Failed(error, epoch));
        try {
            Check(Method<WinRtAddReportEvent>(watcher, slot)(watcher, handler.Pointer, out var token), "AccountWatcher.add event", supportsFallback: true);
            registrations.Add((slot + 1, token, handler));
        } catch {handler.ReleaseOwner();throw;}
    }
    private void Account(nint args, WindowsCellularAccountChangeKind kind, long epoch)
    {
        if (args == 0) throw new DeviceReadoutException(ErrorCode.ReadFailed, "Missing cellular account event.");
        nint text = 0;
        try {
            // This is the supplied event payload, not a follow-up account/device query.
            Check(Method<WinRtGetInterface>(args, 6)(args, out text), "AccountEvent.NetworkAccountId");
            var raw = WindowsGetStringRawBuffer(text, out var length);
            if (length == 0 || length > 65536 || raw == 0) throw new DeviceReadoutException(ErrorCode.ReadFailed, "Invalid cellular account event identity.");
            var change = new WindowsCellularAccountChange(Marshal.PtrToStringUni(raw, (int)length)!, kind);
            Listener[] current;lock (eventsGate) {if (epoch != sourceEpoch || sourceFailure is not null) return;current = listeners.ToArray();}
            foreach (var listener in current) listener.Change(change);
        } finally {if (text != 0) WindowsDeleteString(text);}
    }
    private void Failed(Exception error, long epoch)
    {
        Listener[] current;lock (eventsGate) {if (epoch != sourceEpoch) return;sourceFailure ??= error;current = listeners.ToArray();}
        foreach (var listener in current) listener.Fail(error);
    }
    private void Remove(Listener listener)
    {
        lock (controlGate) {
            listener.Stop();lock (eventsGate) {listeners.Remove(listener);if (listeners.Count != 0) return;}
            try {CloseSource();} catch (Exception error) {cleanupFailure = error;throw;}
        }
    }
    private void CloseSource()
    {
        lock (eventsGate) {sourceEpoch = checked(sourceEpoch + 1);}
        foreach (var item in registrations) item.Handler.Stop();
        Exception? failure = null;
        if (started) {
            var needsStop = true;
            try {
                Check(Method<WinRtGetInt32>(watcher, 16)(watcher, out var status), "AccountWatcher.Status");
                needsStop = status switch {0 or 3 or 4 => false, 1 or 2 => true,
                    _ => throw new DeviceReadoutException(ErrorCode.ReadFailed, "Unknown cellular watcher cleanup state.")};
            } catch (Exception error) {failure = error;}
            if (needsStop) try {Check(Method<WinRtNoArguments>(watcher, 18)(watcher), "AccountWatcher.Stop");} catch (Exception error) {failure ??= error;}
        }
        started = false;
        foreach (var item in registrations.AsEnumerable().Reverse()) {
            try {Check(Method<WinRtRemoveReportEvent>(watcher, item.RemoveSlot)(watcher, item.Token), "AccountWatcher.remove event");}
            catch (Exception error) {failure ??= error;}
            finally {item.Handler.ReleaseOwner();}
        }
        registrations.Clear();
        try {if (watcher != 0) runtime.Release(watcher);} catch (Exception error) {failure ??= error;}
        watcher = 0;lock (eventsGate) sourceFailure = null;
        if (failure is not null) throw failure;
    }
    private static T Method<T>(nint instance, int slot) where T : Delegate
        => Marshal.GetDelegateForFunctionPointer<T>(Marshal.ReadIntPtr(Marshal.ReadIntPtr(instance), slot * nint.Size));
    private static void Check(int result, string operation, bool supportsFallback = false)
    {
        if (result < 0) throw new DeviceReadoutException(result == unchecked((int)0x80070005) ? ErrorCode.PermissionDenied
            : supportsFallback && result == unchecked((int)0x80004001) ? ErrorCode.UnsupportedEntity : ErrorCode.ReadFailed,
            $"{operation} failed (HRESULT 0x{result:X8}).");
    }
    [DllImport("combase.dll")] private static extern nint WindowsGetStringRawBuffer(nint value, out uint length);
    [DllImport("combase.dll")] private static extern int WindowsDeleteString(nint value);
}
