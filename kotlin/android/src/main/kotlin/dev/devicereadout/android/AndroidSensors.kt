package dev.devicereadout.android

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.hardware.TriggerEvent
import android.hardware.TriggerEventListener
import android.os.Build
import dev.devicereadout.*
import java.util.IdentityHashMap
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.time.Duration.Companion.microseconds

internal class AndroidSensors(private val context: Context) {
    private data class Target(val id: String, val sensor: Sensor, var removed: Boolean = false)
    private val gate = Any()
    private val targets = LinkedHashMap<String, Target>()
    private val bySensor = IdentityHashMap<Sensor, Target>()
    private var sequence = 0L
    private fun manager() = context.getSystemService(SensorManager::class.java)
        ?: throw DeviceReadoutException(ErrorCode.UnsupportedEntity, "SensorManager is unavailable.")
    private fun nativeTypes(kind: EntityKind): List<Int>? = when (kind) {
        EntityKind.Accelerometer -> listOf(Sensor.TYPE_ACCELEROMETER)
        EntityKind.LinearAcceleration -> listOf(Sensor.TYPE_LINEAR_ACCELERATION)
        EntityKind.Gravity -> listOf(Sensor.TYPE_GRAVITY)
        EntityKind.Gyroscope -> listOf(Sensor.TYPE_GYROSCOPE)
        EntityKind.Magnetometer -> listOf(Sensor.TYPE_MAGNETIC_FIELD)
        EntityKind.RelativeOrientation -> listOf(Sensor.TYPE_GAME_ROTATION_VECTOR)
        EntityKind.AbsoluteOrientation -> listOf(Sensor.TYPE_ROTATION_VECTOR, Sensor.TYPE_GEOMAGNETIC_ROTATION_VECTOR)
        EntityKind.Pressure -> listOf(Sensor.TYPE_PRESSURE)
        EntityKind.RelativeHumidity -> listOf(Sensor.TYPE_RELATIVE_HUMIDITY)
        EntityKind.AmbientTemperature -> listOf(Sensor.TYPE_AMBIENT_TEMPERATURE)
        EntityKind.Illuminance -> listOf(Sensor.TYPE_LIGHT)
        EntityKind.ProximityNear, EntityKind.ProximityDistance -> listOf(Sensor.TYPE_PROXIMITY)
        EntityKind.HingeAngle -> if (Build.VERSION.SDK_INT >= 30) listOf(Sensor.TYPE_HINGE_ANGLE) else emptyList()
        EntityKind.StepCountSinceBoot -> listOf(Sensor.TYPE_STEP_COUNTER)
        EntityKind.StepDetected -> listOf(Sensor.TYPE_STEP_DETECTOR)
        EntityKind.SignificantMotion -> listOf(Sensor.TYPE_SIGNIFICANT_MOTION)
        else -> null
    }
    fun supportsKind(kind: EntityKind) = nativeTypes(kind) != null
    private fun inventory(kind: EntityKind): List<Target> {
        val types = nativeTypes(kind) ?: throw DeviceReadoutException(ErrorCode.UnsupportedEntity, "No Android sensor mapping exists for this kind.")
        val manager = manager()
        val available = types.flatMap {manager.getSensorList(it) + manager.getDynamicSensorList(it)}.distinct()
        return synchronized(gate) {
            targets.values.filter {it.sensor.type in types && available.none {sensor -> sensor === it.sensor}}.forEach {it.removed = true}
            available.map {sensor ->
                val existing = bySensor[sensor]
                if (existing != null && !existing.removed) existing else {
                    Target("sensor-${++sequence}", sensor).also {targets[it.id] = it;bySensor[sensor] = it}
                }
            }
        }
    }
    fun list(kind: EntityKind): List<String> = inventory(kind).map {it.id}
    fun observeInventory(changed: (EntityKind) -> Unit, fail: (Throwable) -> Unit): CollectorSubscription {
        val manager = manager()
        val lane = CallbackLane("DeviceReadout sensor inventory", fail)
        val closed = AtomicBoolean()
        fun changed(sensor: Sensor, disconnected: Boolean) {
            if (closed.get()) return
            if (disconnected) synchronized(gate) {
                // Retire the observed native object even if it reappears before the next list.
                // Numeric sensor IDs do not identify a generation.
                targets.values.filter {it.sensor === sensor}.forEach {it.removed = true}
            }
            for (kind in EntityKind.entries) {
                if (sensor.type in nativeTypes(kind).orEmpty()) changed(kind)
            }
        }
        val callback = object : SensorManager.DynamicSensorCallback() {
            override fun onDynamicSensorConnected(sensor: Sensor) = lane.deliver {changed(sensor, false)}
            override fun onDynamicSensorDisconnected(sensor: Sensor) = lane.deliver {changed(sensor, true)}
        }
        try {
            manager.registerDynamicSensorCallback(callback, lane.handler)
            return object : CollectorSubscription {
                override val pollingRequired = false
                override fun close() {
                    if (!closed.compareAndSet(false, true)) return
                    try {manager.unregisterDynamicSensorCallback(callback)} finally {lane.close()}
                }
            }
        } catch (error: Throwable) {
            closed.set(true)
            try {manager.unregisterDynamicSensorCallback(callback)} catch (_: Exception) {}
            lane.close();throw error
        }
    }
    private fun resolve(entity: EntityAddress): Target {
        inventory(entity.kind)
        return synchronized(gate) {
            targets[entity.targetId]?.takeIf {!it.removed && it.sensor.type in nativeTypes(entity.kind).orEmpty()}
                ?: throw DeviceReadoutException(ErrorCode.EntityRemoved, "The sensor target was removed.")
        }
    }
    fun capabilities(entity: EntityAddress): EntityCapabilities {
        val available = if (entity.targetId == null) inventory(entity.kind).isNotEmpty() else {
            try {resolve(entity);true} catch (error: DeviceReadoutException) {if (error.code == ErrorCode.EntityRemoved) false else throw error}
        }
        return EntityCapabilities(available, available)
    }
    fun describe(entity: EntityAddress): SensorDescription {
        val sensor = resolve(entity).sensor
        return SensorDescription(
            kind = SensorKind.entries.firstOrNull {it.name == entity.kind.name},
            name = sensor.name,
            vendor = sensor.vendor,
            version = sensor.version.toString(),
            reportingMode = when (sensor.reportingMode) {
                Sensor.REPORTING_MODE_CONTINUOUS -> SensorReportingMode.Continuous
                Sensor.REPORTING_MODE_ON_CHANGE -> SensorReportingMode.OnChange
                Sensor.REPORTING_MODE_ONE_SHOT -> SensorReportingMode.OneShot
                Sensor.REPORTING_MODE_SPECIAL_TRIGGER -> SensorReportingMode.SpecialTrigger
                else -> null
            },
            minimumInterval = sensor.minDelay.takeIf {it >= 0}?.microseconds,
            maximumInterval = sensor.maxDelay.takeIf {it >= 0}?.microseconds,
            maximumRange = metadataValue(entity.kind, sensor.maximumRange.toDouble()),
            resolution = metadataValue(entity.kind, sensor.resolution.toDouble()),
            powerMilliamps = sensor.power.toDouble(),
            fifoCapacity = sensor.fifoMaxEventCount.takeIf {it >= 0},
        )
    }
    fun observe(entity: EntityAddress, rate: SensorSamplingRate, emit: (DeviceSnapshot) -> Unit, fail: (Throwable) -> Unit): CollectorSubscription {
        val target = resolve(entity)
        if (Build.VERSION.SDK_INT >= 29 && entity.kind in setOf(EntityKind.StepCountSinceBoot, EntityKind.StepDetected) &&
            context.checkSelfPermission(Manifest.permission.ACTIVITY_RECOGNITION) != PackageManager.PERMISSION_GRANTED) {
            throw DeviceReadoutException(ErrorCode.PermissionDenied, "The step sensor requires activity recognition permission.")
        }
        val manager = manager()
        if (entity.kind == EntityKind.SignificantMotion) return observeTrigger(target, manager, emit, fail)
        val lane = CallbackLane("DeviceReadout sensor", fail)
        val closed = AtomicBoolean()
        val listener = object : SensorEventListener {
            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
            override fun onSensorChanged(event: SensorEvent) {
                if (closed.get()) return
                lane.deliver {
                    emit(measurement(entity.kind, target.sensor, event.values))
                }
            }
        }
        val dynamic = object : SensorManager.DynamicSensorCallback() {
            override fun onDynamicSensorDisconnected(sensor: Sensor) {
                if (closed.get() || sensor !== target.sensor) return
                synchronized(gate) {target.removed = true}
                if (!closed.get()) fail(DeviceReadoutException(ErrorCode.EntityRemoved, "The sensor was disconnected."))
            }
        }
        var dynamicsRegistered = false
        try {
            manager.registerDynamicSensorCallback(dynamic, lane.handler);dynamicsRegistered = true
            val period = if (rate is SensorSamplingRate.Hertz && target.sensor.reportingMode == Sensor.REPORTING_MODE_CONTINUOUS) {
                val micros = 1_000_000.0 / rate.value
                if (micros < 4) SensorManager.SENSOR_DELAY_FASTEST else micros.coerceAtMost(Int.MAX_VALUE.toDouble()).toInt()
            } else SensorManager.SENSOR_DELAY_NORMAL
            if (!manager.registerListener(listener, target.sensor, period, 0, lane.handler)) throw DeviceReadoutException(ErrorCode.ReadFailed, "Android refused the sensor subscription.")
            return object : CollectorSubscription {
                override val pollingRequired = false
                override fun close() {
                    if (!closed.compareAndSet(false, true)) return
                    try {manager.unregisterListener(listener, target.sensor)} finally {
                        try {manager.unregisterDynamicSensorCallback(dynamic)} finally {lane.close()}
                    }
                }
            }
        } catch (error: Throwable) {
            try {manager.unregisterListener(listener, target.sensor)} catch (_: Exception) {}
            try {if (dynamicsRegistered) manager.unregisterDynamicSensorCallback(dynamic)} catch (_: Exception) {}
            lane.close();throw error
        }
    }
    private fun observeTrigger(target: Target, manager: SensorManager, emit: (DeviceSnapshot) -> Unit, fail: (Throwable) -> Unit): CollectorSubscription {
        val lane = CallbackLane("DeviceReadout trigger", fail)
        val closed = AtomicBoolean()
        val registrationGate = Any()
        val listener = object : TriggerEventListener() {
            override fun onTrigger(event: TriggerEvent) {
                if (closed.get()) return
                // Android's public trigger API has no Handler parameter. Copy the scalar and leave its callback immediately.
                val value = event.values.firstOrNull()
                lane.post {
                    if (closed.get()) return@post
                    if (value != 1f) throw DeviceReadoutException(ErrorCode.ReadFailed, "Android delivered an invalid significant-motion event.")
                    emit(SignificantMotionSnapshot(value = true))
                    synchronized(registrationGate) {
                        // Native one-shot registration was automatically removed before onTrigger.
                        if (!closed.get() && !manager.requestTriggerSensor(this, target.sensor)) {
                            throw DeviceReadoutException(ErrorCode.ReadFailed, "Android refused to rearm the trigger sensor.")
                        }
                    }
                }
            }
        }
        val dynamic = object : SensorManager.DynamicSensorCallback() {
            override fun onDynamicSensorDisconnected(sensor: Sensor) {
                if (closed.get() || sensor !== target.sensor) return
                synchronized(gate) {target.removed = true}
                if (!closed.get()) fail(DeviceReadoutException(ErrorCode.EntityRemoved, "The sensor was disconnected."))
            }
        }
        var dynamicsRegistered = false
        try {
            manager.registerDynamicSensorCallback(dynamic, lane.handler);dynamicsRegistered = true
            if (!manager.requestTriggerSensor(listener, target.sensor)) throw DeviceReadoutException(ErrorCode.ReadFailed, "Android refused the trigger subscription.")
            return object : CollectorSubscription {
                override val pollingRequired = false
                override fun close() {
                    synchronized(registrationGate) {
                        if (!closed.compareAndSet(false, true)) return
                        try {manager.cancelTriggerSensor(listener, target.sensor)} finally {
                            try {manager.unregisterDynamicSensorCallback(dynamic)} finally {lane.close()}
                        }
                    }
                }
            }
        } catch (error: Throwable) {
            closed.set(true)
            try {manager.cancelTriggerSensor(listener, target.sensor)} catch (_: Exception) {}
            try {if (dynamicsRegistered) manager.unregisterDynamicSensorCallback(dynamic)} catch (_: Exception) {}
            lane.close();throw error
        }
    }
    private fun metadataValue(kind: EntityKind, value: Double): Double? = when (kind) {
        EntityKind.Pressure -> value * 100
        EntityKind.RelativeHumidity -> value / 100
        EntityKind.ProximityDistance -> value / 100
        EntityKind.HingeAngle -> Math.toRadians(value)
        EntityKind.ProximityNear, EntityKind.RelativeOrientation, EntityKind.AbsoluteOrientation, EntityKind.StepDetected, EntityKind.SignificantMotion -> null
        else -> value
    }
    private fun measurement(kind: EntityKind, sensor: Sensor, values: FloatArray): DeviceSnapshot {
        fun vector(): Vector3? = if (values.size >= 3) Vector3(values[0].toDouble(), values[1].toDouble(), values[2].toDouble()) else null
        val scalar = values.firstOrNull()?.toDouble()?.takeIf {it.isFinite()}
        return when (kind) {
            EntityKind.Accelerometer -> AccelerometerSnapshot(value = vector())
            EntityKind.LinearAcceleration -> LinearAccelerationSnapshot(value = vector())
            EntityKind.Gravity -> GravitySnapshot(value = vector())
            EntityKind.Gyroscope -> GyroscopeSnapshot(value = vector())
            EntityKind.Magnetometer -> MagnetometerSnapshot(value = vector())
            EntityKind.RelativeOrientation -> RelativeOrientationSnapshot(value = quaternion(values))
            EntityKind.AbsoluteOrientation -> AbsoluteOrientationSnapshot(value = quaternion(values))
            EntityKind.Pressure -> PressureSnapshot(value = scalar?.takeIf {it >= 0}?.times(100))
            EntityKind.RelativeHumidity -> RelativeHumiditySnapshot(value = scalar?.div(100))
            EntityKind.AmbientTemperature -> AmbientTemperatureSnapshot(value = scalar?.takeIf {it >= -273.15})
            EntityKind.Illuminance -> IlluminanceSnapshot(value = scalar?.takeIf {it >= 0})
            EntityKind.ProximityDistance -> ProximityDistanceSnapshot(value = scalar?.takeIf {it >= 0}?.div(100))
            EntityKind.ProximityNear -> ProximityNearSnapshot(value = scalar?.takeIf {it >= 0 && sensor.maximumRange.isFinite() && sensor.maximumRange > 0}?.let {it < sensor.maximumRange})
            EntityKind.HingeAngle -> HingeAngleSnapshot(value = scalar?.takeIf {it in 0.0..360.0}?.let(Math::toRadians))
            // 2^63 is exactly representable as Double; Long.MAX_VALUE rounded to Double is not a safe inclusive bound.
            EntityKind.StepCountSinceBoot -> StepCountSinceBootSnapshot(value = scalar?.takeIf {it >= 0 && it < 9223372036854775808.0 && it % 1.0 == 0.0}?.toLong())
            EntityKind.StepDetected -> {
                if (scalar != 1.0) throw DeviceReadoutException(ErrorCode.ReadFailed, "Android delivered an invalid step event.")
                StepDetectedSnapshot(value = true)
            }
            else -> throw DeviceReadoutException(ErrorCode.UnsupportedEntity, "No sensor measurement mapping exists.")
        }
    }
    private fun quaternion(values: FloatArray): Quaternion? {
        if (values.size < 3 || values.take(4).any {!it.isFinite()}) return null
        val rotation = FloatArray(4)
        SensorManager.getQuaternionFromVector(rotation, values)
        val norm = kotlin.math.sqrt(rotation.sumOf {it.toDouble() * it})
        if (!norm.isFinite() || norm == 0.0) return null
        return Quaternion(rotation[1] / norm, rotation[2] / norm, rotation[3] / norm, rotation[0] / norm)
    }
}
