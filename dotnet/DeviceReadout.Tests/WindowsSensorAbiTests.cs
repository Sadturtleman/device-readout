using DeviceReadout;
using DeviceReadout.Windows;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;

[SupportedOSPlatform("windows")]
internal static class WindowsSensorAbiTests
{
    internal static IEnumerable<(string Name, Func<Task> Run)> Cases() => [
        ("Windows native sensor ABI decodes scalar readings and balances event and runtime ownership", ScalarAbi),
        ("Windows native sensor gyroscope preserves signed axes, radians and complete samples", GyroscopeAbi),
        ("Windows native sensor magnetometer preserves signed microtesla readings and stream cadence", MagnetometerAbi),
        ("Windows native sensor accelerometer converts native G-force into common signed acceleration", AccelerometerAbi),
        ("Windows native sensor linear acceleration and gravity select their own native measurements", AccelerationFamilies),
        ("Windows native sensor acceleration handles reject mismatched native reading types before measurement", AccelerationTypeValidation),
        ("Windows native sensor acceleration obeys observed activity and permissions without prompting", AccelerationLifecycle),
        ("Windows native sensor absolute orientation maps named quaternion components from device to ENU", AbsoluteOrientationAbi),
        ("Windows native sensor relative orientation preserves its native session reference across activity changes", RelativeOrientationAbi),
        ("Windows native sensor orientation handles reject a different reference kind before measurement", OrientationTypeValidation),
        ("Windows native sensor incomplete quaternion samples return null and recover without resubscription", OrientationPropertyFailures),
        ("Windows native sensor hinge angles use asynchronous initial readings and preserve radians and native thresholds", HingeAngleAbi),
        ("Windows native sensor hinge events satisfy the first sample while the initial asynchronous read is pending", HingeInitialEvent),
        ("Windows native sensor hinge initial deadlines and caller cancellation cancel native operations and recover", HingeInitialDeadlines),
        ("Windows native sensor hinge late initial values cannot overwrite a newer native event", HingeLateInitial),
        ("Windows native sensor vector property failures return null and recover on the next complete sample", VectorPropertyFailures),
        ("Windows native sensor held measurement reads preserve host deadlines and stop collecting after cancellation", HeldVectorRead),
        ("Windows native sensor sampling requests coexist and restore the original driver interval", SamplingOwnership),
        ("Windows native sensor asynchronous discovery preserves deadlines and cancels owned operations", () => DiscoveryDeadline(false)),
        ("Windows native sensor capability deadlines cancel the underlying native enumeration", () => DiscoveryDeadline(true))
    ];
    private static async Task ScalarAbi()
    {
        foreach (var pressure in new[] {false, true}) {
            var runtime = new RuntimeFixture(pressure ? EntityKind.Pressure : EntityKind.Illuminance);
            using var access = new DeviceAccess(new WindowsCollector(sensorPlatform: new WindowsSensorPlatform(runtime)));
            if (pressure) {
                var sensor = (await access.Sensors.List(Entities.Pressure)).Single();
                Check((await access.Describe(sensor)).MinimumInterval == TimeSpan.FromMilliseconds(20), "pressure metadata uses native interval slot");
                Check(runtime.CurrentReads == 0 && runtime.Registrations == 0, "metadata does not measure");
                runtime.Value = 1013.25;Check((await access.Get(sensor)).Value == 101325, "native double hPa converts to Pa");
                await TestCompletion.Until(() => runtime.HandlerCount == 0, "one-shot native pressure handler removed");
                await using var watch = access.Watch(sensor).GetAsyncEnumerator();
                Check(await watch.MoveNextAsync() && watch.Current.Value == 101325, "native current pressure sample");
                runtime.Value = 1000;runtime.Fire();runtime.Fire();
                Check(await watch.MoveNextAsync() && watch.Current.Value == 100000, "native pressure event");
                Check(await watch.MoveNextAsync() && watch.Current.Value == 100000, "duplicate native pressure event");
            } else {
                var sensor = (await access.Sensors.List(Entities.Illuminance)).Single();
                Check((await access.Describe(sensor)).Name == "ABI light", "native device metadata name");
                Check(runtime.CurrentReads == 0 && runtime.Registrations == 0, "light metadata does not measure");
                runtime.Value = 250.5;Check((await access.Get(sensor)).Value == 250.5, "native float lux decoded");
                await TestCompletion.Until(() => runtime.HandlerCount == 0, "one-shot native light handler removed");
                await using var watch = access.Watch(sensor).GetAsyncEnumerator();
                Check(await watch.MoveNextAsync() && watch.Current.Value == 250.5, "native current light sample");
                runtime.Value = 0;runtime.Fire();runtime.Fire();
                Check(await watch.MoveNextAsync() && watch.Current.Value == 0, "zero lux retained");
                Check(await watch.MoveNextAsync() && watch.Current.Value == 0, "equal native event retained");
            }
            await TestCompletion.Until(() => runtime.HandlerCount == 0, "native sensor handlers removed before context close");
            access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
            Check(runtime.Registrations == 2 && runtime.Removals == 2 && runtime.Initializations == 1 && runtime.Uninitializations == 1,
                "get and watch have independent balanced native event leases");
            Check(runtime.IntervalWrites.Count == 0, "platform-default queries preserve driver default interval");
        }
    }

    private static async Task GyroscopeAbi()
    {
        var runtime = new RuntimeFixture(EntityKind.Gyroscope) {Value = 180, Y = -90, Z = 0};
        using var access = new DeviceAccess(new WindowsCollector(sensorPlatform: new WindowsSensorPlatform(runtime)));
        var target = (await access.Sensors.List(Entities.Gyroscope)).Single();
        var description = await access.Describe(target);
        Check(description.Kind == SensorKind.Gyroscope && description.Name == "ABI gyroscope" && description.MinimumInterval == TimeSpan.FromMilliseconds(20), "native gyroscope metadata");
        Check(runtime.CurrentReads == 0 && runtime.Registrations == 0, "discovery and metadata do not acquire measurements");
        var value = (await access.Get(target)).Value;
        Check(value is { } v && Math.Abs(v.X - 3.141592653589793) < 1e-12 && Math.Abs(v.Y + 1.5707963267948966) < 1e-12 && v.Z == 0,
            "native degrees/second become radians/second with signed native axes");
        await TestCompletion.Until(() => runtime.HandlerCount == 0, "one-shot gyroscope listener released");
        await using var watch = access.Watch(target).GetAsyncEnumerator();
        Check(await watch.MoveNextAsync() && watch.Current.Value == value, "initial native gyroscope reading");
        runtime.Value = 0;runtime.Y = 0;runtime.Z = -360;runtime.Fire();runtime.Fire();
        Check(await watch.MoveNextAsync() && watch.Current.Value is { } eventValue && eventValue.X == 0 && eventValue.Y == 0 && Math.Abs(eventValue.Z + 6.283185307179586) < 1e-12,
            "negative Z event retains native orientation");
        var previous = watch.Current;
        Check(await watch.MoveNextAsync() && watch.Current.Value == previous.Value && watch.Current.CollectedAt >= previous.CollectedAt, "equal native vector events are retained");
        runtime.Y = double.NaN;runtime.Fire();
        Check(await watch.MoveNextAsync() && watch.Current.Value is null, "one invalid component makes the entire vector null");
        runtime.Value = 90;runtime.Y = 0;runtime.Z = 0;runtime.Fire();
        Check(await watch.MoveNextAsync() && watch.Current.Value is { } recovered && Math.Abs(recovered.X - 1.5707963267948966) < 1e-12,
            "a later valid native reading recovers without resubscription");
        await watch.DisposeAsync();access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(runtime.Registrations == 2 && runtime.Removals == 2 && runtime.IntervalWrites.Count == 0, "native vector leases balance without changing default cadence");
    }

