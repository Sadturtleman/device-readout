package dev.devicereadout

import java.util.concurrent.atomic.AtomicBoolean

/** Per-observation bridge sessions; late samples cannot alias a resumed or sibling observation. */
internal class BindingSensorSources(private val control: (String, Map<String, Any?>) -> Unit) : AutoCloseable {
    private class Session(val kind: EntityKind, val emit: (DeviceSnapshot) -> Unit, val fail: (Throwable) -> Unit) {
        val active = AtomicBoolean(true)
    }
    private val gate = Any()
    private val sessions = HashMap<Int, Session>()
    private var sequence = 0
    private var closed = false

    fun source(kind: EntityKind, address: Map<String, Any?>, description: SensorDescription) = ObservedSensorSource(description) {rate, emit, fail ->
        synchronized(gate) {
            if (closed) throw DeviceReadoutException(ErrorCode.EntityRemoved, "Sensor binding closed.")
            if (sessions.size >= 2048 || sequence == Int.MAX_VALUE) throw DeviceReadoutException(ErrorCode.ReadFailed, "Sensor session limit exceeded.")
            val id = ++sequence
            val session = Session(kind, emit, fail)
            sessions[id] = session
            try {
                control("sensorStart", mapOf("sessionId" to id, "entity" to address, "sensorHertz" to (rate as? SensorSamplingRate.Hertz)?.value))
            } catch (error: Throwable) {sessions.remove(id);session.active.set(false);throw error}
            Subscription({
                synchronized(gate) {
                    if (sessions.remove(id, session)) {
                        session.active.set(false)
                        if (!closed) control("sensorStop", mapOf("sessionId" to id))
                    }
                }
            })
        }
    }

    fun receive(input: Map<*, *>) {
        val rawId = (input["sessionId"] as? Number)?.toDouble()
        if (rawId == null || !rawId.isFinite() || rawId < 1 || rawId > Int.MAX_VALUE || rawId != rawId.toInt().toDouble())
            throw DeviceReadoutException(ErrorCode.InvalidConfiguration, "Invalid sensor session ID.")
        val session = synchronized(gate) {sessions[rawId.toInt()]} ?: return
        if (!session.active.get()) return
        try {
            val error = input["error"]
            if (error != null) {
                val value = error as? Map<*, *> ?: throw DeviceReadoutException(ErrorCode.ReadFailed, "Invalid sensor failure.")
                throw DeviceReadoutException(BindingValues.enum(value["code"], ErrorCode.entries) ?: ErrorCode.ReadFailed,
                    value["message"] as? String ?: "Application sensor observation failed.")
            }
            val values = input["values"] as? Map<*, *> ?: throw DeviceReadoutException(ErrorCode.ReadFailed, "Missing sensor sample.")
            val snapshot = decodeBindingSnapshot(session.kind, values)
            if (session.active.get()) session.emit(snapshot)
        } catch (error: Throwable) {
            if (session.active.get()) session.fail(error as? DeviceReadoutException
                ?: DeviceReadoutException(ErrorCode.ReadFailed, "Application sensor sample failed.", error))
        }
    }

    override fun close() = synchronized(gate) {
        closed = true;sessions.values.forEach {it.active.set(false)};sessions.clear()
    }
}
