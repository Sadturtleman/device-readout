using DeviceReadout;

internal static class TargetIdentityTests
{
    internal static IEnumerable<(string Name, Func<Task> Run)> Cases() => [
        ("same-name native and app targets preserve independent state, discovery and removal", StateTargets),
        ("same-name permission requests preserve target identity and independent responses", Permissions),
        ("same-name sensor sources cannot replace native handles through observer publication", NativeSourceRegistration),
        ("same-name sensor targets retain independent metadata, measurements and failure scopes", SensorTargets)
    ];

    private static async Task StateTargets()
    {
        using var access = new DeviceAccess(new CollisionCollector());
        var native = (await access.Displays.List())[0];
        Check((await access.Get(native)).Label == "Native", "native state before app registration");
        var observed = access.Observers.Target(Entities.Display, "shared");
        access.Observers.Publish(observed, new DisplaySnapshot {Label = "App"});
        Check((await access.Get(native)).Label == "Native", "app registration cannot replace a previously discovered native target");
        Check((await access.Get(observed)).Label == "App", "observed target keeps its own value");
        Check(native != observed && new HashSet<Entity<DisplaySnapshot>> {native, observed}.Count == 2,
            "typed handles distinguish same-name targets");
        Check((await access.Displays.List()).SequenceEqual([observed]), "app inventory contains its own handles");
        Check(await access.Displays.Current() is null, "app inventory does not inherit native current selection");
        access.Observers.Current(Entities.Display, native);
        Check(await access.Displays.Current() == native, "explicit native current retains its identity");
        access.Observers.Current(Entities.Display, observed);
        Check(await access.Displays.Current() == observed, "explicit app current retains its identity");

        await using var nativeStream = access.WithPollInterval(TimeSpan.FromMilliseconds(10)).Watch(native).GetAsyncEnumerator();
        await using var appStream = access.Watch(observed).GetAsyncEnumerator();
        Check(await nativeStream.MoveNextAsync() && nativeStream.Current.Label == "Native", "native watch reads native state");
        Check(await appStream.MoveNextAsync() && appStream.Current.Label == "App", "app watch reads observed state");
        var nextApp = appStream.MoveNextAsync().AsTask();
        access.Observers.Publish(observed, new DisplaySnapshot {Label = "App update"});
        Check(await nextApp.WaitAsync(TimeSpan.FromSeconds(1)) && appStream.Current.Label == "App update", "app watch receives its publication");
        Check(await nativeStream.MoveNextAsync() && nativeStream.Current.Label == "Native", "app publication cannot enter native watch");
        var removed = appStream.MoveNextAsync().AsTask();
        access.Observers.Remove(observed);
        await Error(ErrorCode.EntityRemoved, () => removed.WaitAsync(TimeSpan.FromSeconds(1)));
        await Error(ErrorCode.EntityRemoved, () => access.Get(observed));
        Check((await access.Get(native)).Label == "Native", "app removal leaves native target readable");
        Check(await nativeStream.MoveNextAsync() && nativeStream.Current.Label == "Native", "app removal leaves native watch alive");
        Check((await access.Displays.List()).Length == 0 && await access.Displays.Current() is null,
            "removed app inventory does not silently fall back to same-name native target");
    }

    private static async Task Permissions()
    {
        using var access = new DeviceAccess(new CollisionCollector());
        var native = (await access.Displays.List())[0];
        var observed = access.Observers.Target(Entities.Display, "shared");
        access.Observers.Permission(Entities.Display, PermissionStatus.NotDetermined);
        access.Observers.Permission(native, PermissionStatus.Denied);
        Check(await access.Permissions.Check(native) == PermissionStatus.Denied
            && await access.Permissions.Check(observed) == PermissionStatus.NotDetermined, "target status cannot alias across owners");
        var requests = System.Threading.Channels.Channel.CreateUnbounded<PermissionRequest>();
        using var coordinator = access.Observers.OnPermissionRequest((request, token) => requests.Writer.WriteAsync(request, token).AsTask());
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        var nativePending = access.Permissions.Request(native, deadline.Token);
        var nativeRequest = await requests.Reader.ReadAsync(deadline.Token);
        var appPending = access.Permissions.Request(observed, deadline.Token);
        var appRequest = await requests.Reader.ReadAsync(deadline.Token);
        Check(nativeRequest != appRequest, "application coordinator must distinguish requests for same-name targets");
        access.Observers.Permission(observed, PermissionStatus.Granted);
        Check(await appPending.WaitAsync(TimeSpan.FromSeconds(1)) == PermissionStatus.Granted, "app response completes app request");
        await Task.Delay(20);
        Check(!nativePending.IsCompleted && await access.Permissions.Check(native) == PermissionStatus.Denied,
            "app response leaves native request and status intact");
        access.Observers.Permission(native, PermissionStatus.Restricted);
        Check(await nativePending.WaitAsync(TimeSpan.FromSeconds(1)) == PermissionStatus.Restricted, "native response completes native request");
        access.Observers.Permission(Entities.Display, PermissionStatus.Unavailable);
        Check(await access.Permissions.Check(native) == PermissionStatus.Restricted
            && await access.Permissions.Check(observed) == PermissionStatus.Granted, "family response preserves both explicit overrides");
    }

    private sealed class CollisionCollector : IDeviceCollector
    {
        public IReadOnlyList<string> List(EntityKind kind, CancellationToken token) => ["shared"];
        public string? Current(EntityKind kind, CancellationToken token) => "shared";
        public DeviceSnapshot Read(EntityAddress entity, CancellationToken token) => new DisplaySnapshot {Label = "Native"};
    }

