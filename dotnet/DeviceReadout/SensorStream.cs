using System.Diagnostics;
using System.Runtime.CompilerServices;
using System.Threading.Channels;

namespace DeviceReadout;

public sealed partial class DeviceAccess
{
    private async IAsyncEnumerable<T> SensorWatch<T>(Entity<T> entity, SensorSamplingRate rate,
        [EnumeratorCancellation] CancellationToken cancellationToken) where T : DeviceSnapshot
    {
        var address = entity.Address(context);
        using var linked = Link(cancellationToken);
        using var stop = new CancellationScope(linked.Token);
        var output = Channel.CreateBounded<T>(2048);
        var activities = Channel.CreateBounded<ObservedCollector.Activity>(64);
        var activityGate = new object();
        CancellationScope? activeScope = null;
        long latestGeneration = -1;
        void Fail(Exception error)
        {
            var failure = error as DeviceReadoutException ?? new(ErrorCode.ReadFailed, "Sensor source failed.", error);
            output.Writer.TryComplete(failure);stop.Cancel();
        }
        void ActivityChanged(ObservedCollector.Activity state)
        {
            lock (activityGate) {
                if (state.Generation <= latestGeneration) return;
                latestGeneration = state.Generation;
                activeScope?.Cancel();
                if (!stop.IsCancellationRequested && !activities.Writer.TryWrite(state))
                    Fail(new DeviceReadoutException(ErrorCode.ReadFailed, "Sensor lifecycle updates exceeded the bounded queue."));
            }
        }
        var pump = Pump();
        try {
            await using var reader = output.Reader.ReadAllAsync(linked.Token).GetAsyncEnumerator();
            while (true) {
                bool next;
                try {next = await reader.MoveNextAsync().ConfigureAwait(false);}
                catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) {
                    throw new OperationCanceledException(cancellationToken);
                }
                if (!next) break;
                yield return reader.Current;
            }
        } finally {
            linked.Cancel();await pump.ConfigureAwait(false);
        }

        async Task Pump()
        {
            try {
                using var activity = context.Collector.OnActivity(ActivityChanged);
                using var failure = context.Collector.OnFailure(address, Fail);
                await foreach (var state in activities.Reader.ReadAllAsync(stop.Token).ConfigureAwait(false)) {
                    if (!state.Active || !context.Collector.IsActive(state.Generation)) continue;
                    using var session = new CancellationScope(stop.Token);
                    lock (activityGate) {
                        activeScope = session;
                        if (latestGeneration != state.Generation || !context.Collector.IsActive(state.Generation)) session.Cancel();
                    }
                    var samples = Channel.CreateBounded<DeviceSnapshot>(2048);
                    ICollectorSubscription? allocated = null;
                    var releaseRequested = 0;
                    Action? cancelNative = null;
                    void RegisterCancellation(Action cancel)
                    {
                        Interlocked.Exchange(ref cancelNative, cancel);
                        if (Volatile.Read(ref releaseRequested) != 0) Interlocked.Exchange(ref cancelNative, null)?.Invoke();
                    }
                    bool Current() => !session.IsCancellationRequested && context.Collector.IsActive(state.Generation);
                    void Publish(DeviceSnapshot snapshot)
                    {
                        if (Current() && !samples.Writer.TryWrite(snapshot))
                            Fail(new DeviceReadoutException(ErrorCode.ReadFailed, "Sensor samples exceeded the bounded queue."));
                    }
                    void SourceFailed(Exception error) {if (Current()) Fail(error);}
                    var deadline = Stopwatch.StartNew();
                    try {
                        var subscription = await context.Worker.Run(workerToken => {
                            var created = context.Observe(address, entity.Mode, rate, Publish, SourceFailed, session.Token, registerCancellation: RegisterCancellation);
                            Interlocked.Exchange(ref allocated, created);
                            // Cancellation may win the await even when native registration just returned.
                            if (Volatile.Read(ref releaseRequested) != 0) _ = Release(Interlocked.Exchange(ref allocated, null));
                            return created;
                        }, ReadTimeout, session.Token).ConfigureAwait(false);
                        if (subscription is null) throw new DeviceReadoutException(ErrorCode.UnsupportedEntity, "Sensor observation is unavailable.");
                        var firstSample = entity.Mode == EntityMode.Sample;
                        while (Current()) {
                            var next = samples.Reader.ReadAsync(session.Token).AsTask();
                            var raw = firstSample
                                ? await AsyncTiming.Wait(next, ReadTimeout - deadline.Elapsed, session.Token).ConfigureAwait(false)
                                : await next.ConfigureAwait(false);
                            if (!Current()) break;
                            var remaining = firstSample ? ReadTimeout - deadline.Elapsed : ReadTimeout;
                            var value = await context.Worker.Run(_ => Stamp<T>(raw), remaining, session.Token).ConfigureAwait(false);
                            if (!Current()) break;
                            if (!output.Writer.TryWrite(value))
                                throw new DeviceReadoutException(ErrorCode.ReadFailed, "Consumer cannot keep up with the bounded sensor queue.");
                            firstSample = false;
                        }
                    } catch (Exception) when (!Current()) {
                        // A superseded session cannot fail its replacement or deliver an old normalized sample.
                    } catch (TimeoutException error) {
                        throw new DeviceReadoutException(ErrorCode.ReadTimeout, "No first sensor sample before the deadline.", error);
                    } finally {
                        session.Cancel();samples.Writer.TryComplete();
                        lock (activityGate) {if (ReferenceEquals(activeScope, session)) activeScope = null;}
                        Interlocked.Exchange(ref releaseRequested, 1);
                        // Set the native token immediately; its external callbacks still run asynchronously.
                        Interlocked.Exchange(ref cancelNative, null)?.Invoke();
                        _ = Release(Interlocked.Exchange(ref allocated, null));
                    }
                }
            } catch (OperationCanceledException) when (stop.IsCancellationRequested) { }
            catch (Exception error) {Fail(error);}
            finally {output.Writer.TryComplete();activities.Writer.TryComplete();}
        }
    }
}
