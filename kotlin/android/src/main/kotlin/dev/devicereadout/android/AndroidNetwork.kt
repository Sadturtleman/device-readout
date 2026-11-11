package dev.devicereadout.android

import android.Manifest
import android.annotation.SuppressLint
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Build
import dev.devicereadout.*
import java.net.Inet4Address
import java.net.Inet6Address
import java.util.concurrent.atomic.AtomicBoolean

internal class AndroidNetwork(private val context: Context) {
    private fun manager(): ConnectivityManager {
        requireNetworkPermission(context)
        return context.getSystemService(ConnectivityManager::class.java)
            ?: throw DeviceReadoutException(ErrorCode.UnsupportedEntity, "ConnectivityManager is unavailable.")
    }
    @SuppressLint("MissingPermission") // Checked at this adapter boundary; never requests permission.
    fun read(kind: EntityKind): DeviceSnapshot {
        val manager = manager()
        val network = manager.activeNetwork
        val capabilities = network?.let(manager::getNetworkCapabilities)
        val links = network?.let(manager::getLinkProperties)
        return snapshot(kind, network != null, capabilities, links, dataSaver(manager))
    }
    @SuppressLint("MissingPermission")
    fun observeReads(kind: EntityKind, emit: (() -> DeviceSnapshot) -> Unit, fail: (Throwable) -> Unit): CollectorSubscription {
        val manager = manager()
        val lane = CallbackLane("DeviceReadout network", fail)
        val closed = AtomicBoolean()
        // These variables belong exclusively to the callback lane. Capture each event's payload:
        // querying ConnectivityManager after onLost can still return the previous default network.
        var current: Network? = null
        var capabilities: NetworkCapabilities? = null
        var links: LinkProperties? = null
        fun refresh() {
            if (closed.get()) return
            val connected = current != null
            val capturedCapabilities = capabilities
            val capturedLinks = links
            lane.deliver {emit {snapshot(kind, connected, capturedCapabilities, capturedLinks, dataSaver(manager))}}
        }
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                current = network;capabilities = null;links = null;refresh()
            }
            override fun onCapabilitiesChanged(network: Network, value: NetworkCapabilities) {
                if (network == current) {capabilities = NetworkCapabilities(value);refresh()}
            }
            override fun onLinkPropertiesChanged(network: Network, value: LinkProperties) {
                if (network == current) {links = value;refresh()}
            }
            override fun onLost(network: Network) {
                if (network == current) {current = null;capabilities = null;links = null;refresh()}
            }
        }
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) = refresh()
        }
        var registered = false
        var receiverRegistered = false
        try {
            manager.registerDefaultNetworkCallback(callback, lane.handler);registered = true
            val filter = IntentFilter(ConnectivityManager.ACTION_RESTRICT_BACKGROUND_CHANGED)
            if (Build.VERSION.SDK_INT >= 33) context.registerReceiver(receiver, filter, null, lane.handler, Context.RECEIVER_NOT_EXPORTED)
            else context.registerReceiver(receiver, filter, null, lane.handler)
            receiverRegistered = true
            return object : CollectorSubscription {
                override val pollingRequired = false
                override fun close() {
                    if (!closed.compareAndSet(false, true)) return
                    try {manager.unregisterNetworkCallback(callback)} finally {
                        try {context.unregisterReceiver(receiver)} finally {lane.close()}
                    }
                }
            }
        } catch (error: Throwable) {
            if (registered) attempt {manager.unregisterNetworkCallback(callback)}
            if (receiverRegistered) attempt {context.unregisterReceiver(receiver)}
            lane.close();throw error
        }
    }
    private fun snapshot(kind: EntityKind, connected: Boolean, capabilities: NetworkCapabilities?, links: LinkProperties?, saver: Boolean?): DeviceSnapshot {
        if (kind == EntityKind.NetworkPerformance) return NetworkPerformanceSnapshot(
            downlinkBps = capabilities?.linkDownstreamBandwidthKbps?.takeIf {it >= 0}?.times(1000.0),
            uplinkBps = capabilities?.linkUpstreamBandwidthKbps?.takeIf {it >= 0}?.times(1000.0),
        )
        return NetworkPathSnapshot(
            connectionState = when {
                !connected -> ConnectionState.Disconnected
                Build.VERSION.SDK_INT >= 28 && capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_SUSPENDED) == false -> ConnectionState.Suspended
                else -> ConnectionState.Connected
            },
            transports = if (connected) capabilities?.let(::networkTransports) else emptySet(),
            metered = capabilities?.let {!it.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)},
            saveData = saver,
            supportsIpv4 = if (connected) links?.linkAddresses?.any {it.address is Inet4Address} else false,
            supportsIpv6 = if (connected) links?.linkAddresses?.any {it.address is Inet6Address} else false,
            supportsDns = if (connected) links?.dnsServers?.isNotEmpty() else false,
            internetValidated = if (connected) capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) else false,
            captivePortal = if (connected) capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_CAPTIVE_PORTAL) else false,
        )
    }
    private fun dataSaver(manager: ConnectivityManager): Boolean? = when (manager.restrictBackgroundStatus) {
        ConnectivityManager.RESTRICT_BACKGROUND_STATUS_DISABLED -> false
        ConnectivityManager.RESTRICT_BACKGROUND_STATUS_ENABLED, ConnectivityManager.RESTRICT_BACKGROUND_STATUS_WHITELISTED -> true
        else -> null
    }
}

internal fun requireNetworkPermission(context: Context) {
    if (context.checkSelfPermission(Manifest.permission.ACCESS_NETWORK_STATE) != PackageManager.PERMISSION_GRANTED)
        throw DeviceReadoutException(ErrorCode.PermissionDenied, "The host app must declare ACCESS_NETWORK_STATE.")
}

@SuppressLint("WrongConstant") // Public hasTransport validates bit positions; inspect all bits, including SDK-unknown transports.
internal fun networkTransports(value: NetworkCapabilities): Set<NetworkTransport>? {
    val result = LinkedHashSet<NetworkTransport>()
    // Android represents this set as a 64-bit mask. No hidden API/reflection or toString parsing.
    for (type in 0 until java.lang.Long.SIZE) {
        if (!value.hasTransport(type)) continue
        result += when (type) {
            NetworkCapabilities.TRANSPORT_CELLULAR -> NetworkTransport.Cellular
            NetworkCapabilities.TRANSPORT_WIFI -> NetworkTransport.Wifi
            NetworkCapabilities.TRANSPORT_BLUETOOTH -> NetworkTransport.Bluetooth
            NetworkCapabilities.TRANSPORT_ETHERNET -> NetworkTransport.Ethernet
            NetworkCapabilities.TRANSPORT_VPN -> NetworkTransport.Vpn
            NetworkCapabilities.TRANSPORT_WIFI_AWARE -> NetworkTransport.WifiAware
            NetworkCapabilities.TRANSPORT_LOWPAN -> NetworkTransport.Lowpan
            NetworkCapabilities.TRANSPORT_USB -> NetworkTransport.Usb
            NetworkCapabilities.TRANSPORT_THREAD -> NetworkTransport.Thread
            NetworkCapabilities.TRANSPORT_SATELLITE -> NetworkTransport.Satellite
            else -> return null
        }
    }
    return result
}
private inline fun <T> attempt(read: () -> T): T? = try {read()} catch (_: Exception) {null}
