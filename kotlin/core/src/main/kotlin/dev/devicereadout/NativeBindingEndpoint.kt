package dev.devicereadout

import kotlinx.coroutines.*
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.coroutines.AbstractCoroutineContextElement
import kotlin.coroutines.CoroutineContext
import kotlin.time.Duration.Companion.milliseconds

private class BindingRequest(val id: Int) : AbstractCoroutineContextElement(Key) {
    companion object Key : CoroutineContext.Key<BindingRequest>
}
private class BindingTerminated(val error: DeviceReadoutException) : CancellationException(error.message)

private class BindingInventoryChanges {
    val changes = Channel<EntityKind>(EntityKind.entries.size)
    val dirty = ConcurrentHashMap.newKeySet<EntityKind>()
    private val active = AtomicBoolean(true)
    @Volatile var error: Throwable? = null
        private set
    fun changed(kind: EntityKind) {
        if (active.get() && dirty.add(kind) && !changes.trySend(kind).isSuccess) {
            failed(DeviceReadoutException(ErrorCode.ReadFailed, "Native inventory change queue is full."))
        }
    }
    fun failed(cause: Throwable) {
        if (active.compareAndSet(true, false)) {
            // A collector's failure callback is data, even when its exception is cancellation-shaped.
            val failure = cause as? DeviceReadoutException
                ?: DeviceReadoutException(ErrorCode.ReadFailed, cause.message ?: "Native inventory observation failed.", cause)
            error = failure;changes.close(failure)
        }
    }
    fun close() {active.set(false);changes.cancel();dirty.clear()}
}

/** Internal asynchronous binding seam. Callers own the UI/permission observations. */
internal class NativeBindingEndpoint(private val access: DeviceAccess) : AutoCloseable {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val commands = Channel<Map<String, Any?>>(256)
    private val replies = Channel<String>(2048)
    private val jobs = ConcurrentHashMap<Int, Job>()
    private val closed = AtomicBoolean()
    private val receiving = AtomicBoolean()
    private val inventory = Mutex()
    // The observer belongs to the context. Only explicitly discovered kinds are refreshed.
    private var inventoryStarted = false
    @Volatile private var inventoryChanges: BindingInventoryChanges? = null
    private val inventoryKinds = ConcurrentHashMap.newKeySet<EntityKind>()
    private val inventoryFailures = ConcurrentHashMap<EntityKind, DeviceReadoutException>()
    @Volatile private var inventoryFailure: DeviceReadoutException? = null
    private val targets = ConcurrentHashMap<String, Entity<out DeviceSnapshot>>()
    private val observed = ConcurrentHashMap<Pair<EntityKind, String>, Entity<out DeviceSnapshot>>()
    private val identities = HashMap<Pair<EntityKind, String>, String>()
    // Owned by the identity gate so target selection and retirement cannot cross.
    private val requestTargets = HashMap<Int, String>()
    private val activityGate = Any()
    private var sensorsActive = true
    private val sensorWatches = HashMap<Int, EntityMode>()
    private var sequence = 0
    private val permissionCoordinator = access.observers.onPermissionRequest {
        val id = currentCoroutineContext()[BindingRequest]?.id ?: invalid("Missing permission request context.")
        emit(id, "permissionRequest", null)
    }
    private val sensorSources = BindingSensorSources(::control)

