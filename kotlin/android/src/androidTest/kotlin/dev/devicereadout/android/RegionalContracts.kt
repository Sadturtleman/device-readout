package dev.devicereadout.android

import android.content.Context
import android.annotation.TargetApi
import android.app.LocaleManager
import android.content.ContextWrapper
import android.content.res.Configuration
import android.content.res.Resources
import android.os.Build
import android.os.Bundle
import android.os.LocaleList
import dev.devicereadout.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import kotlin.time.Duration.Companion.seconds
import kotlin.time.Duration.Companion.milliseconds

/** Locale overrides and timezone defaults below belong only to the isolated test application. */
internal object RegionalContracts {
    suspend fun reads(context: Context, results: Bundle) {
        val originalLocale = Locale.getDefault()
        val originalZone = TimeZone.getDefault()
        try {
            val cases = listOf(
                Triple("en-US", Weekday.Sunday, MeasurementSystem.US),
                Triple("fr-FR", Weekday.Monday, MeasurementSystem.Metric),
                Triple("en-GB", Weekday.Monday, MeasurementSystem.UK),
            )
            for ((tag, weekday, units) in cases) {
                val configured = context.createConfigurationContext(Configuration(context.resources.configuration).apply {
                    setLocales(LocaleList.forLanguageTags("$tag,ko-KR"))
                })
                val appContext = object : ContextWrapper(context) {
                    override fun getApplicationContext(): Context = this
                    override fun getResources(): Resources = configured.resources
                }
                AndroidDeviceAccess.create(appContext).use { access ->
                    val value = access.get(LocaleEntity)
                    check(value.currentLanguageTag == tag)
                    check(value.preferredLanguageTags == listOf(tag, "ko-KR"))
                    check(value.regionCode == tag.substringAfter('-'))
                    check(value.scriptCode == null) {"An omitted script must not be fabricated."}
                    check(value.calendar == "gregory" && value.numberingSystem == "latn")
                    check(value.firstWeekday == weekday)
                    check(value.measurementSystem == if (Build.VERSION.SDK_INT >= 28) units else null)
                    check(value.hourCycle != null)
                    check(!value.systemLanguageTags.isNullOrEmpty())
                    if (Build.VERSION.SDK_INT < 33) check(value.appLanguageTags == null)
                    else check(value.appLanguageTags == emptyList<String>()) {"No per-app override is configured in this test APK."}
                    check(Locale.getDefault() == originalLocale && TimeZone.getDefault() == originalZone)
                }
            }
            AndroidDeviceAccess.create(context).use { access ->
                val updates = withTimeout(2000) {access.withPollInterval(50.milliseconds).watch(LocaleEntity).take(2).toList()}
                check(updates[0].currentLanguageTag == updates[1].currentLanguageTag)
                check(Locale.getDefault() == originalLocale && TimeZone.getDefault() == originalZone)
                for ((id, expectedId, seconds) in listOf(
                    Triple("Asia/Kolkata", "Asia/Kolkata", 19800),
                    Triple("Asia/Kathmandu", "Asia/Kathmandu", 20700),
                    Triple("GMT+05:45", null, 20700),
                    Triple("Etc/UTC", "Etc/UTC", 0),
                )) {
                    val zone = TimeZone.getTimeZone(id)
                    TimeZone.setDefault(zone)
                    val value = access.get(TimeZoneEntity)
                    check(value.ianaId == expectedId) {"Expected zone $expectedId, got ${value.ianaId}."}
                    check(value.utcOffsetSeconds == seconds)
                    check(value.daylightSavingTime == zone.inDaylightTime(Date()))
                    check(value.windowsId == null)
                    check(TimeZone.getDefault() == zone) {"SDK changed the application timezone."}
                }
            }
            results.putBoolean("regionalNativeReadsAndDefaultIsolation", true)
        } finally { TimeZone.setDefault(originalZone) }
    }

    suspend fun timeZoneEvents(context: Context, results: Bundle, ready: () -> Unit) {
        AndroidDeviceAccess.create(context).use { access ->
            check(access.get(TimeZoneEntity).ianaId != "Asia/Kathmandu")
            val observed = withTimeout(5000) {
                access.withPollInterval(30.seconds).watch(TimeZoneEntity).onEach {ready()}
                    .first {it.ianaId == "Asia/Kathmandu"}
            }
            check(observed.utcOffsetSeconds == 20700 && observed.daylightSavingTime == false)
            results.putBoolean("timeZoneNativeEvent", true)
        }
    }

    @TargetApi(33)
    suspend fun localeEvents(context: Context, results: Bundle) = coroutineScope {
        check(Build.VERSION.SDK_INT >= 33) {"The per-app language fixture needs API 33+."}
        val manager = context.getSystemService(LocaleManager::class.java)
        val original = manager.applicationLocales
        val systemLanguages = manager.systemLocales.toLanguageTags().split(',')
        try {
            withContext(Dispatchers.Main) {manager.applicationLocales = LocaleList.getEmptyLocaleList()}
            AndroidDeviceAccess.create(context).use { access ->
                withTimeout(5000) {
                    val started = CompletableDeferred<Unit>()
                    val stream = async {
                        access.withPollInterval(30.seconds).watch(LocaleEntity).onEach {
                            results.putString("lastObservedLocale", serializeSnapshot(it));started.complete(Unit)
                        }.first {it.appLanguageTags == listOf("fr-FR") && it.currentLanguageTag == "fr-FR"}
                    }
                    started.await()
                    // The test app changes its own setting; the SDK only observes the platform event.
                    withContext(Dispatchers.Main) {manager.applicationLocales = LocaleList.forLanguageTags("fr-FR")}
                    val observed = stream.await()
                    check(observed.systemLanguageTags == systemLanguages)
                    check(observed.regionCode == "FR" && observed.calendar == "gregory")
                }
                results.putBoolean("appLocaleNativeEventAndSystemSeparation", true)
            }
        } finally {withContext(NonCancellable + Dispatchers.Main) {manager.applicationLocales = original}}
    }
}
