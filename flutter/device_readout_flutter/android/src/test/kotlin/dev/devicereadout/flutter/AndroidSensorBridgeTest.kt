package dev.devicereadout.flutter

import dev.devicereadout.*
import kotlinx.coroutines.*
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.test.*
import kotlin.time.Duration.Companion.milliseconds

class AndroidSensorBridgeTest {
    @Test fun inventoryRegistrationTimeoutReleasesLateSubscriptionOnItsWorker(): Unit = runBlocking {
        val entered = CompletableDeferred<Thread>()
        val released = CompletableDeferred<Thread>()
        val gate = CountDownLatch(1)
        val bridge = AndroidSensorBridge {
            DeviceAccess(object : DeviceCollector {
                override fun read(entity: EntityAddress): DeviceSnapshot = error("Inventory must not measure.")
                override fun observeInventory(changed: (EntityKind) -> Unit, fail: (Throwable) -> Unit): CollectorSubscription {
                    entered.complete(Thread.currentThread())
                    val limit = System.nanoTime() + TimeUnit.SECONDS.toNanos(3)
                    while (gate.count != 0L && System.nanoTime() < limit) {
                        try {gate.await(20, TimeUnit.MILLISECONDS)} catch (_: InterruptedException) {}
                    }
                    return object : CollectorSubscription {
                        override val pollingRequired = false
                        override fun close() { released.complete(Thread.currentThread()) }
                    }
                }
            }).withReadTimeout(150.milliseconds)
        }
        try {
            withTimeout(5000) {
                val id = bridge.invoke("create", emptyMap<Any, Any>()) as Long
                val args = mapOf("context" to id)
                val starting = async {runCatching {bridge.invoke("startInventory", args)}.exceptionOrNull()}
                val worker = entered.await()
                assertNotEquals(Thread.currentThread(), worker)
                assertEquals(ErrorCode.ReadTimeout, assertIs<DeviceReadoutException>(starting.await()).code)
                withTimeout(200) {bridge.invoke("dispose", args)}
                assertFalse(released.isCompleted)
                gate.countDown()
                assertEquals(worker, released.await())
            }
        } finally {gate.countDown();bridge.close()}
    }

    @Test fun absentInventoryObserverRetainsExplicitDiscovery(): Unit = runBlocking {
        val bridge = AndroidSensorBridge {
            DeviceAccess(object : DeviceCollector {
                override fun read(entity: EntityAddress): DeviceSnapshot = error("Inventory must not measure.")
                override fun list(kind: EntityKind) = emptyList<String>()
            })
        }
        try {
            val id = bridge.invoke("create", emptyMap<Any, Any>()) as Long
            val args = mapOf("context" to id)
            assertEquals(false, bridge.invoke("startInventory", args))
            assertEquals(ErrorCode.UnsupportedEntity, assertFailsWith<DeviceReadoutException> {bridge.invoke("nextInventory", args)}.code)
            assertEquals(emptyList<Any>(), bridge.invoke("list", args + ("kind" to "Pressure")))
        } finally {bridge.close()}
    }

    @Test fun malformedInventoryIsRejectedBeforeMetadataAndPreservesPriorHandles(): Unit = runBlocking {
        var identities = listOf("original")
        var descriptions = 0
        val bridge = AndroidSensorBridge {
            DeviceAccess(object : DeviceCollector {
                override fun read(entity: EntityAddress): DeviceSnapshot = error("Inventory must not measure.")
                override fun list(kind: EntityKind) = identities
                override fun describe(sensor: EntityAddress): SensorDescription {
                    descriptions++
                    return SensorDescription(name = "Fixture")
                }
            })
        }
        try {
            val id = bridge.invoke("create", emptyMap<Any, Any>()) as Long
            val args = mapOf("context" to id, "kind" to "Pressure")
            suspend fun target() = ((bridge.invoke("list", args) as List<*>).single() as Map<*, *>)["target"]
            val original = target()
            for (invalid in listOf(listOf("duplicate", "duplicate"), listOf(""), listOf("x".repeat(1025)))) {
                identities = invalid
                val before = descriptions
                assertEquals(ErrorCode.ReadFailed, assertFailsWith<DeviceReadoutException> {bridge.invoke("list", args)}.code)
                assertEquals(before, descriptions, "Validate the complete inventory before metadata work.")
            }
            identities = listOf("original")
            assertEquals(original, target())
        } finally {bridge.close()}
    }

