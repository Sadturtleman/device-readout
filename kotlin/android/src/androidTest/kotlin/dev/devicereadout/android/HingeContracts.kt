package dev.devicereadout.android

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Handler
import android.os.HandlerThread
import android.os.Bundle
import dev.devicereadout.*
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import kotlin.math.PI
import kotlin.math.abs
import kotlin.time.Duration.Companion.seconds
import java.util.concurrent.CopyOnWriteArrayList

internal object HingeContracts {
    suspend fun readsAndEvents(context: Context, results: Bundle, ready: (String) -> Unit) {
        val manager = context.getSystemService(SensorManager::class.java)
        val native = manager.getSensorList(Sensor.TYPE_HINGE_ANGLE).single()
        check(native.reportingMode == Sensor.REPORTING_MODE_ON_CHANGE)
        // Goldfish can initially replay a sentinel/previous angle. Wait for the fixture's actual native 90° state.
        val lane = HandlerThread("Hinge fixture oracle").apply {start()}
        val nativeValues = CopyOnWriteArrayList<Float>()
        var nativeListener: SensorEventListener? = null
        try {
            withTimeout(5000) {suspendCancellableCoroutine<Unit> {continuation ->
                val listener = object : SensorEventListener {
                    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
                    override fun onSensorChanged(event: SensorEvent) {
                        val value = event.values.firstOrNull() ?: Float.NaN
                        nativeValues.add(value)
                        if (value == 90f && continuation.isActive) continuation.resume(Unit)
                    }
                }
                nativeListener = listener
                continuation.invokeOnCancellation {manager.unregisterListener(listener)}
                check(manager.registerListener(listener, native, SensorManager.SENSOR_DELAY_NORMAL, Handler(lane.looper)))
            }}
            results.putFloat("hingeNativeInitialDegrees", nativeValues.first())
            results.putFloat("hingeNativeReadyDegrees", nativeValues.last())
        AndroidDeviceAccess.create(context).use {access ->
            val target = access.sensors.list(HingeAngleEntity).single()
            val description = access.describe(target)
            check(description.reportingMode == SensorReportingMode.OnChange)
            results.putFloat("hingeNativeMaximumDegrees", native.maximumRange)
            check(description.maximumRange != null && abs(description.maximumRange!! * 180 / PI - native.maximumRange) < 1e-4)
            val value = access.get(target)
            results.putString("hinge", serializeSnapshot(value))
            check(value.value != null && abs(value.value!! - PI / 2) < 1e-6) {"Expected a right-angle hinge sample, received ${value.value}."}
            var started = false
            withTimeout(10_000) {
                access.withPollInterval(30.seconds).watch(target).onEach {snapshot ->
                    if (!started) {
                        check(snapshot.value != null && abs(snapshot.value!! - PI / 2) < 1e-6)
                        started = true
                        ready("hingeMove")
                    }
                }.first {it.value != null && abs(it.value!! - PI) < 1e-6}
            }
            results.putString("hinge", serializeSnapshot(value))
            results.putString("hingeDescription", serializeSnapshot(description))
            results.putBoolean("hingeNativeEventAndRadianMapping", true)
        }
        } finally {
            nativeListener?.let(manager::unregisterListener)
            lane.quitSafely()
            results.putString("hingeNativeObservedDegrees", nativeValues.toString())
        }
    }
}
