using System.Collections.Concurrent;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;

namespace DeviceReadout.Windows;

internal enum WindowsNetworkChangeKind { Interface, Address, Route }
[UnmanagedFunctionPointer(CallingConvention.Winapi)]
internal delegate void WindowsNetworkChangeCallback(nint context, nint row, uint type);
internal interface IWindowsNetworkNotifications
{
    uint Register(WindowsNetworkChangeKind kind, WindowsNetworkChangeCallback callback, nint context, out nint handle);
    uint Unregister(nint handle);
}
internal sealed class WindowsNetworkChanges(IWindowsNetworkNotifications platform) : IDisposable
{
    private Group? owned;
    private bool closed;
    internal IDisposable Subscribe(Action changed, Action<Exception> fail)
    {
        if (closed || owned is not null) throw new DeviceReadoutException(ErrorCode.ReadFailed, "Network notifications already have an owner.");
        var group = owned = new Group();
        try {
            foreach (var kind in Enum.GetValues<WindowsNetworkChangeKind>()) {
                Registration.Create(platform, kind, changed, fail, group.Registrations);
            }
            return group;
        } catch {
            try {group.Dispose();} catch (Exception) { /* Retain failed handles for the owner's final cleanup. */ }
            throw; // Cleanup failure must not replace the original registration failure.
        }
    }
    public void Dispose() {closed = true;owned?.Dispose();}
    private sealed class Group : IDisposable
    {
        internal readonly List<Registration> Registrations = [];
        public void Dispose()
        {
            Exception? failure = null;
            foreach (var registration in Registrations) registration.Detach();
            foreach (var registration in Registrations.ToArray()) {
                try {registration.Dispose();Registrations.Remove(registration);}
                catch (Exception error) {failure ??= error;}
            }
            if (failure is not null) throw failure;
        }
    }
    private sealed class Registration(IWindowsNetworkNotifications platform, Action changed, Action<Exception> fail) : IDisposable
    {
        private static readonly ConcurrentDictionary<nint, Registration> Active = new();
        private static readonly WindowsNetworkChangeCallback Callback = Dispatch;
        private static long sequence;
        private Action? changed = changed;
        private Action<Exception>? fail = fail;
        private nint id, handle;
        private int closed;
        internal static void Create(IWindowsNetworkNotifications platform, WindowsNetworkChangeKind kind, Action changed, Action<Exception> fail, List<Registration> owned)
        {
            var registration = new Registration(platform, changed, fail) {id = checked((nint)Interlocked.Increment(ref sequence))};
            owned.Add(registration); // Own even an unexpected handle written before a failed return.
            Active.TryAdd(registration.id, registration);
            try {
                var result = platform.Register(kind, Callback, registration.id, out registration.handle);
                if (result == 0 && registration.handle != 0) return;
                registration.Detach();
                if (result == 50 && registration.handle == 0) {owned.Remove(registration);return;}
                throw Failure("Network notification registration", result == 0 ? 6u : result);
            } catch {registration.Detach();throw;}
        }
        private static void Dispatch(nint context, nint row, uint type)
        {
            if (!Active.TryGetValue(context, out var registration) || Volatile.Read(ref registration.closed) != 0) return;
            try {
                if (type == 3) return; // Registration acknowledgement, not a state transition.
                if (type > 2 || row == 0) throw new DeviceReadoutException(ErrorCode.ReadFailed, "Invalid Windows IP notification.");
                // Rows are partial and OS-owned. Do not retain them or treat a protocol-level deletion as adapter removal.
                Volatile.Read(ref registration.changed)?.Invoke();
            } catch (Exception error) {
                try {Volatile.Read(ref registration.fail)?.Invoke(error);} catch (Exception) { /* Never unwind into IP Helper. */ }
            }
        }
        internal void Detach()
        {
            Interlocked.Exchange(ref closed, 1);Active.TryRemove(id, out _);
            Interlocked.Exchange(ref changed, null);Interlocked.Exchange(ref fail, null);
        }
        public void Dispose()
        {
            Detach();var native = handle;if (native == 0) return;
            // Runs on the collection worker without callback locks: this API waits for callbacks to return.
            var result = platform.Unregister(native);if (result != 0) throw Failure("CancelMibChangeNotify2", result);
            handle = 0;
        }
    }
    private static DeviceReadoutException Failure(string api, uint error)
        => new(error == 5 ? ErrorCode.PermissionDenied : ErrorCode.ReadFailed, $"{api} failed (Win32 {error}).");
}

[SupportedOSPlatform("windows")]
internal sealed class WindowsNetworkNotifications : IWindowsNetworkNotifications
{
    public uint Register(WindowsNetworkChangeKind kind, WindowsNetworkChangeCallback callback, nint context, out nint handle)
        => kind switch {
            WindowsNetworkChangeKind.Interface => NotifyIpInterfaceChange(0, callback, context, 1, out handle),
            WindowsNetworkChangeKind.Address => NotifyUnicastIpAddressChange(0, callback, context, 1, out handle),
            WindowsNetworkChangeKind.Route => NotifyRouteChange2(0, callback, context, 1, out handle),
            _ => throw new ArgumentOutOfRangeException(nameof(kind))
        };
    public uint Unregister(nint handle) => CancelMibChangeNotify2(handle);
    [DllImport("iphlpapi.dll")] private static extern uint NotifyIpInterfaceChange(ushort family, WindowsNetworkChangeCallback callback, nint context, byte initial, out nint handle);
    [DllImport("iphlpapi.dll")] private static extern uint NotifyUnicastIpAddressChange(ushort family, WindowsNetworkChangeCallback callback, nint context, byte initial, out nint handle);
    [DllImport("iphlpapi.dll")] private static extern uint NotifyRouteChange2(ushort family, WindowsNetworkChangeCallback callback, nint context, byte initial, out nint handle);
    [DllImport("iphlpapi.dll")] private static extern uint CancelMibChangeNotify2(nint handle);
}
