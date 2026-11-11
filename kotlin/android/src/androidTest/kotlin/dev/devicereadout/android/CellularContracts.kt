package dev.devicereadout.android

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager
import dev.devicereadout.*
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds

internal object CellularContracts {
    suspend fun events(context: Context, results: Bundle, ready: (String) -> Unit) {
        AndroidDeviceAccess.create(context).use {access ->
            val target = access.cellularSubscriptions.current() ?: error("The fixture requires an active data subscription.")
            check(access.get(target).roaming == false)
            var stage = 0
            val observed = mutableListOf<Boolean?>()
            try {withTimeout(15000) {
                access.withPollInterval(30.seconds).watch(target).onEach {value ->
                    observed.add(value.roaming)
                    when {
                        stage == 0 -> {check(value.roaming == false);stage = 1;ready("cellularRoaming")}
                        stage == 1 && value.roaming == true -> {stage = 2;ready("cellularHome")}
                        stage == 2 && value.roaming == false -> stage = 3
                    }
                }.first {stage == 3}
            }} catch (error: Throwable) {
                results.putString("cellularObservedRoaming", observed.toString())
                results.putString("cellularFinalSnapshot", serializeSnapshot(access.get(target)))
                val native = context.getSystemService(TelephonyManager::class.java)
                results.putBoolean("cellularNativeRoamingAtFailure", native.isNetworkRoaming)
                throw error
            }
            check(access.get(target).roaming == false)
            results.putBoolean("cellularNativeRoamingTransitions", true)
        }
    }
    suspend fun denied(context: Context, results: Bundle, runtimePermissionGranted: Boolean = false) {
        check((context.checkSelfPermission(Manifest.permission.READ_PHONE_STATE) == PackageManager.PERMISSION_GRANTED) == runtimePermissionGranted)
        val native = runCatching {context.getSystemService(SubscriptionManager::class.java).activeSubscriptionInfoList.orEmpty()}
        results.putInt("nativeVisibleSubscriptionCount", native.getOrNull()?.size ?: -1)
        results.putString("nativeSubscriptionError", native.exceptionOrNull()?.javaClass?.simpleName ?: "none")
        @Suppress("DEPRECATION")
        val mode = context.getSystemService(android.app.AppOpsManager::class.java).checkOpNoThrow(android.app.AppOpsManager.OPSTR_READ_PHONE_STATE, android.os.Process.myUid(), context.packageName)
        results.putInt("nativePhoneStateAppOp", mode)
        AndroidDeviceAccess.create(context).use {access ->
            var requests = 0
            access.observers.onPermissionRequest {requests++}
            val error = runCatching {access.cellularSubscriptions.list()}.exceptionOrNull()
            check(error is DeviceReadoutException && error.code == ErrorCode.PermissionDenied) {"Expected actual OS permission failure: $error"}
            check(requests == 0)
        }
        results.putBoolean("cellularActualPermissionDenied", true)
    }
    suspend fun reads(context: Context, results: Bundle) {
        check(context.checkSelfPermission(Manifest.permission.READ_PHONE_STATE) == PackageManager.PERMISSION_GRANTED)
        val native = context.getSystemService(SubscriptionManager::class.java).activeSubscriptionInfoList.orEmpty()
        check(native.size == 1) {"The dedicated AVD fixture exposes one active subscription."}
        val subscription = native.single()
        val phone = context.getSystemService(TelephonyManager::class.java).createForSubscriptionId(subscription.subscriptionId)
        AndroidDeviceAccess.create(context).use {access ->
            var requests = 0
            access.observers.onPermissionRequest {requests++}
            val targets = access.cellularSubscriptions.list()
            check(targets.size == 1)
            val value = access.get(targets.single())
            check(value.slotIndex == subscription.simSlotIndex)
            check(value.carrierName == subscription.carrierName.toString())
            check(value.countryCode == subscription.countryIso)
            val operator = phone.simOperator
            check(operator.matches(Regex("[0-9]{5,6}")))
            check(value.mobileCountryCode == operator.substring(0, 3))
            check(value.mobileNetworkCode == operator.substring(3))
            check(value.roaming == phone.isNetworkRoaming)
            when (phone.dataNetworkType) {
                TelephonyManager.NETWORK_TYPE_LTE -> check(value.radioTechnology == RadioTechnology.Lte)
                TelephonyManager.NETWORK_TYPE_UMTS -> check(value.radioTechnology == RadioTechnology.Umts)
                TelephonyManager.NETWORK_TYPE_EDGE -> check(value.radioTechnology == RadioTechnology.Edge)
                TelephonyManager.NETWORK_TYPE_NR -> check(value.radioTechnology == RadioTechnology.Nr)
                TelephonyManager.NETWORK_TYPE_UNKNOWN -> check(value.radioTechnology == null)
                else -> error("Add a controlled fixture for native data RAT ${phone.dataNetworkType}.")
            }
            val activeId = if (Build.VERSION.SDK_INT >= 30) SubscriptionManager.getActiveDataSubscriptionId() else SubscriptionManager.getDefaultDataSubscriptionId()
            val current = access.cellularSubscriptions.current()
            if (activeId == subscription.subscriptionId) check(current != null && access.get(current).slotIndex == value.slotIndex)
            else check(current == null)
            val pair = withTimeout(5000) {access.withPollInterval(30.milliseconds).watch(targets.single()).take(2).toList()}
            check(pair.all {it.slotIndex == subscription.simSlotIndex})
            check(requests == 0)
            results.putInt("nativeDataNetworkType", phone.dataNetworkType)
            results.putString("cellular", serializeSnapshot(value))
            results.putBoolean("cellularNativeFieldsAndNoPermissionRequest", true)
        }
    }
}
