package dev.devicereadout.android

import android.hardware.Sensor
import android.hardware.SensorManager
import android.hardware.TriggerEvent
import android.hardware.TriggerEventListener
import android.os.Looper
import org.robolectric.annotation.Implementation
import org.robolectric.annotation.Implements
import org.robolectric.shadows.ShadowSensorManager
import org.robolectric.util.ReflectionHelpers
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicInteger

/** External Android service fixture: trigger registration is disabled BEFORE the native callback. */
@Implements(className = "android.hardware.SystemSensorManager", isInAndroidSdk = false)
class TriggerSensorService : ShadowSensorManager() {
    private val triggers = ConcurrentHashMap<TriggerEventListener, Sensor>()
    val serviceCallsOnMain = CopyOnWriteArrayList<Boolean>()
    val cancellations = AtomicInteger()
    val triggerCount get() = triggers.size
    @Volatile var refuseRegistration = false

    @Implementation
    fun requestTriggerSensorImpl(listener: TriggerEventListener, sensor: Sensor): Boolean {
        serviceCallsOnMain.add(Looper.myLooper() == Looper.getMainLooper())
        if (refuseRegistration || sensor.reportingMode != Sensor.REPORTING_MODE_ONE_SHOT) return false
        triggers[listener] = sensor
        return true
    }

    @Implementation
    fun cancelTriggerSensorImpl(listener: TriggerEventListener, sensor: Sensor?, disable: Boolean): Boolean {
        serviceCallsOnMain.add(Looper.myLooper() == Looper.getMainLooper())
        cancellations.incrementAndGet()
        return if (sensor == null) triggers.remove(listener) != null else triggers.remove(listener, sensor)
    }

    fun prepareEvent(sensor: Sensor, value: Float): () -> Unit {
        val deliveries = mutableListOf<() -> Unit>()
        for ((listener, registered) in triggers.entries.toList()) {
            if (registered !== sensor || !triggers.remove(listener, sensor)) continue
            val event = ReflectionHelpers.callConstructor(TriggerEvent::class.java, ReflectionHelpers.ClassParameter.from(Int::class.javaPrimitiveType!!, 1))
            event.sensor = sensor
            event.values[0] = value
            deliveries.add {listener.onTrigger(event)}
        }
        return {deliveries.forEach {it()}}
    }
    fun fire(sensor: Sensor, value: Float) = prepareEvent(sensor, value).invoke()
}