    private static async Task NativeSourceRegistration()
    {
        using var access = new DeviceAccess(new CollisionCollector());
        var native = (await access.Sensors.List(Entities.Accelerometer))[0];
        access.Observers.Publish(native, new AccelerometerSnapshot {Value = new(1, 2, 3)});
        await Error(ErrorCode.InvalidConfiguration, () => {
            using var source = access.Observers.SensorSource(native, _ => null);
            return Task.CompletedTask;
        });
        await Error(ErrorCode.InvalidConfiguration, () => {
            _ = access.Observers.Target(native, "rebound");return Task.CompletedTask;
        });
        Check((await access.Sensors.List(Entities.Accelerometer)).SequenceEqual([native]),
            "publishing a native handle does not turn it into app inventory");
    }

    private static async Task SensorTargets()
    {
        var collector = new NativeSensorCollector();
        using var access = new DeviceAccess(collector);
        var native = (await access.Sensors.List(Entities.Accelerometer))[0];
        var observed = access.Observers.Target(Entities.Accelerometer, "shared");
        using var source = access.Observers.SensorSource(observed, session => {
            session.Publish(new() {Value = new(2, 0, 0)});return null;
        }, new SensorDescription {Name = "App sensor"});
        Check((await access.Describe(native)).Name == "Native sensor" && (await access.Describe(observed)).Name == "App sensor",
            "same-name metadata retains its source");
        Check((await access.Get(native)).Value == new Vector3(1, 0, 0)
            && (await access.Get(observed)).Value == new Vector3(2, 0, 0), "one-shot samples retain their source");
        await using var nativeStream = access.Watch(native).GetAsyncEnumerator();
        await using var appStream = access.Watch(observed).GetAsyncEnumerator();
        Check(await nativeStream.MoveNextAsync() && nativeStream.Current.Value == new Vector3(1, 0, 0), "native watch sample");
        Check(await appStream.MoveNextAsync() && appStream.Current.Value == new Vector3(2, 0, 0), "app watch sample");
        using var appFailure = access.Observers.FailureSource(observed);
        var appPending = appStream.MoveNextAsync().AsTask();
        appFailure.Publish(new(ErrorCode.PermissionDenied, "App source permission lost."));
        await Error(ErrorCode.PermissionDenied, () => appPending.WaitAsync(TimeSpan.FromSeconds(1)));
        var nativePending = nativeStream.MoveNextAsync().AsTask();
        collector.Publish(new() {Value = new(3, 0, 0)});
        Check(await nativePending.WaitAsync(TimeSpan.FromSeconds(1)) && nativeStream.Current.Value == new Vector3(3, 0, 0),
            "app target failure leaves native sensor session running");
        appFailure.Publish(null);
        Check((await access.Get(observed)).Value == new Vector3(2, 0, 0), "app recovery creates a fresh measurement session");
        using var nativeFailure = access.Observers.FailureSource(native);
        nativeFailure.Publish(new(ErrorCode.ReadFailed, "Native source failed."));
        await Error(ErrorCode.ReadFailed, () => access.Describe(native));
        Check((await access.Describe(observed)).Name == "App sensor" && (await access.Get(observed)).Value == new Vector3(2, 0, 0),
            "native target failure leaves app metadata and measurement available");
        access.Observers.Failure(Entities.Accelerometer, new(ErrorCode.PermissionDenied, "Family policy."));
        await Error(ErrorCode.PermissionDenied, () => access.Get(native));
        await Error(ErrorCode.PermissionDenied, () => access.Get(observed));
        await Error(ErrorCode.PermissionDenied, () => access.Sensors.List(Entities.Accelerometer));
        access.Observers.Failure(Entities.Accelerometer, null);nativeFailure.Dispose();
        source.Dispose();
        await Error(ErrorCode.EntityRemoved, () => access.Get(observed));
        await Error(ErrorCode.EntityRemoved, () => access.Describe(observed));
        Check((await access.Get(native)).Value == new Vector3(1, 0, 0) && (await access.Describe(native)).Name == "Native sensor",
            "source disposal never retires the native target with the same name");
        Check((await access.Capabilities.Get(observed)).Readable == false && (await access.Capabilities.Get(native)).Readable == true,
            "capabilities remain scoped to target identity");
    }

    private sealed class NativeSensorCollector : IDeviceCollector
    {
        private readonly System.Collections.Concurrent.ConcurrentDictionary<Action<DeviceSnapshot>, byte> listeners = new();
        public IReadOnlyList<string> List(EntityKind kind, CancellationToken token) => ["shared"];
        public DeviceSnapshot Read(EntityAddress entity, CancellationToken token) => throw new NotSupportedException();
        public SensorDescription Describe(EntityAddress entity, CancellationToken token) => new() {Kind = SensorKind.Accelerometer, Name = "Native sensor"};
        public EntityCapabilities Capabilities(EntityAddress entity) => new(true, true);
        public ICollectorSubscription Observe(EntityAddress entity, SensorSamplingRate rate, Action<DeviceSnapshot> emit, Action<Exception> fail, CancellationToken token)
        {
            Check(!entity.Observed, "app sensor address must never reach a native collector");
            listeners.TryAdd(emit, 0);emit(new AccelerometerSnapshot {Value = new(1, 0, 0)});
            return new Subscription(() => listeners.TryRemove(emit, out _));
        }
        internal void Publish(AccelerometerSnapshot sample) {foreach (var listener in listeners.Keys) listener(sample);}
        private sealed class Subscription(Action release) : ICollectorSubscription
        {
            public bool PollingRequired => false;
            public void Dispose() => release();
        }
    }
    private static void Check(bool condition, string message) {if (!condition) throw new Exception(message);}
    private static async Task Error(ErrorCode expected, Func<Task> run)
    {
        try {await run();throw new Exception($"Expected {expected}");}
        catch (DeviceReadoutException error) when (error.Code == expected) { }
    }
}
