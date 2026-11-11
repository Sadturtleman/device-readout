package dev.devicereadout.android

import android.Manifest
import android.content.Context
import android.content.ContextWrapper
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.wifi.WifiInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Bundle
import dev.devicereadout.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds

internal object WifiContracts {
    @Suppress("DEPRECATION") // Test fixture only: the API 26 emulator does not honor shell svc wifi.
    suspend fun events(context: Context, results: Bundle, ready: (String) -> Unit) {
        val wifi = context.getSystemService(WifiManager::class.java)
        check(wifi.isWifiEnabled) {"This fixture requires initially enabled Wi-Fi."}
        try {
            AndroidDeviceAccess.create(context).use {access ->
                val original = access.current(WifiConnectionEntity) ?: error("The fixture starts on Wi-Fi.")
                var signalled = false
                val failure = withTimeout(10000) {
                    runCatching {
                        access.withPollInterval(30.seconds).watch(original).onEach {
                            if (!signalled) {
                                signalled = true
                                if (Build.VERSION.SDK_INT < 29) check(wifi.setWifiEnabled(false))
                                else ready("wifiDisconnect")
                            }
                        }.collect {}
                    }.exceptionOrNull()
                }
                check(failure is DeviceReadoutException && failure.code == ErrorCode.EntityRemoved) {"Native disconnect must end the old watch before polling: $failure"}
                if (Build.VERSION.SDK_INT < 29) check(wifi.setWifiEnabled(true))
                else ready("wifiReconnect")
                val replacement = withTimeout(10000) {
                    var target = access.current(WifiConnectionEntity)
                    while (target == null) {delay(50);target = access.current(WifiConnectionEntity)}
                    target
                }
                check(access.get(replacement).frequencyHz != null)
                val oldFailure = runCatching {access.get(original)}.exceptionOrNull()
                check(oldFailure is DeviceReadoutException && oldFailure.code == ErrorCode.EntityRemoved)
                results.putBoolean("wifiNativeRemovalAndReconnect", true)
            }
        } finally {
            if (Build.VERSION.SDK_INT < 29) check(wifi.setWifiEnabled(true))
        }
    }
    @Suppress("DEPRECATION")
    suspend fun reads(context: Context, results: Bundle) {
        val legacy = context.getSystemService(WifiManager::class.java).connectionInfo
        val connectivity = context.getSystemService(ConnectivityManager::class.java)
        fun nativeInfo(): WifiInfo = if (Build.VERSION.SDK_INT >= 29) {
            connectivity.getNetworkCapabilities(connectivity.activeNetwork)?.transportInfo as? WifiInfo ?: legacy
        } else legacy
        // NetworkCapabilities and the legacy manager update link rates independently. Use the
        // selected Network's native values as the oracle for the modern connection adapter.
        val native = nativeInfo()
        AndroidDeviceAccess.create(context).use {access ->
            var requests = 0
            access.observers.onPermissionRequest {requests++}
            val targets = access.list(WifiConnectionEntity)
            check(targets.size == 1) {"The dedicated fixture has one Wi-Fi connection."}
            val current = access.current(WifiConnectionEntity) ?: error("The fixture's default network is Wi-Fi.")
            val value = access.get(current)
            check(value.frequencyHz == native.frequency.toDouble() * 1_000_000)
            check(value.rssiDbm != null)
            check(value.bssid != "02:00:00:00:00:00" && value.ssid != WifiManager.UNKNOWN_SSID)
            val visibleSsid = legacy.ssid?.takeUnless {it == WifiManager.UNKNOWN_SSID}?.removeSurrounding("\"")
            check(value.ssid == visibleSsid) {"SSID visibility must follow the platform's granted permission state."}
            if (Build.VERSION.SDK_INT >= 31) check(value.security == WifiSecurity.Open)
            else check(value.security == null)
            if (Build.VERSION.SDK_INT >= 29) {
                val after = nativeInfo()
                val receive = setOf(native.rxLinkSpeedMbps, after.rxLinkSpeedMbps).map {it.takeIf {speed -> speed >= 0}?.times(1_000_000.0)}
                val transmit = setOf(native.txLinkSpeedMbps, after.txLinkSpeedMbps).map {it.takeIf {speed -> speed >= 0}?.times(1_000_000.0)}
                check(value.receiveLinkSpeedBps in receive) {"Rx: SDK ${value.receiveLinkSpeedBps} bit/s, native bracket $receive"}
                check(value.transmitLinkSpeedBps in transmit) {"Tx: SDK ${value.transmitLinkSpeedBps} bit/s, native bracket $transmit"}
            } else check(value.receiveLinkSpeedBps == null && value.transmitLinkSpeedBps == null)
            val pair = withTimeout(5000) {access.withPollInterval(30.milliseconds).watch(targets.single()).take(2).toList()}
            check(pair.all {it.frequencyHz != null})
            check(requests == 0) {"get/watch must not request permission or launch UI."}
            results.putBoolean("wifiSsidVisible", value.ssid != null)
            results.putBoolean("wifiBssidVisible", value.bssid != null)
            results.putBoolean("wifiNativeFieldsAndNoPermissionRequest", true)
        }
        val denied = object : ContextWrapper(context) {
            override fun getApplicationContext(): Context = this
            override fun checkSelfPermission(permission: String): Int = if (permission == Manifest.permission.ACCESS_NETWORK_STATE) PackageManager.PERMISSION_DENIED else super.checkSelfPermission(permission)
        }
        AndroidDeviceAccess.create(denied).use {access ->
            val error = runCatching {access.list(WifiConnectionEntity)}.exceptionOrNull()
            check(error is DeviceReadoutException && error.code == ErrorCode.PermissionDenied)
        }
        results.putBoolean("wifiDiscoveryPermissionFailureTyped", true)
    }
}
