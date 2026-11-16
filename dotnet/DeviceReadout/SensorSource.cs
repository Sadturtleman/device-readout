namespace DeviceReadout;

/// <summary>One demanded observation. Publish only native sample data; the worker normalizes and stamps it.</summary>
public sealed class SensorObserverSession<T> where T : DeviceSnapshot
{
    private readonly Action<DeviceSnapshot> emit;
    private readonly Action<Exception> fail;
    private int stopped;
    public SensorSamplingRate SamplingRate { get; }
    public CancellationToken CancellationToken { get; }
    internal SensorObserverSession(SensorSamplingRate rate, CancellationToken token, Action<DeviceSnapshot> emit, Action<Exception> fail)
        => (SamplingRate, CancellationToken, this.emit, this.fail) = (rate, token, emit, fail);
    public void Publish(T snapshot)
    {
        if (Volatile.Read(ref stopped) != 0 || CancellationToken.IsCancellationRequested) return;
        if (snapshot is null) {Fail(new(ErrorCode.ReadFailed, "A sensor source returned no snapshot."));return;}
        emit(snapshot);
    }
    public void Fail(DeviceReadoutException error)
    {
        if (CancellationToken.IsCancellationRequested || Interlocked.Exchange(ref stopped, 1) != 0) return;
        fail(error ?? new DeviceReadoutException(ErrorCode.ReadFailed, "A sensor source failed."));
    }
    internal void Stop() => Interlocked.Exchange(ref stopped, 1);
}

internal sealed record ObservedSensorSource(SensorDescription Description,
    Func<SensorSamplingRate, Action<DeviceSnapshot>, Action<Exception>, CancellationToken, ICollectorSubscription> Subscribe);
