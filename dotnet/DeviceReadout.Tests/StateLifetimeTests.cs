using DeviceReadout;

internal static class StateLifetimeTests
{
    internal static IEnumerable<(string Name, Func<Task> Run)> Cases() => [
        ("state cancellation completes before held native subscription cleanup", HeldCleanup),
        ("state registration cancellation releases every returned subscription without closing the context", RegistrationCancellation),
        ("state disposal completes before native cleanup and rejects late callbacks", () => HeldExit(false)),
        ("state observer failure reaches the consumer before native cleanup", () => HeldExit(true))
    ];

    private static async Task HeldCleanup()
    {
        using var release = new ManualResetEventSlim();
        var collector = new HeldCleanupCollector(release);
        using var access = new DeviceAccess(collector);
        using var caller = new CancellationTokenSource();
        await using var stream = access.Watch(Entities.Power, caller.Token).GetAsyncEnumerator();
        Check(await stream.MoveNextAsync(), "initial state before cleanup is held");
        var pending = stream.MoveNextAsync().AsTask();
        var hostTicks = 0;
        using var heartbeat = new Timer(_ => Interlocked.Increment(ref hostTicks), null, 0, 5);
        caller.Cancel();
        try {
            await collector.CleanupStarted.Task.WaitAsync(TimeSpan.FromSeconds(1));
            await Canceled(pending.WaitAsync(TimeSpan.FromMilliseconds(500)));
            Check(!collector.CleanupFinished.Task.IsCompleted && Volatile.Read(ref hostTicks) > 0,
                "caller cancellation and host progress do not depend on native cleanup completion");
        } finally {release.Set();await Canceled(pending.WaitAsync(TimeSpan.FromSeconds(2)));}
        await collector.CleanupFinished.Task.WaitAsync(TimeSpan.FromSeconds(1));
        Check(collector.RegisterThread == collector.CleanupThread && collector.CleanupCount == 1,
            "exactly one cleanup remains on the collector worker");
        Check((await access.Get(Entities.Power)).PowerSaveMode == false, "context remains usable after cleanup");
    }

    private static async Task RegistrationCancellation()
    {
        var collector = new RegistrationCollector();
        using var access = new DeviceAccess(collector);
        for (var i = 1; i <= 128; i++) {
            using var caller = new CancellationTokenSource();
            await using var stream = access.Watch(Entities.Power, caller.Token).GetAsyncEnumerator();
            var pending = stream.MoveNextAsync().AsTask();
            Check(await collector.Started.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1)) == i, "registration identity");
            caller.Cancel();
            try {
                if (await pending.WaitAsync(TimeSpan.FromSeconds(1)))
                    await Canceled(stream.MoveNextAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1)));
            } catch (OperationCanceledException) { }
            Check(await collector.Released.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1)) == i,
                "each canceled registration releases its own subscription before context closure");
        }
        Check(collector.ReleaseCount == 128, "no duplicate or missing release");
        Check((await access.Get(Entities.Power)).PowerSaveMode == false, "context remains usable after registration races");
    }

    private static async Task HeldExit(bool fail)
    {
        using var release = new ManualResetEventSlim();
        var collector = new HeldCleanupCollector(release);
        using var access = new DeviceAccess(collector);
        using var owner = access.Observers.FailureSource(Entities.Power);
        await using var stream = access.Watch(Entities.Power).GetAsyncEnumerator();
        Check(await stream.MoveNextAsync(), "initial state before termination");
        Task finished;
        if (fail) {
            var pending = stream.MoveNextAsync().AsTask();
            owner.Publish(new(ErrorCode.PermissionDenied, "Application observer lost access."));
            finished = PermissionDenied(pending);
        } else finished = stream.DisposeAsync().AsTask();
        var lateReads = 0;
        try {
            await collector.CleanupStarted.Task.WaitAsync(TimeSpan.FromSeconds(1));
            await finished.WaitAsync(TimeSpan.FromMilliseconds(500));
            Check(!collector.CleanupFinished.Task.IsCompleted, "termination does not await native release");
            collector.Changed(_ => {Interlocked.Increment(ref lateReads);return new PowerSnapshot {PowerSaveMode = true};});
        } finally {release.Set();await finished.WaitAsync(TimeSpan.FromSeconds(2));}
        await collector.CleanupFinished.Task.WaitAsync(TimeSpan.FromSeconds(1));
        owner.Dispose();
        Check((await access.Get(Entities.Power)).PowerSaveMode == false && Volatile.Read(ref lateReads) == 0,
            "late callbacks cannot enqueue collection after stream termination");
        Check(collector.CleanupCount == 1 && collector.CleanupThread == collector.RegisterThread, "release remains exactly once on its worker");
    }

    private static async Task PermissionDenied(Task task)
    {
        try {await task;throw new Exception("Expected observer PermissionDenied.");}
        catch (DeviceReadoutException error) when (error.Code == ErrorCode.PermissionDenied) { }
    }

    private sealed class RegistrationCollector : IDeviceCollector
    {
        internal readonly System.Threading.Channels.Channel<int> Started = System.Threading.Channels.Channel.CreateUnbounded<int>();
        internal readonly System.Threading.Channels.Channel<int> Released = System.Threading.Channels.Channel.CreateUnbounded<int>();
        internal int ReleaseCount;
        private int count;
        public DeviceSnapshot Read(EntityAddress entity, CancellationToken token) => new PowerSnapshot {PowerSaveMode = false};
        public ICollectorSubscription ObserveChanges(EntityAddress entity, Action<Func<CancellationToken, DeviceSnapshot>> changed,
            Action<Exception> fail, CancellationToken token)
        {
            var id = ++count;var thread = Environment.CurrentManagedThreadId;
            Started.Writer.TryWrite(id);
            return new Subscription(() => {
                Check(Environment.CurrentManagedThreadId == thread, "registration race cleanup stays on the worker");
                Interlocked.Increment(ref ReleaseCount);Released.Writer.TryWrite(id);
            });
        }
    }

    private sealed class HeldCleanupCollector(ManualResetEventSlim release) : IDeviceCollector
    {
        internal readonly TaskCompletionSource CleanupStarted = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly TaskCompletionSource CleanupFinished = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal int RegisterThread, CleanupThread, CleanupCount;
        internal Action<Func<CancellationToken, DeviceSnapshot>> Changed = _ => { };
        public DeviceSnapshot Read(EntityAddress entity, CancellationToken token) => new PowerSnapshot {PowerSaveMode = false};
        public ICollectorSubscription ObserveChanges(EntityAddress entity, Action<Func<CancellationToken, DeviceSnapshot>> changed,
            Action<Exception> fail, CancellationToken token)
        {
            RegisterThread = Environment.CurrentManagedThreadId;Changed = changed;
            return new Subscription(() => {
                CleanupThread = Environment.CurrentManagedThreadId;Interlocked.Increment(ref CleanupCount);CleanupStarted.TrySetResult();
                if (!release.Wait(TimeSpan.FromSeconds(5))) throw new TimeoutException("Test did not release native cleanup.");
                CleanupFinished.TrySetResult();
            });
        }
    }
    private sealed class Subscription(Action release) : ICollectorSubscription
    {
        public bool PollingRequired => false;
        public void Dispose() => release();
    }
    private static async Task Canceled(Task task)
    {
        try {await task;throw new Exception("Expected caller cancellation.");}
        catch (OperationCanceledException) { }
    }
    private static void Check(bool condition, string message) {if (!condition) throw new Exception(message);}
}
