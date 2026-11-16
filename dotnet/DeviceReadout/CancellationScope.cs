namespace DeviceReadout;

/// <summary>Cancellation links never invoke downstream callbacks on the upstream caller.</summary>
internal sealed class CancellationScope : IDisposable
{
    private readonly CancellationTokenSource source = new();
    private readonly CancellationTokenRegistration[] links;
    private readonly object gate = new();
    private Task? cancellation;
    private bool disposed;

    internal CancellationScope(params CancellationToken[] tokens)
    {
        links = new CancellationTokenRegistration[tokens.Length];
        for (var i = 0; i < tokens.Length; i++)
            links[i] = tokens[i].UnsafeRegister(static state => ((CancellationScope)state!).Cancel(), this);
    }
    internal CancellationToken Token => source.Token;
    internal bool IsCancellationRequested => source.IsCancellationRequested;
    internal void Cancel()
    {
        lock (gate) {
            if (disposed || cancellation is not null) return;
            cancellation = source.CancelAsync();
            AsyncTiming.ObserveFailure(cancellation);
        }
    }
    public void Dispose()
    {
        Task? pending;
        lock (gate) {
            if (disposed) return;
            disposed = true;pending = cancellation;
        }
        // Unregister does not join an upstream callback that is already executing.
        foreach (var link in links) link.Unregister();
        if (pending is null || pending.IsCompleted) source.Dispose();
        else _ = pending.ContinueWith(_ => source.Dispose(), CancellationToken.None,
            TaskContinuationOptions.ExecuteSynchronously, TaskScheduler.Default);
    }
}
