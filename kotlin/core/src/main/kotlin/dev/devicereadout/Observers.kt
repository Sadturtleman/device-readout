package dev.devicereadout

import kotlinx.coroutines.*
import kotlinx.coroutines.selects.select
import java.util.concurrent.CompletableFuture
import java.util.concurrent.ExecutionException
import java.util.concurrent.atomic.AtomicBoolean

enum class PermissionStatus { Granted, Denied, NotDetermined, Restricted, Unavailable }
data class PermissionRequest(val entity: Entity<out DeviceSnapshot>)

internal class Subscription(private val action: () -> Unit, override val pollingRequired: Boolean = false) : CollectorSubscription {
    private val closed = AtomicBoolean()
    override fun close() {if (closed.compareAndSet(false, true)) action()}
}

internal class ObservedCollector(private val source: DeviceCollector) : DeviceCollector {
    data class Activity(val active: Boolean, val generation: Long)
    private data class Listener(val emit: (DeviceSnapshot) -> Unit, val fail: (Throwable) -> Unit)
    private class FailureListener(val address: EntityAddress, val fail: (Throwable) -> Unit)
    private data class FailureRecord(val revision: Long, val error: DeviceReadoutException)
    private class State(val mode: EntityMode) {
        var value: DeviceSnapshot? = null
        var removed = false
        var first = CompletableFuture<DeviceSnapshot>()
        val listeners = LinkedHashSet<Listener>()
    }
    private val gate = Any()
    private val states = LinkedHashMap<EntityAddress, State>()
    private val currentTargets = HashMap<EntityKind, EntityAddress?>()
    private val failures = HashMap<EntityAddress, DeviceReadoutException>()
    private val failureHistory = HashMap<EntityAddress, FailureRecord>()
    private var failureRevision = 0L
    private val failureListeners = LinkedHashSet<FailureListener>()
    private val permissions = HashMap<EntityAddress, PermissionStatus?>()
    private val permissionListeners = HashMap<EntityAddress, MutableSet<(PermissionStatus?) -> Unit>>()
    private var coordinator: (suspend (PermissionRequest) -> Unit)? = null
    private var activity = Activity(true, 0)
    private val activityListeners = LinkedHashSet<(Activity) -> Unit>()

    fun sensorActivity(active: Boolean) {
        val (state, listeners) = synchronized(gate) {
            if (activity.active == active) return
            activity = Activity(active, activity.generation + 1)
            activity to activityListeners.toList()
        }
        listeners.forEach {it(state)}
    }
    fun onActivity(listener: (Activity) -> Unit): AutoCloseable {
        val initial = synchronized(gate) {activityListeners.add(listener);activity}
        listener(initial)
        return Subscription({synchronized(gate) {activityListeners.remove(listener)}})
    }
    fun isActive(generation: Long): Boolean = synchronized(gate) {activity.active && activity.generation == generation}

