using System.Collections.Immutable;
using System.Runtime.CompilerServices;
using System.Threading.Channels;
using System.Collections.Concurrent;
using System.Diagnostics;

namespace DeviceReadout;

public sealed partial class DeviceAccess : IDisposable
{
    internal sealed class Context : IDisposable
    {
        internal readonly CollectionWorker Worker = new();
        internal readonly CancellationScope Lifetime = new();
        internal readonly ObservedCollector Collector;
        private readonly ConcurrentDictionary<ICollectorSubscription, byte> subscriptions = new();
        internal Context(IDeviceCollector collector)
        {
            Collector = new(collector);
            Worker.OnStopped = () => {
                foreach(var subscription in subscriptions.Keys) {
                    try {subscription.Dispose();} catch (Exception) { /* Cleanup must not crash the host. */ }
                }
                subscriptions.Clear();
                try {Collector.Dispose();} catch (Exception) { /* Native teardown must not crash the host. */ }
                finally {Lifetime.Dispose();}
            };
        }
        internal ICollectorSubscription? Observe(EntityAddress address, EntityMode mode, SensorSamplingRate rate, Action<DeviceSnapshot> emit, Action<Exception> fail, CancellationToken token,
            Action<Func<CancellationToken, DeviceSnapshot>>? changed = null)
        {
            var nativeLifetime = new CancellationScope(token);
            ICollectorSubscription? native;
            try {native = Collector.Observe(address, rate, emit, fail, nativeLifetime.Token, mode == EntityMode.State, changed);}
            catch {nativeLifetime.Cancel();nativeLifetime.Dispose();throw;}
            if (native is null) {nativeLifetime.Dispose();return null;}
            ICollectorSubscription? tracked = null;
            tracked = new ActionSubscription(() => {
                nativeLifetime.Cancel();
                try {native.Dispose();} finally {nativeLifetime.Dispose();subscriptions.TryRemove(tracked!, out _);}
            }, native.PollingRequired);
            subscriptions.TryAdd(tracked, 0);
            if (token.IsCancellationRequested || Lifetime.IsCancellationRequested) {tracked.Dispose();token.ThrowIfCancellationRequested();}
            return tracked;
        }
        public void Dispose() {Lifetime.Cancel();Worker.Dispose();}
    }
    private readonly Context context;
    public TimeSpan PollInterval { get; }
    public TimeSpan ReadTimeout { get; }
    public SensorSamplingRate SensorSamplingRate { get; }
    public ObserverInputs Observers { get; }
    public PermissionAccess Permissions { get; }
    public CapabilityAccess Capabilities => new(this);
    public EntityCollection<DisplaySnapshot> Displays => new(this, Entities.Display);
    public EntityCollection<CpuCoreSnapshot> CpuCores => new(this, Entities.CpuCore);
    public EntityCollection<BatterySnapshot> Batteries => new(this, Entities.Battery);
    public EntityCollection<NetworkInterfaceSnapshot> NetworkInterfaces => new(this, Entities.NetworkInterface);
    public EntityCollection<StorageVolumeSnapshot> StorageVolumes => new(this, Entities.StorageVolume);
    public EntityCollection<CellularSubscriptionSnapshot> CellularSubscriptions => new(this, Entities.CellularSubscription);
    public EntityCollection<TelephonyIdentitySnapshot> TelephonyIdentities => new(this, Entities.TelephonyIdentity);
    public SensorCollection Sensors => new(this);

    public DeviceAccess(IDeviceCollector collector) : this(new Context(collector), TimeSpan.FromSeconds(1), TimeSpan.FromSeconds(5), SensorSamplingRate.PlatformDefault) { }
    private DeviceAccess(Context context, TimeSpan pollInterval, TimeSpan readTimeout, SensorSamplingRate samplingRate)
    {
        (this.context, PollInterval, ReadTimeout, SensorSamplingRate) = (context, pollInterval, readTimeout, samplingRate);
        Observers = new(context);Permissions = new(context);
    }
    public DeviceAccess WithPollInterval(TimeSpan interval) => new(context, Positive(interval), ReadTimeout, SensorSamplingRate);
    public DeviceAccess WithReadTimeout(TimeSpan timeout) => new(context, PollInterval, Positive(timeout), SensorSamplingRate);
    public DeviceAccess WithSensorSamplingRate(SensorSamplingRate rate)
        => new(context, PollInterval, ReadTimeout, rate ?? throw new DeviceReadoutException(ErrorCode.InvalidConfiguration, "Expected a sampling rate."));
    private static TimeSpan Positive(TimeSpan value)
    {
        if (value <= TimeSpan.Zero)
            throw new DeviceReadoutException(ErrorCode.InvalidConfiguration, "Duration must be positive.");
        return value;
    }
    private CancellationScope Link(CancellationToken cancellationToken)
    {
        if (context.Lifetime.IsCancellationRequested) throw new DeviceReadoutException(ErrorCode.EntityRemoved, "DeviceAccess is closed.");
        return new(cancellationToken, context.Lifetime.Token);
    }
    private static T Stamp<T>(DeviceSnapshot value) where T : DeviceSnapshot
        => value is T ? (T)(SnapshotRules.Normalize(value) with {CollectedAt = DateTimeOffset.UtcNow})
            : throw new DeviceReadoutException(ErrorCode.ReadFailed, "Collector returned the wrong snapshot type.");