    private static async Task MagnetometerAbi()
    {
        var runtime = new RuntimeFixture(EntityKind.Magnetometer) {Value = 12.5, Y = -25.25, Z = 50.75};
        using var access = new DeviceAccess(new WindowsCollector(sensorPlatform: new WindowsSensorPlatform(runtime)));
        var target = (await access.Sensors.List(Entities.Magnetometer)).Single();
        Check((await access.Describe(target)).Kind == SensorKind.Magnetometer && (await access.Capabilities.Get(target)).Readable == true,
            "native magnetometer metadata and capabilities");
        Check(runtime.Registrations == 0 && runtime.CurrentReads == 0, "support queries do not measure");
        Check((await access.Get(target)).Value == new Vector3(12.5, -25.25, 50.75), "float microtesla values retain signs and units");
        await TestCompletion.Until(() => runtime.HandlerCount == 0, "one-shot magnetometer released");
        await using var watch = access.WithSensorSamplingRate(SensorSamplingRate.AtHertz(25)).Watch(target).GetAsyncEnumerator();
        Check(await watch.MoveNextAsync() && runtime.Interval == 40, "configured native magnetic sample interval");
        runtime.Value = 0;runtime.Y = -1;runtime.Z = 2;runtime.Fire();runtime.Fire();
        Check(await watch.MoveNextAsync() && watch.Current.Value == new Vector3(0, -1, 2), "magnetic event keeps all three components");
        Check(await watch.MoveNextAsync() && watch.Current.Value == new Vector3(0, -1, 2), "equal magnetic events are not removed");
        runtime.Z = double.PositiveInfinity;runtime.Fire();
        Check(await watch.MoveNextAsync() && watch.Current.Value is null, "nonfinite native magnetic component invalidates the vector");
        await watch.DisposeAsync();access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(runtime.Registrations == 2 && runtime.Removals == 2 && runtime.IntervalWrites.SequenceEqual(new uint[] {40, 100}),
            "magnetic subscriptions release and restore the original interval");
    }

    private static async Task AccelerometerAbi()
    {
        var runtime = new RuntimeFixture(EntityKind.Accelerometer) {Value = -0.25, Y = 0.5, Z = -1};
        using var access = new DeviceAccess(new WindowsCollector(sensorPlatform: new WindowsSensorPlatform(runtime)));
        var target = (await access.Sensors.List(Entities.Accelerometer)).Single();
        var description = await access.Describe(target);
        Check(description.Kind == SensorKind.Accelerometer && description.Name == "ABI acceleration" && runtime.SelectorReadingTypes.SequenceEqual(new[] {0}),
            "standard acceleration selector and metadata are distinct from linear and gravity");
        Check(runtime.CurrentReads == 0 && runtime.Registrations == 0, "accelerometer discovery and description stay passive");
        var sample = (await access.Get(target)).Value;
        Check(sample is { } v && Math.Abs(v.X - 2.4516625) < 1e-12 && Math.Abs(v.Y + 4.903325) < 1e-12 && Math.Abs(v.Z - 9.80665) < 1e-12,
            "native signed G-force becomes m/s squared with the common acceleration sign");
        await TestCompletion.Until(() => runtime.HandlerCount == 0, "one-shot acceleration listener released");
        runtime.Value = 0;runtime.Y = 0;runtime.Z = -1;
        await using var watch = access.WithSensorSamplingRate(SensorSamplingRate.AtHertz(25)).Watch(target).GetAsyncEnumerator();
        Check(await watch.MoveNextAsync() && watch.Current.Value == new Vector3(0, 0, 9.80665) && runtime.Interval == 40,
            "face-up stationary native sample agrees with the common positive-Z gravity contribution");
        runtime.Z = 0;runtime.Fire();runtime.Fire();
        Check(await watch.MoveNextAsync() && watch.Current.Value == new Vector3(0, 0, 0), "zero G free-fall sample is retained");
        Check(await watch.MoveNextAsync() && watch.Current.Value == new Vector3(0, 0, 0), "equal native acceleration events are retained");
        await watch.DisposeAsync();access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(runtime.Registrations == 2 && runtime.Removals == 2 && runtime.IntervalWrites.SequenceEqual(new uint[] {40, 100}),
            "acceleration leases restore the native report interval and release every reference");
    }

    private static async Task AccelerationFamilies()
    {
        await Verify(Entities.LinearAcceleration, snapshot => snapshot.Value, EntityKind.LinearAcceleration, SensorKind.LinearAcceleration, 1, 0);
        await Verify(Entities.Gravity, snapshot => snapshot.Value, EntityKind.Gravity, SensorKind.Gravity, 2, -1);
        static async Task Verify<T>(Entity<T> kind, Func<T, Vector3?> value, EntityKind nativeKind, SensorKind sensorKind, int readingType, double nativeZ) where T : DeviceSnapshot
        {
            var runtime = new RuntimeFixture(nativeKind) {Value = 0, Y = 0, Z = nativeZ};
            using var access = new DeviceAccess(new WindowsCollector(sensorPlatform: new WindowsSensorPlatform(runtime)));
            var target = (await access.Sensors.List(kind)).Single();
            Check((await access.Describe(target)).Kind == sensorKind && runtime.SelectorReadingTypes.SequenceEqual(new[] {readingType}),
                "native selector preserves the requested measurement kind");
            Check(runtime.Registrations == 0 && runtime.CurrentReads == 0, "linear/gravity metadata stays passive");
            Check(value(await access.Get(target)) == (nativeKind == EntityKind.Gravity ? new Vector3(0, 0, 9.80665) : new Vector3(0, 0, 0)),
                "native stationary gravity and linear acceleration remain distinct measurements");
            await TestCompletion.Until(() => runtime.HandlerCount == 0, "one-shot family listener released");
            await using var watch = access.Watch(target).GetAsyncEnumerator();
            Check(await watch.MoveNextAsync(), "initial family sample");
            runtime.Value = -0.6;runtime.Y = 0.8;runtime.Z = 0;runtime.Fire();runtime.Fire();
            Check(await watch.MoveNextAsync() && value(watch.Current) is { } v && Math.Abs(v.X - 5.88399) < 1e-12 && Math.Abs(v.Y + 7.84532) < 1e-12 && v.Z == 0,
                "selected native family supplies signed three-axis samples in m/s squared");
            var previous = value(watch.Current);
            Check(await watch.MoveNextAsync() && value(watch.Current) == previous, "equal native family events are retained");
            await watch.DisposeAsync();access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
            Check(runtime.Registrations == 2 && runtime.Removals == 2 && runtime.IntervalWrites.Count == 0, "native family lifetime keeps driver defaults");
        }
    }

