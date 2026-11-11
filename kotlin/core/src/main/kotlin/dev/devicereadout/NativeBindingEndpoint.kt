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

/** Internal asynchronous binding seam. Callers own the UI/permission observations. */
internal class NativeBindingEndpoint(private val access: DeviceAccess) : AutoCloseable {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val commands = Channel<Map<String, Any?>>(256)
    private val replies = Channel<String>(2048)
    private val jobs = ConcurrentHashMap<Int, Job>()
    private val closed = AtomicBoolean()
    private val receiving = AtomicBoolean()
    private val inventory = Mutex()
    private val targets = ConcurrentHashMap<String, Entity<out DeviceSnapshot>>()
    private val observed = ConcurrentHashMap<Pair<EntityKind, String>, Entity<out DeviceSnapshot>>()
    private val identities = HashMap<Pair<EntityKind, String>, String>()
    private val activityGate = Any()
    private var sensorsActive = true
    private val sensorWatches = HashMap<Int, EntityMode>()
    private var sequence = 0
    private val permissionCoordinator = access.observers.onPermissionRequest {
        val id = currentCoroutineContext()[BindingRequest]?.id ?: invalid("Missing permission request context.")
        emit(id, "permissionRequest", null)
    }

    init {
        scope.launch {
            for (request in commands) {
                val id = (request["id"] as? Number)?.toInt() ?: 0
                try {
                    if (request["operation"] == "observer") {observe(request);continue}
                    if (id <= 0) invalid("Expected a positive request ID.")
                    if (request["operation"] == "cancel") {jobs.remove(id)?.cancel();continue}
                    val job = scope.launch(BindingRequest(id), start = CoroutineStart.LAZY) {
                        try {execute(id, request)}
                        catch (_: CancellationException) { /* Requested cancellation has no late response. */ }
                        catch (error: Throwable) {failure(id, error)}
                        finally {jobs.remove(id, currentCoroutineContext()[Job])}
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
        when (request["operation"]) {
            "list" -> {
                val result = withTimeoutOrNull(configured.readTimeout) {inventory.withLock {
                    val found = configured.list(kind)
                    val names = found.map {it.targetId}
                    if (found.size > 1024 || names.any {it.isNullOrEmpty() || it.length > 1024} || names.toSet().size != names.size) {
                        throw DeviceReadoutException(ErrorCode.ReadFailed, "Invalid native inventory.")
                    }
                    synchronized(identities) {
                        ensureOpen()
                        val live = found.map(::bind).toSet()
                        for ((target, entity) in targets) if (!access.hasObservedInventory(kind.kind) && entity.kind == kind.kind && target !in live) {
                            targets.remove(target);identities.remove(entity.kind to requireNotNull(entity.targetId))
                        }
                        live.toList()
                    }
                }} ?: throw DeviceReadoutException(ErrorCode.ReadTimeout, "Inventory deadline exceeded.")
                emit(id, "result", result)
            }
            "current" -> {
                // Box nullable results so an absent current target is distinct from a deadline.
                val result = withTimeoutOrNull(configured.readTimeout) {inventory.withLock {
                    val found = configured.current(kind)
                    listOf(synchronized(identities) {ensureOpen();found?.let(::bind)})
                }} ?: throw DeviceReadoutException(ErrorCode.ReadTimeout, "Current target deadline exceeded.")
                emit(id, "result", result.single())
            }
            "get" -> emit(id, "result", configured.get(selected(kind, address)))
            "permissions.check" -> emit(id, "result", configured.permissions.check(selected(kind, address)))
            "permissions.request" -> emit(id, "result", configured.permissions.request(selected(kind, address)))
            "describe" -> emit(id, "result", configured.describe(selected(kind, address)))
            "watch" -> {
                val entity = selected(kind, address)
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
                val capabilities = try {configured.capabilities.get(selected(kind, address))}
                catch (error: DeviceReadoutException) {if (error.code == ErrorCode.EntityRemoved) EntityCapabilities(false, false) else throw error}
                emit(id, "result", mapOf("readable" to capabilities.readable, "watchable" to capabilities.watchable))
            }
            else -> throw DeviceReadoutException(ErrorCode.UnsupportedEntity, "Binding operation is not connected.")
        }
    }
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
    private fun emit(id: Int, type: String, value: Any?) {
        if (closed.get()) return
        val json = encodeBindingResponse(mapOf("id" to id, "type" to type, "value" to value))
        if (json.length > 262144 || !replies.trySend(json).isSuccess) {
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
        synchronized(identities) {targets.clear();identities.clear()}
        observed.clear()
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