    @Test fun inventoryDeadlineIncludesCoordinationAndBlockedMetadataWithoutJoining(): Unit = runBlocking {
        val entered = CompletableDeferred<Unit>()
        val finished = CompletableDeferred<Unit>()
        val gate = CountDownLatch(1)
        var blocked = false
        val bridge = AndroidSensorBridge {
            DeviceAccess(object : DeviceCollector {
                override fun read(entity: EntityAddress): DeviceSnapshot = error("Inventory must not measure.")
                override fun list(kind: EntityKind) = listOf("sensor")
                override fun describe(sensor: EntityAddress): SensorDescription {
                    if (blocked) {
                        entered.complete(Unit)
                        val limit = System.nanoTime() + TimeUnit.SECONDS.toNanos(3)
                        while (gate.count != 0L && System.nanoTime() < limit) {
                            try {gate.await(20, TimeUnit.MILLISECONDS)} catch (_: InterruptedException) {}
                        }
                        finished.complete(Unit)
                    }
                    return SensorDescription(name = "Fixture")
                }
            })
        }
        try {
            withTimeout(5000) {
                val id = bridge.invoke("create", emptyMap<Any, Any>()) as Long
                val args = mapOf("context" to id, "kind" to "Pressure", "timeoutMicros" to 1_000_000L)
                bridge.invoke("list", args)
                blocked = true
                val active = async {runCatching {bridge.invoke("list", args + ("timeoutMicros" to 300_000L))}.exceptionOrNull()}
                entered.await()
                val waiting = async {runCatching {bridge.invoke("list", args + ("timeoutMicros" to 40_000L))}.exceptionOrNull()}
                assertEquals(ErrorCode.ReadTimeout, assertIs<DeviceReadoutException>(withTimeout(1000) {waiting.await()}).code)
                assertEquals(ErrorCode.ReadTimeout, assertIs<DeviceReadoutException>(withTimeout(1000) {active.await()}).code)
                assertFalse(finished.isCompleted, "The caller deadline must not wait for native metadata.")
                withTimeout(200) {bridge.invoke("dispose", mapOf("context" to id))}
                assertFalse(finished.isCompleted)
                gate.countDown()
                finished.await()
            }
        } finally {gate.countDown();bridge.close()}
    }

    @Test fun inventoryChangesAreWorkerRegisteredBoundedAndContextOwned(): Unit = runBlocking {
        val callbacks = CompletableDeferred<Pair<(EntityKind) -> Unit, (Throwable) -> Unit>>()
        val registered = CompletableDeferred<Thread>()
        val released = CompletableDeferred<Thread>()
        val bridge = AndroidSensorBridge {
            DeviceAccess(object : DeviceCollector {
                override fun read(entity: EntityAddress): DeviceSnapshot = error("Inventory observation must not measure.")
                override fun observeInventory(changed: (EntityKind) -> Unit, fail: (Throwable) -> Unit): CollectorSubscription {
                    registered.complete(Thread.currentThread()); callbacks.complete(changed to fail)
                    return object : CollectorSubscription {
                        override val pollingRequired = false
                        override fun close() { released.complete(Thread.currentThread()) }
                    }
                }
            })
        }
        try {
            withTimeout(5000) {
                val id = bridge.invoke("create", emptyMap<Any, Any>()) as Long
                val args = mapOf("context" to id)
                assertEquals(true, bridge.invoke("startInventory", args))
                assertNotEquals(Thread.currentThread(), registered.await())
                assertEquals(ErrorCode.InvalidConfiguration, assertFailsWith<DeviceReadoutException> {
                    bridge.invoke("startInventory", args)
                }.code)
                val (changed, fail) = callbacks.await()
                repeat(10000) { changed(EntityKind.Pressure); changed(EntityKind.Accelerometer) }
                assertEquals(setOf("Pressure", "Accelerometer"), setOf(
                    bridge.invoke("nextInventory", args), bridge.invoke("nextInventory", args)))
                val waiting = async { runCatching { bridge.invoke("nextInventory", args) }.exceptionOrNull() }
                delay(60)
                assertFalse(waiting.isCompleted, "Repeated invalidations coalesce and idle waiting has no read deadline.")
                assertEquals(ErrorCode.InvalidConfiguration, assertFailsWith<DeviceReadoutException> {
                    bridge.invoke("nextInventory", args)
                }.code)
                fail(DeviceReadoutException(ErrorCode.ReadFailed, "Inventory callback failed."))
                assertEquals(ErrorCode.ReadFailed, assertIs<DeviceReadoutException>(waiting.await()).code)
                bridge.invoke("dispose", args)
                assertEquals(registered.await(), released.await())
                changed(EntityKind.Pressure)
                assertEquals(ErrorCode.EntityRemoved, assertFailsWith<DeviceReadoutException> {
                    bridge.invoke("nextInventory", args)
                }.code)
            }
        } finally { bridge.close() }
    }

