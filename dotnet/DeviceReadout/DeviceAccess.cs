using System.Collections.Immutable;
using System.Runtime.CompilerServices;
using System.Threading.Channels;
using System.Collections.Concurrent;
using System.Diagnostics;

namespace DeviceReadout;

public sealed class DeviceAccess : IDisposable
{
    internal sealed class Context : IDisposable
    {
        internal readonly CollectionWorker Worker = new();
        internal readonly CancellationTokenSource Lifetime = new();
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
            };
        }
        internal ICollectorSubscription? Observe(EntityAddress address, EntityMode mode, SensorSamplingRate rate, Action<DeviceSnapshot> emit, Action<Exception> fail, CancellationToken token,
            Action<Func<CancellationToken, DeviceSnapshot>>? changed = null)
        {
            var native = Collector.Observe(address, rate, emit, fail, token, mode == EntityMode.State, changed);
            if (native is null) return null;
            ICollectorSubscription? tracked = null;
            tracked = new ActionSubscription(() => {try {native.Dispose();} finally {subscriptions.TryRemove(tracked!, out _);}}, native.PollingRequired);
            subscriptions.TryAdd(tracked, 0);
            if (token.IsCancellationRequested || Lifetime.IsCancellationRequested) {tracked.Dispose();token.ThrowIfCancellationRequested();}
            return tracked;
        }
        public void Dispose() {if (!Lifetime.IsCancellationRequested) Lifetime.Cancel();Worker.Dispose();}
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
    private CancellationTokenSource Link(CancellationToken cancellationToken)
    {
        if (context.Lifetime.IsCancellationRequested) throw new DeviceReadoutException(ErrorCode.EntityRemoved, "DeviceAccess is closed.");
        return CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, context.Lifetime.Token);
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
        var completion = new TaskCompletionSource<DeviceSnapshot>(TaskCreationOptions.RunContinuationsAsynchronously);
        AsyncTiming.ObserveFailure(completion.Task);
        var deadline = Stopwatch.StartNew();
        ICollectorSubscription? subscription = null;
        try {
            subscription = await context.Worker.Run(token => context.Observe(address, entity.Mode, SensorSamplingRate.PlatformDefault,
                value => completion.TrySetResult(value),
                error => completion.TrySetException(error), linked.Token), ReadTimeout, linked.Token).ConfigureAwait(false);
            if (subscription is null) throw new DeviceReadoutException(ErrorCode.UnsupportedEntity, "Sensor observation is unavailable.");
            try {
                var raw = await AsyncTiming.Wait(completion.Task, ReadTimeout - deadline.Elapsed, linked.Token).ConfigureAwait(false);
                return await context.Worker.Run(_ => Stamp<T>(raw), ReadTimeout - deadline.Elapsed, linked.Token).ConfigureAwait(false);
            }
            catch (TimeoutException error) {throw new DeviceReadoutException(ErrorCode.ReadTimeout, "No sensor sample before the deadline.", error);}
        } finally {
            linked.Cancel();_ = Release(subscription);
        }
    }

    public async Task<ImmutableArray<Entity<T>>> List<T>(Entity<T> kind, CancellationToken cancellationToken = default) where T : DeviceSnapshot
    {
        _ = kind.Address(context, true);
        using var linked = Link(cancellationToken);
        return await context.Worker.Run(token => context.Collector.List(kind.Kind, token).Select(id => kind.Bind(context, id)).ToImmutableArray(), ReadTimeout, linked.Token).ConfigureAwait(false);
    }
    public async Task<Entity<T>?> Current<T>(Entity<T> kind, CancellationToken cancellationToken = default) where T : DeviceSnapshot
    {
        _ = kind.Address(context, true);
        using var linked = Link(cancellationToken);
        var id = await context.Worker.Run(token => context.Collector.Current(kind.Kind, token), ReadTimeout, linked.Token).ConfigureAwait(false);
        return id is null ? null : kind.Bind(context, id);
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
        return await context.Worker.Run(_ => context.Collector.Capabilities(address), ReadTimeout, linked.Token).ConfigureAwait(false);
    }

    private sealed record SnapshotInput(Func<CancellationToken, DeviceSnapshot> Read, TaskCompletionSource? Completed = null);

    public async IAsyncEnumerable<T> Watch<T>(Entity<T> entity, [EnumeratorCancellation] CancellationToken cancellationToken = default) where T : DeviceSnapshot
    {
        var address = entity.Address(context);
        using var linked = Link(cancellationToken);
        var queue = Channel.CreateBounded<T>(new BoundedChannelOptions(2048) {SingleReader = true, FullMode = BoundedChannelFullMode.Wait});
        var incoming = Channel.CreateBounded<SnapshotInput>(new BoundedChannelOptions(2048) {SingleReader = true, FullMode = BoundedChannelFullMode.Wait});
        using var stop = CancellationTokenSource.CreateLinkedTokenSource(linked.Token);
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
            ICollectorSubscription? subscription = null;
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
                subscription = await context.Worker.Run(_ => context.Observe(address, entity.Mode, rate, Emit, Fail, stop.Token, Changed), ReadTimeout, stop.Token).ConfigureAwait(false);
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
            finally {await Release(subscription).ConfigureAwait(false);incoming.Writer.TryComplete();}
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