    fun register(address: EntityAddress, mode: EntityMode) = synchronized(gate) {states.getOrPut(address) {State(mode)};Unit}
    fun onFailure(address: EntityAddress, fail: (Throwable) -> Unit): AutoCloseable {
        val listener = FailureListener(address, fail)
        synchronized(gate) {assertAvailable(address);failureListeners.add(listener)}
        return Subscription({synchronized(gate) {failureListeners.remove(listener)}})
    }
    fun publish(address: EntityAddress, mode: EntityMode, value: DeviceSnapshot) {
        val listeners = synchronized(gate) {
            val state = states.getOrPut(address) {State(mode)}
            if (state.removed) return
            if (mode != EntityMode.State && !activity.active) return
            state.value = value;state.first.complete(value)
            if (failureFor(address) != null) emptyList() else state.listeners.toList()
        }
        listeners.forEach {it.emit(value)}
    }
    fun remove(address: EntityAddress, mode: EntityMode) {
        val error = DeviceReadoutException(ErrorCode.EntityRemoved, "Observed target was removed.")
        val listeners = synchronized(gate) {
            val state = states.getOrPut(address) {State(mode)}
            state.removed = true;state.first.completeExceptionally(error)
            val observing = state.listeners.map {it.fail}.also {state.listeners.clear()}
            val waiting = failureListeners.filter {it.address == address}
            failureListeners.removeAll(waiting.toSet())
            observing + waiting.map {it.fail}
        }
        listeners.forEach {it(error)}
    }
    fun setCurrent(kind: EntityKind, target: EntityAddress?) = synchronized(gate) {currentTargets[kind] = target}
    private fun failureFor(address: EntityAddress): DeviceReadoutException? =
        failures[address] ?: failures[EntityAddress(address.kind, null)]
    private fun assertAvailable(address: EntityAddress, since: Long? = null) {
        if (states[address]?.removed == true) throw DeviceReadoutException(ErrorCode.EntityRemoved, "Observed target was removed.")
        failureFor(address)?.let {throw it}
        if (since != null) {
            failureHistory[address]?.takeIf {it.revision > since}?.let {throw it.error}
            failureHistory[EntityAddress(address.kind, null)]?.takeIf {it.revision > since}?.let {throw it.error}
        }
    }
    fun failure(address: EntityAddress, error: DeviceReadoutException?) {
        val listeners = synchronized(gate) {
            if (error == null) {failures.remove(address);return}
            failures[address] = error
            failureHistory[address] = FailureRecord(++failureRevision, error)
            val observed = states.filterKeys {it.kind == address.kind && (address.targetId == null || it == address)}.values.flatMap {state ->
                if (state.removed) emptyList() else {
                    state.value = null;state.first.completeExceptionally(error)
                    state.first = CompletableFuture()
                    state.listeners.map {it.fail}.also {state.listeners.clear()}
                }
            }
            val native = failureListeners.filter {it.address.kind == address.kind && (address.targetId == null || it.address == address)}
            failureListeners.removeAll(native.toSet())
            observed + native.map {it.fail}
        }
        listeners.forEach {it(error!!)}
    }
    override fun read(entity: EntityAddress): DeviceSnapshot {
        val (pending, revision) = synchronized(gate) {
            assertAvailable(entity)
            states[entity]?.let {
                if (it.value != null && it.mode == EntityMode.State) return it.value!!
                it.first
            } to failureRevision
        }
        val value = try {pending?.get() ?: source.read(entity)} catch (error: ExecutionException) {throw error.cause ?: error}
        synchronized(gate) {assertAvailable(entity, revision)}
        return value
    }
    override fun observe(entity: EntityAddress, rate: SensorSamplingRate, emit: (DeviceSnapshot) -> Unit, fail: (Throwable) -> Unit): CollectorSubscription? {
        synchronized(gate) {
            assertAvailable(entity)
            states[entity]?.let {state ->
                if (state.removed) throw DeviceReadoutException(ErrorCode.EntityRemoved, "Observed target was removed.")
                val listener = Listener(emit, fail);state.listeners.add(listener)
                return Subscription({synchronized(gate) {state.listeners.remove(listener)}})
            }
        }
        return observeSource(entity, fail, false) {source.observe(entity, rate, emit, fail)}
    }
    override fun observeReads(entity: EntityAddress, emit: (() -> DeviceSnapshot) -> Unit, fail: (Throwable) -> Unit): CollectorSubscription? =
        observeSource(entity, fail, true) {source.observeReads(entity, emit, fail)}
    private fun observeSource(entity: EntityAddress, fail: (Throwable) -> Unit, allowPolling: Boolean, subscribe: () -> CollectorSubscription?): CollectorSubscription? {
        val listener = FailureListener(entity, fail)
        synchronized(gate) {assertAvailable(entity);failureListeners.add(listener)}
        try {
            val native = subscribe()
            if (native == null && !allowPolling) {
                synchronized(gate) {failureListeners.remove(listener)}
                return null
            }
            return Subscription({
                synchronized(gate) {failureListeners.remove(listener)}
                native?.close()
            }, pollingRequired = native?.pollingRequired ?: true)
        } catch (error: Throwable) {
            synchronized(gate) {failureListeners.remove(listener)}
            throw error
        }
    }
    fun hasObservedInventory(kind: EntityKind): Boolean = synchronized(gate) {
        states.keys.any {it.kind == kind && it.observed} || currentTargets.containsKey(kind) && currentTargets[kind] == null
    }
    override fun list(kind: EntityKind): List<String> = listAddresses(kind).mapNotNull {it.targetId}
    fun listAddresses(kind: EntityKind): List<EntityAddress> {
        val revision = synchronized(gate) {
            assertAvailable(EntityAddress(kind, null))
            val entries = states.filterKeys {it.kind == kind && it.observed}
            if (hasObservedInventory(kind)) return entries.filterValues {!it.removed}.keys.toList()
            failureRevision
        }
        val result = source.list(kind)
        synchronized(gate) {assertAvailable(EntityAddress(kind, null), revision)}
        return result.map {EntityAddress(kind, it)}
    }
    override fun current(kind: EntityKind): String? = currentAddress(kind)?.targetId
    fun currentAddress(kind: EntityKind): EntityAddress? {
        val revision = synchronized(gate) {
            assertAvailable(EntityAddress(kind, null))
            if (currentTargets.containsKey(kind)) return currentTargets[kind]?.takeUnless {states[it]?.removed == true}
            if (hasObservedInventory(kind)) return null
            failureRevision
        }
        val result = source.current(kind)
        synchronized(gate) {assertAvailable(EntityAddress(kind, null), revision)}
        return result?.let {EntityAddress(kind, it)}
    }
    override fun capabilities(entity: EntityAddress): EntityCapabilities {
        synchronized(gate) {states[entity]?.let {return EntityCapabilities(!it.removed, !it.removed)}}
        return source.capabilities(entity)
    }
    override fun observeInventory(changed: (EntityKind) -> Unit, fail: (Throwable) -> Unit): CollectorSubscription? =
        source.observeInventory(changed, fail)
    override fun describe(sensor: EntityAddress): SensorDescription {
        val revision = synchronized(gate) {
            assertAvailable(sensor)
            states[sensor]?.let {
                if (it.removed) throw DeviceReadoutException(ErrorCode.EntityRemoved, "Observed sensor was removed.")
                if (it.mode == EntityMode.State) throw DeviceReadoutException(ErrorCode.UnsupportedEntity, "Expected a sensor.")
                return SensorDescription(kind = SensorKind.entries.firstOrNull {kind -> kind.name == sensor.kind.name})
            }
            failureRevision
        }
        val result = source.describe(sensor)
        synchronized(gate) {assertAvailable(sensor, revision)}
        return result
    }

