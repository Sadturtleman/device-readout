namespace DeviceReadout;

public enum PermissionStatus { Granted, Denied, NotDetermined, Restricted, Unavailable }
/// <summary>Identifies the requested target, including its native or app-observed namespace.</summary>
public sealed record PermissionRequest(EntityKind Kind, string? TargetId, bool Observed = false);

internal sealed class ObserverFailureOwner(EntityAddress address)
{
    internal readonly EntityAddress Address = address;
    internal bool Closed;
    internal DeviceReadoutException? Error;
}

/// <summary>An independent provider failure slot; application policy and other owners remain intact.</summary>
public sealed class ObserverFailureSource : IDisposable
{
    private readonly DeviceAccess.Context context;
    private readonly ObserverFailureOwner owner;
    internal ObserverFailureSource(DeviceAccess.Context context, ObserverFailureOwner owner)
        => (this.context, this.owner) = (context, owner);
    public void Publish(DeviceReadoutException? error)
    {
        if (context.Lifetime.IsCancellationRequested) throw new DeviceReadoutException(ErrorCode.EntityRemoved, "DeviceAccess is closed.");
        context.Collector.SourceFailure(owner, error);
    }
    /// <summary>Releases only this owner; repeated disposal and disposal after context closure are safe.</summary>
    public void Dispose() => context.Collector.ReleaseFailure(owner);
}

internal sealed class ActionSubscription(Action dispose, bool pollingRequired = false) : ICollectorSubscription
{
    private Action? action = dispose;
    public bool PollingRequired { get; } = pollingRequired;
    public void Dispose() => Interlocked.Exchange(ref action, null)?.Invoke();
}

internal sealed class ObservedCollector(IDeviceCollector source) : IDeviceCollector
{
    internal readonly record struct Activity(bool Active, long Generation);
    public void Dispose() => source.Dispose();
    private sealed record FailureRecord(long Revision, DeviceReadoutException Error);
    private sealed class FailureListener(EntityAddress address, Action<Exception> fail)
    {
        internal readonly EntityAddress Address = address;
        internal readonly Action<Exception> Fail = fail;
    }
    private sealed class State(EntityMode mode)
    {
        internal readonly EntityMode Mode = mode;
        internal DeviceSnapshot? Value;
        internal ObservedSensorSource? SensorSource;
        internal bool Removed;
        internal TaskCompletionSource<DeviceSnapshot> First = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly List<(Action<DeviceSnapshot> Emit, Action<Exception> Fail)> Listeners = [];
    }
    private readonly object gate = new();
    private readonly Dictionary<EntityAddress, State> states = [];
    private readonly Dictionary<EntityKind, EntityAddress?> current = [];
    private readonly Dictionary<EntityAddress, DeviceReadoutException> failures = [];
    private readonly Dictionary<EntityAddress, List<ObserverFailureOwner>> sourceFailures = [];
    private readonly Dictionary<EntityAddress, FailureRecord> failureHistory = [];
    private long failureRevision;
    private readonly List<FailureListener> failureListeners = [];
    private readonly Dictionary<EntityAddress, PermissionStatus?> permissions = [];
    private readonly Dictionary<EntityAddress, List<Action<PermissionStatus?>>> permissionListeners = [];
    private Func<PermissionRequest, CancellationToken, Task>? coordinator;
    private Activity activity = new(true, 0);
    private readonly List<Action<Activity>> activityListeners = [];

    internal void SensorActivity(bool active)
    {
        Action<Activity>[] listeners;Activity next;
        lock (gate) {
            if (activity.Active == active) return;
            activity = next = new(active, activity.Generation + 1);listeners = activityListeners.ToArray();
        }
        foreach (var listener in listeners) listener(next);
    }
    internal bool IsActive(long generation) {lock (gate) return activity.Active && activity.Generation == generation;}
    internal IDisposable OnActivity(Action<Activity> listener)
    {
        Activity initial;lock (gate) {activityListeners.Add(listener);initial = activity;}
        listener(initial);
        return new ActionSubscription(() => {lock (gate) activityListeners.Remove(listener);});
    }
    internal IDisposable OnFailure(EntityAddress address, Action<Exception> fail)
    {
        var listener = new FailureListener(address, fail);
        lock (gate) {AssertAvailable(address);failureListeners.Add(listener);}
        return new ActionSubscription(() => {lock (gate) failureListeners.Remove(listener);});
    }