    init {
        scope.launch {
            for (request in commands) {
                val id = (request["id"] as? Number)?.toInt() ?: 0
                try {
                    if (request["operation"] == "observer") {observe(request);continue}
                    if (request["operation"] == "sensor") {
                        sensorSources.receive(request["value"] as? Map<*, *> ?: invalid("Missing sensor input."));continue
                    }
                    if (id <= 0) invalid("Expected a positive request ID.")
                    if (request["operation"] == "cancel") {
                        synchronized(identities) {requestTargets.remove(id);jobs.remove(id)?.cancel()}
                        continue
                    }
                    val job = scope.launch(BindingRequest(id), start = CoroutineStart.LAZY) {
                        try {execute(id, request)}
                        catch (cancelled: CancellationException) {
                            if (cancelled is BindingTerminated) failure(id, cancelled.error)
                            // Caller cancellation remains silent; discovered removal is a terminal error.
                        }
                        catch (error: Throwable) {failure(id, error)}
                        finally {
                            val owner = currentCoroutineContext()[Job]
                            synchronized(identities) {if (jobs.remove(id, owner)) requestTargets.remove(id)}
                        }
                    }
                    if (jobs.putIfAbsent(id, job) != null) {job.cancel();invalid("Duplicate request ID.")}
                    job.start()
                } catch (error: Throwable) {failure(id, error)}
            }
        }
    }
    @Suppress("UNCHECKED_CAST")
    private fun observe(request: Map<String, Any?>) {
        val input = request["value"] as? Map<*, *> ?: invalid("Missing observer input.")
        if (input["type"] == "sensorActivity") {
            val active = input["active"] as? Boolean ?: invalid("Expected sensor activity state.")
            synchronized(activityGate) {
                if (sensorsActive == active) return
                sensorsActive = active
                for ((id, mode) in sensorWatches) lifecycle(id, mode)
                access.observers.sensorActivity(active)
            }
            return
        }
        val address = request["entity"] as? Map<*, *> ?: invalid("Missing observed entity.")
        val kind = bindingEntity(address["kind"] as? String ?: invalid("Missing observed kind."))
        val target = address["targetId"] as? String
        val entity = if (target == null) kind else if (address["observed"] == true) {
            observed.computeIfAbsent(kind.kind to target) {access.observers.target(kind, target)}
        } else selected(kind, address)
        when (input["type"]) {
            "register" -> Unit
            "sensorSource" -> access.registerSensorSource(entity, sensorSources.source(kind.kind,
                mapOf("kind" to kind.kind.name, "targetId" to target, "observed" to (address["observed"] == true)),
                decodeBindingSensorDescription(kind.kind, input["description"] as? Map<*, *> ?: emptyMap<Any?, Any?>())))
            "state" -> {
                val values = input["values"] as? Map<*, *> ?: invalid("Missing observed snapshot.")
                access.observers.publish(entity as Entity<DeviceSnapshot>, decodeBindingSnapshot(kind.kind, values))
            }
            "remove" -> access.observers.remove(entity)
            "current" -> {
                val current = input["targetId"]?.let {selected(kind, mapOf("targetId" to it, "observed" to (input["observed"] == true)))}
                access.observers.current(kind as Entity<DeviceSnapshot>, current as Entity<DeviceSnapshot>?)
            }
            "permission" -> access.observers.permission(entity, BindingValues.enum(input["status"], PermissionStatus.entries))
            "failure" -> {
                val raw = input["error"]
                val failure = if (raw == null) null else {
                    val error = raw as? Map<*, *> ?: invalid("Invalid observer failure.")
                    DeviceReadoutException(BindingValues.enum(error["code"], ErrorCode.entries) ?: ErrorCode.ReadFailed,
                        error["message"] as? String ?: "Application observer failed.")
                }
                access.observers.failure(entity, failure)
            }
            else -> throw DeviceReadoutException(ErrorCode.UnsupportedEntity, "Observer input is not connected.")
        }
    }