    fun permission(entity: EntityAddress, status: PermissionStatus?) {
        val listeners = synchronized(gate) {
            permissions[entity] = status
            permissionListeners.filter { (address, _) ->
                address == entity || entity.targetId == null && address.kind == entity.kind && !permissions.containsKey(address)
            }.values.flatMap {it.toList()}
        }
        listeners.forEach {it(status)}
    }
    private fun permissionFor(entity: EntityAddress): PermissionStatus? =
        if (permissions.containsKey(entity)) permissions[entity] else permissions[EntityAddress(entity.kind)]
    fun checkPermission(entity: EntityAddress): PermissionStatus? = synchronized(gate) {permissionFor(entity)}
    fun coordinate(handler: suspend (PermissionRequest) -> Unit): AutoCloseable {
        synchronized(gate) {
            if (coordinator != null) throw DeviceReadoutException(ErrorCode.InvalidConfiguration, "A permission coordinator is already registered.")
            coordinator = handler
        }
        return Subscription({synchronized(gate) {if (coordinator === handler) coordinator = null}})
    }
    suspend fun requestPermission(entity: EntityAddress, request: PermissionRequest, context: DeviceAccess.Context): PermissionStatus? = supervisorScope<PermissionStatus?> {
        val observed = CompletableDeferred<PermissionStatus?>()
        val listener: (PermissionStatus?) -> Unit = {observed.complete(it)}
        val handler = synchronized(gate) {
            if (permissionFor(entity) == PermissionStatus.Granted) return@supervisorScope PermissionStatus.Granted
            val value = coordinator ?: throw DeviceReadoutException(ErrorCode.UnsupportedEntity, "Register an application permission coordinator.")
            permissionListeners.getOrPut(entity) {LinkedHashSet()}.add(listener)
            value
        }
        val onClose: () -> Unit = {observed.completeExceptionally(DeviceReadoutException(ErrorCode.EntityRemoved, "DeviceAccess is closed."))}
        context.closeListeners.add(onClose)
        if (context.closed.get()) onClose()
        val coordination = async(start = CoroutineStart.UNDISPATCHED) {handler(request)}
        try {
            select<PermissionStatus?> {
                observed.onAwait {it}
                coordination.onAwait {observed.await()}
            }
        } catch (cancelled: CancellationException) {throw cancelled}
        catch (error: DeviceReadoutException) {throw error}
        catch (error: Exception) {throw DeviceReadoutException(ErrorCode.ReadFailed, "Permission coordinator failed.", error)}
        finally {
            coordination.cancel();observed.cancel();context.closeListeners.remove(onClose)
            synchronized(gate) {
                permissionListeners[entity]?.let {it.remove(listener);if (it.isEmpty()) permissionListeners.remove(entity)}
            }
        }
    }
}