    internal void Register(EntityAddress address, EntityMode mode) {lock (gate) states.TryAdd(address, new(mode));}
    internal IDisposable RegisterSensorSource(EntityAddress address, ObservedSensorSource sensorSource)
    {
        State state;
        lock (gate) {
            if (!address.Observed || !states.TryGetValue(address, out state!) || state.Mode == EntityMode.State)
                throw new DeviceReadoutException(ErrorCode.InvalidConfiguration, "Expected an app-owned sensor target.");
            if (state.Removed) throw new DeviceReadoutException(ErrorCode.EntityRemoved, "Observed sensor was removed.");
            if (state.SensorSource is not null) throw new DeviceReadoutException(ErrorCode.InvalidConfiguration, "A sensor source is already registered for this target.");
            state.SensorSource = sensorSource;state.Value = null;
        }
        return new ActionSubscription(() => Remove(address, state.Mode, sensorSource));
    }
    internal void Publish(EntityAddress address, EntityMode mode, DeviceSnapshot snapshot)
    {
        Action<DeviceSnapshot>[] listeners;
        lock (gate) {
            if (!states.TryGetValue(address, out var state)) states[address] = state = new(mode);
            if (state.Removed) return;
            state.Value = snapshot;state.First.TrySetResult(snapshot);
            listeners = FailureFor(address) is null ? state.Listeners.Select(listener => listener.Emit).ToArray() : [];
        }
        foreach(var emit in listeners) emit(snapshot);
    }
    internal void Remove(EntityAddress address, EntityMode mode, ObservedSensorSource? expectedSource = null)
    {
        var error = new DeviceReadoutException(ErrorCode.EntityRemoved, "Observed target was removed.");
        Action<Exception>[] listeners;
        lock (gate) {
            if (!states.TryGetValue(address, out var state)) states[address] = state = new(mode);
            if (expectedSource is not null && !ReferenceEquals(state.SensorSource, expectedSource)) return;
            state.SensorSource = null;
            state.Removed = true;state.First.TrySetException(error);
            _ = state.First.Task.Exception;
            var native = failureListeners.Where(listener => listener.Address == address).ToArray();
            foreach (var listener in native) failureListeners.Remove(listener);
            listeners = state.Listeners.Select(listener => listener.Fail).Concat(native.Select(listener => listener.Fail)).ToArray();
            state.Listeners.Clear();
        }
        foreach(var fail in listeners) fail(error);
    }
    internal void SetCurrent(EntityKind kind, EntityAddress? address) {lock (gate) current[kind] = address;}
    private DeviceReadoutException? FailureFor(EntityAddress address) =>
        failures.GetValueOrDefault(address) ?? failures.GetValueOrDefault(new(address.Kind, null)) ??
        sourceFailures.GetValueOrDefault(address)?.FirstOrDefault()?.Error ??
        sourceFailures.GetValueOrDefault(new(address.Kind, null))?.FirstOrDefault()?.Error;
    internal ObserverFailureOwner FailureOwner(EntityAddress address)
    {
        lock (gate) {
            if (states.TryGetValue(address, out var state) && state.Removed)
                throw new DeviceReadoutException(ErrorCode.EntityRemoved, "Observed target was removed.");
            return new(address);
        }
    }
    private void ClearSourceFailure(ObserverFailureOwner owner)
    {
        owner.Error = null;
        if (sourceFailures.TryGetValue(owner.Address, out var owners)) {
            owners.Remove(owner);
            if (owners.Count == 0) sourceFailures.Remove(owner.Address);
        }
    }
    internal void ReleaseFailure(ObserverFailureOwner owner)
    {
        lock (gate) {
            if (owner.Closed) return;
            owner.Closed = true;ClearSourceFailure(owner);
        }
    }
    internal void SourceFailure(ObserverFailureOwner owner, DeviceReadoutException? error) => ChangeFailure(owner.Address, error, owner);
    private void AssertAvailable(EntityAddress address, long? since = null)
    {
        if (states.TryGetValue(address, out var state) && state.Removed) throw new DeviceReadoutException(ErrorCode.EntityRemoved, "Observed target was removed.");
        if (FailureFor(address) is { } error) throw error;
        if (since.HasValue) {
            if (failureHistory.TryGetValue(address, out var target) && target.Revision > since.Value) throw target.Error;
            if (failureHistory.TryGetValue(new(address.Kind, null), out var family) && family.Revision > since.Value) throw family.Error;
        }
    }
    internal void Failure(EntityAddress address, DeviceReadoutException? error) => ChangeFailure(address, error, null);
    private void ChangeFailure(EntityAddress address, DeviceReadoutException? error, ObserverFailureOwner? owner)
    {
        Action<Exception>[] listeners;
        lock (gate) {
            if (owner?.Closed == true) throw new DeviceReadoutException(ErrorCode.EntityRemoved, "Failure source is closed.");
            if (error is null) {
                if (owner is null) failures.Remove(address);else ClearSourceFailure(owner);
                return;
            }
            if (owner is null) failures[address] = error;
            else {
                if (!sourceFailures.TryGetValue(address, out var owners)) sourceFailures[address] = owners = [];
                if (owner.Error is null) owners.Add(owner);
                owner.Error = error;
            }
            failureHistory[address] = new(++failureRevision, error);
            var affected = states.Where(item => item.Key.Kind == address.Kind && (address.TargetId is null || item.Key == address) && !item.Value.Removed).Select(item => item.Value).ToArray();
            var native = failureListeners.Where(item => item.Address.Kind == address.Kind && (address.TargetId is null || item.Address == address)).ToArray();
            foreach (var listener in native) failureListeners.Remove(listener);
            listeners = affected.SelectMany(state => state.Listeners.Select(listener => listener.Fail)).Concat(native.Select(item => item.Fail)).ToArray();
            foreach (var state in affected) {
                state.Value = null;state.First.TrySetException(error);_ = state.First.Task.Exception;
                state.First = new(TaskCreationOptions.RunContinuationsAsynchronously);state.Listeners.Clear();
            }
        }
        foreach (var fail in listeners) fail(error);
    }
    public DeviceSnapshot Read(EntityAddress entity, CancellationToken token)
    {
        Task<DeviceSnapshot>? pending = null;
        long revision;
        lock (gate) {
            AssertAvailable(entity);
            revision = failureRevision;
            if (states.TryGetValue(entity, out var state)) {
                if (state.Value is not null && state.Mode == EntityMode.State) return state.Value;
                pending = state.First.Task;
            }
        }
        var value = pending is null ? source.Read(entity, token) : pending.WaitAsync(token).GetAwaiter().GetResult();
        lock (gate) AssertAvailable(entity, revision);
        return value;
    }
    public ICollectorSubscription? Observe(EntityAddress entity, SensorSamplingRate rate, Action<DeviceSnapshot> emit, Action<Exception> fail, CancellationToken token)
        => Observe(entity, rate, emit, fail, token, false);
    internal ICollectorSubscription? Observe(EntityAddress entity, SensorSamplingRate rate, Action<DeviceSnapshot> emit, Action<Exception> fail, CancellationToken token, bool allowPolling,
        Action<Func<CancellationToken, DeviceSnapshot>>? changed = null)
    {
        ObservedSensorSource? sensorSource = null;
        lock (gate) {
            AssertAvailable(entity);
            if (states.TryGetValue(entity, out var state)) {
                if (state.Removed) throw new DeviceReadoutException(ErrorCode.EntityRemoved, "Observed target was removed.");
                sensorSource = state.SensorSource;
                if (sensorSource is null) {
                    var listener = (emit, fail);state.Listeners.Add(listener);
                    return new ActionSubscription(() => {lock (gate) state.Listeners.Remove(listener);});
                }
            }
        }
        var failureListener = new FailureListener(entity, fail);
        long sourceRevision;
        lock (gate) {AssertAvailable(entity);sourceRevision = failureRevision;failureListeners.Add(failureListener);}
        ICollectorSubscription? native = null, changes = null;
        try {
            void Publish(DeviceSnapshot snapshot) {
                try {lock (gate) AssertAvailable(entity, sourceRevision);emit(snapshot);}
                catch (Exception error) {fail(error);}
            }
            token.ThrowIfCancellationRequested();
            native = sensorSource is null ? source.Observe(entity, rate, emit, fail, token) : sensorSource.Subscribe(rate, Publish, fail, token);
            if (allowPolling && changed is not null) changes = source.ObserveChanges(entity, read => {
                try {
                    long revision;lock (gate) {AssertAvailable(entity);revision = failureRevision;}
                    changed(cancellation => {
                        lock (gate) AssertAvailable(entity, revision);
                        var value = read(cancellation);
                        lock (gate) AssertAvailable(entity, revision);
                        return value;
                    });
                } catch (Exception error) {fail(error);}
            }, fail, token);
            if (native is null && !allowPolling) {
                lock (gate) failureListeners.Remove(failureListener);
                return null;
            }
            return new ActionSubscription(() => {
                lock (gate) failureListeners.Remove(failureListener);
                try {native?.Dispose();} finally {changes?.Dispose();}
            }, (native?.PollingRequired ?? false) || (changes?.PollingRequired ?? false) || (native is null && changes is null));
        }
        catch {
            lock (gate) failureListeners.Remove(failureListener);
            try {native?.Dispose();} finally {changes?.Dispose();}
            throw;
        }
    }
    public IReadOnlyList<string> List(EntityKind kind, CancellationToken token)
        => ListAddresses(kind, token).Select(address => address.TargetId!).ToArray();
    private bool HasObservedInventory(EntityKind kind) =>
        states.Keys.Any(address => address.Kind == kind && address.Observed) || current.ContainsKey(kind) && current[kind] is null;
    internal IReadOnlyList<EntityAddress> ListAddresses(EntityKind kind, CancellationToken token)
    {
        long revision;
        lock (gate) {
            AssertAvailable(new(kind, null));
            revision = failureRevision;
            if (HasObservedInventory(kind)) return states.Where(item => item.Key.Kind == kind && item.Key.Observed && !item.Value.Removed)
                .Select(item => item.Key).ToArray();
        }
        var result = source.List(kind, token);
        lock (gate) AssertAvailable(new(kind, null), revision);
        return result.Select(id => new EntityAddress(kind, id)).ToArray();
    }
    public string? Current(EntityKind kind, CancellationToken token)
        => CurrentAddress(kind, token)?.TargetId;
    internal EntityAddress? CurrentAddress(EntityKind kind, CancellationToken token)
    {
        long revision;
        lock (gate) {
            AssertAvailable(new(kind, null));
            revision = failureRevision;
            if (current.TryGetValue(kind, out var address)) return address is { } selected && states.TryGetValue(selected, out var state) && state.Removed ? null : address;
            if (HasObservedInventory(kind)) return null;
        }
        var result = source.Current(kind, token);
        lock (gate) AssertAvailable(new(kind, null), revision);
        return result is null ? null : new(kind, result);
    }
    public EntityCapabilities Capabilities(EntityAddress entity)
        => Capabilities(entity, CancellationToken.None);
    public EntityCapabilities Capabilities(EntityAddress entity, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        lock (gate) {if (states.TryGetValue(entity, out var state)) return new(!state.Removed, !state.Removed);}
        return source.Capabilities(entity, token);
    }
    public SensorDescription Describe(EntityAddress entity, CancellationToken token)
    {
        long revision;
        lock (gate) {
            AssertAvailable(entity);
            revision = failureRevision;
            if (states.TryGetValue(entity, out var state)) {
                if (state.Removed) throw new DeviceReadoutException(ErrorCode.EntityRemoved, "Observed sensor was removed.");
                if (state.Mode == EntityMode.State) throw new DeviceReadoutException(ErrorCode.UnsupportedEntity, "Expected a sensor.");
                return state.SensorSource?.Description ?? new SensorDescription {Kind = Enum.TryParse<SensorKind>(entity.Kind.ToString(), out var kind) ? kind : null};
            }
        }
        var result = source.Describe(entity, token);
        lock (gate) AssertAvailable(entity, revision);
        return result;
    }

