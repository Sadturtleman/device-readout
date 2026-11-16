using DeviceReadout;

internal static class ObserverFailureTests
{
    internal static IEnumerable<(string Name, Func<Task> Run)> Cases() => [
        ("provider failure owners preserve application policy, sibling targets and fresh recovery", IndependentOwners),
        ("provider failures return on the host thread while native cancellation remains blocked", () => BlockedCancellation(false)),
        ("context disposal returns on the host thread while native cancellation remains blocked", () => BlockedCancellation(true)),
        ("native read deadlines survive blocked and throwing cancellation callbacks", () => NativeReadCancellation(false)),
        ("caller cancellation survives blocked and throwing native cancellation callbacks", () => NativeReadCancellation(true)),
        ("provider failure recovery invalidates in-flight native reads, discovery and descriptions", NativeFailureRecovery)
    ];

    private static async Task IndependentOwners()
    {
        var collector = new TestCollector();
        using var access = new DeviceAccess(collector);
        var screen = access.Observers.Target(Entities.Display, "owned-screen");
        var sibling = access.Observers.Target(Entities.Display, "sibling-screen");
        using var first = access.Observers.FailureSource(screen);
        using var second = access.WithReadTimeout(TimeSpan.FromMilliseconds(100)).Observers.FailureSource(screen);
        Check(collector.Reads == 0, "creating owners must not collect");
        access.Observers.Publish(screen, new DisplaySnapshot {Label = "Old"});
        access.Observers.Publish(sibling, new DisplaySnapshot {Label = "Sibling"});
        await using var stream = access.Watch(screen).GetAsyncEnumerator();
        Check(await stream.MoveNextAsync() && stream.Current.Label == "Old", "initial state");
        var pending = stream.MoveNextAsync().AsTask();
        first.Publish(new(ErrorCode.ReadFailed, "First provider failed."));
        await Error(ErrorCode.ReadFailed, () => pending.WaitAsync(TimeSpan.FromSeconds(1)));
        second.Publish(new(ErrorCode.UnsupportedEntity, "Second provider failed."));
        access.Observers.Failure(Entities.Display, new(ErrorCode.PermissionDenied, "Application policy."));
        first.Dispose();
        await Error(ErrorCode.PermissionDenied, () => access.Get(screen));
        access.Observers.Failure(Entities.Display, null);
        await Error(ErrorCode.UnsupportedEntity, () => access.Get(screen));
        second.Publish(null);
        await Error(ErrorCode.ReadTimeout, () => access.WithReadTimeout(TimeSpan.FromMilliseconds(80)).Get(screen));
        access.Observers.Publish(screen, new DisplaySnapshot {Label = "Fresh"});
        access.Observers.Publish(sibling, new DisplaySnapshot {Label = "Fresh sibling"});
        Check((await access.Get(screen)).Label == "Fresh", "clearing all owners permits fresh state");
        second.Publish(new(ErrorCode.ReadFailed, "Provider failed again."));
        Check((await access.Get(sibling)).Label == "Fresh sibling", "target failure stays scoped");
        using var replacement = access.Observers.FailureSource(screen);
        replacement.Publish(new(ErrorCode.PermissionDenied, "Replacement owns this failure."));
        second.Dispose();second.Dispose();first.Dispose();
        await Error(ErrorCode.PermissionDenied, () => access.Get(screen));
        await Error(ErrorCode.EntityRemoved, () => {second.Publish(null);return Task.CompletedTask;});
        replacement.Dispose();
        access.Observers.Publish(screen, new DisplaySnapshot {Label = "Replacement recovered"});
        Check((await access.Get(screen)).Label == "Replacement recovered", "released replacement");
        Check((await access.Get(Entities.Ram)).PhysicalBytes == 9007199254740993UL, "unrelated native read");
        access.Dispose();
        first.Dispose();second.Dispose();replacement.Dispose();
        await Error(ErrorCode.EntityRemoved, () => {access.Observers.FailureSource(screen);return Task.CompletedTask;});
    }

