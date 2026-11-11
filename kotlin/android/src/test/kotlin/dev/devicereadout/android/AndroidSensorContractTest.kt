package dev.devicereadout.android

import android.Manifest
import android.hardware.Sensor
import android.hardware.SensorManager
import dev.devicereadout.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.flow.onEach
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.SensorEventBuilder
import org.robolectric.shadows.ShadowSensor
import org.robolectric.util.ReflectionHelpers
import kotlin.math.PI
import kotlin.test.*
import kotlin.time.Duration.Companion.milliseconds

/** Exercises the public SDK against a controlled Android sensor service, not physical hardware. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class AndroidSensorContractTest {
    @Test fun stepEventsHaveNoSyntheticInitialOrIdleDeadlineAndKeepEqualOccurrences() = runBlocking {
        val context = RuntimeEnvironment.getApplication()
        shadowOf(context).grantPermissions(Manifest.permission.ACTIVITY_RECOGNITION)
        val manager = context.getSystemService(SensorManager::class.java)
        val native = ShadowSensor.newInstance(Sensor.TYPE_STEP_DETECTOR)
        shadowOf(native).setMaximumRange(1f)
        ReflectionHelpers.setField(native, "mFlags", Sensor.REPORTING_MODE_SPECIAL_TRIGGER shl 1)
        shadowOf(manager).addSensor(native)
        AndroidDeviceAccess.create(context).use {access ->
            val target = access.sensors.list(StepDetectedEntity).single()
            val description = access.describe(target)
            assertEquals(SensorReportingMode.SpecialTrigger, description.reportingMode)
            assertNull(description.maximumRange)
            val observed = mutableListOf<Boolean?>()
            val reading = async {access.withReadTimeout(200.milliseconds).watch(target).onEach {observed.add(it.value)}.take(2).toList()}
            withTimeout(5000) {while (shadowOf(manager).listeners.isEmpty()) delay(5)}
            delay(450)
            assertTrue(reading.isActive)
            assertTrue(observed.isEmpty())
            repeat(2) {shadowOf(manager).sendSensorEventToListeners(SensorEventBuilder.newBuilder().setSensor(native).setValues(floatArrayOf(1f)).build())}
            assertEquals(listOf(true, true), withTimeout(5000) {reading.await()}.map {it.value})
            val failure = assertFailsWith<DeviceReadoutException> {access.withReadTimeout(200.milliseconds).get(target)}
            assertEquals(ErrorCode.ReadTimeout, failure.code)
        }
    }

    @Test fun deniedStepCounterReadDoesNotRequestPermission() = runBlocking {
        val context = RuntimeEnvironment.getApplication()
        shadowOf(context).denyPermissions(Manifest.permission.ACTIVITY_RECOGNITION)
        val manager = context.getSystemService(SensorManager::class.java)
        shadowOf(manager).addSensor(ShadowSensor.newInstance(Sensor.TYPE_STEP_COUNTER))
        shadowOf(manager).addSensor(ShadowSensor.newInstance(Sensor.TYPE_STEP_DETECTOR))
        AndroidDeviceAccess.create(context).use {access ->
            var prompts = 0
            access.observers.onPermissionRequest {prompts++}
            for (kind in listOf(StepCountSinceBootEntity, StepDetectedEntity)) {
                val target = access.sensors.list(kind).single()
                val failure = assertFailsWith<DeviceReadoutException> {access.withReadTimeout(500.milliseconds).get(target)}
                assertEquals(ErrorCode.PermissionDenied, failure.code)
            }
            assertEquals(0, prompts)
            assertTrue(shadowOf(manager).listeners.isEmpty())
        }
    }

    @Test fun stepCounterPreservesNativeIntegersAndRejectsInvalidCounts() = runBlocking {
        val context = RuntimeEnvironment.getApplication()
        shadowOf(context).grantPermissions(Manifest.permission.ACTIVITY_RECOGNITION)
        val manager = context.getSystemService(SensorManager::class.java)
        val native = ShadowSensor.newInstance(Sensor.TYPE_STEP_COUNTER)
        ReflectionHelpers.setField(native, "mFlags", Sensor.REPORTING_MODE_ON_CHANGE shl 1)
        shadowOf(manager).addSensor(native)
        AndroidDeviceAccess.create(context).use {access ->
            val target = access.sensors.list(StepCountSinceBootEntity).single()
            assertEquals(SensorReportingMode.OnChange, access.describe(target).reportingMode)
            val values = floatArrayOf(0f, 42f, 1099511627776f, -1f, 1.5f, Float.NaN, Float.POSITIVE_INFINITY, 9223372036854775808f)
            val reading = async {access.watch(target).take(values.size).toList()}
            withTimeout(5000) {while (shadowOf(manager).listeners.isEmpty()) delay(5)}
            for (value in values) shadowOf(manager).sendSensorEventToListeners(SensorEventBuilder.newBuilder().setSensor(native).setValues(floatArrayOf(value)).build())
            assertEquals(listOf(0L, 42L, 1099511627776L, null, null, null, null, null), withTimeout(5000) {reading.await()}.map {it.value})
        }
    }

    @Test fun hingeReadAndDescriptionUseRadians() = runBlocking {
        val context = RuntimeEnvironment.getApplication()
        val manager = context.getSystemService(SensorManager::class.java)
        val native = ShadowSensor.newInstance(Sensor.TYPE_HINGE_ANGLE)
        shadowOf(native).setMaximumRange(180f)
        ReflectionHelpers.setField(native, "mResolution", 1f)
        ReflectionHelpers.setField(native, "mFlags", Sensor.REPORTING_MODE_ON_CHANGE shl 1)
        shadowOf(manager).addSensor(native)
        AndroidDeviceAccess.create(context).use {access ->
            val target = access.sensors.list(HingeAngleEntity).single()
            val description = access.describe(target)
            assertEquals(SensorReportingMode.OnChange, description.reportingMode)
            assertEquals(PI, description.maximumRange!!, 1e-12)
            assertEquals(PI / 180, description.resolution!!, 1e-12)
            val reading = async {access.get(target)}
            withTimeout(5000) {while (shadowOf(manager).listeners.isEmpty()) delay(5)}
            shadowOf(manager).sendSensorEventToListeners(SensorEventBuilder.newBuilder().setSensor(native).setValues(floatArrayOf(90f)).build())
            assertEquals(PI / 2, reading.await().value!!, 1e-12)
            withTimeout(5000) {while (shadowOf(manager).listeners.isNotEmpty()) delay(5)}
            val values = floatArrayOf(-1e30f, -1f, 361f, Float.NaN, 360f, 0f)
            val invalidReading = async {access.watch(target).take(values.size).toList()}
            withTimeout(5000) {while (shadowOf(manager).listeners.isEmpty()) delay(5)}
            for (value in values) shadowOf(manager).sendSensorEventToListeners(SensorEventBuilder.newBuilder().setSensor(native).setValues(floatArrayOf(value)).build())
            assertEquals(listOf(null, null, null, null, 6.283185307179586, 0.0), withTimeout(5000) {invalidReading.await()}.map {it.value})
        }
    }

    @Test fun malformedStepOccurrenceFailsInsteadOfEmittingFalseOrNull() = runBlocking {
        val context = RuntimeEnvironment.getApplication()
        shadowOf(context).grantPermissions(Manifest.permission.ACTIVITY_RECOGNITION)
        val manager = context.getSystemService(SensorManager::class.java)
        val native = ShadowSensor.newInstance(Sensor.TYPE_STEP_DETECTOR)
        ReflectionHelpers.setField(native, "mFlags", Sensor.REPORTING_MODE_SPECIAL_TRIGGER shl 1)
        shadowOf(manager).addSensor(native)
        AndroidDeviceAccess.create(context).use {access ->
            val target = access.sensors.list(StepDetectedEntity).single()
            val reading = async {runCatching {access.get(target)}}
            withTimeout(5000) {while (shadowOf(manager).listeners.isEmpty()) delay(5)}
            shadowOf(manager).sendSensorEventToListeners(SensorEventBuilder.newBuilder().setSensor(native).setValues(floatArrayOf(0f)).build())
            val failure = assertIs<DeviceReadoutException>(withTimeout(5000) {reading.await()}.exceptionOrNull())
            assertEquals(ErrorCode.ReadFailed, failure.code)
        }
    }
}