    private PermissionStatus? PermissionFor(EntityAddress entity) =>
        permissions.TryGetValue(entity, out var value) ? value : permissions.GetValueOrDefault(new(entity.Kind));
    internal PermissionStatus? CheckPermission(EntityAddress entity) {lock (gate) return PermissionFor(entity);}
    internal void Permission(EntityAddress entity, PermissionStatus? status)
    {
        if (status.HasValue && !Enum.IsDefined(status.Value)) status = null;
        Action<PermissionStatus?>[] listeners;
        lock (gate) {
            permissions[entity] = status;
            listeners = permissionListeners.Where(pair => pair.Key == entity ||
                entity.TargetId is null && pair.Key.Kind == entity.Kind && !permissions.ContainsKey(pair.Key))
                .SelectMany(pair => pair.Value).ToArray();
        }
        foreach(var listener in listeners) listener(status);
    }
    internal IDisposable Coordinate(Func<PermissionRequest, CancellationToken, Task> value)
    {
        lock (gate) {
            if (coordinator is not null) throw new DeviceReadoutException(ErrorCode.InvalidConfiguration, "A permission coordinator is already registered.");
            coordinator = value;
        }
        return new ActionSubscription(() => {lock (gate) if (coordinator == value) coordinator = null;});
    }
    internal async Task<PermissionStatus?> RequestPermission(EntityAddress entity, CancellationToken token)
    {
        var completion = new TaskCompletionSource<PermissionStatus?>(TaskCreationOptions.RunContinuationsAsynchronously);
        Action<PermissionStatus?> listener = value => completion.TrySetResult(value);
        Func<PermissionRequest, CancellationToken, Task> request;
        List<Action<PermissionStatus?>> listeners;
        lock (gate) {
            if (PermissionFor(entity) == PermissionStatus.Granted) return PermissionStatus.Granted;
            request = coordinator ?? throw new DeviceReadoutException(ErrorCode.UnsupportedEntity, "Register the application's permission coordinator.");
            if (!permissionListeners.TryGetValue(entity, out listeners!)) permissionListeners[entity] = listeners = [];
            listeners.Add(listener);
        }
        using var lifetime = new CancellationScope(token);
        try {
            // This callback is application-owned. It must dispatch UI work to the application's UI dispatcher.
            var coordination = request(new(entity.Kind, entity.TargetId, entity.Observed), lifetime.Token);
            AsyncTiming.ObserveFailure(coordination);
            var observed = completion.Task.WaitAsync(lifetime.Token);
            var first = await Task.WhenAny(coordination, observed).ConfigureAwait(false);
            if (first == coordination) await coordination.ConfigureAwait(false);
            return await observed.ConfigureAwait(false);
        }
        catch (OperationCanceledException) {throw;}
        catch (DeviceReadoutException) {throw;}
        catch (Exception error) {throw new DeviceReadoutException(ErrorCode.ReadFailed, "Permission coordinator failed.", error);}
        finally {
            lifetime.Cancel();lock (gate) {listeners.Remove(listener);if (listeners.Count == 0) permissionListeners.Remove(entity);}
        }
    }
}