    fun send(request: Map<String, Any?>) {
        if (closed.get()) throw DeviceReadoutException(ErrorCode.EntityRemoved, "Native binding closed.")
        if (!commands.trySend(request).isSuccess) throw DeviceReadoutException(ErrorCode.ReadFailed, "Native command queue is full.")
    }
    suspend fun next(): String {
        if (!receiving.compareAndSet(false, true)) invalid("Only one pending native receive is allowed.")
        try {return replies.receive()} finally {receiving.set(false)}
    }
    private suspend fun execute(id: Int, request: Map<String, Any?>) {
        val address = request["entity"] as? Map<*, *> ?: invalid("Missing entity.")
        val kind = bindingEntity(address["kind"] as? String ?: invalid("Missing entity kind."))
        val settings = request["settings"] as? Map<*, *> ?: invalid("Missing settings.")
        val configured = access.withReadTimeout(settings.duration("readTimeoutMs"))
            .withPollInterval(settings.duration("pollIntervalMs"))
            .withSensorSamplingRate(settings["sensorHertz"]?.let {
                SensorSamplingRate.Hertz((it as? Number)?.toDouble() ?: invalid("Invalid frequency."))
            } ?: SensorSamplingRate.PlatformDefault)
        fun target(): Entity<out DeviceSnapshot> = synchronized(identities) {
            if (jobs[id]?.isActive != true) throw CancellationException("Request cancelled.")
            val selected = selected(kind, address)
            if (address["observed"] != true) (address["targetId"] as? String)?.let {
                (inventoryFailure ?: inventoryFailures[kind.kind])?.let {throw it}
                requestTargets[id] = it
            }
            selected
        }
        when (request["operation"]) {
            "list" -> {
                val result = withTimeoutOrNull(configured.readTimeout) {inventory.withLock {
                    if (!access.hasObservedInventory(kind.kind)) ensureInventoryObservation(configured)
                    val found = configured.list(kind)
                    currentCoroutineContext().ensureActive()
                    reconcileInventory(kind, found)
                }} ?: throw DeviceReadoutException(ErrorCode.ReadTimeout, "Inventory deadline exceeded.")
                emit(id, "result", result)
            }
            "current" -> {
                // Box nullable results so an absent current target is distinct from a deadline.
                val result = withTimeoutOrNull(configured.readTimeout) {inventory.withLock {
                    if (!access.hasObservedInventory(kind.kind)) ensureInventoryObservation(configured)
                    val found = configured.current(kind)
                    listOf(synchronized(identities) {
                        ensureOpen()
                        if (found != null && !found.observed) inventoryKinds.add(kind.kind)
                        found?.let(::bind)
                    })
                }} ?: throw DeviceReadoutException(ErrorCode.ReadTimeout, "Current target deadline exceeded.")
                emit(id, "result", result.single())
            }
            "get" -> emit(id, "result", configured.get(target()))
            "permissions.check" -> emit(id, "result", configured.permissions.check(target()))
            "permissions.request" -> emit(id, "result", configured.permissions.request(target()))
            "describe" -> emit(id, "result", configured.describe(target()))
            "watch" -> {
                val entity = target()
                if (entity.mode != EntityMode.State) synchronized(activityGate) {
                    sensorWatches[id] = entity.mode
                    lifecycle(id, entity.mode)
                }
                try {
                    configured.watch(entity).collect {emit(id, "snapshot", it)}
                    emit(id, "end", null)
                } finally {synchronized(activityGate) {sensorWatches.remove(id)}}
            }
            "capabilities" -> {
                val capabilities = try {configured.capabilities.get(target())}
                catch (error: DeviceReadoutException) {if (error.code == ErrorCode.EntityRemoved) EntityCapabilities(false, false) else throw error}
                emit(id, "result", mapOf("readable" to capabilities.readable, "watchable" to capabilities.watchable))
            }
            else -> throw DeviceReadoutException(ErrorCode.UnsupportedEntity, "Binding operation is not connected.")
        }
    }
    // Called while holding inventory; registration and unregistration stay on the collector lane.
    private suspend fun ensureInventoryObservation(configured: DeviceAccess) {
        inventoryFailure?.let {throw it}
        if (inventoryStarted) return
        val changes = BindingInventoryChanges()
        val subscription = try {configured.observeNativeInventory(changes::changed, changes::failed)}
        catch (error: Throwable) {changes.close();throw error}
        try {
            currentCoroutineContext().ensureActive()
            synchronized(identities) {
                ensureOpen()
                changes.error?.let {throw normalizeFailure(it)}
                inventoryStarted = true
                if (subscription != null) inventoryChanges = changes
            }
        } catch (error: Throwable) {changes.close();access.releaseNativeInventory(subscription);throw error}
        if (subscription == null) {changes.close();return}
        scope.launch {
            try {
                for (kind in changes.changes) {
                    changes.dirty.remove(kind)
                    changes.error?.let {throw it}
                    if (kind !in inventoryKinds) continue
                    try {
                        withTimeout(access.readTimeout) {inventory.withLock {
                            val entity = bindingEntity(kind.name)
                            val found = access.listNative(entity)
                            currentCoroutineContext().ensureActive()
                            changes.error?.let {throw it}
                            reconcileInventory(entity, found, nativeInventory = true)
                        }}
                    } catch (error: Throwable) {
                        if (error is CancellationException && error !is TimeoutCancellationException) throw error
                        val failure = if (error is TimeoutCancellationException)
                            DeviceReadoutException(ErrorCode.ReadTimeout, "Native inventory refresh exceeded its deadline.")
                        else normalizeFailure(error)
                        failInventoryKind(kind, failure)
                    }
                }
            } catch (cancelled: CancellationException) {throw cancelled}
            catch (error: Throwable) {
                val failure = normalizeFailure(error)
                inventoryFailure = failure
                inventoryKinds.forEach {failInventoryKind(it, failure)}
            } finally {changes.close();access.releaseNativeInventory(subscription)}
        }
    }
    private fun reconcileInventory(
        kind: Entity<out DeviceSnapshot>,
        found: List<Entity<out DeviceSnapshot>>,
        nativeInventory: Boolean = !access.hasObservedInventory(kind.kind),
    ): List<Any> {
        val names = found.map {it.targetId}
        if (found.size > 1024 || names.any {it.isNullOrEmpty() || it.length > 1024} || names.toSet().size != names.size) {
            throw DeviceReadoutException(ErrorCode.ReadFailed, "Invalid native inventory.")
        }
        return synchronized(identities) {
            ensureOpen()
            if (nativeInventory) {
                inventoryFailure?.let {throw it}
                inventoryChanges?.error?.let {throw normalizeFailure(it)}
            }
            val live = found.map(::bind).toSet()
            if (nativeInventory) {
                inventoryKinds.add(kind.kind)
                inventoryFailures.remove(kind.kind)
                for ((target, entity) in targets) if (entity.kind == kind.kind && target !in live) {
                    targets.remove(target);identities.remove(entity.kind to requireNotNull(entity.targetId))
                    for ((requestId, selectedTarget) in requestTargets) if (selectedTarget == target) {
                        jobs[requestId]?.cancel(BindingTerminated(DeviceReadoutException(ErrorCode.EntityRemoved, "Native target was removed.")))
                    }
                }
            }
            live.toList()
        }
    }
    private fun failInventoryKind(kind: EntityKind, error: DeviceReadoutException) = synchronized(identities) {
        if (closed.get()) return@synchronized
        inventoryFailures[kind] = error
        for ((id, target) in requestTargets) if (targets[target]?.kind == kind) jobs[id]?.cancel(BindingTerminated(error))
    }
    private fun normalizeFailure(error: Throwable) = error as? DeviceReadoutException
        ?: DeviceReadoutException(ErrorCode.ReadFailed, error.message ?: "Native inventory failed.", error)
    private fun ensureOpen() {if (closed.get()) throw DeviceReadoutException(ErrorCode.EntityRemoved, "Native binding closed.")}
    // Lifecycle messages govern the JavaScript first-sample deadline; Kotlin owns the native subscription.
    private fun lifecycle(id: Int, mode: EntityMode) {
        if (!sensorsActive) emit(id, "suspended", null)
        else if (mode == EntityMode.Sample) emit(id, "reading", null)
    }
    private fun selected(kind: Entity<out DeviceSnapshot>, address: Map<*, *>): Entity<out DeviceSnapshot> {
        val target = address["targetId"] ?: return kind
        if (address["observed"] == true) return observed[kind.kind to target]
            ?: throw DeviceReadoutException(ErrorCode.EntityRemoved, "Observed target was removed.")
        return targets[target]?.takeIf {it.kind == kind.kind}
            ?: throw DeviceReadoutException(ErrorCode.EntityRemoved, "Native target was removed.")
    }
    // Called while owning the identity gate.
    private fun bind(entity: Entity<out DeviceSnapshot>): Any {
        val native = entity.targetId ?: invalid("Expected a selected native target.")
        if (native.isEmpty() || native.length > 1024) throw DeviceReadoutException(ErrorCode.ReadFailed, "Invalid native target identity.")
        if (entity.observed) return mapOf("targetId" to native, "observed" to true)
        val key = entity.kind to native
        val id = identities.getOrPut(key) {"native-${++sequence}"}
        targets[id] = entity
        return id
    }
    private fun control(type: String, value: Map<String, Any?>) {
        ensureOpen()
        val json = encodeBindingResponse(mapOf("id" to 0, "type" to type, "value" to value))
        if (json.length > 262144 || !replies.trySend(json).isSuccess) {
            val error = DeviceReadoutException(ErrorCode.ReadFailed, "Native response queue or payload limit exceeded.")
            replies.close(error);scope.cancel();access.close();throw error
        }
    }
    private fun emit(id: Int, type: String, value: Any?) {
        if (closed.get()) return
        val json = encodeBindingResponse(mapOf("id" to id, "type" to type, "value" to value))
        val sent = synchronized(identities) {
            if (jobs[id]?.isActive != true || requestTargets[id]?.let { !targets.containsKey(it) } == true) return
            json.length <= 262144 && replies.trySend(json).isSuccess
        }
        if (!sent) {
            replies.close(DeviceReadoutException(ErrorCode.ReadFailed, "Native response queue or payload limit exceeded."))
            scope.cancel();access.close()
        }
    }
    private fun failure(id: Int, error: Throwable) {
        if (closed.get()) return
        val normalized = error as? DeviceReadoutException ?: DeviceReadoutException(ErrorCode.ReadFailed, error.message ?: "Native binding failed.", error)
        val json = encodeBindingResponse(mapOf("id" to id, "type" to "error", "error" to mapOf("code" to normalized.code.name, "message" to normalized.message)))
        if (!replies.trySend(json).isSuccess) {replies.close(normalized);scope.cancel();access.close()}
    }
    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        synchronized(identities) {targets.clear();identities.clear();requestTargets.clear()}
        observed.clear()
        sensorSources.close()
        inventoryChanges?.close();inventoryKinds.clear();inventoryFailures.clear()
        synchronized(activityGate) {sensorWatches.clear()}
        permissionCoordinator.close()
        commands.cancel();replies.cancel();scope.cancel();jobs.clear();access.close()
    }
}

private fun invalid(message: String): Nothing = throw DeviceReadoutException(ErrorCode.InvalidConfiguration, message)
private fun Map<*, *>.duration(key: String) = ((this[key] as? Number)?.toDouble() ?: invalid("Missing $key.")).let {
    if (!it.isFinite() || it <= 0) invalid("Invalid $key.")
    it.milliseconds
}
