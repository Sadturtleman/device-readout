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

/** Platform-channel operations. Native queries/registration remain owned by DeviceAccess workers. */
internal class AndroidSensorBridge(private val createAccess: () -> DeviceAccess) : AutoCloseable {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val sequence = AtomicLong()
    private val contexts = ConcurrentHashMap<Long, Context>()
    private val closed = AtomicBoolean()

    private class Context(val access: DeviceAccess) {
        val inventory = Mutex()
        val targets = ConcurrentHashMap<Long, Entity<out DeviceSnapshot>>()
        val identities = ConcurrentHashMap<Pair<EntityKind, String>, Long>()
        val sessions = ConcurrentHashMap<Long, Session>()
        val inventoryStarted = AtomicBoolean()
        val inventoryReceiving = AtomicBoolean()
        val dirtyKinds = ConcurrentHashMap.newKeySet<EntityKind>()
        val changes = Channel<EntityKind>(EntityKind.entries.size)
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
        val id = args.id("context")
        if (method == "dispose") { closeContext(id); return null }
        val context = contexts[id] ?: throw DeviceReadoutException(ErrorCode.EntityRemoved, "Native sensor context removed.")
        return when (method) {
            "startInventory" -> {
                if (!context.inventoryStarted.compareAndSet(false, true)) invalid("Inventory observation is already started.")
                val subscription = context.access.observeNativeInventory({ kind ->
                    if (!context.closed.get() && context.dirtyKinds.add(kind)) {
                        if (!context.changes.trySend(kind).isSuccess) {
                            context.changes.close(DeviceReadoutException(ErrorCode.ReadFailed, "Inventory change queue is full."))
                        }
                    }
                }, { error -> context.changes.close(error) })
                if (context.closed.get()) throw DeviceReadoutException(ErrorCode.EntityRemoved, "Native sensor context removed.")
                if (subscription == null) context.changes.close(DeviceReadoutException(ErrorCode.UnsupportedEntity, "Inventory observation unavailable."))
                subscription != null
            }
            "nextInventory" -> {
                if (!context.inventoryStarted.get()) invalid("Start inventory observation first.")
                if (!context.inventoryReceiving.compareAndSet(false, true)) invalid("Only one pending inventory receive is allowed.")
                try {
                    val kind = context.changes.receive()
                    context.dirtyKinds.remove(kind)
                    kind.name
                } finally {context.inventoryReceiving.set(false)}
            }
            "list" -> {
                val timeout = if (args.containsKey("timeoutMicros")) args.id("timeoutMicros").microseconds else context.access.readTimeout
                withTimeoutOrNull(timeout) { context.inventory.withLock {
                    val access = context.access.withReadTimeout(timeout)
                    val kind = sensorKind(args["kind"] as? String)
                    val found = access.list(kind)
                    val identities = found.map { it.targetId }
                    if (found.size > 1024 || identities.any { it.isNullOrEmpty() || it.length > 1024 } ||
                        identities.toSet().size != identities.size) {
                        throw DeviceReadoutException(ErrorCode.ReadFailed, "Invalid native sensor inventory.")
                    }
                    // Prepare every description before publishing any binding or retirement.
                    val prepared = found.map { it to serializeSnapshot(access.describe(it)) }
                    currentCoroutineContext().ensureActive()
                    synchronized(context) {
                        if (context.closed.get()) throw DeviceReadoutException(ErrorCode.EntityRemoved, "Native sensor context removed.")
                        val result = prepared.map { (entity, description) ->
                            val key = entity.kind to requireNotNull(entity.targetId)
                            val target = context.identities.computeIfAbsent(key) { sequence.incrementAndGet() }
                            context.targets[target] = entity
                            mapOf("target" to target, "description" to description)
                        }
                        val live = result.map { it["target"] }.toSet()
                        for ((target, entity) in context.targets) {
                            if (entity.kind == kind.kind && target !in live) {
                                context.targets.remove(target)
                                context.identities.remove(entity.kind to requireNotNull(entity.targetId))
                            }
                        }
                        result
                    }
                }} ?: throw DeviceReadoutException(ErrorCode.ReadTimeout, "Native sensor inventory exceeded its deadline.")
            }
            "open" -> {
                val entity = context.targets[args.id("target")]
                    ?: throw DeviceReadoutException(ErrorCode.EntityRemoved, "Native sensor target removed.")
                val rate = args["hertz"]?.let {
                    val value = it as? Number ?: invalid("Invalid sampling rate.")
                    SensorSamplingRate.Hertz(value.toDouble())
                } ?: SensorSamplingRate.PlatformDefault
                val timeout = args.id("timeoutMicros").microseconds
                val access = context.access.withSensorSamplingRate(rate).withReadTimeout(timeout)
                val session = Session()
                val sessionId = sequence.incrementAndGet()
                session.job = scope.launch(start = CoroutineStart.LAZY) {
                    try {
                        access.watch(entity).collect { sample ->
                            if (!session.samples.trySend(sample).isSuccess) {
                                throw DeviceReadoutException(ErrorCode.ReadFailed, "Native sensor delivery queue is full.")
                            }
                        }
                        session.samples.close()
                    } catch (error: Throwable) {
                        session.samples.close(error)
                    }
                }
                context.sessions[sessionId] = session
                if (context.closed.get()) { context.sessions.remove(sessionId); session.close(); throw DeviceReadoutException(ErrorCode.EntityRemoved, "Native sensor context removed.") }
                session.job!!.start()
                sessionId
            }
            "next" -> {
                val session = context.sessions[args.id("session")]
                    ?: throw DeviceReadoutException(ErrorCode.EntityRemoved, "Native sensor session removed.")
                if (!session.receiving.compareAndSet(false, true)) invalid("Only one pending next request is allowed per session.")
                try { serializeSnapshot(session.samples.receive()) }
                finally { session.receiving.set(false) }
            }
            "close" -> { context.sessions.remove(args.id("session"))?.close(); null }
            else -> invalid("Unknown sensor protocol operation.")
        }
    }

