using System.Buffers.Binary;
using System.ComponentModel;

namespace DeviceReadout.Windows;

internal sealed class WindowsBatteries(IWindowsBatteryPlatform platform) : IDisposable
{
    private sealed record Target(string Path, uint Tag, long RemovalVersion);
    private sealed record Listener(Target Target, Action<Exception> Fail);
    private readonly ResourceCatalog catalog = new();
    private Dictionary<string, Target> targets = new(StringComparer.OrdinalIgnoreCase);
    private readonly object gate = new();
    private readonly Dictionary<string, long> removals = new(StringComparer.OrdinalIgnoreCase);
    private readonly HashSet<string> absent = new(StringComparer.OrdinalIgnoreCase);
    private readonly List<Listener> listeners = [];
    private IDisposable? observation;
    private bool observing, closed;
    private Exception? observationFailure;

    private void EnsureObservation()
    {
        lock (gate) AssertHealthy();
        if (observing) return;
        observing = true;
        try {observation = platform.ObserveInterfaces(Changed, ObservationFailed);}
        catch (Exception error) {ObservationFailed(error);throw;}
        lock (gate) AssertHealthy();
    }
    private void AssertHealthy()
    {
        if (closed) throw new DeviceReadoutException(ErrorCode.EntityRemoved, "Battery observation is closed.");
        if (observationFailure is { } error) throw error;
    }
    private long Version(string path) {lock (gate) {AssertHealthy();return removals.GetValueOrDefault(path);}}
    private bool IsAbsent(string path) {lock (gate) {AssertHealthy();return absent.Contains(path);}}
    private void Changed(WindowsDeviceInterfaceChange change)
    {
        Action<Exception>[] failed;
        lock (gate) {
            if (closed) return;
            if (!change.Removed) {absent.Remove(change.Path);return;}
            absent.Add(change.Path);
            removals[change.Path] = checked(removals.GetValueOrDefault(change.Path) + 1);
            failed = listeners.Where(listener => StringComparer.OrdinalIgnoreCase.Equals(listener.Target.Path, change.Path)).Select(listener => listener.Fail).ToArray();
        }
        Notify(failed, new DeviceReadoutException(ErrorCode.EntityRemoved, "The selected battery interface was removed."));
    }
    private void ObservationFailed(Exception error)
    {
        Action<Exception>[] failed;
        lock (gate) {
            if (closed) return;
            observationFailure = error;failed = listeners.Select(listener => listener.Fail).ToArray();
        }
        Notify(failed, error);
    }
    private static void Notify(IEnumerable<Action<Exception>> listeners, Exception error)
    {foreach(var fail in listeners) try {fail(error);} catch (Exception) { /* Do not unwind into a native notification. */ }}
    private void RetireObservedRemovals()
    {
        foreach(var pair in targets) if (Version(pair.Value.Path) != pair.Value.RemovalVersion && catalog.Find(pair.Key) is { } handle) catalog.Retire(handle);
    }
    private void AssertCurrent(string? handle, Target target)
    {
        if (Version(target.Path) != target.RemovalVersion) catalog.Retire(handle!);
        _ = catalog.Resolve(handle);
    }
    internal IDisposable ObserveRemoval(string? handle, Action<Exception> fail)
    {
        EnsureObservation();
        lock (gate) {
            var target = targets[catalog.Resolve(handle)];AssertCurrent(handle, target);
            var listener = new Listener(target, fail);listeners.Add(listener);
            return new RemovalSubscription(() => {lock (gate) listeners.Remove(listener);});
        }
    }
    private sealed class RemovalSubscription(Action release) : IDisposable
    {public void Dispose() => release();}
    internal IDisposable ObserveStatus(string? handle, Action<Func<CancellationToken, DeviceSnapshot>> changed, Action<Exception> fail, CancellationToken token)
    {
        var target = targets[catalog.Resolve(handle)];AssertCurrent(handle, target);
        return new WindowsBatteryStatusObservation(() => platform.OpenStatus(target.Path), target.Tag,
            status => changed(cancellation => Read(handle, cancellation, status)), error => {
                if (error is Win32Exception native) {
                    error = Failure(native);
                    if (Removed(native.NativeErrorCode)) {
                        Action<Exception>[] affected;
                        lock (gate) {
                            if (closed) return;
                            if (removals.GetValueOrDefault(target.Path) == target.RemovalVersion)
                                removals[target.Path] = checked(target.RemovalVersion + 1);
                            affected = listeners.Where(listener => listener.Target.Tag == target.Tag && listener.Target.RemovalVersion == target.RemovalVersion
                                && StringComparer.OrdinalIgnoreCase.Equals(listener.Target.Path, target.Path)).Select(listener => listener.Fail).ToArray();
                        }
                        Notify(affected, error);
                    }
                }
                fail(error);
            }, token);
    }
    public void Dispose()
    {
        lock (gate) {if (closed) return;closed = true;listeners.Clear();}
        observation?.Dispose();observation = null;
    }