    private static async Task AccelerationTypeValidation()
    {
        await Verify(Entities.Accelerometer, EntityKind.Accelerometer, 0);
        await Verify(Entities.LinearAcceleration, EntityKind.LinearAcceleration, 1);
        await Verify(Entities.Gravity, EntityKind.Gravity, 2);
        static async Task Verify<T>(Entity<T> kind, EntityKind nativeKind, int expectedType) where T : DeviceSnapshot
        {
            var runtime = new RuntimeFixture(nativeKind);
            using var access = new DeviceAccess(new WindowsCollector(sensorPlatform: new WindowsSensorPlatform(runtime)));
            var target = (await access.Sensors.List(kind)).Single();
            runtime.ReadingType = (expectedType + 1) % 3;
            await Removed(() => access.Get(target));
            Check(runtime.CurrentReads == 0 && runtime.Registrations == 0, "wrong native type is rejected before subscribing or reading");
            runtime.ReadingType = expectedType;
            await Removed(() => access.Get(target));
            var replacement = (await access.Sensors.List(kind)).Single();
            Check(replacement != target, "mismatched target remains retired after native recovery");
            _ = await access.Describe(replacement);_ = await access.Get(replacement);
            await TestCompletion.Until(() => runtime.HandlerCount == 0, "replacement native listener released");
            Check(runtime.CurrentReads == 1, "new handle reads the correct native kind");
            runtime.ReadingType = 99;
            await Removed(() => access.Describe(replacement));
            Check(runtime.CurrentReads == 1, "unknown native kind cannot be described as a known sensor");
            access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
        }
        static async Task Removed(Func<Task> read)
        {
            try {await read();throw new Exception("Expected EntityRemoved for a different native reading kind.");}
            catch (DeviceReadoutException error) when (error.Code == ErrorCode.EntityRemoved) { }
        }
    }

    private static async Task AccelerationLifecycle()
    {
        var runtime = new RuntimeFixture(EntityKind.Accelerometer) {Value = 0, Y = 0, Z = -1};
        using var access = new DeviceAccess(new WindowsCollector(sensorPlatform: new WindowsSensorPlatform(runtime)));
        var requests = 0;using var coordinator = access.Observers.OnPermissionRequest((_, _) => {requests++;return Task.CompletedTask;});
        var target = (await access.Sensors.List(Entities.Accelerometer)).Single();
        using var permissionFailure = access.Observers.FailureSource(target);
        var configured = access.WithReadTimeout(TimeSpan.FromMilliseconds(150)).WithSensorSamplingRate(SensorSamplingRate.AtHertz(60));
        await using var watch = configured.Watch(target).GetAsyncEnumerator();
        Check(await watch.MoveNextAsync() && watch.Current.Value == new Vector3(0, 0, 9.80665) && runtime.Interval == 20, "initial native acceleration session");
        access.Observers.SensorActivity(false);
        await TestCompletion.Until(() => runtime.HandlerCount == 0 && runtime.Interval == 100, "inactivity releases native listener and restores report interval");
        var pending = watch.MoveNextAsync().AsTask();
        await Task.Delay(200);
        Check(!pending.IsCompleted && runtime.Registrations == 1, "inactive native session neither polls nor expires its initial-sample deadline");
        runtime.Value = -1;runtime.Z = 0;access.Observers.SensorActivity(true);
        Check(await pending.WaitAsync(TimeSpan.FromSeconds(1)) && watch.Current.Value == new Vector3(9.80665, 0, 0), "resumption reads a fresh native sample");
        Check(runtime.Registrations == 2 && runtime.Interval == 20, "resumption keeps the immutable sampling request");
        var denied = watch.MoveNextAsync().AsTask();access.Observers.Permission(target, PermissionStatus.Denied);
        // Permission status and a failure that blocks collection are separate observer inputs.
        permissionFailure.Publish(new(ErrorCode.PermissionDenied, "Application permission observer reports blocked sensor collection."));
        try {await denied.WaitAsync(TimeSpan.FromSeconds(1));throw new Exception("Expected permission failure.");}
        catch (DeviceReadoutException error) when (error.Code == ErrorCode.PermissionDenied) { }
        await TestCompletion.Until(() => runtime.HandlerCount == 0 && runtime.Interval == 100, "observed permission loss releases the native sensor");
        var reads = runtime.CurrentReads;
        try {await access.Get(target);throw new Exception("Expected permission failure.");}
        catch (DeviceReadoutException error) when (error.Code == ErrorCode.PermissionDenied) { }
        Check(runtime.CurrentReads == reads && requests == 0, "ordinary denied reads perform no native measurement or permission UI coordination");
        access.Observers.Permission(target, PermissionStatus.Granted);
        permissionFailure.Publish(null);
        Check((await access.Get(target)).Value == new Vector3(9.80665, 0, 0), "explicit observed permission recovery permits a fresh request");
        await watch.DisposeAsync();access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(runtime.Registrations == 3 && runtime.Removals == 3, "native activity, error and one-shot sessions release independently");
    }

    private static async Task AbsoluteOrientationAbi()
    {
        var runtime = new RuntimeFixture(EntityKind.AbsoluteOrientation) {Value = 0, Y = 0, Z = 2, W = 2};
        using var access = new DeviceAccess(new WindowsCollector(sensorPlatform: new WindowsSensorPlatform(runtime)));
        var target = (await access.Sensors.List(Entities.AbsoluteOrientation)).Single();
        var description = await access.Describe(target);
        Check(description.Kind == SensorKind.AbsoluteOrientation && description.Name == "ABI orientation" && description.MinimumInterval == TimeSpan.FromMilliseconds(20), "native absolute orientation metadata");
        Check(runtime.SelectorReadingTypes.SequenceEqual(new[] {0}) && runtime.CurrentReads == 0 && runtime.Registrations == 0, "absolute selector and passive metadata");
        var sample = (await access.Get(target)).Value;
        Check(sample is {X: 0, Y: 0} q && Math.Abs(q.Z - 0.7071067811865476) < 1e-7 && Math.Abs(q.W - 0.7071067811865476) < 1e-7,
            "WinRT W/X/Y/Z getters produce named X/Y/Z/W unit quaternion");
        // MAUI's documented example: face up with top west rotates device +Y to world -X.
        var west = System.Numerics.Vector3.Transform(System.Numerics.Vector3.UnitY,
            new System.Numerics.Quaternion((float)sample!.Value.X, (float)sample.Value.Y, (float)sample.Value.Z, (float)sample.Value.W));
        Check(System.Numerics.Vector3.Distance(west, new(-1, 0, 0)) < 1e-6, "device-to-reference direction is not conjugated");
        await TestCompletion.Until(() => runtime.HandlerCount == 0, "one-shot orientation listener released");
        await using var watch = access.WithSensorSamplingRate(SensorSamplingRate.AtHertz(25)).Watch(target).GetAsyncEnumerator();
        Check(await watch.MoveNextAsync() && watch.Current.Value == sample && runtime.Interval == 40, "native initial orientation and requested cadence");
        runtime.Value = 0;runtime.Y = -1;runtime.Z = 0;runtime.W = 1;runtime.Fire();runtime.Fire();
        Check(await watch.MoveNextAsync() && watch.Current.Value is {X: 0, Z: 0} side && Math.Abs(side.Y + 0.7071067811865476) < 1e-7 && Math.Abs(side.W - 0.7071067811865476) < 1e-7,
            "left-edge-down orientation preserves signed Y rotation");
        var previous = watch.Current;
        Check(await watch.MoveNextAsync() && watch.Current.Value == previous.Value && watch.Current.CollectedAt >= previous.CollectedAt, "equal native quaternion events are retained");
        runtime.Value = 1;runtime.Y = 0;runtime.Z = 0;runtime.W = 1;runtime.Fire();
        Check(await watch.MoveNextAsync() && watch.Current.Value is {Y: 0, Z: 0} upright && Math.Abs(upright.X - 0.7071067811865476) < 1e-7, "upright example preserves positive X rotation");
        runtime.Value = 0;runtime.W = 1;runtime.Fire();
        Check(await watch.MoveNextAsync() && watch.Current.Value == new Quaternion(0, 0, 0, 1), "face-up north identity is retained");
        await watch.DisposeAsync();access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(runtime.Registrations == 2 && runtime.Removals == 2 && runtime.QuaternionReads == 6 && runtime.IntervalWrites.SequenceEqual(new uint[] {40, 100}),
            "one quaternion object per sample with balanced references and restored native interval");
    }

