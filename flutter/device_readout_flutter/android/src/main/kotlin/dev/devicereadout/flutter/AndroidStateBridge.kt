package dev.devicereadout.flutter

import dev.devicereadout.*
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import kotlin.time.Duration.Companion.microseconds

/** Reuses Kotlin's state readers and native-event/polling flows without UI access. */
internal class AndroidStateBridge(private val createAccess: () -> DeviceAccess) : AutoCloseable {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val sequence = AtomicLong()
    private val contexts = ConcurrentHashMap<Long, Context>()
    private val closed = AtomicBoolean()

    private class Context(val access: DeviceAccess) {
        val inventory = Mutex()
        val targets = ConcurrentHashMap<Long, Entity<out DeviceSnapshot>>()
        val identities = ConcurrentHashMap<Pair<EntityKind, String>, Long>()
        val sessions = ConcurrentHashMap<Long, Session>()
        val reads = ConcurrentHashMap<Long, Job>()
        val closed = AtomicBoolean()
    }
    private class Session {
        val samples = Channel<DeviceSnapshot>(2048)
        val receiving = AtomicBoolean()
        var job: Job? = null
        fun close() { job?.cancel(); samples.cancel() }
    }

    suspend fun invoke(method: String, args: Map<*, *>): Any? {
        if (closed.get()) throw DeviceReadoutException(ErrorCode.EntityRemoved, "Plugin detached.")
        if (method == "create") {
            val context = Context(createAccess())
            val id = sequence.incrementAndGet()
            contexts[id] = context
            if (closed.get()) { closeContext(id); throw DeviceReadoutException(ErrorCode.EntityRemoved, "Plugin detached.") }
            return id
        }
        val id = args.positive("context")
        if (method == "dispose") { closeContext(id); return null }
        val context = contexts[id] ?: throw DeviceReadoutException(ErrorCode.EntityRemoved, "Native state context removed.")
        return when (method) {
            "capabilities" -> request(context, args) { access ->
                val name = args["entity"] as? String
                if (EntityKind.entries.none { it.name == name }) invalidState("Unknown entity kind.")
                val kind = stateEntityOrNull(name)
                val support = if (kind == null) {
                    if (args["target"] != null) invalidState("This native state kind has no targets.")
                    EntityCapabilities(false, false)
                } else {
                    val entity = context.inventory.withLock { selected(context, args, collection = true) }
                    access.capabilities.get(entity)
                }
                mapOf("readable" to support.readable, "watchable" to support.watchable)
            }
            "list" -> request(context, args) { access -> context.inventory.withLock {
                val kind = stateCollection(args["entity"] as? String)
                val found = access.list(kind)
                currentCoroutineContext().ensureActive()
                if (context.closed.get()) removedState()
                val identities = found.map { requireNotNull(it.targetId) }
                if (found.size > 4096 || identities.toSet().size != found.size ||
                    identities.any { it.isEmpty() || it.length > 1024 }) {
                    throw DeviceReadoutException(ErrorCode.ReadFailed, "Invalid or oversized state inventory.")
                }
                val result = found.map { bind(context, it) }
                val live = result.toSet()
                for ((target, entity) in context.targets) {
                    if (entity.kind == kind.kind && target !in live) retire(context, target)
                }
                result
            } }
            "current" -> request(context, args) { access -> context.inventory.withLock {
                val found = access.current(stateCollection(args["entity"] as? String))
                currentCoroutineContext().ensureActive()
                if (context.closed.get()) removedState()
                found?.let { bind(context, it) }
            } }
            "read" -> request(context, args) { access ->
                val entity = context.inventory.withLock { selected(context, args) }
                try {
                    serializeSnapshot(access.get(entity))
                } catch (error: DeviceReadoutException) {
                    if (error.code == ErrorCode.EntityRemoved && args["target"] != null) {
                        context.inventory.withLock { retire(context, args.positive("target")) }
                    }
                    throw error
                }
            }
            "cancelRead" -> { context.reads[args.positive("request")]?.cancel(); null }
            "open" -> {
                val entity = context.inventory.withLock { selected(context, args) }
                val access = context.access
                    .withReadTimeout(args.positive("timeoutMicros").microseconds)
                    .withPollInterval(args.positive("pollMicros").microseconds)
                val session = Session()
                val sessionId = sequence.incrementAndGet()
                session.job = scope.launch(start = CoroutineStart.LAZY) {
                    try {
                        access.watch(entity).collect { value ->
                            if (!session.samples.trySend(value).isSuccess) {
                                throw DeviceReadoutException(ErrorCode.ReadFailed, "Native state delivery queue is full.")
                            }
                        }
                        session.samples.close()
                    } catch (error: Throwable) { session.samples.close(error) }
                }
                context.sessions[sessionId] = session
                if (context.closed.get()) {
                    context.sessions.remove(sessionId); session.close()
                    throw DeviceReadoutException(ErrorCode.EntityRemoved, "Native state context removed.")
                }
                session.job!!.start()
                sessionId
            }
            "next" -> {
                val session = context.sessions[args.positive("session")]
                    ?: throw DeviceReadoutException(ErrorCode.EntityRemoved, "Native state session removed.")
                if (!session.receiving.compareAndSet(false, true)) invalidState("Only one pending next request is allowed per session.")
                try { serializeSnapshot(session.samples.receive()) }
                finally { session.receiving.set(false) }
            }
            "close" -> { context.sessions.remove(args.positive("session"))?.close(); null }
            else -> invalidState("Unknown state protocol operation.")
        }
    }