    internal IReadOnlyList<string> List(CancellationToken token)
    {
        EnsureObservation();RetireObservedRemovals();
        var found = new Dictionary<string, Target>(StringComparer.OrdinalIgnoreCase);
        try {
            var paths = platform.Enumerate(token).ToHashSet(StringComparer.OrdinalIgnoreCase);
            // A complete interface inventory can prove a removal even if a later pack query fails.
            foreach (var known in targets.Values) if (!paths.Contains(known.Path)) RetirePath(known.Path);
            foreach (var path in paths) {
                token.ThrowIfCancellationRequested();
                if (IsAbsent(path)) continue;
                var version = Version(path);
                try {
                    using var device = platform.Open(path);
                    var response = device.Query(BatteryIoControl.QueryTag, new byte[4], 4, token);
                    if (response.Length != 4) throw new DeviceReadoutException(ErrorCode.ReadFailed, "Invalid battery tag response.");
                    var tag = BinaryPrimitives.ReadUInt32LittleEndian(response);
                    RetirePath(path, tag == 0 ? null : tag);
                    if (Version(path) != version || IsAbsent(path)) {RetirePath(path);continue;}
                    if (tag != 0) found.Add(Key(path, tag, version), new(path, tag, version));
                } catch (Win32Exception error) when (Removed(error.NativeErrorCode)) {RetirePath(path);}
            }
            token.ThrowIfCancellationRequested();
            lock (gate) {
                AssertHealthy();RetireObservedRemovals();
                foreach(var pair in found.ToArray()) if (Version(pair.Value.Path) != pair.Value.RemovalVersion || IsAbsent(pair.Value.Path)) found.Remove(pair.Key);
                var result = catalog.Update(found.Keys);targets = found;return result;
            }
        } catch (Win32Exception error) {throw Failure(error);}
    }

    private void RetirePath(string path, uint? currentTag = null)
    {
        foreach (var pair in targets) {
            if (StringComparer.OrdinalIgnoreCase.Equals(pair.Value.Path, path) && pair.Value.Tag != currentTag && catalog.Find(pair.Key) is { } handle)
                catalog.Retire(handle);
        }
    }