    @Test fun eventWaitingRetainsDuplicatesAndNativePermissionFailures(): Unit = runBlocking {
        val ready = CompletableDeferred<Pair<(DeviceSnapshot) -> Unit, (Throwable) -> Unit>>()
        val rateSeen = CompletableDeferred<SensorSamplingRate>()
        val bridge = AndroidSensorBridge {
            DeviceAccess(object : DeviceCollector {
                override fun read(entity: EntityAddress): DeviceSnapshot = error("No state read is expected.")
                override fun list(kind: EntityKind) = listOf("event-sensor")
                override fun describe(sensor: EntityAddress) = SensorDescription(name = "Step fixture")
                override fun observe(entity: EntityAddress, rate: SensorSamplingRate,
                    emit: (DeviceSnapshot) -> Unit, fail: (Throwable) -> Unit): CollectorSubscription {
                    rateSeen.complete(rate); ready.complete(emit to fail)
                    return object : CollectorSubscription { override val pollingRequired = false; override fun close() {} }
                }
            })
        }
        try {
            withTimeout(5000) {
                val context = bridge.invoke("create", emptyMap<Any, Any>()) as Long
                val rows = bridge.invoke("list", mapOf("context" to context, "kind" to "StepDetected")) as List<*>
                val target = (rows.single() as Map<*, *>)["target"] as Long
                val session = bridge.invoke("open", mapOf("context" to context, "target" to target,
                    "timeoutMicros" to 200_000L, "hertz" to 60.0)) as Long
                val (emit, fail) = ready.await()
                assertIs<SensorSamplingRate.PlatformDefault>(rateSeen.await())
                val arguments = mapOf("context" to context, "session" to session)
                val next = async { bridge.invoke("next", arguments) as String }
                delay(300)
                assertFalse(next.isCompleted)
                assertEquals(ErrorCode.InvalidConfiguration,
                    assertFailsWith<DeviceReadoutException> { bridge.invoke("next", arguments) }.code)
                emit(StepDetectedSnapshot(value = true))
                assertTrue(next.await().contains("\"value\":true"))
                emit(StepDetectedSnapshot(value = true))
                assertTrue((bridge.invoke("next", arguments) as String).contains("\"value\":true"))
                fail(DeviceReadoutException(ErrorCode.PermissionDenied, "Permission revoked."))
                assertEquals(ErrorCode.PermissionDenied,
                    assertFailsWith<DeviceReadoutException> { bridge.invoke("next", arguments) }.code)
                bridge.invoke("close", arguments)
            }
        } finally { bridge.close() }
    }