    private fun closeContext(id: Long) {
        val context = contexts.remove(id) ?: return
        synchronized(context) {
            context.closed.set(true)
            context.targets.clear(); context.identities.clear()
        }
        context.changes.cancel(); context.dirtyKinds.clear()
        context.sessions.values.forEach { it.close() }; context.sessions.clear()
        context.access.close()
    }
    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        contexts.keys.toList().forEach(::closeContext)
        scope.cancel()
    }
}

private fun Map<*, *>.id(key: String): Long {
    val value = this[key] as? Number ?: invalid("Missing $key.")
    val number = value.toLong()
    if (number <= 0 || value.toDouble() != number.toDouble()) invalid("Invalid $key.")
    return number
}
private fun invalid(message: String): Nothing = throw DeviceReadoutException(ErrorCode.InvalidConfiguration, message)

private fun sensorKind(name: String?): Entity<out DeviceSnapshot> = when (name) {
    "Accelerometer" -> AccelerometerEntity
    "LinearAcceleration" -> LinearAccelerationEntity
    "Gravity" -> GravityEntity
    "Gyroscope" -> GyroscopeEntity
    "Magnetometer" -> MagnetometerEntity
    "RelativeOrientation" -> RelativeOrientationEntity
    "AbsoluteOrientation" -> AbsoluteOrientationEntity
    "Illuminance" -> IlluminanceEntity
    "Pressure" -> PressureEntity
    "AmbientTemperature" -> AmbientTemperatureEntity
    "RelativeHumidity" -> RelativeHumidityEntity
    "ProximityNear" -> ProximityNearEntity
    "ProximityDistance" -> ProximityDistanceEntity
    "RelativeAltitude" -> RelativeAltitudeEntity
    "HingeAngle" -> HingeAngleEntity
    "StepCountSinceBoot" -> StepCountSinceBootEntity
    "StepDetected" -> StepDetectedEntity
    "SignificantMotion" -> SignificantMotionEntity
    "HumanPresence" -> HumanPresenceEntity
    else -> invalid("Expected a supported sensor entity kind.")
}