/// <summary>Receives app-owned UI and permission state. No UI getters or permission dialogs are invoked.</summary>
public sealed class ObserverInputs
{
    private readonly DeviceAccess.Context context;
    internal ObserverInputs(DeviceAccess.Context context) => this.context = context;
    private void Open() {if (context.Lifetime.IsCancellationRequested) throw new DeviceReadoutException(ErrorCode.EntityRemoved, "DeviceAccess is closed.");}
    public Entity<T> Target<T>(Entity<T> kind, string id) where T : DeviceSnapshot
    {
        Open();_ = kind.Address(context, true);
        if (!kind.RequiresTarget || kind.TargetId is not null || string.IsNullOrEmpty(id)) throw new DeviceReadoutException(ErrorCode.InvalidConfiguration, "Expected an unbound multi-target kind and nonempty ID.");
        var entity = kind.Bind(context, id, observed: true);context.Collector.Register(entity.Address(context), kind.Mode);return entity;
    }
    public void Publish<T>(Entity<T> entity, T snapshot) where T : DeviceSnapshot {Open();context.Collector.Publish(entity.Address(context), entity.Mode, snapshot);}
    public void Remove<T>(Entity<T> entity) where T : DeviceSnapshot {Open();context.Collector.Remove(entity.Address(context), entity.Mode);}
    public void Current<T>(Entity<T> kind, Entity<T>? target) where T : DeviceSnapshot
    {
        Open();_ = kind.Address(context, true);
        if (!kind.RequiresTarget || (target is not null && target.Kind != kind.Kind)) throw new DeviceReadoutException(ErrorCode.InvalidConfiguration, "Expected a target of the same kind.");
        context.Collector.SetCurrent(kind.Kind, target?.Address(context));
    }
    public void Permission<T>(Entity<T> entity, PermissionStatus? status) where T : DeviceSnapshot {Open();context.Collector.Permission(entity.Address(context, true), status);}
    /// <summary>Feeds app foreground/visibility policy. Desktop focus loss alone need not deactivate sensors.</summary>
    public void SensorActivity(bool active) {Open();context.Collector.SensorActivity(active);}
    /// <summary>Reports or clears an application observer failure for a target or an entire entity kind.</summary>
    public void Failure<T>(Entity<T> entity, DeviceReadoutException? error) where T : DeviceSnapshot {Open();context.Collector.Failure(entity.Address(context, true), error);}
    /// <summary>Creates an inert, independently disposable provider error slot for a target or entity kind.</summary>
    public ObserverFailureSource FailureSource<T>(Entity<T> entity) where T : DeviceSnapshot
    {
        Open();return new(context, context.Collector.FailureOwner(entity.Address(context, true)));
    }
    /// <summary>Registers an inert sensor source. Subscribe and returned cleanup run on the collector worker.</summary>
    public IDisposable SensorSource<T>(Entity<T> entity, Func<SensorObserverSession<T>, IDisposable?> subscribe, SensorDescription? description = null) where T : DeviceSnapshot
    {
        Open();var address = entity.Address(context);
        if (entity.Mode == EntityMode.State || subscribe is null)
            throw new DeviceReadoutException(ErrorCode.InvalidConfiguration, "Expected a sensor target and subscription callback.");
        var metadata = (description ?? new()) with {Kind = Enum.TryParse<SensorKind>(entity.Kind.ToString(), out var kind) ? kind : null};
        return context.Collector.RegisterSensorSource(address, new(metadata, (rate, emit, fail, token) => {
            var session = new SensorObserverSession<T>(rate, token, emit, fail);
            try {
                var cleanup = subscribe(session);
                return new ActionSubscription(() => {session.Stop();cleanup?.Dispose();});
            } catch {session.Stop();throw;}
        }));
    }
    public IDisposable OnPermissionRequest(Func<PermissionRequest, CancellationToken, Task> coordinator) {Open();return context.Collector.Coordinate(coordinator);}
}

public sealed class PermissionAccess
{
    private readonly DeviceAccess.Context context;
    internal PermissionAccess(DeviceAccess.Context context) => this.context = context;
    public Task<PermissionStatus?> Check<T>(Entity<T> entity, CancellationToken token = default) where T : DeviceSnapshot
    {token.ThrowIfCancellationRequested();return Task.FromResult(context.Collector.CheckPermission(entity.Address(context, true)));}
    public async Task<PermissionStatus?> Request<T>(Entity<T> entity, CancellationToken token = default) where T : DeviceSnapshot
    {
        if (context.Lifetime.IsCancellationRequested) throw new DeviceReadoutException(ErrorCode.EntityRemoved, "DeviceAccess is closed.");
        using var linked = new CancellationScope(token, context.Lifetime.Token);
        return await context.Collector.RequestPermission(entity.Address(context, true), linked.Token).ConfigureAwait(false);
    }
}
