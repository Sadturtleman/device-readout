package dev.devicereadout.android

import android.Manifest
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.VpnService
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Bundle
import dev.devicereadout.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.onEach
import java.net.NetworkInterface
import kotlin.time.Duration.Companion.seconds

internal object NetworkContracts {
    suspend fun reads(context: Context, results: Bundle) {
        val manager = context.getSystemService(ConnectivityManager::class.java)
        val active = manager.activeNetwork ?: error("The dedicated emulator fixture must be connected.")
        val native = manager.getNetworkCapabilities(active) ?: error("Native capabilities unavailable.")
        AndroidDeviceAccess.create(context).use { access ->
            val path = access.get(NetworkPathEntity)
            check(path.connectionState == ConnectionState.Connected)
            check(path.transports?.isNotEmpty() == true)
            if (native.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) check(path.transports!!.contains(NetworkTransport.Wifi))
            check(path.metered == !native.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED))
            check(path.internetValidated == native.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED))
            check(path.captivePortal == native.hasCapability(NetworkCapabilities.NET_CAPABILITY_CAPTIVE_PORTAL))
            check(path.expensive == null && path.constrained == null)
            val performance = access.get(NetworkPerformanceEntity)
            check(performance.downlinkBps == native.linkDownstreamBandwidthKbps.toDouble() * 1000)
            check(performance.uplinkBps == native.linkUpstreamBandwidthKbps.toDouble() * 1000)
            check(performance.roundTripTime == null && performance.effectiveType == null && performance.browserOnline == null)
            results.putString("networkPath", serializeSnapshot(path))
            results.putString("networkPerformance", serializeSnapshot(performance))

