package dev.devicereadout.android

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.telephony.TelephonyManager
import dev.devicereadout.*
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.withTimeout
import kotlin.time.Duration.Companion.milliseconds

/** Native oracles stay in memory: reports contain outcomes, never the actual identifiers. */
@SuppressLint("HardwareIds", "MissingPermission")
internal object IdentityContracts {
    @Suppress("DEPRECATION")
    suspend fun reads(context: Context, results: Bundle, granted: Boolean) {
        check((context.checkSelfPermission(Manifest.permission.READ_PHONE_STATE) == PackageManager.PERMISSION_GRANTED) == granted)
        val modernOs = Build.VERSION.SDK_INT >= 29
        val modernTarget = context.applicationInfo.targetSdkVersion >= 29
        val expectedDenial = !granted || (modernOs && modernTarget)
        val phone = context.getSystemService(TelephonyManager::class.java)
        val count = if (Build.VERSION.SDK_INT >= 30) phone.activeModemCount else phone.phoneCount
        check(count == 1) {"The named project AVD exposes one logical modem."}
        val nativeSerial = runCatching {Build.getSerial()}
        AndroidDeviceAccess.create(context).use {access ->
            var prompts = 0
            access.observers.onPermissionRequest {prompts++}
            check(access.capabilities.get(HardwareSerialEntity) == EntityCapabilities(true, true))
            check(access.capabilities.get(TelephonyIdentityEntity) == EntityCapabilities(true, true))
            val targets = access.telephonyIdentities.list()
            check(targets.size == count)
            check(access.telephonyIdentities.current() == null)
            if (expectedDenial) {
                check(nativeSerial.exceptionOrNull() is SecurityException)
                denied {access.get(HardwareSerialEntity)}
                denied {access.watch(HardwareSerialEntity).first()}
                for ((slot, target) in targets.withIndex()) {
                    check(runCatching {phone.getImei(slot)}.exceptionOrNull() is SecurityException)
                    denied {access.get(target)}
                    denied {access.watch(target).first()}
                }
                results.putString("identityNativePolicy", "PermissionDenied")
            } else if (modernOs) {
                // The legacy target's granted READ_PHONE_STATE produces native unavailability, not access.
                check(nativeSerial.getOrThrow() == Build.UNKNOWN)
                check(access.get(HardwareSerialEntity).serial == null)
                for ((slot, target) in targets.withIndex()) {
                    check(phone.getImei(slot) == null)
                    val snapshot = access.get(target)
                    check(snapshot.imei == null && snapshot.meid == null)
                }
                results.putString("identityNativePolicy", "LegacyTargetUnavailable")
            } else {
                val serial = nativeSerial.getOrThrow().takeUnless {it.isNullOrBlank() || it == Build.UNKNOWN}
                check(serial != null) {"This project emulator supplies a serial when legacy OS permission is granted."}
                check(access.get(HardwareSerialEntity).serial == serial)
                for ((slot, target) in targets.withIndex()) {
                    val imei = phone.getImei(slot)
                    check(!imei.isNullOrBlank()) {"The legacy OS fixture supplies an IMEI."}
                    val meid = runCatching {phone.getMeid(slot)}.getOrNull()?.takeUnless {it.isBlank()}
                    val pair = withTimeout(5000) {access.withPollInterval(20.milliseconds).watch(target).take(2).toList()}
                    check(pair.all {it.imei == imei && it.meid == meid})
                    check(pair.all {it.collectedAt.toEpochMilli() > 0})
                }
                results.putString("identityNativePolicy", "PermittedNativeValues")
            }
            check(prompts == 0)
        }
        results.putBoolean("identityNoAutomaticPermissionRequest", true)
        results.putBoolean("identityReportsContainNoIdentifierValues", true)
    }
    private suspend fun denied(read: suspend () -> Any?) {
        val failure = runCatching {read()}.exceptionOrNull()
        check(failure is DeviceReadoutException && failure.code == ErrorCode.PermissionDenied) {"Expected typed permission denial, got ${failure?.javaClass?.simpleName}."}
    }
}