    @Test fun inventoryRetiresRemovedTargetsAndRejectsCrossContextHandles(): Unit = runBlocking {
        var present = true
        val bridge = AndroidSensorBridge {
            DeviceAccess(object : DeviceCollector {
                override fun read(entity: EntityAddress): DeviceSnapshot = error("No state read is expected.")
                override fun list(kind: EntityKind) = if (present) listOf("sensor") else emptyList()
                override fun describe(sensor: EntityAddress) = SensorDescription(name = "Fixture")
            })
        }
        try {
            val context = bridge.invoke("create", emptyMap<Any, Any>()) as Long
            val other = bridge.invoke("create", emptyMap<Any, Any>()) as Long
            suspend fun list(): List<*> = bridge.invoke("list", mapOf("context" to context, "kind" to "Pressure")) as List<*>
            val first = (list().single() as Map<*, *>)["target"] as Long
            assertEquals(first, (list().single() as Map<*, *>)["target"])
            val request = mapOf("context" to other, "target" to first, "timeoutMicros" to 1_000_000L)
            assertEquals(ErrorCode.EntityRemoved,
                assertFailsWith<DeviceReadoutException> { bridge.invoke("open", request) }.code)
            present = false; assertTrue(list().isEmpty())
            assertEquals(ErrorCode.EntityRemoved,
                assertFailsWith<DeviceReadoutException> { bridge.invoke("open", request + ("context" to context)) }.code)
            present = true
            assertNotEquals(first, (list().single() as Map<*, *>)["target"])
            bridge.invoke("dispose", mapOf("context" to context))
            assertEquals(ErrorCode.EntityRemoved, assertFailsWith<DeviceReadoutException> { list() }.code)
        } finally { bridge.close() }
    }

    @Test fun cancellationDoesNotJoinNativeRegistrationAndLateResourcesAreReleased(): Unit = runBlocking {
        val started = CompletableDeferred<Thread>()
        val released = CompletableDeferred<Thread>()
        val gate = CountDownLatch(1)
        val bridge = AndroidSensorBridge {
            DeviceAccess(object : DeviceCollector {
                override fun read(entity: EntityAddress): DeviceSnapshot = error("No state read is expected.")
                override fun list(kind: EntityKind) = listOf("native-accelerometer")
                override fun describe(sensor: EntityAddress) = SensorDescription(name = "Fixture")
                override fun observe(entity: EntityAddress, rate: SensorSamplingRate,
                    emit: (DeviceSnapshot) -> Unit, fail: (Throwable) -> Unit): CollectorSubscription {
                    started.complete(Thread.currentThread())
                    // Model a native registration that cannot honor Java interruption.
                    val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(3)
                    while (gate.count != 0L && System.nanoTime() < deadline) {
                        try { gate.await(20, TimeUnit.MILLISECONDS) }
                        catch (_: InterruptedException) { /* Native call remains pending. */ }
                    }
                    check(gate.count == 0L)
                    return object : CollectorSubscription {
                        override val pollingRequired = false
                        override fun close() { released.complete(Thread.currentThread()) }
                    }
                }
            })
        }
        try {
            withTimeout(5000) {
                val context = bridge.invoke("create", emptyMap<Any, Any>()) as Long
                val rows = bridge.invoke("list", mapOf("context" to context, "kind" to "Accelerometer")) as List<*>
                val target = (rows.single() as Map<*, *>)["target"] as Long
                val session = bridge.invoke("open", mapOf("context" to context, "target" to target,
                    "timeoutMicros" to 2_000_000L, "hertz" to 60.0)) as Long
                val worker = started.await()
                assertNotEquals(Thread.currentThread(), worker)
                val pending = async { runCatching { bridge.invoke("next", mapOf("context" to context, "session" to session)) }.exceptionOrNull() }
                yield()
                withTimeout(200) { bridge.invoke("close", mapOf("context" to context, "session" to session)) }
                assertIs<CancellationException>(pending.await())
                assertFalse(released.isCompleted)
                gate.countDown()
                assertEquals(worker, released.await())
                bridge.invoke("dispose", mapOf("context" to context))
            }
        } finally { gate.countDown(); bridge.close() }
    }
}