    private static async Task BlockedCancellation(bool closeContext)
    {
        using var release = new ManualResetEventSlim();
        var collector = new CancellationCollector(release);
        using var access = new DeviceAccess(collector);
        using var owner = access.Observers.FailureSource(Entities.Ram);
        await using var stream = access.WithReadTimeout(TimeSpan.FromMilliseconds(100)).Watch(Entities.Ram).GetAsyncEnumerator();
        Check(await stream.MoveNextAsync(), "initial native state");
        var next = stream.MoveNextAsync().AsTask();
        Task? heldRead = null;
        if (closeContext) {
            collector.HoldNextRead = true;
            heldRead = access.Get(Entities.Ram);
            await collector.ReadStarted.Task.WaitAsync(TimeSpan.FromSeconds(1));
        }
        var finished = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var host = new Thread(() => {
            try {
                if (closeContext) access.Dispose();else owner.Publish(new(ErrorCode.PermissionDenied, "Provider lost access."));
                finished.TrySetResult();
            }
            catch (Exception error) {finished.TrySetException(error);}
        }) {IsBackground = true};
        host.Start();
        try {
            await collector.CancellationStarted.Task.WaitAsync(TimeSpan.FromSeconds(1));
            await finished.Task.WaitAsync(TimeSpan.FromMilliseconds(500));
            Check(collector.CancellationThread != host.ManagedThreadId, "native cancellation ran on the host thread");
            if (closeContext) {
                try {await next.WaitAsync(TimeSpan.FromSeconds(1));throw new Exception("Expected context cancellation");}
                catch (OperationCanceledException) { }
            } else await Error(ErrorCode.PermissionDenied, () => next.WaitAsync(TimeSpan.FromSeconds(1)));
            Check(!collector.Released.Task.IsCompleted, "native cleanup must remain worker-owned until callback release");
        } finally {
            release.Set();
            await finished.Task.WaitAsync(TimeSpan.FromSeconds(1));
            try {await next;} catch (DeviceReadoutException) { } catch (OperationCanceledException) { }
            if (heldRead is not null) {
                try {await heldRead.WaitAsync(TimeSpan.FromSeconds(1));}
                catch (OperationCanceledException) { }
            }
        }
        await collector.Released.Task.WaitAsync(TimeSpan.FromSeconds(1));
        if (!closeContext) {
            owner.Publish(null);
            Check((await access.Get(Entities.Ram)).AvailableBytes == 42, "context recovers after native cleanup");
        }
    }

    private sealed class CancellationCollector(ManualResetEventSlim release) : IDeviceCollector
    {
        internal readonly TaskCompletionSource CancellationStarted = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly TaskCompletionSource Released = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly TaskCompletionSource ReadStarted = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal volatile bool HoldNextRead;
        internal int CancellationThread;
        public DeviceSnapshot Read(EntityAddress entity, CancellationToken token)
        {
            if (HoldNextRead) {
                HoldNextRead = false;ReadStarted.TrySetResult();
                if (!release.Wait(TimeSpan.FromSeconds(5))) throw new TimeoutException("Test did not release native read.");
            }
            return new RamSnapshot {AvailableBytes = 42};
        }
        public ICollectorSubscription Observe(EntityAddress entity, SensorSamplingRate rate, Action<DeviceSnapshot> emit, Action<Exception> fail, CancellationToken token)
        {
            var registration = token.Register(() => {
                CancellationThread = Environment.CurrentManagedThreadId;
                CancellationStarted.TrySetResult();
                if (!release.Wait(TimeSpan.FromSeconds(5))) throw new TimeoutException("Test did not release native cancellation.");
            });
            return new CancellationSubscription(registration, Released);
        }
        private sealed class CancellationSubscription(CancellationTokenRegistration registration, TaskCompletionSource released) : ICollectorSubscription
        {
            public bool PollingRequired => false;
            public void Dispose() {registration.Dispose();released.TrySetResult();}
        }
    }

