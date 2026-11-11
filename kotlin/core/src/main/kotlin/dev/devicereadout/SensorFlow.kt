package dev.devicereadout

import kotlinx.coroutines.*
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.selects.onTimeout
import kotlinx.coroutines.selects.select
import java.util.concurrent.atomic.AtomicReference
import kotlin.time.Duration
import kotlin.time.TimeSource

private sealed interface SensorMessage {
    data class Activity(val state: ObservedCollector.Activity) : SensorMessage
    data class Value(val generation: Long, val snapshot: DeviceSnapshot) : SensorMessage
    data class Failure(val generation: Long, val error: Throwable) : SensorMessage
    data class ObserverFailure(val error: Throwable) : SensorMessage
    data class Ready(val subscription: CollectorSubscription?) : SensorMessage
    data object Deadline : SensorMessage
}

@OptIn(ExperimentalCoroutinesApi::class)
internal fun <S : DeviceSnapshot> sensorFlow(
    context: DeviceAccess.Context,
    entity: Entity<S>,
    rate: SensorSamplingRate,
    timeout: Duration,
    normalize: (Entity<S>, DeviceSnapshot) -> S,
): Flow<S> = flow {
    coroutineScope {
        val address = entity.address(context)
        val messages = Channel<SensorMessage>(2048)
        val job = currentCoroutineContext()[Job]!!
        val onClose: () -> Unit = {job.cancel()}
        fun enqueue(message: SensorMessage) {
            if (!messages.trySend(message).isSuccess) messages.close(DeviceReadoutException(ErrorCode.ReadFailed, "Consumer cannot keep up with the bounded snapshot queue."))
        }
        var generation = -1L
        var pending: Deferred<CollectorSubscription?>? = null
        var allocated = AtomicReference<CollectorSubscription?>()
        var deadline: kotlin.time.TimeMark? = null
        var firstSample = true
        fun releaseSession() {
            pending?.cancel();pending = null
            context.worker.release(allocated.getAndSet(null))
            deadline = null
        }
        context.closeListeners.add(onClose)
        val lifecycle = context.collector.onActivity {enqueue(SensorMessage.Activity(it))}
        var failures: AutoCloseable? = null
        try {
            if (context.closed.get()) throw DeviceReadoutException(ErrorCode.EntityRemoved, "DeviceAccess is closed.")
            failures = context.collector.onFailure(address) {enqueue(SensorMessage.ObserverFailure(it))}
            while (currentCoroutineContext().isActive) {
                val message = select<SensorMessage> {
                    messages.onReceive {it}
                    pending?.onAwait {SensorMessage.Ready(it)}
                    deadline?.let {onTimeout((-it.elapsedNow()).coerceAtLeast(Duration.ZERO)) {SensorMessage.Deadline}}
                }
                when (message) {
                    is SensorMessage.ObserverFailure -> throw message.error
                    is SensorMessage.Activity -> {
                        if (message.state.generation <= generation) continue
                        releaseSession();generation = message.state.generation
                        if (!message.state.active || !context.collector.isActive(generation)) continue
                        firstSample = true
                        deadline = TimeSource.Monotonic.markNow() + timeout
                        val session = generation
                        val slot = AtomicReference<CollectorSubscription?>();allocated = slot
                        pending = async {
                            context.worker.call {
                                context.collector.observe(address, rate,
                                    {if (context.collector.isActive(session)) enqueue(SensorMessage.Value(session, it))},
                                    {enqueue(SensorMessage.Failure(session, it))})
                                    .also {slot.set(it)}
                            }
                        }
                    }
                    is SensorMessage.Ready -> {
                        pending = null
                        if (message.subscription == null) throw DeviceReadoutException(ErrorCode.UnsupportedEntity, "Sensor observation unavailable.")
                        if (entity.mode == EntityMode.Event || !firstSample) deadline = null
                    }
                    is SensorMessage.Value -> {
                        if (message.generation != generation || !context.collector.isActive(generation)) continue
                        val remaining = deadline?.let {-it.elapsedNow()} ?: timeout
                        val value = withTimeoutOrNull(remaining) {context.worker.call {normalize(entity, message.snapshot)}}
                            ?: throw DeviceReadoutException(ErrorCode.ReadTimeout, "Read deadline exceeded.")
                        if (!context.collector.isActive(generation)) continue
                        firstSample = false;deadline = null
                        emit(value)
                    }
                    is SensorMessage.Failure -> {
                        if (message.generation != generation || !context.collector.isActive(generation)) continue
                        throw if (message.error is DeviceReadoutException) message.error
                            else DeviceReadoutException(ErrorCode.ReadFailed, "Sensor failed.", message.error)
                    }
                    SensorMessage.Deadline -> {
                        if (context.collector.isActive(generation)) throw DeviceReadoutException(ErrorCode.ReadTimeout, "Read deadline exceeded.")
                        deadline = null
                    }
                }
            }
        } catch (cancelled: CancellationException) {
            if (context.closed.get()) throw DeviceReadoutException(ErrorCode.EntityRemoved, "DeviceAccess is closed.", cancelled)
            throw cancelled
        } finally {
            failures?.close();lifecycle.close();context.closeListeners.remove(onClose);messages.cancel();releaseSession()
        }
    }
}