    private static async Task RelativeOrientationAbi()
    {
        var runtime = new RuntimeFixture(EntityKind.RelativeOrientation) {Value = 1, Y = 2, Z = 3, W = 4};
        using var access = new DeviceAccess(new WindowsCollector(sensorPlatform: new WindowsSensorPlatform(runtime)));
        var target = (await access.Sensors.List(Entities.RelativeOrientation)).Single();
        Check((await access.Describe(target)).Kind == SensorKind.RelativeOrientation && runtime.SelectorReadingTypes.SequenceEqual(new[] {1}), "relative selector and kind remain distinct from absolute orientation");
        Check(runtime.CurrentReads == 0 && runtime.Registrations == 0, "relative metadata does not establish a measurement session");
        var sample = (await access.Get(target)).Value;
        Check(sample is { } q && Math.Abs(q.X - 0.18257418583505536) < 1e-7 && Math.Abs(q.Y - 0.3651483716701107) < 1e-7 && Math.Abs(q.Z - 0.5477225575051661) < 1e-7 && Math.Abs(q.W - 0.7302967433402214) < 1e-7,
            "relative sample preserves the native baseline and every named component");
        await TestCompletion.Until(() => runtime.HandlerCount == 0, "one-shot relative listener released");
        await using var watch = access.WithReadTimeout(TimeSpan.FromMilliseconds(150)).Watch(target).GetAsyncEnumerator();
        Check(await watch.MoveNextAsync() && watch.Current.Value == sample, "initial relative sample is not rebased to identity by the SDK");
        access.Observers.SensorActivity(false);
        await TestCompletion.Until(() => runtime.HandlerCount == 0, "observed inactivity releases the relative orientation session");
        var pending = watch.MoveNextAsync().AsTask();await Task.Delay(200);
        Check(!pending.IsCompleted && runtime.Registrations == 2, "inactive relative watch waits without sampling or expiring");
        runtime.Value = 0;runtime.Y = 0;runtime.Z = 1;runtime.W = 0;access.Observers.SensorActivity(true);
        Check(await pending.WaitAsync(TimeSpan.FromSeconds(1)) && watch.Current.Value == new Quaternion(0, 0, 1, 0), "resumed session uses the new native reference without carrying an old offset");
        runtime.Fire();runtime.Fire();
        Check(await watch.MoveNextAsync() && watch.Current.Value == new Quaternion(0, 0, 1, 0), "relative native event");
        Check(await watch.MoveNextAsync() && watch.Current.Value == new Quaternion(0, 0, 1, 0), "equal relative events are retained");
        await watch.DisposeAsync();access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(runtime.Registrations == 3 && runtime.Removals == 3 && runtime.IntervalWrites.Count == 0, "relative sessions balance without changing driver defaults");
    }

    private static async Task OrientationTypeValidation()
    {
        await Verify(Entities.AbsoluteOrientation, EntityKind.AbsoluteOrientation, 0);
        await Verify(Entities.RelativeOrientation, EntityKind.RelativeOrientation, 1);
        static async Task Verify<T>(Entity<T> kind, EntityKind nativeKind, int expected) where T : DeviceSnapshot
        {
            var runtime = new RuntimeFixture(nativeKind);
            using var access = new DeviceAccess(new WindowsCollector(sensorPlatform: new WindowsSensorPlatform(runtime)));
            var target = (await access.Sensors.List(kind)).Single();
            runtime.ReadingType = 1 - expected;
            await Removed(() => access.Get(target));
            Check(runtime.CurrentReads == 0 && runtime.Registrations == 0, "wrong reference kind is rejected before measurements");
            runtime.ReadingType = expected;
            await Removed(() => access.Get(target));
            var replacement = (await access.Sensors.List(kind)).Single();
            Check(replacement != target, "reference mismatch permanently retires the old target");
            _ = await access.Get(replacement);
            await TestCompletion.Until(() => runtime.HandlerCount == 0, "replacement orientation listener released");
            runtime.ReadingType = 99;
            await Removed(() => access.Describe(replacement));
            Check(runtime.CurrentReads == 1, "unknown reference kind cannot masquerade as a known orientation");
            access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
        }
        static async Task Removed(Func<Task> operation)
        {
            try {await operation();throw new Exception("Expected EntityRemoved for a changed orientation reference kind.");}
            catch (DeviceReadoutException error) when (error.Code == ErrorCode.EntityRemoved) { }
        }
    }

    private static async Task OrientationPropertyFailures()
    {
        await Verify(Entities.AbsoluteOrientation, snapshot => snapshot.Value, EntityKind.AbsoluteOrientation);
        await Verify(Entities.RelativeOrientation, snapshot => snapshot.Value, EntityKind.RelativeOrientation);
        static async Task Verify<T>(Entity<T> kind, Func<T, Quaternion?> value, EntityKind nativeKind) where T : DeviceSnapshot
        {
            var runtime = new RuntimeFixture(nativeKind) {Value = 0, Y = 0, Z = 0, W = 1};
            using var access = new DeviceAccess(new WindowsCollector(sensorPlatform: new WindowsSensorPlatform(runtime)));
            var target = (await access.Sensors.List(kind)).Single();
            await using var watch = access.Watch(target).GetAsyncEnumerator();
            Check(await watch.MoveNextAsync() && value(watch.Current) == new Quaternion(0, 0, 0, 1), "initial complete rotation");
            for (var component = 1; component <= 4; component++) {
                runtime.AxisFailure = component;runtime.Fire();
                Check(await watch.MoveNextAsync() && value(watch.Current) is null, "unreadable component invalidates the entire quaternion");
                runtime.AxisFailure = 0;runtime.Fire();
                Check(await watch.MoveNextAsync() && value(watch.Current) == new Quaternion(0, 0, 0, 1), "next complete quaternion recovers");
            }
            foreach (var invalid in new[] {0d, double.NaN, double.PositiveInfinity}) {
                runtime.W = invalid;runtime.Fire();
                Check(await watch.MoveNextAsync() && value(watch.Current) is null, "zero norm and nonfinite quaternion are unavailable values");
            }
            runtime.W = 1;runtime.QuaternionFailure = true;runtime.Fire();
            Check(await watch.MoveNextAsync() && value(watch.Current) is null, "unreadable quaternion property is a nullable measurement");
            runtime.QuaternionFailure = false;runtime.MissingQuaternion = true;
            Check(value(await access.Get(target)) is null, "one-shot reading without a quaternion returns null");
            runtime.MissingQuaternion = false;runtime.Fire();
            Check(await watch.MoveNextAsync() && value(watch.Current) == new Quaternion(0, 0, 0, 1), "watch recovers after native property failures");
            await watch.DisposeAsync();access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
            Check(runtime.Registrations == 2 && runtime.Removals == 2, "invalid fields do not restart the watch and all native references are released");
        }
    }

