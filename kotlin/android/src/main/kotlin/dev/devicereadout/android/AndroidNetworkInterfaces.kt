package dev.devicereadout.android

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import dev.devicereadout.*
import java.io.File
import java.net.NetworkInterface
import java.util.Collections
import java.util.concurrent.atomic.AtomicBoolean

internal class AndroidNetworkInterfaces(private val context: Context) {
    private data class Key(val name: String, val index: Int)
    private data class Target(val id: String, val key: Key, var removed: Boolean = false)
    private data class Configuration(val links: LinkProperties, val capabilities: NetworkCapabilities?)
    private val gate = Any()
    private val targets = LinkedHashMap<String, Target>()
    private val byKey = HashMap<Key, Target>()
    private var sequence = 0L
    private fun inventory(): List<Target> = synchronized(gate) {
        // Android's native interface enumeration can otherwise return an empty result without this
        // socket permission. Reading the inventory does not open an Internet connection.
        if (context.checkSelfPermission(Manifest.permission.INTERNET) != PackageManager.PERMISSION_GRANTED)
            throw DeviceReadoutException(ErrorCode.PermissionDenied, "The host app must declare INTERNET for native interface enumeration.")
        val interfaces = NetworkInterface.getNetworkInterfaces()?.let(Collections::list).orEmpty()
        val available = interfaces.map {Key(it.name, it.index)}
        targets.values.filter {it.key !in available}.forEach {it.removed = true}
        available.map {key ->
            byKey[key]?.takeUnless {it.removed} ?: Target("interface-${++sequence}", key).also {targets[it.id] = it;byKey[key] = it}
        }
    }
    fun list(): List<String> = inventory().map {it.id}
    private fun resolve(id: String?): Pair<Target, NetworkInterface> {
        inventory()
        val target = synchronized(gate) {targets[id]?.takeUnless {it.removed}}
            ?: throw DeviceReadoutException(ErrorCode.EntityRemoved, "The network interface target was removed.")
        val native = NetworkInterface.getByName(target.key.name)?.takeIf {it.index == target.key.index}
        if (native == null) {
            synchronized(gate) {target.removed = true}
            throw DeviceReadoutException(ErrorCode.EntityRemoved, "The network interface was removed.")
        }
        return target to native
    }
    @SuppressLint("MissingPermission")
    fun current(): String? {
        requireNetworkPermission(context)
        val manager = context.getSystemService(ConnectivityManager::class.java) ?: return null
        val network = manager.activeNetwork ?: return null
        val name = manager.getLinkProperties(network)?.interfaceName ?: return null
        return inventory().singleOrNull {it.key.name == name}?.id
    }
    @SuppressLint("MissingPermission")
    @Suppress("DEPRECATION") // One-shot inventory; ongoing updates use NetworkCallback and its supplied values.
    private fun configurations(): List<Configuration>? {
        if (context.checkSelfPermission(Manifest.permission.ACCESS_NETWORK_STATE) != PackageManager.PERMISSION_GRANTED) return null
        val manager = context.getSystemService(ConnectivityManager::class.java) ?: return null
        return manager.allNetworks.mapNotNull {network -> manager.getLinkProperties(network)?.let {Configuration(it, manager.getNetworkCapabilities(network))}}
    }
    fun read(id: String?): NetworkInterfaceSnapshot = read(id, attempt {configurations()})
    private fun read(id: String?, configurations: List<Configuration>?): NetworkInterfaceSnapshot {
        val (_, native) = resolve(id)
        val matches = configurations?.filter {it.links.interfaceName == native.name}?.takeIf {it.isNotEmpty()}
        val links = matches?.map {it.links}
        val types = matches?.map {it.capabilities?.let(::networkTransports)}
        val transports = if (types == null || types.any {it == null}) null else types.filterNotNull().flatten().toSet()
        return NetworkInterfaceSnapshot(
            name = native.name,
            interfaceType = when {
                attempt {native.isLoopback} == true -> NetworkInterfaceType.Loopback
                transports == null -> null
                NetworkTransport.Vpn in transports -> NetworkInterfaceType.Tunnel
                else -> when (transports.singleOrNull()) {
                    NetworkTransport.Wifi -> NetworkInterfaceType.Wifi
                    NetworkTransport.Cellular -> NetworkInterfaceType.Cellular
                    NetworkTransport.Ethernet -> NetworkInterfaceType.Ethernet
                    NetworkTransport.Bluetooth -> NetworkInterfaceType.Bluetooth
                    else -> null
                }
            },
            operationalState = attempt {operationalState(native)},
            hardwareAddress = attempt {native.hardwareAddress?.takeIf {it.isNotEmpty()}?.joinToString(":") {byte -> "%02X".format(byte.toInt() and 255)}
                ?.takeUnless {it == "02:00:00:00:00:00" || it == "00:00:00:00:00:00"}},
            ipAddresses = attempt {native.interfaceAddresses.map {IpAddressInfo(it.address.hostAddress!!, it.networkPrefixLength.toInt().takeIf {prefix -> prefix >= 0})}},
            dnsServers = links?.flatMap {it.dnsServers.mapNotNull {address -> address.hostAddress}}?.distinct(),
            gateways = links?.flatMap {it.routes.mapNotNull {route -> route.gateway?.takeUnless {gateway -> gateway.isAnyLocalAddress}?.hostAddress}}?.distinct(),
            routes = links?.flatMap {it.routes.map {route -> NetworkRoute(route.destination.address.hostAddress!!, route.destination.prefixLength, route.gateway?.takeUnless {gateway -> gateway.isAnyLocalAddress}?.hostAddress)}}?.distinct(),
            mtuBytes = attempt {native.mtu.takeIf {it > 0}?.toULong()},
        )
    }
    private fun operationalState(native: NetworkInterface): NetworkOperationalState? {
        if (!native.name.matches(Regex("[a-zA-Z0-9_.:-]+"))) return null
        val state = attempt {File("/sys/class/net/${native.name}/operstate").bufferedReader().use {it.readLine()}}
        return when (state) {
            "up" -> NetworkOperationalState.Up; "down" -> NetworkOperationalState.Down
            "testing" -> NetworkOperationalState.Testing; "dormant" -> NetworkOperationalState.Dormant
            "notpresent" -> NetworkOperationalState.NotPresent; "lowerlayerdown" -> NetworkOperationalState.LowerLayerDown
            else -> null
        }
    }
    @SuppressLint("MissingPermission")
    fun observeChanges(id: String?, changed: () -> Unit, fail: (Throwable) -> Unit): CollectorSubscription? {
        resolve(id)
        if (context.checkSelfPermission(Manifest.permission.ACCESS_NETWORK_STATE) != PackageManager.PERMISSION_GRANTED) return null
        val manager = context.getSystemService(ConnectivityManager::class.java) ?: return null
        val lane = CallbackLane("DeviceReadout interfaces", fail)
        val closed = AtomicBoolean()
        fun refresh() {if (!closed.get()) lane.deliver(changed)}
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onCapabilitiesChanged(network: Network, value: NetworkCapabilities) = refresh()
            override fun onLinkPropertiesChanged(network: Network, value: LinkProperties) = refresh()
            override fun onLost(network: Network) = refresh()
        }
        try {
            val request = NetworkRequest.Builder().apply {
                if (Build.VERSION.SDK_INT >= 30) clearCapabilities()
                else {
                    removeCapability(NetworkCapabilities.NET_CAPABILITY_NOT_RESTRICTED)
                    removeCapability(NetworkCapabilities.NET_CAPABILITY_TRUSTED)
                    removeCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
                }
            }.build()
            manager.registerNetworkCallback(request, callback, lane.handler)
            return object : CollectorSubscription {
                // Some interfaces (loopback, local/unmanaged interfaces) have no ConnectivityManager events.
                override val pollingRequired = true
                override fun close() {
                    if (!closed.compareAndSet(false, true)) return
                    try {manager.unregisterNetworkCallback(callback)} finally {lane.close()}
                }
            }
        } catch (error: Throwable) {lane.close();throw error}
    }
}
private inline fun <T> attempt(read: () -> T): T? = try {read()} catch (_: Exception) {null}
