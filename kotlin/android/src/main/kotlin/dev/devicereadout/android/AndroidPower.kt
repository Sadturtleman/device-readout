package dev.devicereadout.android

import android.content.Context
import android.annotation.TargetApi
import android.content.BroadcastReceiver
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import android.os.Handler
import dev.devicereadout.*
import kotlin.time.Duration.Companion.milliseconds
import java.util.concurrent.Executor
import java.util.concurrent.atomic.AtomicBoolean

internal class AndroidPower(private val context: Context) {
    private val aggregateBattery = "android-aggregate-battery"
    private fun batteryIntent(): Intent? = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
    fun listBatteries(): List<String> = if (batteryIntent() == null) emptyList() else listOf(aggregateBattery)
    fun currentBattery(): String? = if (batteryIntent() == null) null else aggregateBattery
    fun observeChanges(entity: EntityAddress, changed: () -> Unit, fail: (Throwable) -> Unit): CollectorSubscription {
        if (entity.kind == EntityKind.Battery && entity.targetId != aggregateBattery) throw DeviceReadoutException(ErrorCode.EntityRemoved, "Unknown aggregate battery handle.")
        val lane = CallbackLane("DeviceReadout power", fail)
        val closed = AtomicBoolean()
        fun refresh() = lane.deliver(changed)
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {if (!isInitialStickyBroadcast && !closed.get()) refresh()}
        }
        val filter = IntentFilter(Intent.ACTION_BATTERY_CHANGED).apply {addAction(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED)}
        var registered = false
        var thermal: AutoCloseable? = null
        try {
            if (Build.VERSION.SDK_INT >= 33) context.registerReceiver(receiver, filter, null, lane.handler, Context.RECEIVER_NOT_EXPORTED)
            else context.registerReceiver(receiver, filter, null, lane.handler)
            registered = true
            if (entity.kind == EntityKind.Power && Build.VERSION.SDK_INT >= 29) thermal = observeThermal(lane.handler, ::refresh)
            return object : CollectorSubscription {
                // Instantaneous current and energy do not have complete broadcast coverage.
                override val pollingRequired = entity.kind == EntityKind.Battery
                override fun close() {
                    if (!closed.compareAndSet(false, true)) return
                    try {context.unregisterReceiver(receiver)} finally {
                        try {thermal?.close()} finally {lane.close()}
                    }
                }
            }
        } catch (error: Throwable) {
            if (registered) attempt {context.unregisterReceiver(receiver)}
            attempt {thermal?.close()};lane.close();throw error
        }
    }
    @TargetApi(29)
    private fun observeThermal(handler: Handler, refresh: () -> Unit): AutoCloseable? {
        val manager = context.getSystemService(PowerManager::class.java) ?: return null
        val active = AtomicBoolean(true)
        val listener = PowerManager.OnThermalStatusChangedListener {if (active.get()) refresh()}
        manager.addThermalStatusListener(Executor {task -> if (active.get()) handler.post(task)}, listener)
        return AutoCloseable {if (active.compareAndSet(true, false)) manager.removeThermalStatusListener(listener)}
    }
    fun readPower(): PowerSnapshot {
        val battery = attempt {batteryIntent()}
        val manager = context.getSystemService(PowerManager::class.java)
        val plugged = battery?.intValue(BatteryManager.EXTRA_PLUGGED)
        val knownPlugs = BatteryManager.BATTERY_PLUGGED_AC or BatteryManager.BATTERY_PLUGGED_USB or BatteryManager.BATTERY_PLUGGED_WIRELESS or
            (if (Build.VERSION.SDK_INT >= 33) BatteryManager.BATTERY_PLUGGED_DOCK else 0)
        return PowerSnapshot(
            powerSource = when {
                plugged == null -> null
                plugged == 0 && battery.booleanValue(BatteryManager.EXTRA_PRESENT) != false -> PowerSource.Battery
                plugged > 0 && plugged and knownPlugs.inv() == 0 -> PowerSource.External
                else -> null
            },
            powerSaveMode = attempt {manager?.isPowerSaveMode},
            thermalState = if (Build.VERSION.SDK_INT >= 29) attempt {thermalState(manager?.currentThermalStatus)} else null,
        )
    }
    fun readBattery(target: String?): BatterySnapshot {
        if (target != aggregateBattery) throw DeviceReadoutException(ErrorCode.EntityRemoved, "The aggregate battery handle is no longer available.")
        val intent = batteryIntent() ?: throw DeviceReadoutException(ErrorCode.EntityRemoved, "The aggregate battery is unavailable.")
        val manager = context.getSystemService(BatteryManager::class.java)
        // getLongProperty retains Long.MIN_VALUE on every target SDK; getIntProperty can return a misleading zero on older targets.
        fun property(id: Int): Long? = attempt {manager?.getLongProperty(id)?.takeUnless {it == Long.MIN_VALUE}}
        val level = intent.intValue(BatteryManager.EXTRA_LEVEL)
        val scale = intent.intValue(BatteryManager.EXTRA_SCALE)
        val state = when (intent.intValue(BatteryManager.EXTRA_STATUS)) {
            BatteryManager.BATTERY_STATUS_CHARGING -> BatteryState.Charging
            BatteryManager.BATTERY_STATUS_DISCHARGING -> BatteryState.Discharging
            BatteryManager.BATTERY_STATUS_FULL -> BatteryState.Full
            BatteryManager.BATTERY_STATUS_NOT_CHARGING -> BatteryState.NotCharging
            else -> null
        }
        return BatterySnapshot(
            present = intent.booleanValue(BatteryManager.EXTRA_PRESENT),
            level = if (level != null && scale != null && scale > 0 && level in 0..scale) level.toDouble() / scale else null,
            charging = state?.let {it == BatteryState.Charging},
            state = state,
            timeToFull = if (Build.VERSION.SDK_INT >= 28) attempt {manager?.computeChargeTimeRemaining()?.takeIf {it >= 0}?.milliseconds} else null,
            voltageMillivolts = intent.intValue(BatteryManager.EXTRA_VOLTAGE)?.takeIf {it >= 0}?.toDouble(),
            currentMicroamps = property(BatteryManager.BATTERY_PROPERTY_CURRENT_NOW)?.toDouble(),
            averageCurrentMicroamps = property(BatteryManager.BATTERY_PROPERTY_CURRENT_AVERAGE)?.toDouble(),
            temperatureCelsius = intent.intValue(BatteryManager.EXTRA_TEMPERATURE)?.div(10.0),
            chargeCounterMicroampHours = property(BatteryManager.BATTERY_PROPERTY_CHARGE_COUNTER)?.takeIf {it >= 0},
            remainingEnergyMilliwattHours = property(BatteryManager.BATTERY_PROPERTY_ENERGY_COUNTER)?.takeIf {it >= 0}?.div(1_000_000.0),
            technology = intent.getStringExtra(BatteryManager.EXTRA_TECHNOLOGY),
            health = when (intent.intValue(BatteryManager.EXTRA_HEALTH)) {
                BatteryManager.BATTERY_HEALTH_GOOD -> BatteryHealth.Good
                BatteryManager.BATTERY_HEALTH_OVERHEAT -> BatteryHealth.Overheated
                BatteryManager.BATTERY_HEALTH_COLD -> BatteryHealth.Cold
                BatteryManager.BATTERY_HEALTH_DEAD -> BatteryHealth.Dead
                BatteryManager.BATTERY_HEALTH_OVER_VOLTAGE -> BatteryHealth.OverVoltage
                BatteryManager.BATTERY_HEALTH_UNSPECIFIED_FAILURE -> BatteryHealth.UnspecifiedFailure
                else -> null
            },
            cycleCount = if (Build.VERSION.SDK_INT >= 34) intent.intValue(BatteryManager.EXTRA_CYCLE_COUNT)?.takeIf {it >= 0}?.toLong() else null,
        )
    }
    private fun thermalState(value: Int?): AndroidThermalState? = when (value) {
        PowerManager.THERMAL_STATUS_NONE -> AndroidThermalState.None
        PowerManager.THERMAL_STATUS_LIGHT -> AndroidThermalState.Light
        PowerManager.THERMAL_STATUS_MODERATE -> AndroidThermalState.Moderate
        PowerManager.THERMAL_STATUS_SEVERE -> AndroidThermalState.Severe
        PowerManager.THERMAL_STATUS_CRITICAL -> AndroidThermalState.Critical
        PowerManager.THERMAL_STATUS_EMERGENCY -> AndroidThermalState.Emergency
        PowerManager.THERMAL_STATUS_SHUTDOWN -> AndroidThermalState.Shutdown
        else -> null
    }
}

private fun Intent.intValue(name: String): Int? = if (hasExtra(name)) getIntExtra(name, 0) else null
private fun Intent.booleanValue(name: String): Boolean? = if (hasExtra(name)) getBooleanExtra(name, false) else null
private inline fun <T> attempt(read: () -> T): T? = try {read()} catch (_: Exception) {null}
