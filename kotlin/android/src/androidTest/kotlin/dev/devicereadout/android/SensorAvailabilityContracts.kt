package dev.devicereadout.android

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorManager
import android.os.Build
import android.os.Bundle
import dev.devicereadout.*

internal object SensorAvailabilityContracts {
    suspend fun reads(context: Context, results: Bundle) {
        val native = context.getSystemService(SensorManager::class.java)
        AndroidDeviceAccess.create(context).use {access ->
            for ((kind, type) in listOf(
                HingeAngleEntity to Sensor.TYPE_HINGE_ANGLE,
                StepCountSinceBootEntity to Sensor.TYPE_STEP_COUNTER,
                StepDetectedEntity to Sensor.TYPE_STEP_DETECTOR,
                SignificantMotionEntity to Sensor.TYPE_SIGNIFICANT_MOTION,
            )) {
                val expected = if (type == Sensor.TYPE_HINGE_ANGLE && Build.VERSION.SDK_INT < 30) 0
                    else (native.getSensorList(type) + native.getDynamicSensorList(type)).distinct().size
                val targets = access.sensors.list(kind)
                check(targets.size == expected)
                val supported = access.capabilities.get(kind)
                check(supported.readable == (expected > 0) && supported.watchable == (expected > 0))
                for (target in targets) check(access.describe(target).reportingMode != null)
                results.putInt("nativeSensor${type}TargetCount", targets.size)
            }
            // These meanings have no matching standard Android sensor type; off-body detection is not human presence.
            for (kind in listOf(RelativeAltitudeEntity, HumanPresenceEntity)) {
                val supported = access.capabilities.get(kind)
                check(supported.readable == false && supported.watchable == false)
                val failure = runCatching {access.sensors.list(kind)}.exceptionOrNull()
                check(failure is DeviceReadoutException && failure.code == ErrorCode.UnsupportedEntity)
            }
        }
        results.putBoolean("sensorAvailabilityMatchesNativeAndUnsupportedKindsStayExplicit", true)
    }
}
