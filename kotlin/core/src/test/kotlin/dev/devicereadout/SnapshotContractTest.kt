package dev.devicereadout

import kotlinx.coroutines.runBlocking
import org.junit.Test
import kotlin.test.*
import kotlin.time.Duration

class SnapshotContractTest {
    @Test fun returnedCollectionsAreDetachedAndCannotBeMutated() = runBlocking<Unit> {
        val languages = mutableListOf("ko-KR", "en-US")
        val transports = mutableSetOf(NetworkTransport.Wifi)
        DeviceAccess(object : DeviceCollector {
            override fun read(entity: EntityAddress): DeviceSnapshot = when(entity.kind) {
                EntityKind.Locale -> LocaleSnapshot(preferredLanguageTags = languages)
                else -> NetworkPathSnapshot(transports = transports)
            }
        }).use { access ->
            val locale = access.get(LocaleEntity)
            val network = access.get(NetworkPathEntity)
            languages.clear();transports.clear()
            assertEquals(listOf("ko-KR", "en-US"), locale.preferredLanguageTags)
            assertEquals(setOf(NetworkTransport.Wifi), network.transports)
            assertFailsWith<UnsupportedOperationException> {(locale.preferredLanguageTags as MutableList).add("fr-FR")}
            assertFailsWith<UnsupportedOperationException> {(network.transports as MutableSet).add(NetworkTransport.Ethernet)}
        }
    }
    @Test fun invalidNumbersAndInfiniteDurationsBecomeNullWithoutChangingZero() = runBlocking {
        DeviceAccess(object : DeviceCollector {
            override fun read(entity: EntityAddress): DeviceSnapshot = NetworkPerformanceSnapshot(
                downlinkBps = Double.NaN, uplinkBps = 0.0, roundTripTime = Duration.INFINITE)
        }).use { access ->
            val snapshot = access.get(NetworkPerformanceEntity)
            assertNull(snapshot.downlinkBps);assertNull(snapshot.roundTripTime)
            assertEquals(0.0, snapshot.uplinkBps)
        }
    }
    @Test fun jsonUsesExactIntegerStringsAndEscapesNames() {
        val ram = RamSnapshot(physicalBytes = 9007199254740993uL, availableBytes = 0uL)
        assertContains(serializeSnapshot(ram), "\"physicalBytes\":\"9007199254740993\"")
        assertContains(serializeSnapshot(ram), "\"availableBytes\":\"0\"")
        assertContains(serializeSnapshot(ram), "\"freeBytes\":null")
        assertContains(serializeSnapshot(DeviceInfoSnapshot(deviceName = "test\n\"phone")), "test\\n\\\"phone")
        assertContains(serializeSnapshot(PowerSnapshot(thermalState = AppleThermalState.Serious)), "AppleThermalState.Serious")
    }
}