    private static async Task HingeAngleAbi()
    {
        var runtime = new RuntimeFixture(EntityKind.HingeAngle) {Value = 180};
        using var access = new DeviceAccess(new WindowsCollector(sensorPlatform: new WindowsSensorPlatform(runtime)));
        var target = (await access.Sensors.List(Entities.HingeAngle)).Single();
        var description = await access.Describe(target);
        Check(description.Kind == SensorKind.HingeAngle && description.Name == "ABI hinge" && description.MinimumInterval is null && description.Resolution is null,
            "hinge angle threshold is not mislabeled as a time interval or resolution");
        Check(runtime.CurrentReads == 0 && runtime.Registrations == 0 && runtime.ThresholdCalls == 0, "hinge discovery and description stay passive");
        Check((await access.Get(target)).Value is { } radians && Math.Abs(radians - 3.141592653589793) < 1e-12, "native double degrees become radians");
        await TestCompletion.Until(() => runtime.HandlerCount == 0, "one-shot hinge listener released");
        await using var watch = access.WithSensorSamplingRate(SensorSamplingRate.AtHertz(50)).Watch(target).GetAsyncEnumerator();
        Check(await watch.MoveNextAsync() && watch.Current.Value is { } initial && Math.Abs(initial - 3.141592653589793) < 1e-12, "watch obtains its initial value from the native asynchronous operation");
        runtime.Value = 0;runtime.Fire();runtime.Fire();
        Check(await watch.MoveNextAsync() && watch.Current.Value == 0, "closed hinge zero angle retained");
        Check(await watch.MoveNextAsync() && watch.Current.Value == 0, "equal native hinge events retained");
        runtime.Value = 360;runtime.Fire();
        Check(await watch.MoveNextAsync() && watch.Current.Value is { } full && Math.Abs(full - 6.283185307179586) < 1e-12, "full native turn is not wrapped to zero");
        runtime.AxisFailure = 1;runtime.Fire();
        Check(await watch.MoveNextAsync() && watch.Current.Value is null, "failed angle property is null without ending the stream");
        runtime.AxisFailure = 0;runtime.Value = double.NaN;runtime.Fire();
        Check(await watch.MoveNextAsync() && watch.Current.Value is null, "nonfinite angle is unavailable");
        runtime.Value = 90;runtime.Fire();
        Check(await watch.MoveNextAsync() && watch.Current.Value is { } recovered && Math.Abs(recovered - 1.5707963267948966) < 1e-12, "later complete angle recovers without resubscription");
        await watch.DisposeAsync();access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(runtime.ReadingResults == 2 && runtime.ReadingClosed == 2 && runtime.Registrations == 2 && runtime.Removals == 2 && runtime.ThresholdCalls == 0,
            "initial read operations and listeners balance without reading or modifying native angle thresholds");
    }

    private static async Task HingeInitialEvent()
    {
        var runtime = new RuntimeFixture(EntityKind.HingeAngle) {Value = 90, HoldReading = true};
        using var access = new DeviceAccess(new WindowsCollector(sensorPlatform: new WindowsSensorPlatform(runtime)));
        var target = (await access.Sensors.List(Entities.HingeAngle)).Single();
        var pending = access.WithReadTimeout(TimeSpan.FromMilliseconds(250)).Get(target);
        await runtime.ReadingStarted.Task.WaitAsync(TimeSpan.FromSeconds(2));
        runtime.Value = 180;runtime.Fire();
        var sample = await pending.WaitAsync(TimeSpan.FromSeconds(1));
        Check(sample.Value is { } radians && Math.Abs(radians - 3.141592653589793) < 1e-12 && runtime.HoldReading,
            "an actual native event supplies the first value without waiting for initial operation completion");
        await TestCompletion.Until(() => runtime.HandlerCount == 0 && runtime.ReadingClosed == 1, "superseded initial operation and one-shot listener released");
        Check(runtime.ReadingCanceled == 1 && runtime.ReadingResults == 0, "unused pending operation is canceled without consuming a stale result");
        runtime.HoldReading = false;runtime.Value = 45;
        Check((await access.Get(target)).Value is { } recovered && Math.Abs(recovered - 0.7853981633974483) < 1e-12, "subsequent initial native read still works");
        access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
    }

    private static async Task HingeInitialDeadlines()
    {
        foreach (var stream in new[] {false, true}) foreach (var cancel in new[] {false, true}) {
            var runtime = new RuntimeFixture(EntityKind.HingeAngle) {Value = 90, HoldReading = true};
            using var access = new DeviceAccess(new WindowsCollector(sensorPlatform: new WindowsSensorPlatform(runtime)));
            var target = (await access.Sensors.List(Entities.HingeAngle)).Single();
            using var cancellation = new CancellationTokenSource();
            var bounded = access.WithReadTimeout(TimeSpan.FromMilliseconds(150));
            await using var watch = bounded.Watch(target, cancellation.Token).GetAsyncEnumerator();
            var ticks = 0;using var heartbeat = new Timer(_ => Interlocked.Increment(ref ticks), null, 0, 5);
            Task pending = stream ? watch.MoveNextAsync().AsTask() : bounded.Get(target, cancellation.Token);
            await runtime.ReadingStarted.Task.WaitAsync(TimeSpan.FromSeconds(2));
            if (cancel) cancellation.Cancel();
            try {await pending.WaitAsync(TimeSpan.FromSeconds(1));throw new Exception("Expected pending hinge read termination.");}
            catch (OperationCanceledException) when (cancel && cancellation.IsCancellationRequested) { }
            catch (DeviceReadoutException error) when (!cancel && error.Code == ErrorCode.ReadTimeout) { }
            if (!cancel) Check(Volatile.Read(ref ticks) > 2, "host timer progresses during the pending native operation");
            await TestCompletion.Until(() => runtime.ReadingCanceled == 1 && runtime.ReadingClosed == 1 && runtime.HandlerCount == 0, "terminated initial reading cancels/closes its operation and releases its listener");
            Check(runtime.ReadingResults == 0 && runtime.HoldReading, "pending native result is never consumed after termination");
            runtime.HoldReading = false;
            Check((await access.Get(target)).Value is { } radians && Math.Abs(radians - 1.5707963267948966) < 1e-12, "fresh initial read recovers after timeout or caller cancellation");
            await watch.DisposeAsync();access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
            Check(runtime.Registrations == 2 && runtime.Removals == 2 && runtime.ReadingClosed == 2, "terminated and replacement operations release independently");
        }
    }

    private static async Task HingeLateInitial()
    {
        var runtime = new RuntimeFixture(EntityKind.HingeAngle) {Value = 90, HoldFirstAxis = true};
        using var access = new DeviceAccess(new WindowsCollector(sensorPlatform: new WindowsSensorPlatform(runtime)));
        var target = (await access.Sensors.List(Entities.HingeAngle)).Single();
        await using var watch = access.Watch(target).GetAsyncEnumerator();
        var first = watch.MoveNextAsync().AsTask();
        try {
            await runtime.AxisStarted.Task.WaitAsync(TimeSpan.FromSeconds(2));
            runtime.HoldFirstAxis = false;runtime.Value = 180;runtime.Fire();
        } finally {runtime.AxisRelease.Set();}
        Check(await first.WaitAsync(TimeSpan.FromSeconds(1)) && watch.Current.Value is { } newest && Math.Abs(newest - 3.141592653589793) < 1e-12,
            "new native event supplies the initial snapshot despite the older in-flight sample");
        var next = watch.MoveNextAsync().AsTask();await Task.Delay(80);
        Check(!next.IsCompleted, "late initial value is not emitted after a newer native event");
        runtime.Value = 270;runtime.Fire();runtime.Fire();
        Check(await next.WaitAsync(TimeSpan.FromSeconds(1)) && watch.Current.Value is { } fresh && Math.Abs(fresh - 4.71238898038469) < 1e-12, "subsequent event remains live");
        var previous = watch.Current.Value;
        Check(await watch.MoveNextAsync() && watch.Current.Value == previous, "initial-read suppression does not deduplicate native events");
        await watch.DisposeAsync();access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
    }

