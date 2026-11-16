using DeviceReadout;
using DeviceReadout.Windows;
using System.Runtime.Versioning;
using System.Threading.Channels;

[SupportedOSPlatform("windows")]
internal static class WindowsSensorTests
{
    internal static IEnumerable<(string Name, Func<Task> Run)> Cases() => [
        ("Windows native sensor discovery is passive and measurements preserve units, targets and sessions", DiscoveryAndSamples),
        ("Windows native sensor selectors and asynchronous inventories use a balanced worker-owned runtime", ActualDiscovery),
        ("Windows native sensor removal errors retire old handles before a device reappears", RemovalError)
    ];

    private static async Task DiscoveryAndSamples()
    {
        var platform = new SensorPlatformFixture();
        using var access = new DeviceAccess(new WindowsCollector(sensorPlatform: platform));
        Check(platform.Calls == 0, "construction is inert");
        var lights = await access.Sensors.List(Entities.Illuminance);
        var pressure = (await access.Sensors.List(Entities.Pressure)).Single();
        Check(lights.Length == 2 && lights[0] != lights[1], "multiple physical sensor handles");
        var metadata = await access.Describe(pressure);
        Check(metadata.Name == "Pressure sensor" && metadata.Kind == SensorKind.Pressure && metadata.MinimumInterval == TimeSpan.FromMilliseconds(20), "native metadata without measurement");
        Check((await access.Capabilities.Get(pressure)).Readable == true && platform.Subscribed == 0, "passive support check");
        var get = access.WithSensorSamplingRate(SensorSamplingRate.AtHertz(90)).Get(pressure);
        var once = await platform.Sessions.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1));
        Check(once.Kind == EntityKind.Pressure && once.Rate == SensorSamplingRate.PlatformDefault, "get requests platform default");
        once.Emit(1013.25);
        Check((await get).Value == 101325, "hPa is converted to Pa");
        await once.Closed.Task.WaitAsync(TimeSpan.FromSeconds(1));
        await using var watch = access.WithSensorSamplingRate(SensorSamplingRate.AtHertz(25)).Watch(lights[1]).GetAsyncEnumerator();
        var first = watch.MoveNextAsync().AsTask();
        var continuous = await platform.Sessions.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1));
        Check(continuous.Id == "light-b" && continuous.Rate.Hertz == 25, "selected native target and configured sampling request");
        continuous.Emit(250);
        Check(await first && watch.Current.Value == 250, "lux retained");
        continuous.Emit(250);
        Check(await watch.MoveNextAsync() && watch.Current.Value == 250, "equal sensor readings retained");
        await watch.DisposeAsync();await continuous.Closed.Task.WaitAsync(TimeSpan.FromSeconds(1));
        Check(platform.Threads.Distinct().Count() == 1, "discovery, metadata, registration and cleanup share the worker");
    }

    private sealed class SensorPlatformFixture : IWindowsSensorPlatform
    {
        internal int Calls, Subscribed;
        internal DeviceReadoutException? SubscribeError;
        internal readonly List<int> Threads = [];
        internal readonly Channel<SensorSession> Sessions = Channel.CreateUnbounded<SensorSession>();
        private void Record() {Calls++;Threads.Add(Environment.CurrentManagedThreadId);}
        public IReadOnlyList<WindowsSensorInfo> List(EntityKind kind, CancellationToken token)
        {
            Record();return kind == EntityKind.Illuminance ? [new("light-a", "Light A"), new("light-b", "Light B")] : [new("pressure", "Pressure sensor")];
        }
        public WindowsSensorInfo Describe(EntityKind kind, string id, CancellationToken token)
        {Record();return new(id, "Pressure sensor", TimeSpan.FromMilliseconds(20));}
        public IDisposable Subscribe(EntityKind kind, string id, SensorSamplingRate rate, Action<WindowsSensorSample> emit, Action<Exception> fail, CancellationToken token)
        {
            Record();if (SubscribeError is { } error) throw error;
            Subscribed++;var session = new SensorSession(kind, id, rate, value => emit(new(Scalar: value)), fail, Record);Sessions.Writer.TryWrite(session);return session;
        }
        public void Dispose() => Record();
    }
    private static async Task RemovalError()
    {
        var platform = new SensorPlatformFixture();
        using var access = new DeviceAccess(new WindowsCollector(sensorPlatform: platform));
        var target = (await access.Sensors.List(Entities.Pressure)).Single();
        platform.SubscribeError = new(ErrorCode.EntityRemoved, "Native sensor disappeared during open.");
        await Removed(() => access.Get(target));platform.SubscribeError = null;
        await Removed(() => access.WithReadTimeout(TimeSpan.FromMilliseconds(80)).Get(target));
        Check(platform.Subscribed == 0, "an old native handle cannot subscribe after read-time removal");
        var replacement = (await access.Sensors.List(Entities.Pressure)).Single();
        Check(replacement != target, "reappearance creates a new generation");
        var read = access.Get(replacement);
        var session = await platform.Sessions.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1));session.Emit(1000);
        Check((await read).Value == 100000, "new generation reads normally");
        await Removed(() => access.Describe(target));
    }
    private static async Task Removed(Func<Task> read)
    {
        try {await read();throw new Exception("Expected EntityRemoved.");}
        catch (DeviceReadoutException error) when (error.Code == ErrorCode.EntityRemoved) { }
    }
    private static async Task ActualDiscovery()
    {
        var runtime = new RuntimeProbe();
        using var access = new DeviceAccess(new WindowsCollector(sensorPlatform: new WindowsSensorPlatform(runtime)));
        Check(runtime.Initializations == 0, "native runtime remains inert before discovery");
        var caller = Environment.CurrentManagedThreadId;
        var light = await access.Sensors.List(Entities.Illuminance);
        var pressure = await access.Sensors.List(Entities.Pressure);
        var gyroscope = await access.Sensors.List(Entities.Gyroscope);
        var magnetometer = await access.Sensors.List(Entities.Magnetometer);
        var acceleration = await access.Sensors.List(Entities.Accelerometer);
        var linear = await access.Sensors.List(Entities.LinearAcceleration);
        var gravity = await access.Sensors.List(Entities.Gravity);
        Check((await access.Sensors.List(Entities.Illuminance)).SequenceEqual(light), "stable actual inventory handles");
        foreach (var item in light) Check((await access.Describe(item)).Kind == SensorKind.Illuminance, "actual light metadata");
        foreach (var item in pressure) Check((await access.Describe(item)).Kind == SensorKind.Pressure, "actual pressure metadata");
        foreach (var item in gyroscope) Check((await access.Describe(item)).Kind == SensorKind.Gyroscope, "actual gyroscope metadata");
        foreach (var item in magnetometer) Check((await access.Describe(item)).Kind == SensorKind.Magnetometer, "actual magnetometer metadata");
        foreach (var item in acceleration) Check((await access.Describe(item)).Kind == SensorKind.Accelerometer, "actual accelerometer metadata");
        foreach (var item in linear) Check((await access.Describe(item)).Kind == SensorKind.LinearAcceleration, "actual linear acceleration metadata");
        foreach (var item in gravity) Check((await access.Describe(item)).Kind == SensorKind.Gravity, "actual gravity metadata");
        Check(runtime.Initializations == 1 && runtime.FactoryCount == 6, "one MTA context and cached sensor/enumeration factories");
        access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(runtime.Uninitializations == 1 && runtime.FactoryReleases == 6 && runtime.Threads.Distinct().Count() == 1 && !runtime.Threads.Contains(caller),
            "actual factories and MTA lifetime balance on one collection worker");
        Console.WriteLine($"Native Windows sensor inventory: Illuminance={light.Length}, Pressure={pressure.Length}, Gyroscope={gyroscope.Length}, Magnetometer={magnetometer.Length}, Accelerometer={acceleration.Length}, LinearAcceleration={linear.Length}, Gravity={gravity.Length}; no identifiers or measurements logged.");
    }
    private sealed class RuntimeProbe : IWindowsSensorRuntime
    {
        private readonly WindowsSensorPlatform.SensorRuntime native = new();
        private readonly HashSet<nint> factories = [];
        internal readonly List<int> Threads = [];
        internal int Initializations, Uninitializations, FactoryCount, FactoryReleases;
        internal readonly TaskCompletionSource Stopped = new(TaskCreationOptions.RunContinuationsAsynchronously);
        private void Record() => Threads.Add(Environment.CurrentManagedThreadId);
        public int Initialize() {Record();Initializations++;return native.Initialize();}
        public nint Factory(string name, Guid iid) {Record();var pointer = native.Factory(name, iid);factories.Add(pointer);FactoryCount++;return pointer;}
        public void Release(nint value) {Record();if (factories.Remove(value)) FactoryReleases++;native.Release(value);}
        public void Uninitialize() {Record();native.Uninitialize();Uninitializations++;Stopped.TrySetResult();}
    }
    private sealed class SensorSession(EntityKind kind, string id, SensorSamplingRate rate, Action<double?> emit, Action<Exception> fail, Action release) : IDisposable
    {
        internal EntityKind Kind = kind;
        internal string Id = id;
        internal SensorSamplingRate Rate = rate;
        internal Action<double?> Emit = emit;
        internal Action<Exception> Fail = fail;
        internal readonly TaskCompletionSource Closed = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public void Dispose() {release();Closed.TrySetResult();}
    }
    private static void Check(bool condition, string message) {if (!condition) throw new Exception(message);}
}