            val targets = access.networkInterfaces.list()
            check(targets.isNotEmpty())
            for (target in targets) {
                val value = access.get(target)
                val source = NetworkInterface.getByName(value.name) ?: error("Discovered interface disappeared in stable fixture.")
                check(value.mtuBytes == source.mtu.toULong())
                val expectedAddresses = source.interfaceAddresses.map {IpAddressInfo(it.address.hostAddress!!, it.networkPrefixLength.toInt())}
                check(value.ipAddresses?.toSet() == expectedAddresses.toSet())
                check(value.hardwareAddress != "02:00:00:00:00:00") {"Android's redacted MAC sentinel must be null."}
                if (source.isLoopback) check(value.interfaceType == NetworkInterfaceType.Loopback)
            }
            val current = access.networkInterfaces.current() ?: error("The connected emulator has a current interface.")
            val currentSnapshot = access.get(current)
            val links = manager.getLinkProperties(active)!!
            check(currentSnapshot.name == links.interfaceName)
            check(currentSnapshot.dnsServers?.toSet() == links.dnsServers.map {it.hostAddress!!}.toSet())
            check(currentSnapshot.routes != null)
            results.putInt("networkInterfaceTargetsVerified", targets.size)
        }
        val deniedContext = object : ContextWrapper(context) {
            override fun getApplicationContext(): Context = this
            override fun checkSelfPermission(permission: String): Int = if (permission in listOf(Manifest.permission.ACCESS_NETWORK_STATE, Manifest.permission.INTERNET)) PackageManager.PERMISSION_DENIED else super.checkSelfPermission(permission)
        }
        AndroidDeviceAccess.create(deniedContext).use { access ->
            for (kind in listOf(NetworkPathEntity, NetworkPerformanceEntity)) {
                val error = runCatching {access.get(kind)}.exceptionOrNull()
                check(error is DeviceReadoutException && error.code == ErrorCode.PermissionDenied)
            }
            val discoveryError = runCatching {access.networkInterfaces.list()}.exceptionOrNull()
            check(discoveryError is DeviceReadoutException && discoveryError.code == ErrorCode.PermissionDenied) {"Interface discovery must distinguish missing permission from an empty inventory."}
        }
        results.putBoolean("networkPermissionFailureTyped", true)
    }

    @Suppress("DEPRECATION") // The isolated API 26 test APK uses its own authorized Wi-Fi control, never SDK code.
    suspend fun events(context: Context, results: Bundle, ready: () -> Unit) {
        val wifi = if (Build.VERSION.SDK_INT < 29) context.getSystemService(WifiManager::class.java) else null
        val originalWifi = wifi?.isWifiEnabled
        var requested = false
        try {
        AndroidDeviceAccess.create(context).use { access ->
            var wasConnected = false
            var count = 0
            val value = withTimeout(10000) {
                access.withPollInterval(30.seconds).watch(NetworkPathEntity).onEach {
                    results.putInt("networkEventSnapshotCount", ++count)
                    results.putString("lastObservedNetwork", serializeSnapshot(it))
                    if (it.connectionState == ConnectionState.Connected) {
                        wasConnected = true
                        if (!requested) {
                            requested = true;ready()
                            if (wifi != null) results.putBoolean("fixtureWifiDisableAccepted", wifi.setWifiEnabled(false))
                        }
                    }
                }.first {wasConnected && it.connectionState == ConnectionState.Disconnected}
            }
            check(value.transports == emptySet<NetworkTransport>())
            check(value.metered == null && value.internetValidated == false)
            val performance = access.get(NetworkPerformanceEntity)
            check(performance.downlinkBps == null && performance.uplinkBps == null)
            results.putBoolean("networkDisconnectNativeEvent", true)
        }
        } finally {
            results.putBoolean("nativeHasActiveNetworkAtEnd", context.getSystemService(ConnectivityManager::class.java).activeNetwork != null)
            if (requested && wifi != null && originalWifi != null) wifi.setWifiEnabled(originalWifi)
        }
    }

    suspend fun interfaceHotplug(context: Context, results: Bundle) {
        check(VpnService.prepare(context) == null) {"Only the project test APK may be authorized for this fixture."}
        InterfaceFixtureService.ready = CompletableDeferred()
        val serviceIntent = Intent(context, InterfaceFixtureService::class.java)
        withContext(Dispatchers.Main) {context.startService(serviceIntent)}
        try {
            val service = withTimeout(5000) {InterfaceFixtureService.ready.await()}
            AndroidDeviceAccess.create(context).use { access ->
                suspend fun discover(): Entity<NetworkInterfaceSnapshot> = withTimeout(5000) {
                    var match: Entity<NetworkInterfaceSnapshot>? = null
                    while (match == null) {
                        match = access.networkInterfaces.list().firstOrNull {target ->
                            access.get(target).ipAddresses?.any {it.address == "192.0.2.1"} == true
                        }
                        if (match == null) delay(25)
                    }
                    match
                }
                service.createInterface().use { tunnel ->
                    val original = discover()
                    val initial = access.get(original)
                    check(initial.mtuBytes == 1400uL)
                    withTimeout(5000) {
                        while (access.get(original).interfaceType != NetworkInterfaceType.Tunnel) delay(25)
                    }
                    withTimeout(5000) {
                        val started = CompletableDeferred<Unit>()
                        val ended = async {
                            runCatching {access.withPollInterval(30.seconds).watch(original).onEach {started.complete(Unit)}.collect {}}
                                .exceptionOrNull()
                        }
                        started.await();tunnel.close()
                        val error = ended.await()
                        check(error is DeviceReadoutException && error.code == ErrorCode.EntityRemoved) {"Removal must terminate the original watch with EntityRemoved: $error"}
                    }
                    service.createInterface().use {
                        val replacement = discover()
                        check(access.get(replacement).mtuBytes == 1400uL)
                        val oldError = runCatching {access.get(original)}.exceptionOrNull()
                        check(oldError is DeviceReadoutException && oldError.code == ErrorCode.EntityRemoved) {"An old target must never bind to the replacement interface."}
                    }
                }
                results.putBoolean("realInterfaceRemovalAndReplacement", true)
            }
        } finally {withContext(NonCancellable + Dispatchers.Main) {context.stopService(serviceIntent)}}
    }
}
