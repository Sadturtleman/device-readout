namespace DeviceReadout.Windows;

internal sealed record WindowsSensorInfo(string Id, string? Name, TimeSpan? MinimumInterval = null, double? MaximumRange = null);
internal readonly record struct WindowsSensorSample(double? Scalar = null, Vector3? Vector = null, Quaternion? Rotation = null, bool? Detected = null);
internal interface IWindowsSensorPlatform : IDisposable
{
    IReadOnlyList<WindowsSensorInfo> List(EntityKind kind, CancellationToken token);
    WindowsSensorInfo Describe(EntityKind kind, string id, CancellationToken token);
    IDisposable Subscribe(EntityKind kind, string id, SensorSamplingRate rate, Action<WindowsSensorSample> emit, Action<Exception> fail, CancellationToken token);
}

internal sealed class WindowsSensors(IWindowsSensorPlatform platform) : IDisposable
{
    private sealed class Target(string id, WindowsSensorInfo info)
    {
        internal readonly string Id = id;
        internal WindowsSensorInfo Info = info;
        internal bool Removed;
        internal readonly HashSet<Action<Exception>> Failures = [];
    }
    private readonly object gate = new();
    private readonly Dictionary<EntityKind, ResourceCatalog> catalogs = [];
    private readonly Dictionary<(EntityKind Kind, string Handle), Target> targets = [];
    internal static bool Supports(EntityKind kind) => kind is EntityKind.Illuminance or EntityKind.Pressure or EntityKind.Gyroscope or EntityKind.Magnetometer
        or EntityKind.Accelerometer or EntityKind.LinearAcceleration or EntityKind.Gravity or EntityKind.AbsoluteOrientation or EntityKind.RelativeOrientation
        or EntityKind.ProximityNear or EntityKind.ProximityDistance or EntityKind.HingeAngle or EntityKind.HumanPresence or EntityKind.RelativeAltitude;
    internal IReadOnlyList<string> List(EntityKind kind, CancellationToken token)
    {
        var found = platform.List(kind, token);token.ThrowIfCancellationRequested();
        if (found.Count > 4096 || found.Any(item => string.IsNullOrEmpty(item.Id)) || found.Select(item => item.Id).Distinct(StringComparer.OrdinalIgnoreCase).Count() != found.Count)
            throw new DeviceReadoutException(ErrorCode.ReadFailed, "Malformed native sensor inventory.");
        List<Action<Exception>> removed = [];IReadOnlyList<string> handles;
        lock (gate) {
            if (!catalogs.TryGetValue(kind, out var catalog)) catalogs[kind] = catalog = new();
            handles = catalog.Update(found.Select(item => item.Id));
            foreach (var pair in targets.Where(item => item.Key.Kind == kind && !handles.Contains(item.Key.Handle))) {
                if (pair.Value.Removed) continue;pair.Value.Removed = true;removed.AddRange(pair.Value.Failures);
            }
            foreach (var item in found) {
                var handle = catalog.Find(item.Id)!;
                if (targets.TryGetValue((kind, handle), out var target)) target.Info = item;
                else targets[(kind, handle)] = new(item.Id, item);
            }
        }
        foreach (var fail in removed) fail(new DeviceReadoutException(ErrorCode.EntityRemoved, "Native sensor was removed."));
        return handles;
    }
    private Target Resolve(EntityAddress address)
    {
        lock (gate) return address.TargetId is { } handle && targets.TryGetValue((address.Kind, handle), out var target) && !target.Removed
            ? target : throw new DeviceReadoutException(ErrorCode.EntityRemoved, "Native sensor target is unavailable.");
    }
    internal SensorDescription Describe(EntityAddress address, CancellationToken token)
    {
        var target = Resolve(address);
        try {
            var info = platform.Describe(address.Kind, target.Id, token);token.ThrowIfCancellationRequested();_ = Resolve(address);
            return new() {Kind = address.Kind switch {EntityKind.Illuminance => SensorKind.Illuminance, EntityKind.Pressure => SensorKind.Pressure,
                    EntityKind.Gyroscope => SensorKind.Gyroscope, EntityKind.Magnetometer => SensorKind.Magnetometer,
                    EntityKind.Accelerometer => SensorKind.Accelerometer, EntityKind.LinearAcceleration => SensorKind.LinearAcceleration,
                    EntityKind.Gravity => SensorKind.Gravity, EntityKind.AbsoluteOrientation => SensorKind.AbsoluteOrientation,
                    EntityKind.RelativeOrientation => SensorKind.RelativeOrientation, EntityKind.ProximityNear => SensorKind.ProximityNear,
                    EntityKind.ProximityDistance => SensorKind.ProximityDistance, EntityKind.HingeAngle => SensorKind.HingeAngle,
                    EntityKind.HumanPresence => SensorKind.HumanPresence, EntityKind.RelativeAltitude => SensorKind.RelativeAltitude, _ => null},
                Name = info.Name ?? target.Info.Name, MinimumInterval = info.MinimumInterval, MaximumRange = info.MaximumRange};
        } catch (DeviceReadoutException error) when (error.Code == ErrorCode.EntityRemoved) {Retire(address, error);throw;}
    }
    private void Retire(EntityAddress address, DeviceReadoutException error)
    {
        Action<Exception>[] failed;
        lock (gate) {
            if (address.TargetId is not { } handle || !targets.TryGetValue((address.Kind, handle), out var target) || target.Removed) return;
            target.Removed = true;catalogs[address.Kind].Retire(handle);failed = target.Failures.ToArray();
        }
        foreach (var fail in failed) fail(error);
    }
    internal EntityCapabilities Capabilities(EntityAddress address, CancellationToken token)
    {
        if (address.TargetId is null) {var available = List(address.Kind, token).Count > 0;return new(available, available);}
        _ = Resolve(address);return new(true, true);
    }
    internal ICollectorSubscription Observe(EntityAddress address, SensorSamplingRate rate, Action<DeviceSnapshot> emit, Action<Exception> fail, CancellationToken token)
    {
        var target = Resolve(address);var stopped = 0;
        void Notify(Exception error) {if (Volatile.Read(ref stopped) == 0) fail(error);}
        void Failure(Exception error) {
            if (error is DeviceReadoutException {Code: ErrorCode.EntityRemoved} removed) Retire(address, removed);
            else Notify(error);
        }
        lock (gate) {if (target.Removed) throw new DeviceReadoutException(ErrorCode.EntityRemoved, "Native sensor was removed.");target.Failures.Add(Notify);}
        try {
            var subscription = platform.Subscribe(address.Kind, target.Id, rate, raw => {
                lock (gate) if (target.Removed || Volatile.Read(ref stopped) != 0) return;
                emit(address.Kind switch {
                    EntityKind.Illuminance => new IlluminanceSnapshot {Value = raw.Scalar},
                    EntityKind.Pressure => new PressureSnapshot {Value = raw.Scalar * 100},
                    EntityKind.Gyroscope => new GyroscopeSnapshot {Value = raw.Vector is { } v ? new Vector3(v.X * Math.PI / 180, v.Y * Math.PI / 180, v.Z * Math.PI / 180) : null},
                    EntityKind.Magnetometer => new MagnetometerSnapshot {Value = raw.Vector},
                    EntityKind.Accelerometer => new AccelerometerSnapshot {Value = Acceleration(raw.Vector)},
                    EntityKind.LinearAcceleration => new LinearAccelerationSnapshot {Value = Acceleration(raw.Vector)},
                    EntityKind.Gravity => new GravitySnapshot {Value = Acceleration(raw.Vector)},
                    EntityKind.AbsoluteOrientation => new AbsoluteOrientationSnapshot {Value = Rotation(raw.Rotation)},
                    EntityKind.RelativeOrientation => new RelativeOrientationSnapshot {Value = Rotation(raw.Rotation)},
                    EntityKind.ProximityNear => new ProximityNearSnapshot {Value = raw.Detected},
                    EntityKind.ProximityDistance => new ProximityDistanceSnapshot {Value = raw.Scalar / 1000},
                    EntityKind.HingeAngle => new HingeAngleSnapshot {Value = raw.Scalar * Math.PI / 180},
                    EntityKind.HumanPresence => new HumanPresenceSnapshot {Value = raw.Detected},
                    EntityKind.RelativeAltitude => new RelativeAltitudeSnapshot {Value = raw.Scalar},
                    _ => throw new DeviceReadoutException(ErrorCode.UnsupportedEntity, "Windows sensor mapping is unavailable.")
                });
            }, Failure, token);
            return new Subscription(() => {
                Interlocked.Exchange(ref stopped, 1);lock (gate) target.Failures.Remove(Notify);subscription.Dispose();
            });
        } catch (Exception error) {
            Interlocked.Exchange(ref stopped, 1);lock (gate) target.Failures.Remove(Notify);
            if (error is DeviceReadoutException {Code: ErrorCode.EntityRemoved} removed) Retire(address, removed);
            throw;
        }
    }
    // WinRT G-force points with gravity; common acceleration follows the Android/Generic Sensor sign.
    private static Vector3? Acceleration(Vector3? value)
        => value is { } v ? new(v.X * -9.80665, v.Y * -9.80665, v.Z * -9.80665) : null;
    // WinRT uses the same right-handed device-to-reference direction; preserve named components.
    private static Quaternion? Rotation(Quaternion? value)
    {
        if (value is not { } q) return null;
        var length = Math.Sqrt(q.X * q.X + q.Y * q.Y + q.Z * q.Z + q.W * q.W);
        return double.IsFinite(length) && length > 0 ? new(q.X / length, q.Y / length, q.Z / length, q.W / length) : null;
    }
    private sealed class Subscription(Action dispose) : ICollectorSubscription
    {
        private Action? cleanup = dispose;
        public bool PollingRequired => false;
        public void Dispose() => Interlocked.Exchange(ref cleanup, null)?.Invoke();
    }
    public void Dispose() => platform.Dispose();
}