    internal BatterySnapshot Read(string? handle, CancellationToken token, byte[]? capturedStatus = null)
    {
        token.ThrowIfCancellationRequested();
        var target = targets[catalog.Resolve(handle)];
        AssertCurrent(handle, target);
        try {
            using var device = platform.Open(target.Path);
            var tag = Query(device, BatteryIoControl.QueryTag, new byte[4], 4, token);
            if (U32(tag, 0) != target.Tag) {
                catalog.Retire(handle!);
                throw new DeviceReadoutException(ErrorCode.EntityRemoved, "The selected battery generation changed.");
            }
            var errors = new List<Win32Exception>();
            byte[]? Optional(BatteryIoControl control, byte[] input, int size)
            {
                try {return Query(device, control, input, size, token);}
                catch (Win32Exception error) when (!Removed(error.NativeErrorCode)) {errors.Add(error);return null;}
            }
            var info = Optional(BatteryIoControl.QueryInformation, InformationRequest(target.Tag, 0), 36);
            var status = capturedStatus ?? Optional(BatteryIoControl.QueryStatus, StatusRequest(target.Tag), 16);
            var temperature = Optional(BatteryIoControl.QueryInformation, InformationRequest(target.Tag, 2), 4);
            var time = Optional(BatteryIoControl.QueryInformation, InformationRequest(target.Tag, 3), 4);
            if (info is null && status is null && temperature is null && time is null)
                throw Failure(errors.FirstOrDefault(error => error.NativeErrorCode == 5) ?? errors[0]);
            var absoluteUnits = info is not null && (U32(info, 0) & 0x40000000) == 0;
            var remaining = Capacity(U32(status, 4));var full = Capacity(U32(info, 16));
            var level = full > 0 ? remaining / full : null;
            var flags = U32(status, 0);
            var knownState = flags.HasValue && (flags & ~0xfu) == 0 && (flags & 6) != 6;
            bool? charging = knownState ? (flags & 4) != 0 : null;
            var state = !knownState ? (BatteryState?)null : (flags & 4) != 0 ? BatteryState.Charging :
                (flags & 2) != 0 ? BatteryState.Discharging : level == 1 ? BatteryState.Full :
                (flags & 1) != 0 ? BatteryState.NotCharging : BatteryState.Idle;
            int? rawRate = status is null ? null : BinaryPrimitives.ReadInt32LittleEndian(status.AsSpan(12));
            double? rate = absoluteUnits && rawRate != int.MinValue ? rawRate : null;
            var voltage = Capacity(U32(status, 8));
            var chemistry = info is null ? null : System.Text.Encoding.ASCII.GetString(info, 8, 4).TrimEnd('\0');
            AssertCurrent(handle, target);
            return new BatterySnapshot {
                Present = true, Level = level, Charging = charging, State = state, VoltageMillivolts = voltage,
                ChargeRateMilliwatts = rate, CurrentMicroamps = voltage > 0 ? rate / voltage * 1_000_000 : null,
                RemainingEnergyMilliwattHours = absoluteUnits ? remaining : null,
                FullChargeEnergyMilliwattHours = absoluteUnits ? full : null,
                DesignEnergyMilliwattHours = absoluteUnits ? Capacity(U32(info, 12)) : null,
                TemperatureCelsius = U32(temperature, 0) / 10.0 - 273.15,
                TimeToEmpty = Capacity(U32(time, 0)) is { } seconds ? TimeSpan.FromSeconds(seconds) : null,
                Technology = string.IsNullOrEmpty(chemistry) ? null : chemistry,
                CycleCount = U32(info, 32) == 0 ? null : U32(info, 32)
            };
        } catch (Win32Exception error) {
            if (Removed(error.NativeErrorCode)) catalog.Retire(handle!);
            throw Failure(error);
        }
    }

    internal EntityCapabilities Capabilities(string? handle)
    {
        if (handle is null) return new(true, true);
        try {AssertCurrent(handle, targets[catalog.Resolve(handle)]);return new(true, true);}
        catch (DeviceReadoutException) {return new(false, false);}
    }

    private static uint? U32(byte[]? bytes, int offset) => bytes is null ? null : BinaryPrimitives.ReadUInt32LittleEndian(bytes.AsSpan(offset));
    private static double? Capacity(uint? value) => value == uint.MaxValue ? null : value;
    private static byte[] Query(IWindowsBatteryDevice device, BatteryIoControl control, byte[] input, int size, CancellationToken token)
    {
        var output = device.Query(control, input, size, token);
        token.ThrowIfCancellationRequested();
        if (output.Length != size) throw new DeviceReadoutException(ErrorCode.ReadFailed, "Invalid battery response length.");
        return output;
    }
    private static byte[] InformationRequest(uint tag, uint level)
    {
        var input = new byte[12];BinaryPrimitives.WriteUInt32LittleEndian(input, tag);BinaryPrimitives.WriteUInt32LittleEndian(input.AsSpan(4), level);return input;
    }
    private static byte[] StatusRequest(uint tag)
    {
        var input = new byte[20];BinaryPrimitives.WriteUInt32LittleEndian(input, tag);return input;
    }

    private static string Key(string path, uint tag, long version) => path + "\0" + tag.ToString(System.Globalization.CultureInfo.InvariantCulture) + "\0" + version.ToString(System.Globalization.CultureInfo.InvariantCulture);
    private static bool Removed(int code) => code is 2 or 433 or 1167;
    private static DeviceReadoutException Failure(Win32Exception error) => new(
        error.NativeErrorCode == 5 ? ErrorCode.PermissionDenied : Removed(error.NativeErrorCode) ? ErrorCode.EntityRemoved : ErrorCode.ReadFailed,
        $"Windows battery query failed (Win32 {error.NativeErrorCode}).", error);
}
