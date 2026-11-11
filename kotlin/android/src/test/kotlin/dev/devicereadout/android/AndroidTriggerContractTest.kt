package dev.devicereadout.android

import android.hardware.Sensor
import android.hardware.SensorManager
import android.os.Looper
import dev.devicereadout.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.shadow.api.Shadow
import org.robolectric.shadows.ShadowSensor
import org.robolectric.util.ReflectionHelpers
import kotlin.test.*
import kotlin.time.Duration.Companion.milliseconds

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36], shadows = [TriggerSensorService::class])
class AndroidTriggerContractTest {
    @Test fun triggerRegistrationRefusalAndInvalidOccurrenceAreTypedFailures() = runBlocking {
        val context = RuntimeEnvironment.getApplication()
        val service = Shadow.extract<TriggerSensorService>(context.getSystemService(SensorManager::class.java))
        val native = ShadowSensor.newInstance(Sensor.TYPE_SIGNIFICANT_MOTION)
        ReflectionHelpers.setField(native, "mFlags", Sensor.REPORTING_MODE_ONE_SHOT shl 1)
        service.addSensor(native)
        AndroidDeviceAccess.create(context).use {access ->
            val target = access.sensors.list(SignificantMotionEntity).single()
            service.refuseRegistration = true
            val refused = assertFailsWith<DeviceReadoutException> {access.get(target)}
            assertEquals(ErrorCode.ReadFailed, refused.code)
            service.refuseRegistration = false
            val reading = async {runCatching {access.get(target)}}
            withTimeout(5000) {while (service.triggerCount == 0) delay(5)}
            service.fire(native, 0f)
            val malformed = assertIs<DeviceReadoutException>(withTimeout(5000) {reading.await()}.exceptionOrNull())
            assertEquals(ErrorCode.ReadFailed, malformed.code)
            withTimeout(5000) {while (service.triggerCount != 0) delay(5)}
            assertTrue(service.serviceCallsOnMain.none {it})
        }
    }

    @Test fun appActivityObserverReleasesTriggerAndDiscardsPreviousSessionEvent() = runBlocking {
        val context = RuntimeEnvironment.getApplication()
        val service = Shadow.extract<TriggerSensorService>(context.getSystemService(SensorManager::class.java))
        val native = ShadowSensor.newInstance(Sensor.TYPE_SIGNIFICANT_MOTION)
        ReflectionHelpers.setField(native, "mFlags", Sensor.REPORTING_MODE_ONE_SHOT shl 1)
        service.addSensor(native)
        AndroidDeviceAccess.create(context).use {access ->
            val target = access.sensors.list(SignificantMotionEntity).single()
            val reading = async {access.withReadTimeout(200.milliseconds).watch(target).first()}
            withTimeout(5000) {while (service.triggerCount == 0) delay(5)}
            val lateEvent = service.prepareEvent(native, 1f)
            access.observers.sensorActivity(false)
            withTimeout(5000) {while (service.cancellations.get() == 0) delay(5)}
            lateEvent()
            delay(450)
            assertTrue(reading.isActive)
            assertEquals(0, service.triggerCount)
            access.observers.sensorActivity(true)
            withTimeout(5000) {while (service.triggerCount == 0) delay(5)}
            service.fire(native, 1f)
            assertEquals(true, withTimeout(5000) {reading.await()}.value)
            withTimeout(5000) {while (service.triggerCount != 0) delay(5)}
            assertTrue(service.serviceCallsOnMain.none {it})
        }
    }

    @Test fun oneShotWatchRearmsOffMainAndStopsOnCancellation() = runBlocking {
        val context = RuntimeEnvironment.getApplication()
        val manager = context.getSystemService(SensorManager::class.java)
        val service = Shadow.extract<TriggerSensorService>(manager)
        val native = ShadowSensor.newInstance(Sensor.TYPE_SIGNIFICANT_MOTION)
        ReflectionHelpers.setField(native, "mFlags", Sensor.REPORTING_MODE_ONE_SHOT shl 1)
        service.addSensor(native)
        AndroidDeviceAccess.create(context).use {access ->
            val target = access.sensors.list(SignificantMotionEntity).single()
            val description = access.describe(target)
            assertEquals(SensorReportingMode.OneShot, description.reportingMode)
            assertNull(description.maximumRange)
            val observed = mutableListOf<Boolean?>()
            val reading = async {access.withReadTimeout(200.milliseconds).watch(target).onEach {observed.add(it.value)}.take(2).toList()}
            withTimeout(5000) {while (service.triggerCount == 0) delay(5)}
            delay(450)
            assertTrue(reading.isActive)
            assertTrue(observed.isEmpty())
            assertSame(Looper.getMainLooper(), Looper.myLooper())
            service.fire(native, 1f)
            withTimeout(5000) {while (service.triggerCount == 0) delay(5)}
            service.fire(native, 1f)
            assertEquals(listOf(true, true), withTimeout(5000) {reading.await()}.map {it.value})
            withTimeout(5000) {while (service.triggerCount != 0) delay(5)}
            assertTrue(service.serviceCallsOnMain.isNotEmpty())
            assertTrue(service.serviceCallsOnMain.none {it}, "Trigger registration and cancellation must stay off the main Looper.")
        }
    }
}