    private static async Task NativeFailureRecovery()
    {
        for (var operation = 0; operation < 4; operation++) {
            using var collector = new PendingNativeCollector();
            using var access = new DeviceAccess(collector);
            var sensor = (await access.List(Entities.Accelerometer))[0];
            using var owner = operation == 0 ? access.Observers.FailureSource(Entities.Ram) : access.Observers.FailureSource(Entities.Accelerometer);
            Task Query() => operation switch {
                0 => access.Get(Entities.Ram), 1 => access.List(Entities.Accelerometer),
                2 => access.Current(Entities.Accelerometer), _ => access.Describe(sensor)
            };
            if (operation != 0) collector.ArmDiscovery();
            var pending = Query();
            try {
                await collector.Started.Task.WaitAsync(TimeSpan.FromSeconds(1));
                owner.Publish(new(ErrorCode.PermissionDenied, "Provider lost access during native collection."));
                owner.Publish(null);
            } finally {collector.Release.Set();}
            await Error(ErrorCode.PermissionDenied, () => pending);
            await Query();
        }
    }

    private static async Task NativeReadCancellation(bool cancelByCaller)
    {
        using var release = new ManualResetEventSlim();
        var collector = new HeldReadCollector(release);
        using var access = new DeviceAccess(collector);
        using var caller = new CancellationTokenSource();
        var request = access.WithReadTimeout(TimeSpan.FromMilliseconds(cancelByCaller ? 5000 : 100)).Get(Entities.Ram, caller.Token);
        try {
            await collector.Started.Task.WaitAsync(TimeSpan.FromSeconds(1));
            if (cancelByCaller) {
                var returned = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
                new Thread(() => {
                    try {caller.Cancel();returned.TrySetResult();}
                    catch (Exception error) {returned.TrySetException(error);}
                }) {IsBackground = true}.Start();
                await returned.Task.WaitAsync(TimeSpan.FromMilliseconds(500));
                try {await request.WaitAsync(TimeSpan.FromSeconds(1));throw new Exception("Expected caller cancellation");}
                catch (OperationCanceledException) { }
            } else await Error(ErrorCode.ReadTimeout, () => request.WaitAsync(TimeSpan.FromSeconds(1)));
            await collector.CancellationStarted.Task.WaitAsync(TimeSpan.FromSeconds(1));
            Check(!collector.ReadExited.Task.IsCompleted, "caller finished while native read remains held");
        } finally {release.Set();}
        await collector.CancellationExited.Task.WaitAsync(TimeSpan.FromSeconds(1));
        await collector.ReadExited.Task.WaitAsync(TimeSpan.FromSeconds(1));
        Check((await access.Get(Entities.Ram)).AvailableBytes == 99, "throwing cancellation callback cannot poison future reads");
    }

    private sealed class HeldReadCollector(ManualResetEventSlim release) : IDeviceCollector
    {
        internal readonly TaskCompletionSource Started = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly TaskCompletionSource CancellationStarted = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly TaskCompletionSource CancellationExited = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly TaskCompletionSource ReadExited = new(TaskCreationOptions.RunContinuationsAsynchronously);
        private int reads;
        public DeviceSnapshot Read(EntityAddress entity, CancellationToken token)
        {
            if (Interlocked.Increment(ref reads) == 1) {
                using var registration = token.Register(() => {
                    CancellationStarted.TrySetResult();
                    try {
                        if (!release.Wait(TimeSpan.FromSeconds(5))) throw new TimeoutException("Cancellation fixture was not released.");
                        throw new InvalidOperationException("Native cancellation callback failed.");
                    } finally {CancellationExited.TrySetResult();}
                });
                Started.TrySetResult();
                try {if (!release.Wait(TimeSpan.FromSeconds(5))) throw new TimeoutException("Read fixture was not released.");}
                finally {ReadExited.TrySetResult();}
            }
            return new RamSnapshot {AvailableBytes = 99};
        }
    }

    private static void Check(bool condition, string message) {if (!condition) throw new Exception(message);}
    private static async Task Error(ErrorCode expected, Func<Task> run)
    {
        try {await run();throw new Exception($"Expected {expected}");}
        catch (DeviceReadoutException error) when (error.Code == expected) { }
    }
}
