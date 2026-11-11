namespace DeviceReadout;

internal static class AsyncTiming
{
    private static readonly TimeSpan MaximumTimer = TimeSpan.FromMilliseconds(uint.MaxValue - 2);
    internal static async Task Delay(TimeSpan duration, CancellationToken token)
    {
        while (duration > MaximumTimer) {
            await Task.Delay(MaximumTimer, token).ConfigureAwait(false);
            duration -= MaximumTimer;
        }
        await Task.Delay(duration, token).ConfigureAwait(false);
    }
    internal static async Task<T> Wait<T>(Task<T> task, TimeSpan timeout, CancellationToken token)
    {
        if (timeout <= TimeSpan.Zero) throw new TimeoutException();
        if (timeout <= MaximumTimer) return await task.WaitAsync(timeout, token).ConfigureAwait(false);
        using var lifetime = CancellationTokenSource.CreateLinkedTokenSource(token);
        var deadline = Delay(timeout, lifetime.Token);
        try {
            if (await Task.WhenAny(task, deadline).ConfigureAwait(false) == task) return await task.ConfigureAwait(false);
            token.ThrowIfCancellationRequested();throw new TimeoutException();
        } finally {lifetime.Cancel();}
    }
    internal static void ObserveFailure(Task task) => _ = task.ContinueWith(faulted => _ = faulted.Exception,
        CancellationToken.None, TaskContinuationOptions.OnlyOnFaulted | TaskContinuationOptions.ExecuteSynchronously, TaskScheduler.Default);
}