    private data class Result<T>(val value: T)
    private suspend fun <T> request(context: Context, args: Map<*, *>, action: suspend (DeviceAccess) -> T): T {
        val timeout = args.positive("timeoutMicros").microseconds
        val request = args.positive("request")
        val job = currentCoroutineContext()[Job]!!
        if (context.reads.putIfAbsent(request, job) != null) invalidState("Duplicate read request.")
        try {
            if (context.closed.get()) removedState()
            val result = withTimeoutOrNull(timeout) { Result(action(context.access.withReadTimeout(timeout))) }
                ?: throw DeviceReadoutException(ErrorCode.ReadTimeout, "Native state request exceeded its deadline.")
            return result.value
        } finally { context.reads.remove(request, job) }
    }

    // Called under the inventory mutex; IDs are opaque, context-scoped generations.
    private fun bind(context: Context, entity: Entity<out DeviceSnapshot>): Long {
        val identity = entity.targetId ?: invalidState("Expected a native target identity.")
        if (identity.isEmpty() || identity.length > 1024) {
            throw DeviceReadoutException(ErrorCode.ReadFailed, "Invalid native target identity.")
        }
        val key = entity.kind to identity
        val id = context.identities.computeIfAbsent(key) { sequence.incrementAndGet() }
        context.targets[id] = entity
        return id
    }
    private fun retire(context: Context, id: Long) {
        val entity = context.targets.remove(id) ?: return
        context.identities.remove(entity.kind to requireNotNull(entity.targetId), id)
    }
    private fun selected(context: Context, args: Map<*, *>, collection: Boolean = false): Entity<out DeviceSnapshot> {
        val kind = stateEntity(args["entity"] as? String)
        if (!kind.targeted) {
            if (args["target"] != null) invalidState("A singleton cannot select a target.")
            return kind
        }
        if (collection && args["target"] == null) return kind
        val target = context.targets[args.positive("target")] ?: removedState()
        if (target.kind != kind.kind) invalidState("The target belongs to another entity kind.")
        return target
    }

    private fun closeContext(id: Long) {
        val context = contexts.remove(id) ?: return
        context.closed.set(true)
        context.reads.values.forEach { it.cancel() }; context.reads.clear()
        context.sessions.values.forEach { it.close() }; context.sessions.clear()
        context.access.close()
        context.targets.clear(); context.identities.clear()
    }
    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        contexts.keys.toList().forEach(::closeContext)
        scope.cancel()
    }
}

private fun stateEntity(name: String?): Entity<out DeviceSnapshot> = stateEntityOrNull(name)
    ?: throw DeviceReadoutException(ErrorCode.UnsupportedEntity, "This Android state entity is not connected.")

private fun stateEntityOrNull(name: String?): Entity<out DeviceSnapshot>? = when (name) {
    "DeviceInfo" -> DeviceInfoEntity
    "Os" -> OsEntity
    "Runtime" -> RuntimeEntity
    "Cpu" -> CpuEntity
    "CpuCore" -> CpuCoreEntity
    "Ram" -> RamEntity
    "Locale" -> LocaleEntity
    "TimeZone" -> TimeZoneEntity
    "AndroidBuild" -> AndroidBuildEntity
    "AndroidIdentity" -> AndroidIdentityEntity
    "HardwareSerial" -> HardwareSerialEntity
    "TelephonyIdentity" -> TelephonyIdentityEntity
    "Power" -> PowerEntity
    "Battery" -> BatteryEntity
    "NetworkPath" -> NetworkPathEntity
    "NetworkPerformance" -> NetworkPerformanceEntity
    "NetworkInterface" -> NetworkInterfaceEntity
    "WifiConnection" -> WifiConnectionEntity
    "CellularSubscription" -> CellularSubscriptionEntity
    "StorageVolume" -> StorageVolumeEntity
    else -> null
}

private fun stateCollection(name: String?): Entity<out DeviceSnapshot> = stateEntity(name).also {
    if (!it.targeted) invalidState("Expected a multi-target state kind.")
}
private fun removedState(): Nothing = throw DeviceReadoutException(ErrorCode.EntityRemoved, "Native state context or target removed.")

private fun Map<*, *>.positive(key: String): Long {
    val value = this[key] as? Number ?: invalidState("Missing $key.")
    val number = value.toLong()
    if (number <= 0 || value.toDouble() != number.toDouble()) invalidState("Invalid $key.")
    return number
}
private fun invalidState(message: String): Nothing = throw DeviceReadoutException(ErrorCode.InvalidConfiguration, message)
