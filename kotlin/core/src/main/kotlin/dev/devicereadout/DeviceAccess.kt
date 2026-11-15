package dev.devicereadout

import kotlinx.coroutines.*
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.selects.onTimeout
import kotlinx.coroutines.selects.select
import java.util.concurrent.CopyOnWriteArraySet
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds
import kotlin.time.TimeSource

class DeviceAccess private constructor(
    private val context: Context,
    val pollInterval: Duration,
    val readTimeout: Duration,
    val sensorSamplingRate: SensorSamplingRate,
) : AutoCloseable {
    internal class Context(source: DeviceCollector) : AutoCloseable {
        val collector = ObservedCollector(source)
        val worker = CollectionWorker()
        val closed = AtomicBoolean()
        val closeListeners = CopyOnWriteArraySet<() -> Unit>()
        override fun close() {
            if (!closed.compareAndSet(false, true)) return
            closeListeners.forEach { it() };closeListeners.clear();worker.close()
        }
    }
    constructor(collector: DeviceCollector) : this(Context(collector), 1.seconds, 5.seconds, SensorSamplingRate.PlatformDefault)
    val observers = ObserverInputs(context)
    val permissions = PermissionAccess(context)
    val capabilities = CapabilityAccess(this)
    val displays get() = EntityCollection(this, DisplayEntity)
    val cpuCores get() = EntityCollection(this, CpuCoreEntity)
    val batteries get() = EntityCollection(this, BatteryEntity)
    val networkInterfaces get() = EntityCollection(this, NetworkInterfaceEntity)
    val storageVolumes get() = EntityCollection(this, StorageVolumeEntity)
    val cellularSubscriptions get() = EntityCollection(this, CellularSubscriptionEntity)
    val telephonyIdentities get() = EntityCollection(this, TelephonyIdentityEntity)
    val sensors get() = SensorCollection(this)
    fun withPollInterval(interval: Duration): DeviceAccess = DeviceAccess(context, positive(interval), readTimeout, sensorSamplingRate)
    fun withReadTimeout(timeout: Duration): DeviceAccess = DeviceAccess(context, pollInterval, positive(timeout), sensorSamplingRate)
    fun withSensorSamplingRate(rate: SensorSamplingRate): DeviceAccess = DeviceAccess(context, pollInterval, readTimeout, rate)
    private data class Result<T>(val value: T)
    private suspend fun <T> bounded(timeout: Duration = readTimeout, read: suspend () -> T): T {
        if (context.closed.get()) throw DeviceReadoutException(ErrorCode.EntityRemoved, "DeviceAccess is closed.")
        val result = withTimeoutOrNull(timeout) {Result(read())}
            ?: throw DeviceReadoutException(ErrorCode.ReadTimeout, "Read deadline exceeded.")
        return result.value
    }
    internal fun <S : DeviceSnapshot> snapshot(entity: Entity<S>, raw: DeviceSnapshot): S {
        if (!entity.snapshotType.isInstance(raw)) throw DeviceReadoutException(ErrorCode.ReadFailed, "Wrong snapshot type.")
        return entity.snapshotType.cast(stamp(raw))
    }
    suspend fun <S : DeviceSnapshot> get(entity: Entity<S>): S {
        val address = entity.address(context)
        if (entity.mode == EntityMode.State) return bounded {context.worker.call {snapshot(entity, context.collector.read(address))}}
        return bounded {sensorFlow(context, entity, SensorSamplingRate.PlatformDefault, readTimeout, ::snapshot).first()}
    }
    suspend fun <S : DeviceSnapshot> list(kind: Entity<S>): List<Entity<S>> {
        kind.address(context, collection = true)
        return bounded {context.worker.call {java.util.Collections.unmodifiableList(context.collector.listAddresses(kind.kind).map {kind.bind(context, requireNotNull(it.targetId), it.observed)})}}
    }
    internal suspend fun <S : DeviceSnapshot> listNative(kind: Entity<S>): List<Entity<S>> {
        kind.address(context, collection = true)
        return bounded {context.worker.call {java.util.Collections.unmodifiableList(context.collector.listNativeAddresses(kind.kind).map {kind.bind(context, requireNotNull(it.targetId))})}}
    }
    suspend fun <S : DeviceSnapshot> current(kind: Entity<S>): Entity<S>? {
        kind.address(context, collection = true)
        return bounded {context.worker.call {context.collector.currentAddress(kind.kind)?.let {kind.bind(context, requireNotNull(it.targetId), it.observed)}}}
    }
    internal fun hasObservedInventory(kind: EntityKind): Boolean = context.collector.hasObservedInventory(kind)
    suspend fun <S : DeviceSnapshot> describe(entity: Entity<S>): SensorDescription {
        val address = entity.address(context)
        return bounded {context.worker.call {stamp(context.collector.describe(address)) as SensorDescription}}
    }
    internal suspend fun <S : DeviceSnapshot> getCapabilities(entity: Entity<S>): EntityCapabilities {
        val address = entity.address(context, collection = true)
        return bounded {context.worker.call {context.collector.capabilities(address)}}
    }

    /** Binding seam. The owning context retains and releases the native subscription. */
    internal suspend fun observeNativeInventory(changed: (EntityKind) -> Unit, fail: (Throwable) -> Unit): CollectorSubscription? =
        bounded {context.worker.call {context.collector.observeInventory(changed, fail)}}
    internal fun releaseNativeInventory(subscription: CollectorSubscription?) = context.worker.release(subscription)

    @OptIn(ExperimentalCoroutinesApi::class)
    fun <S : DeviceSnapshot> watch(entity: Entity<S>): Flow<S> {
        val address = entity.address(context)
        if (entity.mode != EntityMode.State) return sensorFlow(context, entity,
            if (entity.mode == EntityMode.Sample) sensorSamplingRate else SensorSamplingRate.PlatformDefault, readTimeout, ::snapshot)
        return flow {
            coroutineScope {
                val job = currentCoroutineContext()[Job]!!
                val onClose: () -> Unit = {job.cancel()}
                context.closeListeners.add(onClose)
                val events = Channel<() -> DeviceSnapshot>(2048)
                var subscription: CollectorSubscription? = null
                try {
                    fun enqueue(read: () -> DeviceSnapshot) {
                        if (!events.trySend(read).isSuccess) events.close(DeviceReadoutException(ErrorCode.ReadFailed, "Consumer cannot keep up with the bounded snapshot queue."))
                    }
                    fun failed(error: Throwable) {events.close(if (error is DeviceReadoutException) error else DeviceReadoutException(ErrorCode.ReadFailed, "Observation failed.", error))}
                    subscription = bounded {context.worker.call {
                        context.collector.observe(address, SensorSamplingRate.PlatformDefault,
                            {raw -> enqueue {raw}}, ::failed) ?: context.collector.observeReads(address, ::enqueue, ::failed)
                    }}
                    emit(get(entity))
                    var nextPoll = TimeSource.Monotonic.markNow() + pollInterval
                    while (currentCoroutineContext().isActive) {
                        if (subscription == null) {
                            delay(pollInterval);emit(get(entity));continue
                        }
                        val remaining = -nextPoll.elapsedNow()
                        val read = if (subscription.pollingRequired) {
                            if (remaining <= Duration.ZERO) null else select<(() -> DeviceSnapshot)?> {
                                events.onReceive {it}
                                onTimeout(remaining) {null}
                            }
                        } else events.receive()
                        emit(if (read == null) get(entity) else bounded {context.worker.call {snapshot(entity, read())}})
                        if (read == null) nextPoll = TimeSource.Monotonic.markNow() + pollInterval
                    }
                } catch (cancelled: CancellationException) {
                    if (context.closed.get()) throw DeviceReadoutException(ErrorCode.EntityRemoved, "DeviceAccess is closed.", cancelled)
                    throw cancelled
                } finally {
                    context.closeListeners.remove(onClose);events.cancel();context.worker.release(subscription)
                }
            }
        }
    }
    override fun close() = context.close()
}