    public async Task<T> Get<T>(Entity<T> entity, CancellationToken cancellationToken = default) where T : DeviceSnapshot
    {
        var address = entity.Address(context);
        using var linked = Link(cancellationToken);
        if (entity.Mode == EntityMode.State)
            return await context.Worker.Run(token => Stamp<T>(context.Collector.Read(address, token)), ReadTimeout, linked.Token).ConfigureAwait(false);
        await using var stream = SensorWatch(entity, SensorSamplingRate.PlatformDefault, linked.Token).GetAsyncEnumerator();
        var pending = stream.MoveNextAsync().AsTask();
        try {
            if (!await AsyncTiming.Wait(pending, ReadTimeout, linked.Token).ConfigureAwait(false))
                throw new DeviceReadoutException(ErrorCode.ReadFailed, "Sensor ended without a sample.");
            return stream.Current;
        } catch (TimeoutException error) {
            linked.Cancel();
            try {await pending.ConfigureAwait(false);} catch (Exception) { }
            throw new DeviceReadoutException(ErrorCode.ReadTimeout, "No sensor sample before the deadline.", error);
        } catch (OperationCanceledException) {
            linked.Cancel();
            // Async iterators cannot be disposed while MoveNextAsync is still completing cancellation.
            try {await pending.ConfigureAwait(false);} catch (Exception) { }
            throw;
        } finally {linked.Cancel();}
    }

    public async Task<ImmutableArray<Entity<T>>> List<T>(Entity<T> kind, CancellationToken cancellationToken = default) where T : DeviceSnapshot
    {
        _ = kind.Address(context, true);
        using var linked = Link(cancellationToken);
        return await context.Worker.Run(token => context.Collector.ListAddresses(kind.Kind, token)
            .Select(address => kind.Bind(context, address.TargetId!, address.Observed)).ToImmutableArray(), ReadTimeout, linked.Token).ConfigureAwait(false);
    }
    public async Task<Entity<T>?> Current<T>(Entity<T> kind, CancellationToken cancellationToken = default) where T : DeviceSnapshot
    {
        _ = kind.Address(context, true);
        using var linked = Link(cancellationToken);
        var address = await context.Worker.Run(token => context.Collector.CurrentAddress(kind.Kind, token), ReadTimeout, linked.Token).ConfigureAwait(false);
        return address is { } selected ? kind.Bind(context, selected.TargetId!, selected.Observed) : null;
    }
    public async Task<SensorDescription> Describe<T>(Entity<T> sensor, CancellationToken cancellationToken = default) where T : DeviceSnapshot
    {
        var address = sensor.Address(context);
        using var linked = Link(cancellationToken);
        return await context.Worker.Run(token => Stamp<SensorDescription>(context.Collector.Describe(address, token)), ReadTimeout, linked.Token).ConfigureAwait(false);
    }
    internal async Task<EntityCapabilities> GetCapabilities<T>(Entity<T> entity, CancellationToken cancellationToken = default) where T : DeviceSnapshot
    {
        var address = entity.Address(context, true);
        using var linked = Link(cancellationToken);
        return await context.Worker.Run(token => context.Collector.Capabilities(address, token), ReadTimeout, linked.Token).ConfigureAwait(false);
    }

    private sealed record SnapshotInput(Func<CancellationToken, DeviceSnapshot> Read, TaskCompletionSource? Completed = null);

