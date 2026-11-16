using DeviceReadout;
using System.Diagnostics;
using DeviceReadout.Windows;
using System.Collections.Immutable;

if (args is ["--cpu-availability-child"]) {
    if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException();
    try {await WindowsCpuAvailabilityTests.RunChild();return 0;}
    catch (Exception error) {Console.Error.WriteLine(error);return 1;}
}

var tests = new List<(string Name, Func<Task> Run)> {
    ("target permissions inherit kind status and preserve explicit overrides", async () => {
        using var access = new DeviceAccess(new TestCollector());
        var first = access.Observers.Target(Entities.Accelerometer, "permission-first");
        var second = access.Observers.Target(Entities.Accelerometer, "permission-second");
        access.Observers.Permission(Entities.Accelerometer, PermissionStatus.NotDetermined);
        Check(await access.Permissions.Check(first) == PermissionStatus.NotDetermined, "inherited status");
        var requests = System.Threading.Channels.Channel.CreateUnbounded<PermissionRequest>();
        using var coordinator = access.Observers.OnPermissionRequest((request, token) => requests.Writer.WriteAsync(request, token).AsTask());
        var pending = access.Permissions.Request(first);
        Check((await requests.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1))).TargetId == "permission-first", "first request target");
        access.Observers.Permission(Entities.Accelerometer, PermissionStatus.Granted);
        Check(await pending.WaitAsync(TimeSpan.FromSeconds(1)) == PermissionStatus.Granted, "inherited request response");
        access.Observers.Permission(second, PermissionStatus.Denied);
        access.Observers.Permission(Entities.Accelerometer, PermissionStatus.Restricted);
        Check(await access.Permissions.Check(first) == PermissionStatus.Restricted, "updated inherited status");
        Check(await access.Permissions.Check(second) == PermissionStatus.Denied, "explicit target override");
        access.Observers.Permission(second, null);
        var overridden = access.Permissions.Request(second);
        Check((await requests.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1))).TargetId == "permission-second", "second request target");
        access.Observers.Permission(Entities.Accelerometer, PermissionStatus.Granted);
        await Task.Delay(25);Check(!overridden.IsCompleted, "kind response cannot replace target override");
        Check(await access.Permissions.Check(second) is null, "explicit unknown overrides kind");
        access.Observers.Permission(second, PermissionStatus.Denied);
        Check(await overridden.WaitAsync(TimeSpan.FromSeconds(1)) == PermissionStatus.Denied, "target response");
    }),
    ("native discovery and description discard results across observer failure", async () => {
        for (var operation = 0; operation < 3; operation++) {
            using var collector = new PendingNativeCollector();
            using var access = new DeviceAccess(collector);
            var sensor = (await access.List(Entities.Accelerometer))[0];
            Task Query() => operation switch {0 => access.List(Entities.Accelerometer), 1 => access.Current(Entities.Accelerometer), _ => access.Describe(sensor)};
            collector.ArmDiscovery();
            var pending = Query();
            try {
                await collector.Started.Task.WaitAsync(TimeSpan.FromSeconds(1));
                access.Observers.Failure(Entities.Accelerometer, new DeviceReadoutException(ErrorCode.PermissionDenied, "Discovery permission changed."));
                access.Observers.Failure(Entities.Accelerometer, null);
            } finally {collector.Release.Set();}
            await Error(ErrorCode.PermissionDenied, () => pending);
            await Query();
        }
    }),
    ("failure and recovery during a native read discard its pre-failure result", async () => {
        using var collector = new PendingNativeCollector();
        using var access = new DeviceAccess(collector);
        var pending = access.Get(Entities.Ram);
        try {
            await collector.Started.Task.WaitAsync(TimeSpan.FromSeconds(1));
            access.Observers.Failure(Entities.Ram, new DeviceReadoutException(ErrorCode.PermissionDenied, "Permission changed during read."));
            access.Observers.Failure(Entities.Ram, null);
        } finally {collector.Release.Set();}
        await Error(ErrorCode.PermissionDenied, () => pending);
        Check((await access.Get(Entities.Ram)).AvailableBytes == 2, "new native read after recovery");
    }),
    ("empty observer inventory and pending reads preserve failures", async () => {
        using var access = new DeviceAccess(new TestCollector());
        access.Observers.Current(Entities.Display, null);
        Check((await access.List(Entities.Display)).Length == 0, "known empty inventory");
        Check(await access.Current(Entities.Display) is null, "known empty current");
        var screen = access.Observers.Target(Entities.Display, "awaiting-screen");
        var pending = access.Get(screen);
        await Task.Delay(30);Check(!pending.IsCompleted, "first state wait");
        access.Observers.Failure(Entities.Display, new DeviceReadoutException(ErrorCode.PermissionDenied, "Permission revoked before first state."));
        await Error(ErrorCode.PermissionDenied, () => pending.WaitAsync(TimeSpan.FromSeconds(1)));
        access.Observers.Publish(screen, new DisplaySnapshot {Label = "Refreshed while recovering"});
        await Error(ErrorCode.PermissionDenied, () => access.Get(screen));
        access.Observers.Failure(Entities.Display, null);
        Check((await access.Get(screen)).Label == "Refreshed while recovering", "refreshed state");
    }),
    ("native event get and watch receive app failures and release on the worker", async () => {
        foreach (var once in new[] {false, true}) {
            var collector = new NativeEventCollector();
            using var access = new DeviceAccess(collector);
            var sensor = (await access.List(Entities.StepDetected))[0];
            using var cancellation = new CancellationTokenSource();
            async Task First() {
                await using var stream = access.Watch(sensor, cancellation.Token).GetAsyncEnumerator();
                Check(await stream.MoveNextAsync(), "event stream should fail before its first value");
            }
            Task pending = once ? access.Get(sensor, cancellation.Token) : First();
            await collector.Registered.Task.WaitAsync(TimeSpan.FromSeconds(1));
            access.Observers.Failure(Entities.StepDetected, new DeviceReadoutException(ErrorCode.PermissionDenied, "Sensor permission revoked."));
            try {await Error(ErrorCode.PermissionDenied, () => pending.WaitAsync(TimeSpan.FromSeconds(1)));}
            finally {
                cancellation.Cancel();
                try {await pending;} catch (OperationCanceledException) { } catch (DeviceReadoutException) { }
            }
            await collector.Released.Task.WaitAsync(TimeSpan.FromSeconds(1));
            Check(collector.ObserveThread == collector.DisposeThread, "native release thread");
            await Error(ErrorCode.PermissionDenied, () => access.Describe(sensor));
        }
    }),
    ("app failure ends native polling without waiting for the next poll", async () => {
        using var access = new DeviceAccess(new TestCollector());
        using var cancellation = new CancellationTokenSource();
        await using var stream = access.WithPollInterval(TimeSpan.FromSeconds(30)).Watch(Entities.Ram, cancellation.Token).GetAsyncEnumerator();
        Check(await stream.MoveNextAsync(), "initial native state");
        var next = stream.MoveNextAsync().AsTask();
        access.Observers.Failure(Entities.Ram, new DeviceReadoutException(ErrorCode.PermissionDenied, "Host-observed denial."));
        try {await Error(ErrorCode.PermissionDenied, async () => {await next.WaitAsync(TimeSpan.FromSeconds(1));});}
        finally {
            cancellation.Cancel();
            try {await next;} catch (OperationCanceledException) { } catch (DeviceReadoutException) { }
        }
        access.Observers.Failure(Entities.Ram, null);
        Check((await access.Get(Entities.Ram)).AvailableBytes == 0, "native recovery");
    }),
    ("observer failures invalidate state and preserve target removal", async () => {
        using var access = new DeviceAccess(new TestCollector());
        var first = access.Observers.Target(Entities.Display, "first");
        var second = access.Observers.Target(Entities.Display, "second");
        access.Observers.Publish(first, new DisplaySnapshot {Label = "First"});
        access.Observers.Publish(second, new DisplaySnapshot {Label = "Second"});
        access.Observers.Current(Entities.Display, second);
        await using var stream = access.Watch(first).GetAsyncEnumerator();
        Check(await stream.MoveNextAsync(), "initial screen");
        var next = stream.MoveNextAsync();
        access.Observers.Failure(first, new DeviceReadoutException(ErrorCode.PermissionDenied, "Observer lost permission."));
        await Error(ErrorCode.PermissionDenied, async () => {await next.AsTask().WaitAsync(TimeSpan.FromSeconds(1));});
        await Error(ErrorCode.PermissionDenied, () => access.Get(first));
        Check((await access.Get(second)).Label == "Second", "unaffected target");
        access.Observers.Failure(Entities.Display, new DeviceReadoutException(ErrorCode.ReadFailed, "Inventory unavailable."));
        await Error(ErrorCode.ReadFailed, () => access.List(Entities.Display));
        await Error(ErrorCode.ReadFailed, () => access.Current(Entities.Display));
        await Error(ErrorCode.ReadFailed, () => access.Get(second));
        access.Observers.Permission(Entities.Display, PermissionStatus.Denied);
        Check(await access.Permissions.Check(Entities.Display) == PermissionStatus.Denied, "independent permission state");
        access.Observers.Failure(Entities.Display, null);
        access.Observers.Failure(first, null);
        await Error(ErrorCode.ReadTimeout, () => access.WithReadTimeout(TimeSpan.FromMilliseconds(80)).Get(first));
        access.Observers.Publish(first, new DisplaySnapshot {Label = "Fresh"});
        Check((await access.Get(first)).Label == "Fresh", "fresh recovery");
        access.Observers.Remove(first);
        access.Observers.Failure(first, new DeviceReadoutException(ErrorCode.ReadFailed, "Late failure."));
        access.Observers.Publish(first, new DisplaySnapshot {Label = "Late value"});
        await Error(ErrorCode.EntityRemoved, () => access.Get(first));
    }),
    ("resource handles never rebind to a resource that disappeared and returned", () => {
        var catalog = new ResourceCatalog();
        catalog.Update(["volume-guid-A", "volume-guid-B"]);
        var original = catalog.Find("volume-guid-A")!;
        Check(catalog.Resolve(original) == "volume-guid-A", "initial native identity");
        catalog.Update(["volume-guid-B"]);
        try {catalog.Resolve(original);throw new Exception("removed handle resolved");} catch(DeviceReadoutException error) when(error.Code == ErrorCode.EntityRemoved) { }
        catalog.Update(["volume-guid-A", "volume-guid-B"]);
        Check(catalog.Find("volume-guid-A") != original, "new resource generation");
        return Task.CompletedTask;
    }),
    ("configuration is immutable and construction performs no collection", async () => {
        var collector = new TestCollector();
        using var access = new DeviceAccess(collector);
        var fast = access.WithPollInterval(TimeSpan.FromMilliseconds(15));
        Check(access.PollInterval == TimeSpan.FromSeconds(1), "default poll");
        Check(access.ReadTimeout == TimeSpan.FromSeconds(5), "default timeout");
        Check(access.SensorSamplingRate == SensorSamplingRate.PlatformDefault, "default sampling");
        Check(fast.PollInterval == TimeSpan.FromMilliseconds(15), "copied poll");
        Check(collector.Reads == 0, "construction must be inert");
        await Error(ErrorCode.InvalidConfiguration, () => Task.FromResult(access.WithPollInterval(TimeSpan.Zero)));
    }),
    ("get executes outside the host thread and stamps a complete RAM snapshot", async () => {
        var caller = Environment.CurrentManagedThreadId;
        var collector = new TestCollector();
        using var access = new DeviceAccess(collector);
        var value = await access.Get(Entities.Ram);
        Check(collector.ReadThread != caller, "collection on calling thread");
        Check(value.PhysicalBytes == 9007199254740993UL && value.AvailableBytes == 0UL && value.LowMemory == false, "precision/zero/false");
        Check(value.CollectedAt != default && value.CollectedAt.Offset == TimeSpan.Zero, "completion timestamp");
        Check(value.FreeBytes is null, "missing fields");
    }),
    ("blocking collection preserves host deadlines and heartbeat", async () => {
        var collector = new TestCollector { Block = TimeSpan.FromMilliseconds(800) };
        using var access = new DeviceAccess(collector);
        var ticks = 0;
        using var timer = new Timer(_ => Interlocked.Increment(ref ticks), null, 0, 5);
        var elapsed = Stopwatch.StartNew();
        await Error(ErrorCode.ReadTimeout, () => access.WithReadTimeout(TimeSpan.FromMilliseconds(90)).Get(Entities.Ram));
        Check(elapsed.ElapsedMilliseconds < 600, "deadline blocked by collector");
        Check(ticks > 2, "host heartbeat blocked");
    }),
    ("watch emits equal values with new completion timestamps and stops on cancellation", async () => {
        var collector = new TestCollector();
        using var access = new DeviceAccess(collector);
        using var cancellation = new CancellationTokenSource();
        await using var stream = access.WithPollInterval(TimeSpan.FromMilliseconds(15)).Watch(Entities.Ram, cancellation.Token).GetAsyncEnumerator();
        Check(collector.Reads == 0, "watch is lazy");
        Check(await stream.MoveNextAsync(), "first");var first = stream.Current;
        Check(await stream.MoveNextAsync(), "second");var second = stream.Current;
        Check(first.PhysicalBytes == second.PhysicalBytes, "equal values");
        Check(second.CollectedAt > first.CollectedAt, "fresh completion timestamp");
        cancellation.Cancel();
        try {await stream.MoveNextAsync();throw new Exception("expected cancellation");} catch(OperationCanceledException) { }
    }),
    ("screen snapshots and current selection are supplied by observers", async () => {
        using var access = new DeviceAccess(new TestCollector());
        var display = access.Observers.Target(Entities.Display, "app-screen");
        access.Observers.Publish(display, new DisplaySnapshot {PixelSize = new Size<int>(800, 600)});
        access.Observers.Current(Entities.Display, display);
        var current = await access.Current(Entities.Display);
        Check((await access.Get(current!)).PixelSize?.Width == 800, "observed screen");
        await using var stream = access.Watch(display).GetAsyncEnumerator();
        Check(await stream.MoveNextAsync(), "initial screen");
        var next = stream.MoveNextAsync();
        access.Observers.Publish(display, new DisplaySnapshot {PixelSize = new Size<int>(600, 800)});
        Check(await next && stream.Current.PixelSize?.Width == 600, "changed screen");
        var removed = stream.MoveNextAsync();
        access.Observers.Remove(display);
        await Error(ErrorCode.EntityRemoved, async () => {await removed;});
        Check(await access.Current(Entities.Display) is null, "removed current");
    }),
    ("event sensors wait for real events and a sample watch times out without its first sample", async () => {
        using var access = new DeviceAccess(new TestCollector());
        var step = access.Observers.Target(Entities.StepDetected, "steps");
        await using var stream = access.WithReadTimeout(TimeSpan.FromMilliseconds(25)).Watch(step).GetAsyncEnumerator();
        var next = stream.MoveNextAsync();
        await Task.Delay(80);Check(!next.IsCompleted, "event wait has no timeout");
        access.Observers.Publish(step, new StepDetectedSnapshot {Value = true});
        Check(await next && stream.Current.Value == true, "real step event");
        var accelerometer = access.Observers.Target(Entities.Accelerometer, "accelerometer");
        await using var continuous = access.WithReadTimeout(TimeSpan.FromMilliseconds(25)).Watch(accelerometer).GetAsyncEnumerator();
        await Error(ErrorCode.ReadTimeout, async () => {await continuous.MoveNextAsync();});
    }),
    ("permission requests wait for host-observed status outside the read deadline", async () => {
        using var access = new DeviceAccess(new TestCollector());
        access.Observers.Permission(Entities.Display, PermissionStatus.NotDetermined);
        using var coordinator = access.Observers.OnPermissionRequest(async (request, token) => {
            await Task.Delay(70, token);
            access.Observers.Permission(Entities.Display, PermissionStatus.Granted);
        });
        var status = await access.WithReadTimeout(TimeSpan.FromMilliseconds(10)).Permissions.Request(Entities.Display);
        Check(status == PermissionStatus.Granted, "permission response");
    }),
    ("closing the context releases active native subscriptions on the collection lane", async () => {
        var collector = new ObservingTestCollector();
        var access = new DeviceAccess(collector);
        var sensor = (await access.List(Entities.Accelerometer))[0];
        await using var stream = access.Watch(sensor).GetAsyncEnumerator();
        Check(await stream.MoveNextAsync(), "initial native sample");
        access.Dispose();
        await collector.Released.Task.WaitAsync(TimeSpan.FromSeconds(1));
        Check(collector.DisposeThread == collector.ObserveThread, "native release thread");
    }),
    ("unknown enums invalidate the whole set, while empty sets and zero remain", async () => {
        using var access = new DeviceAccess(new TestCollector());
        access.Observers.Publish(Entities.NetworkPath, new NetworkPathSnapshot {ConnectionState = (ConnectionState)999,
            Transports = ImmutableHashSet.Create(NetworkTransport.Wifi, (NetworkTransport)999), SaveData = false});
        var network = await access.Get(Entities.NetworkPath);
        Check(network.ConnectionState is null && network.Transports is null && network.SaveData == false, "unknown enum contract");
        access.Observers.Publish(Entities.NetworkPath, new NetworkPathSnapshot {Transports = ImmutableHashSet<NetworkTransport>.Empty});
        Check((await access.Get(Entities.NetworkPath)).Transports?.Count == 0, "empty enum set");
        var display = access.Observers.Target(Entities.Display, "screen");
        access.Observers.Publish(display, new DisplaySnapshot {Brightness = double.NaN, RotationDegrees = 0});
        var screen = await access.Get(display);Check(screen.Brightness is null && screen.RotationDegrees == 0, "finite numeric contract");
    }),
    ("JSON preserves integer precision, nullable values and platform thermal levels", async () => {
        using var access = new DeviceAccess(new TestCollector());
        var json = System.Text.Json.JsonDocument.Parse(SnapshotJson.Serialize(await access.Get(Entities.Ram)));
        Check(json.RootElement.GetProperty("physicalBytes").GetString() == "9007199254740993", "JSON byte count");
        Check(json.RootElement.GetProperty("freeBytes").ValueKind == System.Text.Json.JsonValueKind.Null, "JSON null");
        var power = new PowerSnapshot {ThermalState = new ThermalState.Apple(AppleThermalState.Serious)};
        Check(SnapshotJson.Serialize(power).Contains("AppleThermalState.Serious"), "thermal tag");
    })
};
if (OperatingSystem.IsWindows()) tests.Add(("real Windows memory, OS, runtime, CPU, storage and network queries", async () => {
    if (!OperatingSystem.IsWindows()) return;
    using var access = WindowsDeviceAccess.Create();
    var ram = await access.Get(Entities.Ram);
    Check(ram.KernelAccessibleBytes > 0 && ram.AvailableBytes >= 0, "native RAM values");
    Check((ram.PhysicalBytes is null || ram.PhysicalBytes >= ram.KernelAccessibleBytes) && ram.KernelAccessibleBytes >= ram.AvailableBytes, "RAM meanings");
    Check((await access.Get(Entities.Os)).Family == OsFamily.Windows, "Windows family");
    Check((await access.Get(Entities.Runtime)).ProcessBitness == (Environment.Is64BitProcess ? 64 : 32), "process bitness");
    var cpu = await access.Get(Entities.Cpu);
    Check(cpu.AvailableLogicalProcessorCount is > 0 && cpu.AvailableLogicalProcessorCount <= cpu.LogicalProcessorCount, "current process processor count");
    Check((await access.Get(Entities.ProcessMemory)).AllocationRemainingBytes > 0, "process allocation");
    Check((await access.Get(Entities.Locale)).CurrentLanguageTag is not null, "locale");
    Check((await access.Get(Entities.TimeZone)).WindowsId is not null, "time zone");
    _ = await access.Get(Entities.Power);
    var batterySupport = await access.Capabilities.Get(Entities.Battery);
    Check(batterySupport.Readable == true && batterySupport.Watchable == true, "Windows battery capability");
    var batteries = await access.Batteries.List();
    Console.WriteLine($"Native battery discovery: {batteries.Length} targets");
    var volumes = await access.List(Entities.StorageVolume);
    Check(volumes.Length > 0, "volumes");
    var current = await access.Current(Entities.StorageVolume);
    Check(current is not null, "app volume");
    var volume = await access.Get(current!);
    Check(volume.TotalBytes > 0 && volume.FreeBytes >= 0 && volume.AvailableToCallerBytes >= 0, "volume capacity");
    var adapters = await access.List(Entities.NetworkInterface);
    Check(adapters.Length > 0, "network adapters");
    foreach(var adapter in adapters) Check((await access.Get(adapter)).Name is not null, "adapter name");
    await Error(ErrorCode.UnsupportedEntity, () => access.Get(Entities.AndroidIdentity));
    Console.WriteLine($"Native evidence: physical={ram.PhysicalBytes}, kernel={ram.KernelAccessibleBytes}, available={ram.AvailableBytes}, volumes={volumes.Length}, adapters={adapters.Length}");
}));
if (OperatingSystem.IsWindows()) tests.AddRange(WindowsBatteryTests.Cases());
if (OperatingSystem.IsWindows()) tests.AddRange(WindowsPowerTests.Cases());
if (OperatingSystem.IsWindows()) tests.AddRange(WindowsAggregateBatteryTests.Cases());
if (OperatingSystem.IsWindows()) tests.AddRange(WindowsCpuTests.Cases());
if (OperatingSystem.IsWindows()) tests.AddRange(WindowsCpuAvailabilityTests.Cases());
if (OperatingSystem.IsWindows()) tests.AddRange(WindowsNetworkTests.Cases());
if (OperatingSystem.IsWindows()) tests.AddRange(WindowsIdentityTests.Cases());
if (OperatingSystem.IsWindows()) tests.AddRange(WindowsConnectivityTests.Cases());
tests.AddRange(StateChangeTests.Cases());
tests.AddRange(ObserverFailureTests.Cases());
tests.AddRange(SensorSourceTests.Cases());
if (args is ["--filter", var filter]) {
    tests = tests.Where(test => test.Name.Contains(filter, StringComparison.OrdinalIgnoreCase)).ToList();
    if (tests.Count == 0) {Console.Error.WriteLine("No tests match the filter.");return 2;}
} else if (args.Length != 0) {Console.Error.WriteLine("Expected --filter <test name fragment>.");return 2;}
var failures = 0;
foreach(var (name, run) in tests) {
    try {await run();Console.WriteLine($"PASS {name}");}
    catch(Exception error) {failures++;Console.Error.WriteLine($"FAIL {name}: {error}");}
}
Console.WriteLine($"{tests.Count - failures}/{tests.Count} passed");
return failures == 0 ? 0 : 1;

