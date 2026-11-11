package dev.devicereadout

import kotlinx.coroutines.*
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import org.junit.Test
import java.util.concurrent.atomic.AtomicInteger
import kotlin.test.*
import kotlin.time.Duration.Companion.milliseconds

class ObserverContractTest {
    @Test fun appTargetNamesDoNotAliasNativeTargetsOrTheirPermissions() = runBlocking {
        DeviceAccess(object : DeviceCollector {
            override fun list(kind: EntityKind) = listOf("shared-name")
            override fun read(entity: EntityAddress): DeviceSnapshot = CpuCoreSnapshot(logicalIndex = 7)
        }).use {access ->
            val native = access.cpuCores.list().single()
            access.observers.current(CpuCoreEntity, native)
            assertEquals(1, access.cpuCores.list().size)
            val app = access.observers.target(CpuCoreEntity, "shared-name")
            access.observers.publish(app, CpuCoreSnapshot(logicalIndex = 99))
            access.observers.permission(app, PermissionStatus.Denied)
            access.observers.permission(native, PermissionStatus.Granted)
            assertEquals(99, access.get(app).logicalIndex)
            assertEquals(7, access.get(native).logicalIndex)
            assertEquals(PermissionStatus.Denied, access.permissions.check(app))
            assertEquals(PermissionStatus.Granted, access.permissions.check(native))
            assertEquals(7, access.get(access.cpuCores.current()!!).logicalIndex)
            assertEquals(99, access.get(access.cpuCores.list().single()).logicalIndex)
            access.observers.failure(app, DeviceReadoutException(ErrorCode.PermissionDenied, "App observer failed."))
            assertEquals(7, access.get(native).logicalIndex)
            assertEquals(ErrorCode.PermissionDenied, assertFailsWith<DeviceReadoutException> {access.get(app)}.code)
            access.observers.remove(app)
            assertEquals(7, access.get(native).logicalIndex)
            assertEquals(ErrorCode.EntityRemoved, assertFailsWith<DeviceReadoutException> {access.get(app)}.code)
        }
    }
    @Test fun targetPermissionsInheritKindStatusAndPreserveExplicitOverrides() = runBlocking {
        withTimeout(3000) {
            access().use {access ->
                val first = access.observers.target(AccelerometerEntity, "permission-first")
                val second = access.observers.target(AccelerometerEntity, "permission-second")
                access.observers.permission(AccelerometerEntity, PermissionStatus.NotDetermined)
                assertEquals(PermissionStatus.NotDetermined, access.permissions.check(first))
                val requests = kotlinx.coroutines.channels.Channel<PermissionRequest>(2)
                access.observers.onPermissionRequest {requests.send(it)}.use {
                    val pending = async {access.permissions.request(first)}
                    assertSame(first, requests.receive().entity)
                    access.observers.permission(AccelerometerEntity, PermissionStatus.Granted)
                    assertEquals(PermissionStatus.Granted, pending.await())
                    access.observers.permission(second, PermissionStatus.Denied)
                    access.observers.permission(AccelerometerEntity, PermissionStatus.Restricted)
                    assertEquals(PermissionStatus.Restricted, access.permissions.check(first))
                    assertEquals(PermissionStatus.Denied, access.permissions.check(second))
                    access.observers.permission(second, null)
                    val overridden = async {access.permissions.request(second)}
                    assertSame(second, requests.receive().entity)
                    access.observers.permission(AccelerometerEntity, PermissionStatus.Granted)
                    delay(25)
                    assertFalse(overridden.isCompleted)
                    assertNull(access.permissions.check(second))
                    access.observers.permission(second, PermissionStatus.Denied)
                    assertEquals(PermissionStatus.Denied, overridden.await())
                }
            }
        }
    }
    @Test fun emptyObserverInventoryAndPendingReadsPreserveFailures() = runBlocking {
        access().use {access ->
            withTimeout(2000) {
                access.observers.current(DisplayEntity, null)
                assertTrue(access.displays.list().isEmpty())
                assertNull(access.displays.current())
                val screen = access.observers.target(DisplayEntity, "awaiting-screen")
                val pending = async {runCatching {access.get(screen)}.exceptionOrNull()}
                delay(30)
                assertFalse(pending.isCompleted)
                access.observers.failure(DisplayEntity, DeviceReadoutException(ErrorCode.PermissionDenied, "Permission revoked before first state."))
                assertEquals(ErrorCode.PermissionDenied, (pending.await() as DeviceReadoutException).code)
                access.observers.publish(screen, DisplaySnapshot(label = "Refreshed while recovering"))
                assertEquals(ErrorCode.PermissionDenied, assertFailsWith<DeviceReadoutException> {access.get(screen)}.code)
                access.observers.failure(DisplayEntity, null)
                assertEquals("Refreshed while recovering", access.get(screen).label)
            }
        }
    }
    private fun access() = DeviceAccess(object : DeviceCollector {
        override fun read(entity: EntityAddress): DeviceSnapshot = error("Observed entities must not call platform UI APIs.")
    })
    @Test fun screenStateAndCurrentSelectionComeFromTheAppObserver() = runBlocking {
        access().use { access ->
            val screen = access.observers.target(DisplayEntity, "app-screen")
            access.observers.publish(screen, DisplaySnapshot(pixelSize = Size(800, 600)))
            assertNull(access.displays.current())
            access.observers.current(DisplayEntity, screen)
            assertEquals(Size(800, 600), access.get(access.displays.current()!!).pixelSize)
            val initial = CompletableDeferred<DisplaySnapshot>()
            val snapshots = async {access.watch(screen).onEach {initial.complete(it)}.take(2).toList()}
            assertEquals(800, withTimeout(2000) {initial.await()}.pixelSize?.width)
            access.observers.publish(screen, DisplaySnapshot(pixelSize = Size(600, 800)))
            assertEquals(listOf(800, 600), snapshots.await().map {it.pixelSize?.width})
            access.observers.remove(screen)
            assertTrue(access.displays.list().isEmpty())
            assertNull(access.displays.current())
            assertEquals(ErrorCode.EntityRemoved, assertFailsWith<DeviceReadoutException> {access.get(screen)}.code)
        }
    }
    @Test fun explicitPermissionRequestWaitsForObservedStatusWithoutAReadTimeout() = runBlocking {
        access().use { access ->
            access.observers.permission(DisplayEntity, PermissionStatus.NotDetermined)
            access.observers.onPermissionRequest { request ->
                assertSame(DisplayEntity, request.entity)
                delay(80)
                access.observers.permission(DisplayEntity, PermissionStatus.Granted)
            }.use {
                assertEquals(PermissionStatus.NotDetermined, access.permissions.check(DisplayEntity))
                assertEquals(PermissionStatus.Granted, access.withReadTimeout(10.milliseconds).permissions.request(DisplayEntity))
            }
        }
    }
    @Test fun oneShotSensorReadsWaitForANewSampleAndDoNotReturnCachedEvents() = runBlocking {
        access().use { access ->
            val step = access.observers.target(StepDetectedEntity, "steps")
            access.observers.publish(step, StepDetectedSnapshot(value = true))
            val first = async {access.get(step)}
            delay(30)
            assertFalse(first.isCompleted)
            access.observers.publish(step, StepDetectedSnapshot(value = true))
            assertEquals(true, first.await().value)
            assertEquals(ErrorCode.ReadTimeout, assertFailsWith<DeviceReadoutException> {access.withReadTimeout(25.milliseconds).get(step)}.code)
        }
    }
    @Test fun inactiveSensorsReleaseTheirSubscriptionAndResumeWithAFreshSession() = runBlocking {
        val started = kotlinx.coroutines.channels.Channel<Pair<Int, (DeviceSnapshot) -> Unit>>(4)
        val released = kotlinx.coroutines.channels.Channel<Int>(4)
        val sessions = AtomicInteger()
        DeviceAccess(object : DeviceCollector {
            override fun read(entity: EntityAddress): DeviceSnapshot = error("A sensor read needs a fresh sample.")
            override fun list(kind: EntityKind) = listOf("accelerometer")
            override fun observe(entity: EntityAddress, rate: SensorSamplingRate, emit: (DeviceSnapshot) -> Unit, fail: (Throwable) -> Unit): CollectorSubscription {
                val session = sessions.incrementAndGet()
                started.trySend(session to emit)
                return object : CollectorSubscription {
                    override val pollingRequired = false
                    override fun close() {released.trySend(session)}
                }
            }
        }).use { access ->
            val sensor = access.sensors.list(AccelerometerEntity).single()
            access.observers.sensorActivity(false)
            val snapshots = async {access.withReadTimeout(150.milliseconds).watch(sensor).take(2).toList()}
            delay(200)
            assertFalse(snapshots.isCompleted)
            assertEquals(0, sessions.get())
            access.observers.sensorActivity(true)
            val (firstId, firstEmit) = withTimeout(1000) {started.receive()}
            firstEmit(AccelerometerSnapshot(value = Vector3(1.0, 0.0, 0.0)))
            delay(30)
            access.observers.sensorActivity(false)
            assertEquals(firstId, withTimeout(1000) {released.receive()})
            firstEmit(AccelerometerSnapshot(value = Vector3(99.0, 0.0, 0.0)))
            delay(200)
            access.observers.sensorActivity(true)
            val (secondId, secondEmit) = withTimeout(1000) {started.receive()}
            assertNotEquals(firstId, secondId)
            secondEmit(AccelerometerSnapshot(value = Vector3(2.0, 0.0, 0.0)))
            assertEquals(listOf(1.0, 2.0), withTimeout(1000) {snapshots.await()}.map {it.value?.x})
            assertEquals(secondId, withTimeout(1000) {released.receive()})
        }
    }
}
