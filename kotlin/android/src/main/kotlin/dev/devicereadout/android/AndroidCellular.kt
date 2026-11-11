package dev.devicereadout.android

import android.Manifest
import android.app.AppOpsManager
import android.annotation.SuppressLint
import android.annotation.TargetApi
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Process
import android.telephony.PhoneStateListener
import android.telephony.ServiceState
import android.telephony.SubscriptionInfo
import android.telephony.SubscriptionManager
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager
import dev.devicereadout.*
import java.util.concurrent.CompletableFuture
import java.util.concurrent.ExecutionException
import java.util.concurrent.Executor
import java.util.concurrent.atomic.AtomicBoolean

@SuppressLint("MissingPermission") // The OS accepts READ_PHONE_STATE or carrier privileges; SecurityException is typed by the runtime.
internal class AndroidCellular(private val context: Context) {
    private data class Target(val id: String, val subscriptionId: Int, var info: SubscriptionInfo, var removed: Boolean = false)
    private val gate = Any()
    private val targets = LinkedHashMap<String, Target>()
    private val bySubscription = HashMap<Int, Target>()
    private var sequence = 0L
    private fun manager(): SubscriptionManager = context.getSystemService(SubscriptionManager::class.java)
        ?: throw DeviceReadoutException(ErrorCode.UnsupportedEntity, "SubscriptionManager is unavailable.")
    private fun phone(subscriptionId: Int): TelephonyManager = (context.getSystemService(TelephonyManager::class.java)
        ?: throw DeviceReadoutException(ErrorCode.UnsupportedEntity, "TelephonyManager is unavailable.")).createForSubscriptionId(subscriptionId)
    private fun inventory(): List<Target> {
        val manager = manager()
        val records = platform {manager.activeSubscriptionInfoList.orEmpty()}
        // The list API can silently filter denied access to empty. Newer count implementations
        // enforce access; older ones also return zero for a denied app-op.
        if (records.isEmpty()) {
            platform {manager.activeSubscriptionInfoCount}
            requireEmptyInventoryAccess()
        }
        return synchronized(gate) {
            val ids = records.map {it.subscriptionId}.toSet()
            targets.values.filter {it.subscriptionId !in ids}.forEach {it.removed = true}
            records.map {info ->
                bySubscription[info.subscriptionId]?.takeUnless {it.removed}?.also {it.info = info}
                    ?: Target("subscription-${++sequence}", info.subscriptionId, info).also {targets[it.id] = it;bySubscription[it.subscriptionId] = it}
            }
        }
    }
    @Suppress("DEPRECATION") // checkOpNoThrow supports the API 26 baseline and does not request access.
    private fun requireEmptyInventoryAccess() {
        if (context.checkSelfPermission(PRIVILEGED_PHONE_STATE_PERMISSION) == PackageManager.PERMISSION_GRANTED ||
            optional {context.getSystemService(TelephonyManager::class.java)?.hasCarrierPrivileges()} == true) return
        val granted = context.checkSelfPermission(Manifest.permission.READ_PHONE_STATE) == PackageManager.PERMISSION_GRANTED
        val packageName = if (Build.VERSION.SDK_INT >= 29) context.opPackageName else context.packageName
        val mode = context.getSystemService(AppOpsManager::class.java)?.checkOpNoThrow(AppOpsManager.OPSTR_READ_PHONE_STATE, Process.myUid(), packageName)
        if (!granted || mode == AppOpsManager.MODE_IGNORED || mode == AppOpsManager.MODE_ERRORED)
            throw DeviceReadoutException(ErrorCode.PermissionDenied, "Subscription discovery is not authorized.")
    }
    fun list(): List<String> = inventory().map {it.id}
    fun current(): String? {
        val available = inventory()
        val active = if (Build.VERSION.SDK_INT >= 30) SubscriptionManager.getActiveDataSubscriptionId() else SubscriptionManager.getDefaultDataSubscriptionId()
        return available.singleOrNull {it.subscriptionId == active}?.id
    }
    private fun resolve(id: String?): SubscriptionInfo {
        inventory()
        return synchronized(gate) {targets[id]?.takeUnless {it.removed}?.info}
            ?: throw DeviceReadoutException(ErrorCode.EntityRemoved, "The cellular subscription target was removed.")
    }
    fun read(id: String?): CellularSubscriptionSnapshot = read(id, null, null)
    private fun read(id: String?, dataType: Int?, roaming: Boolean?): CellularSubscriptionSnapshot {
        val info = resolve(id)
        val phone = phone(info.subscriptionId)
        val operator = optional {phone.simOperator.takeIf {it.matches(Regex("[0-9]{5,6}"))}}
        val mcc = if (Build.VERSION.SDK_INT >= 29) code(info.mccString, 3..3) else null
        val mnc = if (Build.VERSION.SDK_INT >= 29) code(info.mncString, 2..3) else null
        return CellularSubscriptionSnapshot(
            slotIndex = info.simSlotIndex.takeIf {it >= 0},
            carrierName = info.carrierName?.toString()?.takeIf {it.isNotBlank()},
            countryCode = info.countryIso?.takeIf {it.isNotBlank()},
            mobileCountryCode = mcc ?: operator?.substring(0, 3),
            mobileNetworkCode = mnc ?: operator?.substring(3),
            radioTechnology = (dataType ?: optional {phone.dataNetworkType})?.let(::radio),
            roaming = roaming ?: optional {phone.isNetworkRoaming},
        )
    }
    @Suppress("DEPRECATION") // API 26–30 needs a Looper-owned PhoneStateListener; newer APIs use TelephonyCallback.
    fun observeReads(id: String?, emit: (() -> DeviceSnapshot) -> Unit, fail: (Throwable) -> Unit): CollectorSubscription {
        val info = resolve(id)
        val phone = phone(info.subscriptionId)
        val manager = manager()
        val lane = CallbackLane("DeviceReadout cellular", fail)
        val closed = AtomicBoolean()
        var subscriptionListener: SubscriptionManager.OnSubscriptionsChangedListener? = null
        var subscriptionRegistered = false
        var closePhone: (() -> Unit)? = null
        fun changed(dataType: Int? = null, roaming: Boolean? = null) {
            if (!closed.get()) lane.deliver {emit {read(id, dataType, roaming)}}
        }
        fun release() {
            if (!closed.compareAndSet(false, true)) return
            try {closePhone?.invoke()} finally {
                try {if (subscriptionRegistered) manager.removeOnSubscriptionsChangedListener(subscriptionListener!!)} finally {lane.close()}
            }
        }
        try {
            subscriptionListener = onLane(lane) {object : SubscriptionManager.OnSubscriptionsChangedListener() {
                override fun onSubscriptionsChanged() = changed()
            }}
            val executor = Executor {task -> lane.post {task.run()}}
            if (Build.VERSION.SDK_INT >= 30) manager.addOnSubscriptionsChangedListener(executor, subscriptionListener)
            else manager.addOnSubscriptionsChangedListener(subscriptionListener)
            subscriptionRegistered = true
            try {
                if (Build.VERSION.SDK_INT >= 31) {
                    val callback = ModernCallback({changed(dataType = it)}, {changed(roaming = it)})
                    phone.registerTelephonyCallback(executor, callback)
                    closePhone = {phone.unregisterTelephonyCallback(callback)}
                } else {
                    val listener = onLane(lane) {object : PhoneStateListener() {
                        override fun onDataConnectionStateChanged(state: Int, networkType: Int) = changed(dataType = networkType)
                        override fun onServiceStateChanged(serviceState: ServiceState?) = changed(roaming = serviceState?.roaming)
                    }}
                    phone.listen(listener, PhoneStateListener.LISTEN_DATA_CONNECTION_STATE or PhoneStateListener.LISTEN_SERVICE_STATE)
                    closePhone = {phone.listen(listener, PhoneStateListener.LISTEN_NONE)}
                }
            } catch (_: SecurityException) {
                // Some callback permissions exceed the metadata query's rights. Continue with serial polling.
            } catch (_: UnsupportedOperationException) {
                // A subscription may exist on a device without every telephony radio feature.
            }
            return object : CollectorSubscription {
                override val pollingRequired = true
                override fun close() = release()
            }
        } catch (error: Throwable) {release();throw error}
    }
    @TargetApi(31)
    private class ModernCallback(private val data: (Int) -> Unit, private val roaming: (Boolean) -> Unit) : TelephonyCallback(), TelephonyCallback.DataConnectionStateListener, TelephonyCallback.ServiceStateListener {
        override fun onDataConnectionStateChanged(state: Int, networkType: Int) = data(networkType)
        override fun onServiceStateChanged(serviceState: ServiceState) = roaming(serviceState.roaming)
    }
    private fun <T> onLane(lane: CallbackLane, create: () -> T): T {
        val result = CompletableFuture<T>()
        if (!lane.handler.post {try {result.complete(create())} catch (error: Throwable) {result.completeExceptionally(error)}})
            throw DeviceReadoutException(ErrorCode.ReadFailed, "The cellular callback lane stopped.")
        return try {result.get()} catch (error: ExecutionException) {throw error.cause ?: error}
    }
    private fun code(value: String?, length: IntRange): String? = value?.takeIf {it.length in length && it.all {char -> char in '0'..'9'}}
    private fun radio(value: Int): RadioTechnology? = when (value) {
        TelephonyManager.NETWORK_TYPE_GSM -> RadioTechnology.Gsm
        TelephonyManager.NETWORK_TYPE_GPRS -> RadioTechnology.Gprs
        TelephonyManager.NETWORK_TYPE_EDGE -> RadioTechnology.Edge
        TelephonyManager.NETWORK_TYPE_CDMA -> RadioTechnology.Cdma
        TelephonyManager.NETWORK_TYPE_1xRTT -> RadioTechnology.Cdma1x
        TelephonyManager.NETWORK_TYPE_EVDO_0 -> RadioTechnology.Evdo0
        TelephonyManager.NETWORK_TYPE_EVDO_A -> RadioTechnology.EvdoA
        TelephonyManager.NETWORK_TYPE_EVDO_B -> RadioTechnology.EvdoB
        TelephonyManager.NETWORK_TYPE_EHRPD -> RadioTechnology.Ehrpd
        TelephonyManager.NETWORK_TYPE_UMTS -> RadioTechnology.Umts
        TelephonyManager.NETWORK_TYPE_HSDPA -> RadioTechnology.Hsdpa
        TelephonyManager.NETWORK_TYPE_HSUPA -> RadioTechnology.Hsupa
        TelephonyManager.NETWORK_TYPE_HSPA -> RadioTechnology.Hspa
        TelephonyManager.NETWORK_TYPE_HSPAP -> RadioTechnology.HspaPlus
        TelephonyManager.NETWORK_TYPE_IDEN -> RadioTechnology.Iden
        TelephonyManager.NETWORK_TYPE_TD_SCDMA -> RadioTechnology.TdScdma
        TelephonyManager.NETWORK_TYPE_LTE -> RadioTechnology.Lte
        TelephonyManager.NETWORK_TYPE_NR -> RadioTechnology.Nr
        TelephonyManager.NETWORK_TYPE_IWLAN -> RadioTechnology.Iwlan
        else -> null
    }
}
private const val PRIVILEGED_PHONE_STATE_PERMISSION = "android.permission.READ_PRIVILEGED_PHONE_STATE"
private inline fun <T> optional(read: () -> T): T? = try {read()} catch (_: Exception) {null}
private inline fun <T> platform(read: () -> T): T = try {read()} catch (error: UnsupportedOperationException) {
    throw DeviceReadoutException(ErrorCode.UnsupportedEntity, "Telephony subscription access is unavailable.", error)
}
