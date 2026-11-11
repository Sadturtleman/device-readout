package dev.devicereadout.android

import android.hardware.Sensor
import android.hardware.SensorManager
import android.os.Handler
import android.os.Looper
import kotlinx.coroutines.CompletableDeferred
import org.robolectric.annotation.Implementation
import org.robolectric.annotation.Implements
import org.robolectric.shadows.ShadowSensorManager
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicInteger

/** Controlled external sensor service. Normal deliveries honor the supplied Handler. */
@Implements(className = "android.hardware.SystemSensorManager", isInAndroidSdk = false)
class InventorySensorService : ShadowSensorManager() {
    val dynamic = CopyOnWriteArrayList<Sensor>()
    val callbacks = ConcurrentHashMap<SensorManager.DynamicSensorCallback, Handler>()
    val callsOnMain = CopyOnWriteArrayList<Boolean>()
    val callbacksOnMain = CopyOnWriteArrayList<Boolean>()

    @Implementation fun getFullDynamicSensorList(): List<Sensor> {
        callsOnMain.add(Looper.myLooper() == Looper.getMainLooper())
        return dynamic.toList()
    }
    @Implementation fun registerDynamicSensorCallbackImpl(callback: SensorManager.DynamicSensorCallback, handler: Handler?) {
        callsOnMain.add(Looper.myLooper() == Looper.getMainLooper())
        callbacks[callback] = requireNotNull(handler)
    }
    @Implementation fun unregisterDynamicSensorCallbackImpl(callback: SensorManager.DynamicSensorCallback) {
        callsOnMain.add(Looper.myLooper() == Looper.getMainLooper())
        callbacks.remove(callback)
    }
    fun notify(sensor: Sensor, connected: Boolean): CompletableDeferred<Unit> {
        val result = CompletableDeferred<Unit>()
        val recipients = callbacks.entries.toList()
        if (recipients.isEmpty()) {result.complete(Unit);return result}
        val remaining = AtomicInteger(recipients.size)
        recipients.forEach {(callback, handler) ->
            check(handler.post {
                try {
                    callbacksOnMain.add(Looper.myLooper() == Looper.getMainLooper())
                    if (connected) callback.onDynamicSensorConnected(sensor) else callback.onDynamicSensorDisconnected(sensor)
                    if (remaining.decrementAndGet() == 0) result.complete(Unit)
                } catch (error: Throwable) {result.completeExceptionally(error)}
            })
        }
        return result
    }
    fun lateDisconnect(sensor: Sensor): () -> Unit {
        val captured = callbacks.keys.toList()
        return {captured.forEach {it.onDynamicSensorDisconnected(sensor)}}
    }
}