    private static async Task VectorPropertyFailures()
    {
        await Verify(Entities.Gyroscope, snapshot => snapshot.Value, EntityKind.Gyroscope);
        await Verify(Entities.Magnetometer, snapshot => snapshot.Value, EntityKind.Magnetometer);
        await Verify(Entities.Accelerometer, snapshot => snapshot.Value, EntityKind.Accelerometer);
        await Verify(Entities.LinearAcceleration, snapshot => snapshot.Value, EntityKind.LinearAcceleration);
        await Verify(Entities.Gravity, snapshot => snapshot.Value, EntityKind.Gravity);
        static async Task Verify<T>(Entity<T> kind, Func<T, Vector3?> value, EntityKind nativeKind) where T : DeviceSnapshot
        {
            var runtime = new RuntimeFixture(nativeKind) {Value = 1, Y = -2, Z = 3};
            using var access = new DeviceAccess(new WindowsCollector(sensorPlatform: new WindowsSensorPlatform(runtime)));
            var target = (await access.Sensors.List(kind)).Single();
            await using var watch = access.Watch(target).GetAsyncEnumerator();
            Check(await watch.MoveNextAsync() && value(watch.Current) is not null, "initial complete native vector");
            var original = value(watch.Current);
            for (var axis = 1; axis <= 3; axis++) {
                runtime.AxisFailure = axis;runtime.Fire();
                Check(await watch.MoveNextAsync() && value(watch.Current) is null, "failed property invalidates the complete vector instead of terminating the watch");
                runtime.AxisFailure = 0;runtime.Fire();
                Check(await watch.MoveNextAsync() && value(watch.Current) == original, "next complete sample recovers without retained partial components");
            }
            runtime.AxisFailure = 2;
            Check(value(await access.Get(target)) is null, "one-shot incomplete vector is nullable too");
            await watch.DisposeAsync();access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
        }
    }

    private static async Task HeldVectorRead()
    {
        await Verify(Entities.Gyroscope, EntityKind.Gyroscope);
        await Verify(Entities.Magnetometer, EntityKind.Magnetometer);
        await Verify(Entities.Accelerometer, EntityKind.Accelerometer);
        await Verify(Entities.LinearAcceleration, EntityKind.LinearAcceleration);
        await Verify(Entities.Gravity, EntityKind.Gravity);
        await Verify(Entities.AbsoluteOrientation, EntityKind.AbsoluteOrientation);
        await Verify(Entities.RelativeOrientation, EntityKind.RelativeOrientation);
        await Verify(Entities.HingeAngle, EntityKind.HingeAngle);
        static async Task Verify<T>(Entity<T> kind, EntityKind nativeKind) where T : DeviceSnapshot
        {
            var runtime = new RuntimeFixture(nativeKind) {HoldFirstAxis = true};
            using var access = new DeviceAccess(new WindowsCollector(sensorPlatform: new WindowsSensorPlatform(runtime)));
            var target = (await access.Sensors.List(kind)).Single();
            var ticks = 0;using var heartbeat = new Timer(_ => Interlocked.Increment(ref ticks), null, 0, 5);
            var caller = Environment.CurrentManagedThreadId;
            try {
                var pending = access.WithReadTimeout(TimeSpan.FromMilliseconds(150)).Get(target);
                await runtime.AxisStarted.Task.WaitAsync(TimeSpan.FromSeconds(2));
                try {await pending.WaitAsync(TimeSpan.FromSeconds(1));throw new Exception("Expected native vector read timeout.");}
                catch (DeviceReadoutException error) when (error.Code == ErrorCode.ReadTimeout) { }
                Check(!runtime.AxisRelease.IsSet && Volatile.Read(ref ticks) > 2 && runtime.FirstAxisThread != caller,
                    "caller deadline and heartbeat complete while the native axis call stays on its worker");
                var before = System.Diagnostics.Stopwatch.StartNew();access.Dispose();
                Check(before.Elapsed < TimeSpan.FromMilliseconds(500) && !runtime.Stopped.Task.IsCompleted, "context disposal does not join the held native axis call");
            } finally {runtime.AxisRelease.Set();access.Dispose();}
            await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
            Check(runtime.AxisReads[0] == 1 && runtime.AxisReads.Skip(1).All(count => count == 0),
                "late canceled reading releases its reference without querying the remaining native axes");
            Check(runtime.Registrations == 1 && runtime.Removals == 1, "late canceled registration releases its native listener");
        }
    }

    private static async Task SamplingOwnership()
    {
        var runtime = new RuntimeFixture();
        using var access = new DeviceAccess(new WindowsCollector(sensorPlatform: new WindowsSensorPlatform(runtime)));
        var target = (await access.Sensors.List(Entities.Illuminance)).Single();
        await using var slow = access.WithSensorSamplingRate(SensorSamplingRate.AtHertz(25)).Watch(target).GetAsyncEnumerator();
        Check(await slow.MoveNextAsync() && runtime.Interval == 40, "25 Hz request uses 40 milliseconds");
        var fastAccess = access.WithSensorSamplingRate(SensorSamplingRate.AtHertz(100));
        Check(runtime.Interval == 40, "creating configuration does not change an existing native request");
        await using var fast = fastAccess.Watch(target).GetAsyncEnumerator();
        Check(await fast.MoveNextAsync() && runtime.Interval == 20 && runtime.HandlerCount == 2, "fastest request respects 20ms device minimum");
        Check((await access.Get(target)).Value == 250, "default one-shot coexists with configured watches");
        await TestCompletion.Until(() => runtime.HandlerCount == 2, "one-shot handler removed");
        Check(runtime.Interval == 20, "default one-shot cleanup preserves the faster watch");
        await fast.DisposeAsync();await TestCompletion.Until(() => runtime.HandlerCount == 1 && runtime.Interval == 40, "fast watch release restores surviving request");
        runtime.Value = 99;runtime.Fire();Check(await slow.MoveNextAsync() && slow.Current.Value == 99, "surviving watch still receives actual samples");
        await slow.DisposeAsync();await TestCompletion.Until(() => runtime.HandlerCount == 0 && runtime.Interval == 100, "last release restores original driver configuration");
        Check(runtime.IntervalWrites.SequenceEqual(new uint[] {40, 20, 40, 100}), "only requested interval transitions occur");
        access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
    }
    private static async Task DiscoveryDeadline(bool capabilities)
    {
        var runtime = new RuntimeFixture {HoldEnumeration = true};
        using var access = new DeviceAccess(new WindowsCollector(sensorPlatform: new WindowsSensorPlatform(runtime)));
        var ticks = 0;using var heartbeat = new Timer(_ => Interlocked.Increment(ref ticks), null, 0, 5);
        var bounded = access.WithReadTimeout(TimeSpan.FromMilliseconds(100));
        Task pending = capabilities ? bounded.Capabilities.Get(Entities.Illuminance) : bounded.Sensors.List(Entities.Illuminance);
        await runtime.EnumerationStarted.Task.WaitAsync(TimeSpan.FromSeconds(1));
        try {await pending;throw new Exception("Expected native discovery timeout.");}
        catch (DeviceReadoutException error) when (error.Code == ErrorCode.ReadTimeout) { }
        Check(Volatile.Read(ref ticks) > 2, "host progresses while native async discovery is pending");
        try {await TestCompletion.Until(() => runtime.CanceledOperations == 1 && runtime.ClosedOperations == 1, "timed-out native operation canceled and closed");}
        finally {runtime.HoldEnumeration = false;}
        Check(runtime.EnumerationResults == 0, "no late result is consumed after timeout");
        runtime.HoldEnumeration = false;
        Check((await access.Sensors.List(Entities.Illuminance)).Length == 1 && runtime.EnumerationResults == 1, "fresh enumeration recovers");
        access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
    }

