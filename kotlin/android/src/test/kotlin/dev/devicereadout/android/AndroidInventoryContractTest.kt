package dev.devicereadout.android

import android.hardware.Sensor
import android.hardware.SensorManager
import dev.devicereadout.*
import kotlinx.coroutines.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.shadow.api.Shadow
import org.robolectric.shadows.ShadowSensor
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.Executors
import kotlin.test.*

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36], shadows = [InventorySensorService::class])
class AndroidInventoryContractTest {
    @Test fun dynamicInventoryPreservesRemovalAcrossReconnectionAndUsesItsHandler(): Unit = runBlocking {
        val context = RuntimeEnvironment.getApplication()
        val service = Shadow.extract<InventorySensorService>(context.getSystemService(SensorManager::class.java))
        val source = AndroidSensors(context)
        val sensor = ShadowSensor.newInstance(Sensor.TYPE_PROXIMITY)
        service.dynamic.add(sensor)
        val lane = Executors.newSingleThreadExecutor().asCoroutineDispatcher()
        val changes = CopyOnWriteArrayList<EntityKind>()
        val errors = CopyOnWriteArrayList<Throwable>()
        var observer: CollectorSubscription? = null
        try {
            withTimeout(5000) {
                observer = withContext(lane) {source.observeInventory(changes::add, errors::add)}
                val old = withContext(lane) {source.list(EntityKind.ProximityNear).single()}
                service.notify(sensor, true).await()
                assertEquals(setOf(EntityKind.ProximityNear, EntityKind.ProximityDistance), changes.toSet())
                service.dynamic.remove(sensor)
                service.notify(sensor, false).await()
                service.dynamic.add(sensor)
                service.notify(sensor, true).await()
                val fresh = withContext(lane) {source.list(EntityKind.ProximityNear).single()}
                assertNotEquals(old, fresh, "A disconnect observed between two lists retires the generation.")
                assertFalse(withContext(lane) {source.capabilities(EntityAddress(EntityKind.ProximityNear, old)).readable}!!)
                val late = service.lateDisconnect(sensor)
                withContext(lane) {observer!!.close()}
                val count = changes.size
                late()
                assertEquals(count, changes.size)
                assertEquals(fresh, withContext(lane) {source.list(EntityKind.ProximityNear).single()})
                assertTrue(service.callbacks.isEmpty())
                assertTrue(errors.isEmpty())
                assertTrue(service.callsOnMain.isNotEmpty() && service.callsOnMain.none {it})
                assertTrue(service.callbacksOnMain.isNotEmpty() && service.callbacksOnMain.none {it})
            }
        } finally {withContext(lane) {observer?.close()};lane.close()}
    }

    @Test fun anOldNativeObjectCannotDisconnectAnotherSensorWithTheSameNumericId(): Unit = runBlocking {
        val context = RuntimeEnvironment.getApplication()
        val service = Shadow.extract<InventorySensorService>(context.getSystemService(SensorManager::class.java))
        val source = AndroidSensors(context)
        val old = ShadowSensor.newInstance(Sensor.TYPE_PRESSURE)
        val current = ShadowSensor.newInstance(Sensor.TYPE_PRESSURE)
        assertEquals(old.id, current.id)
        service.dynamic.add(current)
        val lane = Executors.newSingleThreadExecutor().asCoroutineDispatcher()
        val errors = CopyOnWriteArrayList<Throwable>()
        var observer: CollectorSubscription? = null
        var samples: CollectorSubscription? = null
        try {
            withTimeout(5000) {
                val target = withContext(lane) {source.list(EntityKind.Pressure).single()}
                observer = withContext(lane) {source.observeInventory({}, errors::add)}
                samples = withContext(lane) {source.observe(EntityAddress(EntityKind.Pressure, target),
                    SensorSamplingRate.PlatformDefault, {}, errors::add)}
                service.notify(old, false).await()
                assertTrue(errors.isEmpty(), "A numeric ID is not the identity of the native sensor object.")
                assertEquals(target, withContext(lane) {source.list(EntityKind.Pressure).single()})
            }
        } finally {withContext(lane) {samples?.close();observer?.close()};lane.close()}
    }
}
