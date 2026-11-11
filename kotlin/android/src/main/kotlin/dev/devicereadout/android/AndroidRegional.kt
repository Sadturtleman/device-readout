package dev.devicereadout.android

import android.annotation.TargetApi
import android.app.LocaleManager
import android.content.BroadcastReceiver
import android.content.ComponentCallbacks
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.res.Resources
import android.content.res.Configuration
import android.database.ContentObserver
import android.icu.text.NumberingSystem
import android.icu.util.Calendar
import android.icu.util.LocaleData
import android.icu.util.ULocale
import android.os.Build
import android.os.LocaleList
import android.provider.Settings
import android.text.format.DateFormat
import dev.devicereadout.*
import java.text.SimpleDateFormat
import java.util.Date
import java.util.TimeZone
import java.util.concurrent.atomic.AtomicBoolean

internal class AndroidRegional(private val context: Context) {
    fun readLocale(): LocaleSnapshot {
        val locales = context.resources.configuration.locales
        val current = if (locales.isEmpty) null else locales[0]
        val locale = current?.let(ULocale::forLocale)
        val calendar = locale?.let {attempt {Calendar.getInstance(it)}}
        return LocaleSnapshot(
            currentLanguageTag = current?.toLanguageTag(),
            preferredLanguageTags = locales.tags(),
            systemLanguageTags = attempt {
                if (Build.VERSION.SDK_INT >= 33) context.getSystemService(LocaleManager::class.java)?.systemLocales?.tags()
                else Resources.getSystem().configuration.locales.tags()
            },
            appLanguageTags = if (Build.VERSION.SDK_INT >= 33) attempt {context.getSystemService(LocaleManager::class.java)?.applicationLocales?.tags()} else null,
            regionCode = current?.country?.takeIf {it.isNotEmpty()},
            scriptCode = current?.script?.takeIf {it.isNotEmpty()},
            calendar = calendar?.type?.let {ULocale.toUnicodeLocaleType("ca", it)},
            numberingSystem = locale?.let {attempt {NumberingSystem.getInstance(it).name}},
            hourCycle = attempt {(DateFormat.getTimeFormat(context) as? SimpleDateFormat)?.toPattern()?.let(::hourCycle)},
            firstWeekday = when (calendar?.firstDayOfWeek) {
                Calendar.MONDAY -> Weekday.Monday; Calendar.TUESDAY -> Weekday.Tuesday
                Calendar.WEDNESDAY -> Weekday.Wednesday; Calendar.THURSDAY -> Weekday.Thursday
                Calendar.FRIDAY -> Weekday.Friday; Calendar.SATURDAY -> Weekday.Saturday
                Calendar.SUNDAY -> Weekday.Sunday; else -> null
            },
            measurementSystem = if (Build.VERSION.SDK_INT >= 28 && locale != null) attempt {measurementSystem(locale)} else null,
        )
    }
    fun readTimeZone(): TimeZoneSnapshot {
        val zone = TimeZone.getDefault()
        val now = Date()
        val systemId = BooleanArray(1)
        android.icu.util.TimeZone.getCanonicalID(zone.id, systemId)
        return TimeZoneSnapshot(
            ianaId = zone.id.takeIf {systemId[0]},
            utcOffsetSeconds = zone.getOffset(now.time) / 1000,
            daylightSavingTime = zone.inDaylightTime(now),
        )
    }
    fun observeChanges(kind: EntityKind, changed: () -> Unit, fail: (Throwable) -> Unit): CollectorSubscription {
        val lane = CallbackLane("DeviceReadout regional", fail)
        val closed = AtomicBoolean()
        fun refresh() {if (!closed.get()) lane.deliver(changed)}
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) = refresh()
        }
        val clockPreference = object : ContentObserver(lane.handler) {
            override fun onChange(selfChange: Boolean) = refresh()
        }
        val configuration = object : ComponentCallbacks {
            // Android can broadcast the app locale before updating process Resources. Its configuration
            // observer supplies the later completion signal. The main-thread callback only posts work.
            override fun onConfigurationChanged(newConfig: Configuration) {if (!closed.get()) lane.post(::refresh)}
            override fun onLowMemory() {}
        }
        val filter = IntentFilter().apply {
            if (kind == EntityKind.Locale) addAction(Intent.ACTION_LOCALE_CHANGED)
            else {addAction(Intent.ACTION_TIMEZONE_CHANGED);addAction(Intent.ACTION_TIME_CHANGED)}
        }
        var registered = false
        var preferenceRegistered = false
        var configurationRegistered = false
        try {
            if (Build.VERSION.SDK_INT >= 33) context.registerReceiver(receiver, filter, null, lane.handler, Context.RECEIVER_NOT_EXPORTED)
            else context.registerReceiver(receiver, filter, null, lane.handler)
            registered = true
            if (kind == EntityKind.Locale) {
                context.registerComponentCallbacks(configuration)
                configurationRegistered = true
                context.contentResolver.registerContentObserver(Settings.System.getUriFor(Settings.System.TIME_12_24), false, clockPreference)
                preferenceRegistered = true
            }
            return object : CollectorSubscription {
                // App-local configuration overrides and DST transitions do not have complete broadcast coverage.
                override val pollingRequired = true
                override fun close() {
                    if (!closed.compareAndSet(false, true)) return
                    try {context.unregisterReceiver(receiver)} finally {
                        try {if (preferenceRegistered) context.contentResolver.unregisterContentObserver(clockPreference)} finally {
                            try {if (configurationRegistered) context.unregisterComponentCallbacks(configuration)} finally {lane.close()}
                        }
                    }
                }
            }
        } catch (error: Throwable) {
            if (registered) attempt {context.unregisterReceiver(receiver)}
            if (preferenceRegistered) attempt {context.contentResolver.unregisterContentObserver(clockPreference)}
            if (configurationRegistered) attempt {context.unregisterComponentCallbacks(configuration)}
            lane.close();throw error
        }
    }
    @TargetApi(28)
    private fun measurementSystem(locale: ULocale): MeasurementSystem? = when (LocaleData.getMeasurementSystem(locale)) {
        LocaleData.MeasurementSystem.SI -> MeasurementSystem.Metric
        LocaleData.MeasurementSystem.US -> MeasurementSystem.US
        LocaleData.MeasurementSystem.UK -> MeasurementSystem.UK
        else -> null
    }
    private fun hourCycle(pattern: String): HourCycle? {
        var quoted = false
        for (character in pattern) {
            if (character == '\'') {quoted = !quoted;continue}
            if (quoted) continue
            when (character) {
                'K' -> return HourCycle.H11; 'h' -> return HourCycle.H12
                'H' -> return HourCycle.H23; 'k' -> return HourCycle.H24
            }
        }
        return null
    }
}

private fun LocaleList.tags(): List<String> = (0 until size()).map {get(it).toLanguageTag()}
private inline fun <T> attempt(read: () -> T): T? = try {read()} catch (_: Exception) {null}
