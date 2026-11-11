package dev.devicereadout.android

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiInfo
import android.net.wifi.WifiManager
import android.os.Build
import dev.devicereadout.*
import java.util.Locale
import java.util.concurrent.CompletableFuture
import java.util.concurrent.ExecutionException
import java.util.concurrent.atomic.AtomicBoolean

@SuppressLint("MissingPermission") // Network permission checked here; OS redacts fields independently. Never requests permission.
internal class AndroidWifi(private val context: Context) {
    private data class Target(val id: String, val network: Network, var removed: Boolean = false)
    private val gate = Any()
    private val targets = LinkedHashMap<String, Target>()
    private val byNetwork = HashMap<Network, Target>()
    private var sequence = 0L
    private fun manager(): ConnectivityManager {
        requireNetworkPermission(context)
        return context.getSystemService(ConnectivityManager::class.java)
            ?: throw DeviceReadoutException(ErrorCode.UnsupportedEntity, "ConnectivityManager is unavailable.")
    }
    @Suppress("DEPRECATION") // One-shot network discovery; observations use native callbacks.
    private fun inventory(): List<Target> {
        val manager = manager()
        val networks = manager.allNetworks.associateWith(manager::getNetworkCapabilities)
        return synchronized(gate) {
            targets.values.filter {it.network !in networks || networks[it.network]?.let {caps -> !wifi(caps)} == true}.forEach {it.removed = true}
            networks.mapNotNull {(network, capabilities) ->
                if (capabilities == null) byNetwork[network]?.takeUnless {it.removed}
                else if (!wifi(capabilities)) null
                else byNetwork[network]?.takeUnless {it.removed} ?: Target("wifi-${++sequence}", network).also {targets[it.id] = it;byNetwork[network] = it}
            }
        }
    }
    fun list(): List<String> = inventory().map {it.id}
    fun current(): String? {
        val active = manager().activeNetwork ?: return null
        return inventory().singleOrNull {it.network == active}?.id
    }
    private fun resolve(id: String?): Target {
        inventory()
        return synchronized(gate) {targets[id]?.takeUnless {it.removed}}
            ?: throw removed()
    }
    private fun ensurePresent(target: Target) {synchronized(gate) {if (target.removed) throw removed()}}
    private fun retire(target: Target) {synchronized(gate) {target.removed = true}}
    fun read(id: String?): WifiConnectionSnapshot {
        val target = resolve(id)
        val info = when {
            Build.VERSION.SDK_INT >= 31 -> freshInfo(target)
            Build.VERSION.SDK_INT >= 29 -> manager().getNetworkCapabilities(target.network)?.transportInfo as? WifiInfo ?: legacyInfo(target)
            else -> legacyInfo(target)
        }
        ensurePresent(target)
        return snapshot(info)
    }
    @Suppress("DEPRECATION")
    private fun legacyInfo(target: Target): WifiInfo? {
        // The legacy API cannot select a Network. Use it only for an unambiguous sole connection.
        if (inventory().singleOrNull()?.network != target.network) return null
        if (context.checkSelfPermission(Manifest.permission.ACCESS_WIFI_STATE) != PackageManager.PERMISSION_GRANTED)
            throw DeviceReadoutException(ErrorCode.PermissionDenied, "The host must declare ACCESS_WIFI_STATE for legacy Wi-Fi information.")
        return context.getSystemService(WifiManager::class.java)?.connectionInfo
    }
    @android.annotation.TargetApi(31) // Called only from the API 31+ branch in read().
    private fun freshInfo(target: Target): WifiInfo? {
        val manager = manager()
        val result = CompletableFuture<WifiInfo?>()
        val lane = CallbackLane("DeviceReadout Wi-Fi read") {result.completeExceptionally(it)}
        val callback = callback({network, value ->
            if (network == target.network) result.complete(value.transportInfo as? WifiInfo)
        }, {network ->
            if (network == target.network) {retire(target);result.completeExceptionally(removed())}
        })
        var registered = false
        try {
            manager.registerNetworkCallback(request(), callback, lane.handler);registered = true
            // The collection worker is interruptible; get's deadline/cancellation releases this callback.
            return try {result.get()} catch (error: ExecutionException) {throw error.cause ?: error}
        } finally {
            try {if (registered) manager.unregisterNetworkCallback(callback)} finally {lane.close()}
        }
    }
    fun observeReads(id: String?, emit: (() -> DeviceSnapshot) -> Unit, fail: (Throwable) -> Unit): CollectorSubscription {
        val target = resolve(id)
        val manager = manager()
        val lane = CallbackLane("DeviceReadout Wi-Fi", fail)
        val closed = AtomicBoolean()
        val callback = callback({network, value ->
            if (network == target.network && !closed.get()) lane.deliver {
                val info = if (Build.VERSION.SDK_INT >= 29) value.transportInfo as? WifiInfo else null
                if (info != null) emit {ensurePresent(target);snapshot(info)}
                else emit {read(id)}
            }
        }, {network ->
            if (network == target.network && !closed.get()) {retire(target);fail(removed())}
        })
        try {manager.registerNetworkCallback(request(), callback, lane.handler)}
        catch (error: Throwable) {lane.close();throw error}
        return object : CollectorSubscription {
            override val pollingRequired = true // Link speed/RSSI changes are not guaranteed to notify every change.
            override fun close() {
                if (!closed.compareAndSet(false, true)) return
                try {manager.unregisterNetworkCallback(callback)} finally {lane.close()}
            }
        }
    }
    private fun callback(changed: (Network, NetworkCapabilities) -> Unit, lost: (Network) -> Unit): ConnectivityManager.NetworkCallback =
        if (Build.VERSION.SDK_INT >= 31) object : ConnectivityManager.NetworkCallback(ConnectivityManager.NetworkCallback.FLAG_INCLUDE_LOCATION_INFO) {
            override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) = changed(network, capabilities)
            override fun onLost(network: Network) = lost(network)
        } else object : ConnectivityManager.NetworkCallback() {
            override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) = changed(network, capabilities)
            override fun onLost(network: Network) = lost(network)
        }
    private fun request(): NetworkRequest = NetworkRequest.Builder().apply {
        if (Build.VERSION.SDK_INT >= 30) clearCapabilities() else {
            removeCapability(NetworkCapabilities.NET_CAPABILITY_TRUSTED)
            removeCapability(NetworkCapabilities.NET_CAPABILITY_NOT_RESTRICTED)
            removeCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
        }
        addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
    }.build()
    private fun wifi(capabilities: NetworkCapabilities): Boolean = capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) && !capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
    @SuppressLint("HardwareIds", "InlinedApi") // Explicit fields only; UNKNOWN_SSID's inlined redaction marker also applies before API 30.
    private fun snapshot(info: WifiInfo?): WifiConnectionSnapshot {
        if (info == null) return WifiConnectionSnapshot()
        return WifiConnectionSnapshot(
            ssid = info.ssid?.takeUnless {it == WifiManager.UNKNOWN_SSID}?.removeSurrounding("\""),
            bssid = info.bssid?.uppercase(Locale.ROOT)?.takeUnless {it == "02:00:00:00:00:00" || it == "00:00:00:00:00:00"},
            security = if (Build.VERSION.SDK_INT >= 31) security(info.currentSecurityType) else null,
            rssiDbm = info.rssi.takeUnless {it == -127}?.toDouble(),
            frequencyHz = info.frequency.takeIf {it >= 0}?.times(1_000_000.0),
            receiveLinkSpeedBps = if (Build.VERSION.SDK_INT >= 29) info.rxLinkSpeedMbps.takeIf {it >= 0}?.times(1_000_000.0) else null,
            transmitLinkSpeedBps = if (Build.VERSION.SDK_INT >= 29) info.txLinkSpeedMbps.takeIf {it >= 0}?.times(1_000_000.0) else null,
        )
    }
    private fun security(value: Int): WifiSecurity? = when (value) {
        WifiInfo.SECURITY_TYPE_OPEN -> WifiSecurity.Open
        WifiInfo.SECURITY_TYPE_WEP -> WifiSecurity.Wep
        WifiInfo.SECURITY_TYPE_PSK -> WifiSecurity.Psk
        WifiInfo.SECURITY_TYPE_EAP -> WifiSecurity.Eap
        WifiInfo.SECURITY_TYPE_SAE -> WifiSecurity.Sae
        WifiInfo.SECURITY_TYPE_OWE -> WifiSecurity.Owe
        WifiInfo.SECURITY_TYPE_WAPI_PSK -> WifiSecurity.WapiPsk
        WifiInfo.SECURITY_TYPE_WAPI_CERT -> WifiSecurity.WapiCert
        WifiInfo.SECURITY_TYPE_EAP_WPA3_ENTERPRISE -> WifiSecurity.EapWpa3Enterprise
        WifiInfo.SECURITY_TYPE_EAP_WPA3_ENTERPRISE_192_BIT -> WifiSecurity.EapWpa3Enterprise192Bit
        WifiInfo.SECURITY_TYPE_PASSPOINT_R1_R2 -> WifiSecurity.PasspointR1R2
        WifiInfo.SECURITY_TYPE_PASSPOINT_R3 -> WifiSecurity.PasspointR3
        WifiInfo.SECURITY_TYPE_DPP -> WifiSecurity.Dpp
        else -> null
    }
    private fun removed() = DeviceReadoutException(ErrorCode.EntityRemoved, "The Wi-Fi connection target was removed.")
}
