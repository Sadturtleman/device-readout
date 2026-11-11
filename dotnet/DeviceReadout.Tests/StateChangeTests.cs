using DeviceReadout;

internal static class StateChangeTests
{
    internal static IEnumerable<(string Name, Func<Task> Run)> Cases() => [
        ("state change callbacks defer collection, retain equal events and release subscriptions", DeferredStateEvents),
        ("timed-out event reads release subscriptions after an uncooperative native call returns", DeferredReadDeadline),
        ("state subscription cleanup survives a saturated read queue", CleanupUnderPressure),
        ("context closure releases collector-owned resources on the worker even before its first read", CollectorLifetime)
    ];
    private static async Task DeferredStateEvents()
    {
        var collector = new ChangeCollector();
        using var access = new DeviceAccess(collector);
        var stream = access.Watch(Entities.Power).GetAsyncEnumerator();
        try {
            Check(await stream.MoveNextAsync() && stream.Current.PowerSaveMode == false, "initial read");
            Check(collector.Registered == 1, "native state-change registration");
            var caller = Environment.CurrentManagedThreadId;
            var collectionThreads = new List<int>();
            collector.Emit(_ => {collectionThreads.Add(Environment.CurrentManagedThreadId);return new PowerSnapshot {PowerSaveMode = true};});
            collector.Emit(_ => {collectionThreads.Add(Environment.CurrentManagedThreadId);return new PowerSnapshot {PowerSaveMode = true};});
            Check(await stream.MoveNextAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1)) && stream.Current.PowerSaveMode == true, "first event");
            Check(await stream.MoveNextAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1)) && stream.Current.PowerSaveMode == true, "equal event retained");
            Check(collectionThreads.Count == 2 && collectionThreads.All(thread => thread == collector.ReadThread && thread != caller), "event reads use collection lane");
            Check(collector.Reads == 1, "event-only source does not poll");
        } finally {await stream.DisposeAsync();}
        Check(collector.Stopped.Task.IsCompletedSuccessfully, "subscription cleanup");
        var lateRead = false;collector.Emit(_ => {lateRead = true;return new PowerSnapshot();});
        await Task.Delay(20);Check(!lateRead, "late event cannot read after cancellation");
    }
    private static void Check(bool condition, string message) {if (!condition) throw new Exception(message);}

    private static async Task DeferredReadDeadline()
    {
        var collector = new ChangeCollector();using var access = new DeviceAccess(collector);
        await using var stream = access.WithReadTimeout(TimeSpan.FromMilliseconds(80)).Watch(Entities.Power).GetAsyncEnumerator();
        Check(await stream.MoveNextAsync(), "initial state before blocked event");
        using var release = new ManualResetEventSlim();
        var started = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        collector.Emit(_ => {started.TrySetResult();release.Wait();return new PowerSnapshot {PowerSaveMode = true};});
        try {
            await started.Task.WaitAsync(TimeSpan.FromSeconds(1));
            try {await stream.MoveNextAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1));throw new Exception("Expected ReadTimeout");}
            catch (DeviceReadoutException error) when (error.Code == ErrorCode.ReadTimeout) { }
            Check(!collector.Stopped.Task.IsCompleted, "cleanup waits for native lane rather than running on caller");
        } finally {release.Set();}
        await collector.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(1));
        Check((await access.Get(Entities.Power)).PowerSaveMode == false, "context remains usable after timed-out event");
    }

    private static async Task CleanupUnderPressure()
    {
        var collector = new ChangeCollector();using var access = new DeviceAccess(collector);
        await using var stream = access.WithReadTimeout(TimeSpan.FromMilliseconds(80)).Watch(Entities.Power).GetAsyncEnumerator();
        Check(await stream.MoveNextAsync(), "initial state");
        using var release = new ManualResetEventSlim();
        var started = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        collector.Emit(_ => {started.TrySetResult();release.Wait();return new PowerSnapshot();});
        Task<ErrorCode?>[] reads = [];
        try {
            await started.Task.WaitAsync(TimeSpan.FromSeconds(1));
            reads = Enumerable.Range(0, 140).Select(async _ => {
                try {await access.Get(Entities.Power);return (ErrorCode?)null;}
                catch (DeviceReadoutException error) {return error.Code;}
            }).ToArray();
            try {await stream.MoveNextAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1));throw new Exception("Expected ReadTimeout");}
            catch (DeviceReadoutException error) when (error.Code == ErrorCode.ReadTimeout) { }
        } finally {release.Set();}
        await collector.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
        var results = await Task.WhenAll(reads);
        Check(results.Any(code => code == ErrorCode.ReadFailed) && results.Any(code => code is null), "bounded queue rejects excess reads while admitted reads recover");
        Check(results.All(code => code is null or ErrorCode.ReadFailed), "queue pressure does not strand admitted reads");
    }

    private sealed class ChangeCollector : IDeviceCollector
    {
        internal int Registered, Reads, ReadThread;
        internal Action<Func<CancellationToken, DeviceSnapshot>> Emit = _ => { };
        internal readonly TaskCompletionSource Stopped = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public DeviceSnapshot Read(EntityAddress entity, CancellationToken token) {Reads++;ReadThread = Environment.CurrentManagedThreadId;return new PowerSnapshot {PowerSaveMode = false};}
        public ICollectorSubscription? ObserveChanges(EntityAddress entity, Action<Func<CancellationToken, DeviceSnapshot>> changed, Action<Exception> fail, CancellationToken token)
        {Registered++;Emit = changed;return new Subscription(() => Stopped.TrySetResult());}
        private sealed class Subscription(Action stop) : ICollectorSubscription
        {public bool PollingRequired => false;public void Dispose() => stop();}
    }

    private static async Task CollectorLifetime()
    {
        foreach (var readFirst in new[] {false, true}) {
            var collector = new LifetimeCollector();using var access = new DeviceAccess(collector);
            if (readFirst) await access.Get(Entities.Power);
            var caller = Environment.CurrentManagedThreadId;
            access.WithPollInterval(TimeSpan.FromSeconds(2)).Dispose();access.Dispose();
            var thread = await collector.Disposed.Task.WaitAsync(TimeSpan.FromSeconds(1));
            Check(thread != caller && (!readFirst || thread == collector.ReadThread), "collector cleanup is worker-owned");
            Check(collector.DisposeCount == 1, "shared context disposes collector once");
            try {await access.Get(Entities.Power);throw new Exception("Expected closed context");}
            catch (DeviceReadoutException error) when (error.Code == ErrorCode.EntityRemoved) { }
        }
    }
    private sealed class LifetimeCollector : IDeviceCollector, IDisposable
    {
        internal readonly TaskCompletionSource<int> Disposed = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal int ReadThread, DisposeCount;
        public DeviceSnapshot Read(EntityAddress entity, CancellationToken token) {ReadThread = Environment.CurrentManagedThreadId;return new PowerSnapshot();}
        public void Dispose() {DisposeCount++;Disposed.TrySetResult(Environment.CurrentManagedThreadId);}
    }
}