    // Vtable shapes, types, slots and event IIDs are from Windows SDK 10.0.26100.0 headers.
    private sealed class RuntimeFixture : IWindowsSensorRuntime
    {
        private readonly Dictionary<nint, int> references = [];
        private readonly List<nint> allocations = [];
        private readonly List<Delegate> delegates = [];
        private readonly Dictionary<long, nint> handlers = [];
        private readonly object gate = new();
        private readonly bool pressure;
        private readonly bool acceleration;
        private readonly bool orientation;
        private readonly bool hinge;
        private readonly EntityKind kind;
        private readonly nint factory, enumeration, collection, information, sensor, reading, args;
        private long nextToken;
        internal double Value = 250;
        internal double Y, Z;
        internal double W = 1;
        internal int QuaternionReads;
        internal int ThresholdCalls, ReadingResults, ReadingClosed;
        internal int ReadingCanceled;
        internal volatile bool HoldReading;
        internal readonly TaskCompletionSource ReadingStarted = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal bool QuaternionFailure, MissingQuaternion;
        internal int AxisFailure;
        internal int ReadingType;
        internal volatile bool HoldFirstAxis;
        internal int FirstAxisThread;
        internal readonly int[] AxisReads = new int[4];
        internal readonly TaskCompletionSource AxisStarted = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly ManualResetEventSlim AxisRelease = new(false);
        internal uint Interval = 100;
        internal int Initializations, Uninitializations, Registrations, Removals, CurrentReads;
        internal volatile bool HoldEnumeration;
        internal int CanceledOperations, ClosedOperations, EnumerationResults;
        internal readonly TaskCompletionSource EnumerationStarted = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly List<uint> IntervalWrites = [];
        internal readonly List<int> SelectorReadingTypes = [];
        internal readonly TaskCompletionSource Stopped = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal int HandlerCount {get {lock (gate) return handlers.Count;}}
        internal RuntimeFixture(EntityKind kind = EntityKind.Illuminance)
        {
            this.kind = kind;pressure = kind == EntityKind.Pressure;acceleration = kind is EntityKind.Accelerometer or EntityKind.LinearAcceleration or EntityKind.Gravity;
            orientation = kind is EntityKind.AbsoluteOrientation or EntityKind.RelativeOrientation;
            hinge = kind == EntityKind.HingeAngle;
            ReadingType = kind switch {EntityKind.LinearAcceleration or EntityKind.RelativeOrientation => 1, EntityKind.Gravity => 2, _ => 0};
            factory = Object(hinge ? 10 : orientation ? 9 : 8);enumeration = Object(11);collection = Object(8);information = Object(8);
            sensor = Object(pressure || hinge ? 13 : 12);reading = Object(orientation ? 9 : acceleration || kind is EntityKind.Gyroscope or EntityKind.Magnetometer ? 10 : 8);args = Object(7);
            if (acceleration || orientation) {
                var typedSensor = Object(orientation ? 9 : 7);
                Set(sensor, 0, new Query((nint self, in Guid iid, out nint value) => {
                    value = iid == new Guid(orientation ? "0d924cf9-2f1f-49c9-8042-4a1813d67760" : "1d373c4f-42d3-45b2-8144-ab7fb665eb59") ? Take(typedSensor) : 0;
                    return value == 0 ? unchecked((int)0x80004002) : 0;
                }));
                Set(typedSensor, orientation ? 8 : 6, new WinRtGetInt32((nint self, out int value) => {value = ReadingType;return 0;}));
            }
            if (acceleration || orientation) Set(factory, orientation ? 6 : 7, new SensorSelectorByType((nint self, int readingType, out nint value) => {
                SelectorReadingTypes.Add(readingType);value = Text("typed sensor selector");return 0;
            }));
            else Set(factory, pressure ? 7 : 6, new WinRtGetInterface((nint self, out nint value) => {value = Text("sensor selector");return 0;}));
            Set(factory, hinge ? 9 : orientation ? 8 : pressure || acceleration ? 6 : 7, new SensorStringCall((nint self, nint id, out nint operation) => {operation = Operation(sensor);return 0;}));
            Set(enumeration, 10, new SensorStringCall((nint self, nint selector, out nint operation) => {operation = Operation(collection, isEnumeration: true);return 0;}));
            Set(collection, 7, new SensorGetUInt((nint self, out uint size) => {size = 1;return 0;}));
            Set(collection, 6, new SensorGetAt((nint self, uint index, out nint item) => {item = Take(information);return index == 0 ? 0 : unchecked((int)0x8000000b);}));
            Set(information, 6, new WinRtGetInterface((nint self, out nint id) => {id = Text("abi-sensor");return 0;}));
            Set(information, 7, new WinRtGetInterface((nint self, out nint name) => {name = Text(hinge ? "ABI hinge" : orientation ? "ABI orientation" : acceleration ? "ABI acceleration" : kind == EntityKind.Magnetometer ? "ABI magnetometer" : kind == EntityKind.Gyroscope ? "ABI gyroscope" : pressure ? "ABI pressure" : "ABI light");return 0;}));
            Set(sensor, 6, new WinRtGetInterface((nint self, out nint value) => {CurrentReads++;value = hinge ? Operation(reading, isReading: true) : Take(reading);return 0;}));
            if (hinge) {
                Set(sensor, 7, new WinRtGetInterface((nint self, out nint value) => {value = Text("abi-sensor");return 0;}));
                Set(sensor, 8, new SensorGetDouble((nint self, out double value) => {ThresholdCalls++;value = 0.1;return 0;}));
                Set(sensor, 9, new SensorGetDouble((nint self, out double value) => {ThresholdCalls++;value = 1;return 0;}));
                Set(sensor, 10, new PutDouble((nint self, double value) => {ThresholdCalls++;return 0;}));
            } else {
                Set(sensor, pressure ? 8 : 7, new SensorGetUInt((nint self, out uint value) => {value = 20;return 0;}));
                Set(sensor, pressure ? 9 : 8, new SensorPutUInt((nint self, uint value) => {Interval = value;IntervalWrites.Add(value);return 0;}));
                Set(sensor, pressure ? 10 : 9, new SensorGetUInt((nint self, out uint value) => {value = Interval;return 0;}));
            }
            Set(sensor, pressure || hinge ? 11 : 10, new WinRtAddReportEvent((nint self, nint handler, out long token) => {
                var iid = new Guid(hinge ? "68de2bf4-243c-5aee-9dd9-d2e5e3165866" : orientation ? "91ae0c43-e1f7-577d-a161-8aaf275eb927" : acceleration ? "a5e83e40-b597-5b83-92f5-5bed3926ca80" : kind == EntityKind.Magnetometer ? "f9a0da76-c4fd-50ab-98b6-bfd26d6d3d82" : kind == EntityKind.Gyroscope ? "15171524-5786-59a5-af5b-a01245726c44" : pressure ? "e4caf459-d101-5ca5-a4ea-deb0917ae27e" : "1ecf183a-9f0a-5f73-9225-5a33eab5594f");
                Check(Marshal.QueryInterface(handler, in iid, out var supported) == 0, "typed native handler interface");Marshal.Release(supported);
                Marshal.AddRef(handler);lock (gate) {token = ++nextToken;handlers.Add(token, handler);Registrations++;}return 0;
            }));
            Set(sensor, pressure || hinge ? 12 : 11, new WinRtRemoveReportEvent((nint self, long token) => {
                lock (gate) {Check(handlers.Remove(token, out var handler), "matching native event token");Marshal.Release(handler);Removals++;}return 0;
            }));
            Set(args, 6, new WinRtGetInterface((nint self, out nint value) => {value = Take(reading);return 0;}));
            if (orientation) {
                var quaternion = Object(10);
                Set(reading, 8, new WinRtGetInterface((nint self, out nint value) => {QuaternionReads++;value = MissingQuaternion ? 0 : Take(quaternion);return QuaternionFailure ? unchecked((int)0x80004005) : 0;}));
                Set(quaternion, 6, new SensorGetFloat((nint self, out float value) => {value = (float)W;return AxisStatus(1);}));
                Set(quaternion, 7, new SensorGetFloat((nint self, out float value) => {value = (float)Value;return AxisStatus(2);}));
                Set(quaternion, 8, new SensorGetFloat((nint self, out float value) => {value = (float)Y;return AxisStatus(3);}));
                Set(quaternion, 9, new SensorGetFloat((nint self, out float value) => {value = (float)Z;return AxisStatus(4);}));
            } else if (acceleration || kind == EntityKind.Gyroscope) {
                Set(reading, 7, new SensorGetDouble((nint self, out double value) => {value = Value;return AxisStatus(1);}));
                Set(reading, 8, new SensorGetDouble((nint self, out double value) => {value = Y;return AxisStatus(2);}));
                Set(reading, 9, new SensorGetDouble((nint self, out double value) => {value = Z;return AxisStatus(3);}));
            } else if (kind == EntityKind.Magnetometer) {
                Set(reading, 7, new SensorGetFloat((nint self, out float value) => {value = (float)Value;return AxisStatus(1);}));
                Set(reading, 8, new SensorGetFloat((nint self, out float value) => {value = (float)Y;return AxisStatus(2);}));
                Set(reading, 9, new SensorGetFloat((nint self, out float value) => {value = (float)Z;return AxisStatus(3);}));
            } else if (hinge) Set(reading, 7, new SensorGetDouble((nint self, out double value) => {value = Value;return AxisStatus(1);}));
            else if (pressure) Set(reading, 7, new SensorGetDouble((nint self, out double value) => {value = Value;return 0;}));
            else Set(reading, 7, new SensorGetFloat((nint self, out float value) => {value = (float)Value;return 0;}));
        }
        private int AxisStatus(int axis)
        {
            Interlocked.Increment(ref AxisReads[axis - 1]);
            if (axis == 1 && HoldFirstAxis) {
                FirstAxisThread = Environment.CurrentManagedThreadId;AxisStarted.TrySetResult();
                Check(AxisRelease.Wait(TimeSpan.FromSeconds(5)), "held native axis was externally released");
            }
            return AxisFailure == axis ? unchecked((int)0x80004005) : 0;
        }
        private nint Operation(nint result, bool isEnumeration = false, bool isReading = false)
        {
            var operation = Object(9);var info = Object(11);
            Set(operation, 0, new Query((nint self, in Guid iid, out nint value) => {
                value = iid == new Guid("00000036-0000-0000-c000-000000000046") ? Take(info) : 0;
                return value == 0 ? unchecked((int)0x80004002) : 0;
            }));
            Set(operation, 8, new WinRtGetInterface((nint self, out nint value) => {if (isEnumeration) EnumerationResults++;if (isReading) ReadingResults++;value = Take(result);return 0;}));
            Set(info, 7, new WinRtGetInt32((nint self, out int value) => {
                value = isEnumeration && HoldEnumeration || isReading && HoldReading ? 0 : 1;
                if (value == 0) {if (isReading) ReadingStarted.TrySetResult();else EnumerationStarted.TrySetResult();}return 0;
            }));
            Set(info, 8, new WinRtGetInt32((nint self, out int value) => {value = 0;return 0;}));
            Set(info, 9, new WinRtNoArguments(_ => {Interlocked.Increment(ref CanceledOperations);if (isReading) ReadingCanceled++;return 0;}));
            Set(info, 10, new WinRtNoArguments(_ => {Interlocked.Increment(ref ClosedOperations);if (isReading) ReadingClosed++;return 0;}));
            return Take(operation);
        }
        internal void Fire()
        {
            nint[] current;lock (gate) current = handlers.Values.ToArray();
            foreach (var handler in current) {
                var invoke = Marshal.GetDelegateForFunctionPointer<WinRtCellularEventInvoke>(Marshal.ReadIntPtr(Marshal.ReadIntPtr(handler), nint.Size * 3));
                Check(invoke(handler, sensor, args) == 0, "callback never unwinds into native caller");
            }
        }
        private nint Object(int slots)
        {
            var instance = Marshal.AllocHGlobal(nint.Size);var table = Marshal.AllocHGlobal(slots * nint.Size);
            for (var slot = 0; slot < slots; slot++) Marshal.WriteIntPtr(table, slot * nint.Size, 0);
            Marshal.WriteIntPtr(instance, table);allocations.Add(instance);allocations.Add(table);references.Add(instance, 0);return instance;
        }
        private void Set(nint instance, int slot, Delegate callback) {delegates.Add(callback);Marshal.WriteIntPtr(Marshal.ReadIntPtr(instance), slot * nint.Size, Marshal.GetFunctionPointerForDelegate(callback));}
        private nint Take(nint value) {lock (gate) references[value]++;return value;}
        public int Initialize() {Initializations++;return 0;}
        public nint Factory(string name, Guid iid)
        {
            var expected = new Guid(name == "Windows.Devices.Enumeration.DeviceInformation" ? "c17f100e-3a46-4a78-8013-769dc9b97390"
                : hinge ? "b7b63910-fbb1-4123-89ce-4ea34eb0dfca" : orientation ? "a67feb55-2c85-4b28-a0fe-58c4b20495f5" : acceleration ? "9de218cf-455d-4cf3-8200-70e1410340f8" : kind == EntityKind.Magnetometer ? "2c0819f0-ffc6-4f89-a06f-18fa10792933" : kind == EntityKind.Gyroscope ? "ef83f7a1-d700-4204-9613-79c6b161df4e" : pressure ? "8fc6b1e7-95ff-44ac-878e-d65c8308c34c" : "0ec0a650-ddc6-40ab-ace3-ec3359d42c51");
            Check(iid == expected, "native factory IID");return Take(name == "Windows.Devices.Enumeration.DeviceInformation" ? enumeration : factory);
        }
        public void Release(nint value) {lock (gate) {Check(references[value] > 0, "owned native reference");references[value]--;}}
        public void Uninitialize()
        {
            Uninitializations++;
            try {Check(references.Values.All(count => count == 0) && HandlerCount == 0, "every async result, sensor, reading, factory and event reference released");}
            catch (Exception error) {Stopped.TrySetException(error);throw;}
            finally {foreach (var pointer in allocations) Marshal.FreeHGlobal(pointer);delegates.Clear();}
            Stopped.TrySetResult();
        }
        private static nint Text(string value) {Check(WindowsCreateString(value, value.Length, out var text) == 0, "fixture HSTRING");return text;}
        [UnmanagedFunctionPointer(CallingConvention.StdCall)] private delegate int Query(nint self, in Guid iid, out nint result);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)] private delegate int PutDouble(nint self, double value);
        [DllImport("combase.dll", CharSet = CharSet.Unicode)] private static extern int WindowsCreateString(string source, int length, out nint value);
    }
    private static void Check(bool condition, string message) {if (!condition) throw new Exception(message);}
}
