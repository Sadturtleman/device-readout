package dev.devicereadout.android

import android.annotation.SuppressLint
import android.content.Context
import android.content.BroadcastReceiver
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.telephony.TelephonyManager
import dev.devicereadout.*
import java.util.concurrent.CancellationException
import java.util.concurrent.atomic.AtomicBoolean

internal class AndroidTelephonyIdentity(private val context: Context) {
    private data class Target(val id: String, val slot: Int, var removed: Boolean = false)
    private val gate = Any()
    private val targets = LinkedHashMap<String, Target>()
    private val bySlot = HashMap<Int, Target>()
    private var sequence = 0L
    private fun manager() = context.getSystemService(TelephonyManager::class.java)
        ?: throw DeviceReadoutException(ErrorCode.UnsupportedEntity, "TelephonyManager is unavailable.")
    @Suppress("DEPRECATION")
    private fun inventory(): List<Target> {
        val phone = manager()
        val count = if (Build.VERSION.SDK_INT >= 30) phone.activeModemCount else phone.phoneCount
        if (count < 0) throw DeviceReadoutException(ErrorCode.ReadFailed, "Android returned an invalid modem count.")
        return synchronized(gate) {
            targets.values.filter {it.slot >= count}.forEach {it.removed = true}
            (0 until count).map {slot ->
                bySlot[slot]?.takeUnless {it.removed}
                    ?: Target("radio-slot-${++sequence}", slot).also {targets[it.id] = it;bySlot[slot] = it}
            }
        }
    }
    fun list(): List<String> = inventory().map {it.id}
    fun capabilities(id: String?): EntityCapabilities {
        val available = inventory()
        val supported = if (id == null) available.isNotEmpty() else available.any {it.id == id}
        return EntityCapabilities(supported, supported)
    }
    private fun resolve(id: String?): Target {
        inventory()
        return synchronized(gate) {targets[id]?.takeUnless {it.removed}}
            ?: throw DeviceReadoutException(ErrorCode.EntityRemoved, "The logical modem slot was removed.")
    }
    fun observeReads(id: String?, emit: (() -> DeviceSnapshot) -> Unit, fail: (Throwable) -> Unit): CollectorSubscription? {
        resolve(id)
        if (Build.VERSION.SDK_INT < 30) return null
        val lane = CallbackLane("DeviceReadout modem slots", fail)
        val closed = AtomicBoolean()
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (closed.get() || intent?.action != TelephonyManager.ACTION_MULTI_SIM_CONFIG_CHANGED) return
                lane.deliver {
                    val count = intent.getIntExtra(TelephonyManager.EXTRA_ACTIVE_SIM_SUPPORTED_COUNT, -1)
                    if (count >= 0) synchronized(gate) {
                        // The OS may already have re-enabled a slot by the time the deferred read runs.
                        targets.values.filter {it.slot >= count}.forEach {it.removed = true}
                    }
                    emit {read(id)}
                }
            }
        }
        try {
            val filter = IntentFilter(TelephonyManager.ACTION_MULTI_SIM_CONFIG_CHANGED)
            // This is a protected system broadcast; the telephony sender can use a distinct privileged UID.
            if (Build.VERSION.SDK_INT >= 33) context.registerReceiver(receiver, filter, null, lane.handler, Context.RECEIVER_EXPORTED)
            else context.registerReceiver(receiver, filter, null, lane.handler)
        } catch (error: Throwable) {lane.close();throw error}
        return object : CollectorSubscription {
            override val pollingRequired = true
            override fun close() {
                if (!closed.compareAndSet(false, true)) return
                try {context.unregisterReceiver(receiver)} finally {lane.close()}
            }
        }
    }
    // Identity access is explicit. Android enforces its own privileged/owner/carrier/role rules.
    @SuppressLint("HardwareIds", "MissingPermission")
    fun read(id: String?): TelephonyIdentitySnapshot {
        val target = resolve(id)
        val phone = manager()
        val imei = field {phone.getImei(target.slot)}
        val meid = field {phone.getMeid(target.slot)}
        resolve(id) // Do not return a snapshot for a slot removed during the native field reads.
        val failures = listOfNotNull(imei.exceptionOrNull(), meid.exceptionOrNull())
        if (imei.getOrNull() == null && meid.getOrNull() == null) {
            failures.firstOrNull {it is SecurityException}?.let {
                throw DeviceReadoutException(ErrorCode.PermissionDenied, "Telephony identifiers are not authorized.", it)
            }
            if (failures.size == 2) {
                val unsupported = failures.all {it is UnsupportedOperationException}
                throw DeviceReadoutException(if (unsupported) ErrorCode.UnsupportedEntity else ErrorCode.ReadFailed,
                    "Telephony identifiers could not be read.", failures.first())
            }
        }
        return TelephonyIdentitySnapshot(imei = imei.getOrNull(), meid = meid.getOrNull())
    }
    private inline fun field(read: () -> String?): Result<String?> = try {
        if (Thread.currentThread().isInterrupted) throw CancellationException("Identifier read was cancelled.")
        Result.success(read()?.takeUnless {it.isBlank()})
    } catch (cancelled: CancellationException) {throw cancelled}
    catch (error: RuntimeException) {Result.failure(error)}
}