static void Check(bool condition, string message) {if (!condition) throw new Exception(message);}
static async Task Error(ErrorCode expected, Func<Task> run) {
    try {await run();throw new Exception($"Expected {expected}");}
    catch(DeviceReadoutException error) when(error.Code == expected) { }
}
sealed class TestCollector : IDeviceCollector {
    public int Reads;
    public int ReadThread;
    public TimeSpan Block;
    public DeviceSnapshot Read(EntityAddress entity, CancellationToken cancellationToken) {
        ReadThread = Environment.CurrentManagedThreadId;Interlocked.Increment(ref Reads);
        if(Block > TimeSpan.Zero) Thread.Sleep(Block);
        return new RamSnapshot {PhysicalBytes = 9007199254740993UL, AvailableBytes = 0UL, LowMemory = false};
    }
}
sealed class PendingNativeCollector : IDeviceCollector, IDisposable {
    public TaskCompletionSource Started = new(TaskCreationOptions.RunContinuationsAsynchronously);
    public ManualResetEventSlim Release = new();
    private int reads;
    private int discoveryArmed;
    public void ArmDiscovery() => Interlocked.Exchange(ref discoveryArmed, 1);
    private void AwaitRelease() {Started.TrySetResult();if (!Release.Wait(TimeSpan.FromSeconds(2))) throw new TimeoutException();}
    private void DiscoveryGate() {if (Interlocked.Exchange(ref discoveryArmed, 0) == 1) AwaitRelease();}
    public DeviceSnapshot Read(EntityAddress entity, CancellationToken token) {
        var count = Interlocked.Increment(ref reads);
        if (count == 1) AwaitRelease();
        return new RamSnapshot {AvailableBytes = (ulong)count};
    }
    public IReadOnlyList<string> List(EntityKind kind, CancellationToken token) {DiscoveryGate();return ["native-sensor"];}
    public string? Current(EntityKind kind, CancellationToken token) {DiscoveryGate();return "native-sensor";}
    public SensorDescription Describe(EntityAddress entity, CancellationToken token) {DiscoveryGate();return new() {Kind = SensorKind.Accelerometer};}
    public void Dispose() => Release.Dispose();
}
sealed class NativeEventCollector : IDeviceCollector {
    public int ObserveThread, DisposeThread;
    public TaskCompletionSource Registered = new(TaskCreationOptions.RunContinuationsAsynchronously);
    public TaskCompletionSource Released = new(TaskCreationOptions.RunContinuationsAsynchronously);
    public DeviceSnapshot Read(EntityAddress entity, CancellationToken token) => throw new NotSupportedException();
    public IReadOnlyList<string> List(EntityKind kind, CancellationToken token) => ["native-step"];
    public ICollectorSubscription? Observe(EntityAddress entity, SensorSamplingRate rate, Action<DeviceSnapshot> emit, Action<Exception> fail, CancellationToken token) {
        ObserveThread = Environment.CurrentManagedThreadId;Registered.TrySetResult();
        return new Subscription(() => {DisposeThread = Environment.CurrentManagedThreadId;Released.TrySetResult();});
    }
    private sealed class Subscription(Action action) : ICollectorSubscription {
        public bool PollingRequired => false;
        public void Dispose() => action();
    }
}
sealed class ObservingTestCollector : IDeviceCollector {
    public int ObserveThread, DisposeThread;
    public TaskCompletionSource Released = new(TaskCreationOptions.RunContinuationsAsynchronously);
    public DeviceSnapshot Read(EntityAddress entity, CancellationToken token) => throw new NotSupportedException();
    public IReadOnlyList<string> List(EntityKind kind, CancellationToken token) => ["native-accelerometer"];
    public ICollectorSubscription? Observe(EntityAddress entity, SensorSamplingRate rate, Action<DeviceSnapshot> emit, Action<Exception> fail, CancellationToken token) {
        ObserveThread = Environment.CurrentManagedThreadId;
        emit(new AccelerometerSnapshot {Value = new Vector3(1, 2, 3)});
        return new Subscription(() => {DisposeThread = Environment.CurrentManagedThreadId;Released.TrySetResult();});
    }
    private sealed class Subscription(Action action) : ICollectorSubscription {
        public bool PollingRequired => false;
        public void Dispose() => action();
    }
}
