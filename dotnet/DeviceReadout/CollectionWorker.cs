using System.Collections.Concurrent;

namespace DeviceReadout;

/// <summary>One bounded, lazy, background collection lane; never uses the host synchronization context.</summary>
internal sealed class CollectionWorker : IDisposable
{
    private sealed record Work(Action Run, Action Cancel, bool IsRead = true);
    // Reads stay bounded; cleanup for already owned subscriptions must always have a slot.
    private readonly BlockingCollection<Work> queue = new();
    private int queuedReads;
    private readonly object gate = new();
    private Thread? thread;
    private bool disposed;
    internal Action? OnStopped;

    internal async Task<T> Run<T>(Func<CancellationToken, T> collect, TimeSpan timeout, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        using var cancellation = CancellationTokenSource.CreateLinkedTokenSource(token);
        var completion = new TaskCompletionSource<T>(TaskCreationOptions.RunContinuationsAsynchronously);
        AsyncTiming.ObserveFailure(completion.Task);
        var work = new Work(() => {
            if (cancellation.IsCancellationRequested) {completion.TrySetCanceled();return;}
            try {completion.TrySetResult(collect(cancellation.Token));}
            catch (OperationCanceledException) {completion.TrySetCanceled();}
            catch (DeviceReadoutException error) {completion.TrySetException(error);}
            catch (UnauthorizedAccessException error) {completion.TrySetException(new DeviceReadoutException(ErrorCode.PermissionDenied, error.Message, error));}
            catch (Exception error) {completion.TrySetException(new DeviceReadoutException(ErrorCode.ReadFailed, error.Message, error));}
        }, () => completion.TrySetCanceled());
        lock (gate)
        {
            if (disposed) throw new DeviceReadoutException(ErrorCode.EntityRemoved, "DeviceAccess is closed.");
            if (thread is null) {
                thread = new Thread(Consume) {IsBackground = true, Name = "DeviceReadout collector"};
                thread.Start();
            }
            if (queuedReads == 128) throw new DeviceReadoutException(ErrorCode.ReadFailed, "The collection queue is full.");
            queuedReads++;queue.Add(work);
        }
        try {return await AsyncTiming.Wait(completion.Task, timeout, token).ConfigureAwait(false);}
        catch (TimeoutException error) {cancellation.Cancel();throw new DeviceReadoutException(ErrorCode.ReadTimeout, "Read deadline exceeded.", error);}
        catch (OperationCanceledException) {cancellation.Cancel();throw;}
    }

    internal Task<bool> Cleanup(Action release)
    {
        var completion = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        AsyncTiming.ObserveFailure(completion.Task);
        var work = new Work(() => {
            try {release();completion.TrySetResult(true);}
            catch (Exception error) {completion.TrySetException(new DeviceReadoutException(ErrorCode.ReadFailed, "Subscription cleanup failed.", error));}
        }, () => completion.TrySetResult(false), IsRead: false);
        lock (gate) {
            // Context.OnStopped releases tracked subscriptions after the lane has stopped.
            if (disposed) return Task.FromResult(false);
            queue.Add(work);
        }
        return completion.Task;
    }

    private void Consume()
    {
        try {
            foreach (var work in queue.GetConsumingEnumerable()) {
                lock (gate) {if (work.IsRead) queuedReads--;}
                work.Run();
            }
        }
        finally {OnStopped?.Invoke();lock (gate) queue.Dispose();}
    }
    public void Dispose()
    {
        lock (gate) {
            if (disposed) return;
            disposed = true;queue.CompleteAdding();
            while (queue.TryTake(out var work)) {if (work.IsRead) queuedReads--;work.Cancel();}
            if (thread is null) {
                thread = new Thread(Consume) {IsBackground = true, Name = "DeviceReadout collector"};
                thread.Start();
            }
        }
        // Never Join a collector that may be blocked in a native call on the application's thread.
    }
}