/** Receives app-owned screen and permission state without invoking platform UI operations. */
class ObserverInputs internal constructor(private val context: DeviceAccess.Context) {
    private fun ensureOpen() {if (context.closed.get()) throw DeviceReadoutException(ErrorCode.EntityRemoved, "DeviceAccess is closed.")}
    fun <S : DeviceSnapshot> target(kind: Entity<S>, id: String): Entity<S> {
        ensureOpen();kind.address(context, collection = true)
        if (!kind.targeted || kind.targetId != null || id.isEmpty()) throw DeviceReadoutException(ErrorCode.InvalidConfiguration, "Expected an entity kind and nonempty target ID.")
        return kind.bind(context, id, observed = true).also {context.collector.register(it.address(context), it.mode)}
    }
    fun <S : DeviceSnapshot> publish(entity: Entity<S>, snapshot: S) {ensureOpen();context.collector.publish(entity.address(context), entity.mode, snapshot)}
    fun <S : DeviceSnapshot> remove(entity: Entity<S>) {ensureOpen();context.collector.remove(entity.address(context), entity.mode)}
    fun <S : DeviceSnapshot> current(kind: Entity<S>, target: Entity<S>?) {
        ensureOpen();kind.address(context, collection = true)
        if (!kind.targeted || kind.targetId != null || (target != null && target.kind != kind.kind)) throw DeviceReadoutException(ErrorCode.InvalidConfiguration, "Expected a target of the same entity kind.")
        context.collector.setCurrent(kind.kind, target?.address(context))
    }
    fun <S : DeviceSnapshot> permission(entity: Entity<S>, status: PermissionStatus?) {ensureOpen();context.collector.permission(entity.address(context, collection = true), status)}
    /** Reports or clears an application observer failure for a target or an entire entity kind. */
    fun <S : DeviceSnapshot> failure(entity: Entity<S>, error: DeviceReadoutException?) {ensureOpen();context.collector.failure(entity.address(context, collection = true), error)}
    fun onPermissionRequest(coordinator: suspend (PermissionRequest) -> Unit): AutoCloseable {ensureOpen();return context.collector.coordinate(coordinator)}
    /** The application supplies foreground/visibility state; desktop focus loss alone need not deactivate sensors. */
    fun sensorActivity(active: Boolean) {ensureOpen();context.collector.sensorActivity(active)}
}
class PermissionAccess internal constructor(private val context: DeviceAccess.Context) {
    suspend fun <S : DeviceSnapshot> check(entity: Entity<S>): PermissionStatus? {
        currentCoroutineContext().ensureActive()
        if (context.closed.get()) throw DeviceReadoutException(ErrorCode.EntityRemoved, "DeviceAccess is closed.")
        return context.collector.checkPermission(entity.address(context, collection = true))
    }
    suspend fun <S : DeviceSnapshot> request(entity: Entity<S>): PermissionStatus? {
        currentCoroutineContext().ensureActive()
        if (context.closed.get()) throw DeviceReadoutException(ErrorCode.EntityRemoved, "DeviceAccess is closed.")
        return context.collector.requestPermission(entity.address(context, collection = true), PermissionRequest(entity), context)
    }
}