    public async IAsyncEnumerable<T> Watch<T>(Entity<T> entity, [EnumeratorCancellation] CancellationToken cancellationToken = default) where T : DeviceSnapshot
    {
        if (entity.Mode != EntityMode.State) {
            var rate = entity.Mode == EntityMode.Sample ? SensorSamplingRate : SensorSamplingRate.PlatformDefault;
            await foreach (var sample in SensorWatch(entity, rate, cancellationToken).ConfigureAwait(false)) yield return sample;
            yield break;
        }
        var address = entity.Address(context);
        using var linked = Link(cancellationToken);
        var queue = Channel.CreateBounded<T>(new BoundedChannelOptions(2048) {SingleReader = true, FullMode = BoundedChannelFullMode.Wait});
        var incoming = Channel.CreateBounded<SnapshotInput>(new BoundedChannelOptions(2048) {SingleReader = true, FullMode = BoundedChannelFullMode.Wait});
        using var stop = new CancellationScope(linked.Token);
        var firstSample = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        var normalization = Normalize();
        var producer = Produce();
        try {
            await foreach (var snapshot in queue.Reader.ReadAllAsync(linked.Token).ConfigureAwait(false)) yield return snapshot;
        } finally {
            linked.Cancel();await producer.ConfigureAwait(false);await normalization.ConfigureAwait(false);
        }

        void Fail(Exception error) {queue.Writer.TryComplete(error);incoming.Writer.TryComplete(error);stop.Cancel();}
        async Task Normalize()
        {
            try {
                await foreach(var raw in incoming.Reader.ReadAllAsync(stop.Token).ConfigureAwait(false)) {
                    var snapshot = await context.Worker.Run(token => Stamp<T>(raw.Read(token)), ReadTimeout, stop.Token).ConfigureAwait(false);
                    if (!queue.Writer.TryWrite(snapshot)) {
                        Fail(new DeviceReadoutException(ErrorCode.ReadFailed, "Consumer cannot keep up with the bounded snapshot queue."));return;
                    }
                    firstSample.TrySetResult(true);
                    raw.Completed?.TrySetResult();
                }
            } catch (OperationCanceledException) when (stop.IsCancellationRequested) { }
            catch (Exception error) {Fail(error);}
            finally {queue.Writer.TryComplete();}
        }

        async Task Produce()
        {
            ICollectorSubscription? allocated = null;
            var releaseRequested = 0;
            void Enqueue(SnapshotInput input) {
                try {
                    if (!stop.IsCancellationRequested && !incoming.Writer.TryWrite(input))
                        Fail(new DeviceReadoutException(ErrorCode.ReadFailed, "Consumer cannot keep up with the bounded snapshot queue."));
                } catch (Exception error) {Fail(error);}
            }
            void Emit(DeviceSnapshot value) => Enqueue(new(_ => value));
            void Changed(Func<CancellationToken, DeviceSnapshot> read) => Enqueue(new(read));
            async Task ReadState() {
                var completed = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
                Enqueue(new(token => context.Collector.Read(address, token), completed));
                await completed.Task.WaitAsync(stop.Token).ConfigureAwait(false);
            }
            try {
                var rate = entity.Mode == EntityMode.Sample ? SensorSamplingRate : SensorSamplingRate.PlatformDefault;
                var deadline = Stopwatch.StartNew();
                var subscription = await context.Worker.Run(workerToken => {
                    var created = context.Observe(address, entity.Mode, rate, Emit, Fail, stop.Token, Changed);
                    Interlocked.Exchange(ref allocated, created);
                    // Preserve ownership even when cancellation wins the caller's registration await.
                    if (Volatile.Read(ref releaseRequested) != 0) _ = Release(Interlocked.Exchange(ref allocated, null));
                    return created;
                }, ReadTimeout, stop.Token).ConfigureAwait(false);
                if (entity.Mode != EntityMode.State && subscription is null)
                    throw new DeviceReadoutException(ErrorCode.UnsupportedEntity, "Sensor observation is unavailable.");
                if (entity.Mode == EntityMode.State) {
                    do {
                        await ReadState().ConfigureAwait(false);
                        if (subscription is {PollingRequired:false}) break;
                        await AsyncTiming.Delay(PollInterval, stop.Token).ConfigureAwait(false);
                    } while (!stop.IsCancellationRequested);
                }
                if (entity.Mode == EntityMode.Sample) {
                    try {await AsyncTiming.Wait(firstSample.Task, ReadTimeout - deadline.Elapsed, stop.Token).ConfigureAwait(false);}
                    catch (TimeoutException error) {throw new DeviceReadoutException(ErrorCode.ReadTimeout, "No first sample before the deadline.", error);}
                }
                if (subscription is not null) await Task.Delay(Timeout.InfiniteTimeSpan, stop.Token).ConfigureAwait(false);
            }
            catch (OperationCanceledException) when (stop.IsCancellationRequested) { }
            catch (Exception error) {Fail(error);}
            finally {
                Interlocked.Exchange(ref releaseRequested, 1);
                _ = Release(Interlocked.Exchange(ref allocated, null));
                incoming.Writer.TryComplete();
            }
        }
    }

    private async Task Release(ICollectorSubscription? subscription)
    {
        if (subscription is null) return;
        try {await AsyncTiming.Wait(context.Worker.Cleanup(subscription.Dispose), ReadTimeout, CancellationToken.None).ConfigureAwait(false);}
        catch (TimeoutException) { /* The caller stops waiting; cleanup still runs when the native lane is available. */ }
        catch (DeviceReadoutException) { /* An already closed/broken context cannot deliver another stream error. */ }
    }
    public void Dispose() => context.Dispose();
}
