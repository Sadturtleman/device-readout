using DeviceReadout;
using System.Collections.Concurrent;
using System.Threading.Channels;
using System.Diagnostics;

internal static class SensorSourceTests
{
    internal static IEnumerable<(string Name, Func<Task> Run)> Cases() => [
        ("app sensor sources are inert until demand and retain independent sampling and cleanup", IndependentDemand),
        ("app sensor sources pause without a watch deadline and resume with fresh sessions", Lifecycle),
        ("app sensor source get cancellation preserves the caller cancellation and releases its session", CancelGet),
        ("app sensor source failures and deadlines release only the affected observation", ScopedFailure),
        ("app event sensor sources wait for actual occurrences while one-shot reads retain deadlines", EventSource),
        ("app sensor source blocked registration preserves deadlines and releases late resources off the host", BlockedRegistration)
    ];

    private static async Task IndependentDemand()
    {
        var collector = new TestCollector();
        using var access = new DeviceAccess(collector);
        var target = access.Observers.Target(Entities.Accelerometer, "app-accelerometer");
        var sessions = Channel.CreateUnbounded<SensorObserverSession<AccelerometerSnapshot>>();
        var stopped = Channel.CreateUnbounded<int>();
        var threads = new ConcurrentQueue<int>();
        var subscriptions = 0;
        using var source = access.Observers.SensorSource(target, session => {
            var id = Interlocked.Increment(ref subscriptions);threads.Enqueue(Environment.CurrentManagedThreadId);
            sessions.Writer.TryWrite(session);
            return new Cleanup(() => {threads.Enqueue(Environment.CurrentManagedThreadId);stopped.Writer.TryWrite(id);});
        }, new SensorDescription {Name = "App source", Vendor = "Example", Kind = SensorKind.Gyroscope});
        Check((await access.Sensors.List(Entities.Accelerometer)).Single() == target, "source discovery");
        var description = await access.Describe(target);
        Check(description.Name == "App source" && description.Vendor == "Example" && description.Kind == SensorKind.Accelerometer, "passive source metadata and entity kind");
        Check((await access.Capabilities.Get(target)).Readable == true && subscriptions == 0 && collector.Reads == 0, "passive registration and capability queries");
        var caller = Environment.CurrentManagedThreadId;
        var once = access.WithSensorSamplingRate(SensorSamplingRate.AtHertz(90)).Get(target);
        var oneShot = await sessions.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1));
        await using var stream = access.WithSensorSamplingRate(SensorSamplingRate.AtHertz(60)).Watch(target).GetAsyncEnumerator();
        var first = stream.MoveNextAsync().AsTask();
        var continuous = await sessions.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1));
        Check(oneShot.SamplingRate == SensorSamplingRate.PlatformDefault && continuous.SamplingRate.Hertz == 60, "independent get/watch rates");
        oneShot.Publish(new() {Value = new(1, 2, 3), CollectedAt = DateTimeOffset.UnixEpoch});
        continuous.Publish(new() {Value = new(4, 5, 6)});
        var read = await once;
        Check(read.Value == new Vector3(1, 2, 3) && read.CollectedAt > DateTimeOffset.UnixEpoch, "one actual sample and worker timestamp");
        Check(await first && stream.Current.Value == new Vector3(4, 5, 6), "continuous sample");
        Check(await stopped.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1)) == 1, "one-shot releases only its own session");
        continuous.Publish(new() {Value = new(4, 5, 6)});
        Check(await stream.MoveNextAsync() && stream.Current.Value == new Vector3(4, 5, 6), "equal samples retained");
        var removed = stream.MoveNextAsync().AsTask();source.Dispose();
        await Error(ErrorCode.EntityRemoved, () => removed.WaitAsync(TimeSpan.FromSeconds(1)));
        Check(await stopped.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1)) == 2, "source removal releases live session");
        continuous.Publish(new() {Value = new(9, 9, 9)});
        await Error(ErrorCode.EntityRemoved, () => access.Get(target));
        Check((await access.Sensors.List(Entities.Accelerometer)).Length == 0, "removed source stays absent");
        Check(threads.Distinct().Count() == 1 && threads.All(thread => thread != caller), "subscription and cleanup use worker lane");
        source.Dispose();
    }

    private static async Task Lifecycle()
    {
        using var access = new DeviceAccess(new TestCollector());
        var target = access.Observers.Target(Entities.Accelerometer, "lifecycle-sensor");
        var sessions = Channel.CreateUnbounded<SensorObserverSession<AccelerometerSnapshot>>();
        var stopped = Channel.CreateUnbounded<int>();var count = 0;
        using var source = access.Observers.SensorSource(target, session => {
            var id = Interlocked.Increment(ref count);sessions.Writer.TryWrite(session);
            return new Cleanup(() => stopped.Writer.TryWrite(id));
        });
        access.Observers.SensorActivity(false);
        var configured = access.WithReadTimeout(TimeSpan.FromMilliseconds(100)).WithSensorSamplingRate(SensorSamplingRate.AtHertz(55));
        await using var stream = configured.Watch(target).GetAsyncEnumerator();
        var next = stream.MoveNextAsync().AsTask();
        await Error(ErrorCode.ReadTimeout, () => configured.Get(target));
        await Task.Delay(140);
        Check(!next.IsCompleted && count == 0, "inactive watch waits without starting a source or expiring");
        Check((await access.Get(Entities.Ram)).AvailableBytes == 0, "inactive sensors do not pause state queries");
        access.Observers.SensorActivity(true);
        var first = await sessions.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1));
        first.Publish(new() {Value = new(1, 2, 3)});
        Check(await next && stream.Current.Value == new Vector3(1, 2, 3), "first active sample");
        access.Observers.SensorActivity(false);
        Check(await stopped.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1)) == 1, "inactive source released");
        next = stream.MoveNextAsync().AsTask();
        first.Publish(new() {Value = new(9, 9, 9)});
        await Task.Delay(140);Check(!next.IsCompleted, "late inactive sample cannot satisfy pending watch");
        access.Observers.SensorActivity(true);
        var resumed = await sessions.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1));
        Check(!ReferenceEquals(first, resumed) && resumed.SamplingRate.Hertz == 55, "fresh session with original subscription settings");
        resumed.Publish(new() {Value = new(4, 5, 6)});
        Check(await next && stream.Current.Value == new Vector3(4, 5, 6), "fresh resumed sample");
        access.Observers.SensorActivity(false);
        Check(await stopped.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1)) == 2, "resumed session released");
        next = stream.MoveNextAsync().AsTask();
        using var failure = access.Observers.FailureSource(target);
        failure.Publish(new(ErrorCode.PermissionDenied, "Permission lost while inactive."));
        await Error(ErrorCode.PermissionDenied, () => next.WaitAsync(TimeSpan.FromSeconds(1)));
        Check(count == 2, "inactive errors do not restart a source");
    }

    private static async Task CancelGet()
    {
        for (var attempt = 0; attempt < 24; attempt++) await CancelGetOnce();
    }

    private static async Task CancelGetOnce()
    {
        using var access = new DeviceAccess(new TestCollector());
        var target = access.Observers.Target(Entities.Accelerometer, "cancelled-get");
        var sessions = Channel.CreateUnbounded<SensorObserverSession<AccelerometerSnapshot>>();
        var stopped = Channel.CreateUnbounded<bool>();
        using var source = access.Observers.SensorSource(target, session => {
            sessions.Writer.TryWrite(session);return new Cleanup(() => stopped.Writer.TryWrite(true));
        });
        using var cancellation = new CancellationTokenSource();
        var pending = access.Get(target, cancellation.Token);
        var session = await sessions.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1));
        cancellation.Cancel();
        try {await pending.WaitAsync(TimeSpan.FromSeconds(1));throw new Exception("Expected caller cancellation");}
        catch (OperationCanceledException error) when (error.CancellationToken == cancellation.Token) { }
        Check(await stopped.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1)), "cancelled get releases source");
        session.Publish(new() {Value = new(9, 9, 9)});
        var fresh = access.Get(target);
        var next = await sessions.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1));
        next.Publish(new() {Value = new(1, 2, 3)});
        Check((await fresh).Value == new Vector3(1, 2, 3), "later get needs a fresh source session");
    }

    private static async Task ScopedFailure()
    {
        using var access = new DeviceAccess(new TestCollector());
        var target = access.Observers.Target(Entities.Accelerometer, "scoped-failure");
        var sessions = Channel.CreateUnbounded<SensorObserverSession<AccelerometerSnapshot>>();
        var stopped = Channel.CreateUnbounded<int>();var count = 0;
        using var source = access.Observers.SensorSource(target, session => {
            var id = Interlocked.Increment(ref count);sessions.Writer.TryWrite(session);
            return new Cleanup(() => stopped.Writer.TryWrite(id));
        });
        await using var first = access.Watch(target).GetAsyncEnumerator();
        var firstNext = first.MoveNextAsync().AsTask();
        var a = await sessions.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1));
        await using var second = access.Watch(target).GetAsyncEnumerator();
        var secondNext = second.MoveNextAsync().AsTask();
        var b = await sessions.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1));
        a.Publish(new() {Value = new(1, 2, 3)});b.Publish(new() {Value = new(4, 5, 6)});
        Check(await firstNext && await secondNext, "independent first samples");
        firstNext = first.MoveNextAsync().AsTask();secondNext = second.MoveNextAsync().AsTask();
        a.Fail(new(ErrorCode.PermissionDenied, "Only this native session failed."));
        await Error(ErrorCode.PermissionDenied, () => firstNext.WaitAsync(TimeSpan.FromSeconds(1)));
        Check(await stopped.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1)) == 1, "failed session cleanup");
        a.Publish(new() {Value = new(9, 9, 9)});b.Publish(new() {Value = new(7, 8, 9)});
        Check(await secondNext && second.Current.Value == new Vector3(7, 8, 9), "sibling survives source error");
        var timedOut = access.WithReadTimeout(TimeSpan.FromMilliseconds(100)).Get(target);
        _ = await sessions.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1));
        await Error(ErrorCode.ReadTimeout, () => timedOut);
        Check(await stopped.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1)) == 3, "timed-out session cleanup");
        b.Publish(new() {Value = new(double.NaN, 0, 0)});
        Check(await second.MoveNextAsync() && second.Current.Value is null, "worker normalizes one malformed vector as a grouped null");
    }

    private static async Task EventSource()
    {
        using var access = new DeviceAccess(new TestCollector());
        var target = access.Observers.Target(Entities.StepDetected, "step-event-source");
        var sessions = Channel.CreateUnbounded<SensorObserverSession<StepDetectedSnapshot>>();
        var stopped = Channel.CreateUnbounded<int>();var count = 0;
        using var source = access.Observers.SensorSource(target, session => {
            var id = Interlocked.Increment(ref count);sessions.Writer.TryWrite(session);
            return new Cleanup(() => stopped.Writer.TryWrite(id));
        });
        var configured = access.WithReadTimeout(TimeSpan.FromMilliseconds(80)).WithSensorSamplingRate(SensorSamplingRate.AtHertz(99));
        await using var stream = configured.Watch(target).GetAsyncEnumerator();
        var next = stream.MoveNextAsync().AsTask();
        var watching = await sessions.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1));
        await Task.Delay(150);
        Check(!next.IsCompleted && watching.SamplingRate == SensorSamplingRate.PlatformDefault, "event watch has no initial sample deadline or frequency request");
        var once = configured.Get(target);
        var reading = await sessions.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1));
        await Error(ErrorCode.ReadTimeout, () => once);
        Check(await stopped.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1)) == 2, "event get deadline releases only that session");
        reading.Publish(new() {Value = true});
        Check(!next.IsCompleted, "another session cannot supply the watch event");
        watching.Publish(new() {Value = true});
        Check(await next && stream.Current.Value == true, "actual event starts delivery");
        next = stream.MoveNextAsync().AsTask();source.Dispose();
        await Error(ErrorCode.EntityRemoved, () => next.WaitAsync(TimeSpan.FromSeconds(1)));
        Check(await stopped.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1)) == 1, "event source removal releases watch");
    }

    private static async Task BlockedRegistration()
    {
        using var release = new ManualResetEventSlim();
        using var access = new DeviceAccess(new TestCollector());
        var target = access.Observers.Target(Entities.Accelerometer, "blocked-sensor-source");
        var started = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var stopped = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var subscribeThread = 0;var stopThread = 0;var ticks = 0;
        using var timer = new Timer(_ => Interlocked.Increment(ref ticks), null, 0, 5);
        using var source = access.Observers.SensorSource(target, session => {
            subscribeThread = Environment.CurrentManagedThreadId;started.TrySetResult();
            if (!release.Wait(TimeSpan.FromSeconds(5))) throw new TimeoutException("Test did not release subscription setup.");
            return new Cleanup(() => {stopThread = Environment.CurrentManagedThreadId;stopped.TrySetResult();});
        });
        await using var stream = access.WithReadTimeout(TimeSpan.FromMilliseconds(100)).Watch(target).GetAsyncEnumerator();
        var pending = stream.MoveNextAsync().AsTask();
        try {
            await started.Task.WaitAsync(TimeSpan.FromSeconds(1));
            await Error(ErrorCode.ReadTimeout, () => pending.WaitAsync(TimeSpan.FromSeconds(1)));
            Check(!stopped.Task.IsCompleted && Volatile.Read(ref ticks) > 2, "host deadline and heartbeat complete before native registration releases");
            var hostThread = Environment.CurrentManagedThreadId;
            var clock = Stopwatch.StartNew();access.Dispose();
            Check(clock.Elapsed < TimeSpan.FromMilliseconds(500) && subscribeThread != hostThread, "context disposal does not join blocked source setup");
        } finally {release.Set();}
        await stopped.Task.WaitAsync(TimeSpan.FromSeconds(1));
        Check(stopThread == subscribeThread, "late resource cleanup uses the subscription worker");
    }

    private sealed class Cleanup(Action release) : IDisposable
    {
        private Action? action = release;
        public void Dispose() => Interlocked.Exchange(ref action, null)?.Invoke();
    }
    private static void Check(bool condition, string message) {if (!condition) throw new Exception(message);}
    private static async Task Error(ErrorCode expected, Func<Task> run)
    {
        try {await run();throw new Exception($"Expected {expected}");}
        catch (DeviceReadoutException error) when (error.Code == expected) { }
    }
}
