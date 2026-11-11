package dev.devicereadout.android

import android.os.Build
import android.os.Looper
import android.content.Intent
import android.telephony.TelephonyManager
import dev.devicereadout.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.collect
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowBuild
import org.robolectric.shadow.api.Shadow
import kotlin.test.*
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class AndroidIdentityContractTest {
    @Test
    @Config(shadows = [IdentityTelephonyService::class])
    fun slotRemovedDuringReadDoesNotReturnACompletedIdentitySnapshot() = runBlocking {
        val context = RuntimeEnvironment.getApplication()
        val native = Shadow.extract<IdentityTelephonyService>(context.getSystemService(TelephonyManager::class.java))
        native.setActiveModemCount(1)
        native.setImei(0, "001234567890123")
        AndroidDeviceAccess.create(context).use {access ->
            val target = access.telephonyIdentities.list().single()
            native.onImeiRead = {native.setActiveModemCount(0)}
            val failure = assertFailsWith<DeviceReadoutException> {access.get(target)}
            assertEquals(ErrorCode.EntityRemoved, failure.code)
            native.onImeiRead = null
            native.setActiveModemCount(1)
            val replacement = access.telephonyIdentities.list().single()
            assertEquals("001234567890123", access.get(replacement).imei)
            assertEquals(ErrorCode.EntityRemoved, assertFailsWith<DeviceReadoutException> {access.get(target)}.code)
        }
    }

    @Test fun modemRemovalEventRetiresWatchedSlotEvenWhenCountAlreadyRecovered() = runBlocking {
        val context = RuntimeEnvironment.getApplication()
        val native = shadowOf(context.getSystemService(TelephonyManager::class.java))
        native.setActiveModemCount(2)
        native.setImei(1, "009876543210987")
        AndroidDeviceAccess.create(context).use {access ->
            val old = access.telephonyIdentities.list()[1]
            val first = CompletableDeferred<Unit>()
            val collection = async {runCatching {access.withPollInterval(30.seconds).watch(old).onEach {first.complete(Unit)}.collect()}}
            withTimeout(5000) {first.await()}
            native.setActiveModemCount(1)
            context.sendBroadcast(Intent(TelephonyManager.ACTION_MULTI_SIM_CONFIG_CHANGED).putExtra(TelephonyManager.EXTRA_ACTIVE_SIM_SUPPORTED_COUNT, 1))
            native.setActiveModemCount(2)
            shadowOf(Looper.getMainLooper()).idle()
            val removed = assertIs<DeviceReadoutException>(withTimeout(3000) {collection.await()}.exceptionOrNull())
            assertEquals(ErrorCode.EntityRemoved, removed.code)
            val replacement = access.telephonyIdentities.list()[1]
            assertEquals("009876543210987", access.get(replacement).imei)
            val oldRead = assertFailsWith<DeviceReadoutException> {access.get(old)}
            assertEquals(ErrorCode.EntityRemoved, oldRead.code)
            assertEquals(EntityCapabilities(false, false), access.capabilities.get(old))
        }
    }

    @Test
    @Config(shadows = [IdentityTelephonyService::class])
    fun telephonyIdentityRetainsReadableFieldAndTypesWholeReadFailures() = runBlocking {
        val context = RuntimeEnvironment.getApplication()
        val native = Shadow.extract<IdentityTelephonyService>(context.getSystemService(TelephonyManager::class.java))
        native.setActiveModemCount(1)
        native.setImei(0, "001234567890123")
        native.meidFailure = SecurityException("Fixture denied MEID")
        AndroidDeviceAccess.create(context).use {access ->
            var prompts = 0
            access.observers.onPermissionRequest {prompts++}
            val target = access.telephonyIdentities.list().single()
            val partial = access.get(target)
            assertEquals("001234567890123", partial.imei)
            assertNull(partial.meid)
            native.setImei(0, null)
            val denied = assertFailsWith<DeviceReadoutException> {access.get(target)}
            assertEquals(ErrorCode.PermissionDenied, denied.code)
            native.meidFailure = null
            native.setMeid(0, "a1000000000001")
            assertEquals("a1000000000001", access.get(target).meid)
            native.setMeid(0, null)
            assertNull(access.get(target).imei)
            assertNull(access.get(target).meid)
            native.imeiFailure = UnsupportedOperationException("Fixture has no IMEI API")
            native.meidFailure = UnsupportedOperationException("Fixture has no CDMA API")
            val unsupported = assertFailsWith<DeviceReadoutException> {access.get(target)}
            assertEquals(ErrorCode.UnsupportedEntity, unsupported.code)
            assertEquals(0, prompts)
            assertTrue(native.readsOnMain.isNotEmpty() && native.readsOnMain.none {it})
        }
    }

    @Test fun telephonyIdentityUsesEachLogicalSlotWithoutRequiringAnActiveSubscription() = runBlocking {
        val context = RuntimeEnvironment.getApplication()
        val native = shadowOf(context.getSystemService(TelephonyManager::class.java))
        native.setActiveModemCount(2)
        native.setImei(0, "001234567890123")
        native.setImei(1, "009876543210987")
        native.setMeid(0, null)
        native.setMeid(1, "a1000000000001")
        AndroidDeviceAccess.create(context).use {access ->
            val targets = access.telephonyIdentities.list()
            assertEquals(2, targets.size)
            assertNull(access.telephonyIdentities.current())
            val first = access.get(targets[0])
            val second = access.get(targets[1])
            assertEquals("001234567890123", first.imei)
            assertNull(first.meid)
            assertEquals("009876543210987", second.imei)
            assertEquals("a1000000000001", second.meid)
            assertEquals(EntityCapabilities(true, true), access.capabilities.get(TelephonyIdentityEntity))
        }
    }

    @Test fun hardwareSerialPreservesNativeValueAndHasNoFallbackForUnknown() = runBlocking {
        ShadowBuild.setSerial("FixtureSerial-a9")
        AndroidDeviceAccess.create(RuntimeEnvironment.getApplication()).use {access ->
            val values = withTimeout(5000) {access.withPollInterval(20.milliseconds).watch(HardwareSerialEntity).take(2).toList()}
            assertEquals(listOf("FixtureSerial-a9", "FixtureSerial-a9"), values.map {it.serial})
            assertTrue(values.all {it.collectedAt.toEpochMilli() > 0})
            ShadowBuild.setSerial(Build.UNKNOWN)
            assertNull(access.get(HardwareSerialEntity).serial)
            ShadowBuild.setSerial("")
            assertNull(access.get(HardwareSerialEntity).serial)
        }
    }
}
