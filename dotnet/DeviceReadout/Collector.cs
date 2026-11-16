namespace DeviceReadout;

/// <summary>All collector methods are dispatched away from the calling/UI thread.</summary>
public interface IDeviceCollector : IDisposable
{
    /// <summary>Releases context-owned native resources on the collection worker after subscriptions stop.</summary>
    void IDisposable.Dispose() { }
    DeviceSnapshot Read(EntityAddress entity, CancellationToken cancellationToken);
    IReadOnlyList<string> List(EntityKind kind, CancellationToken cancellationToken)
        => throw new DeviceReadoutException(ErrorCode.UnsupportedEntity, "Target discovery is unavailable.");
    string? Current(EntityKind kind, CancellationToken cancellationToken) => null;
    SensorDescription Describe(EntityAddress sensor, CancellationToken cancellationToken)
        => throw new DeviceReadoutException(ErrorCode.UnsupportedEntity, "Sensor descriptions are unavailable.");
    EntityCapabilities Capabilities(EntityAddress entity) => new(null, null);
    /// <summary>Override for capability probes that perform cancellable native work.</summary>
    EntityCapabilities Capabilities(EntityAddress entity, CancellationToken cancellationToken)
    {cancellationToken.ThrowIfCancellationRequested();return Capabilities(entity);}
    ICollectorSubscription? Observe(EntityAddress entity, SensorSamplingRate samplingRate,
        Action<DeviceSnapshot> emit, Action<Exception> fail, CancellationToken cancellationToken) => null;
    /// <summary>State callbacks copy event data and enqueue a read; the SDK executes that read on its collection lane with a deadline.</summary>
    ICollectorSubscription? ObserveChanges(EntityAddress entity, Action<Func<CancellationToken, DeviceSnapshot>> changed,
        Action<Exception> fail, CancellationToken cancellationToken) => null;
}

public interface ICollectorSubscription : IDisposable
{
    bool PollingRequired { get; }
}
