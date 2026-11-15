package dev.devicereadout

import kotlinx.coroutines.*
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.test.*

class NativeBindingInventoryTest {
    @Test fun appInventoryDoesNotHideNativeRemovalOrLoseItsOwnState(): Unit = runBlocking {
        val present = AtomicBoolean(true)
        val registered = CompletableDeferred<(EntityKind) -> Unit>()
        val endpoint = NativeBindingEndpoint(DeviceAccess(object : DeviceCollector {
            override fun read(entity: EntityAddress): DeviceSnapshot = CpuCoreSnapshot(logicalIndex = 7)
            override fun list(kind: EntityKind) = if (present.get()) listOf("core") else emptyList()
            override fun observeInventory(changed: (EntityKind) -> Unit, fail: (Throwable) -> Unit): CollectorSubscription {
                registered.complete(changed)
                return object : CollectorSubscription {
                    override val pollingRequired = false
                    override fun close() {}
                }
            }
        }))
        val collection = mapOf("kind" to "CpuCore")
        fun query(id: Int, operation: String, entity: Map<String, Any?> = collection) = endpoint.send(mapOf(
            "id" to id, "operation" to operation, "entity" to entity,
            "settings" to mapOf("readTimeoutMs" to 1000, "pollIntervalMs" to 100000)))
        fun observe(entity: Map<String, Any?>, value: Map<String, Any?>) = endpoint.send(mapOf(
            "id" to 0, "operation" to "observer", "entity" to entity, "value" to value))
        try {
            withTimeout(5000) {
                query(1, "list")
                val changed = registered.await()
                val first = endpoint.next()
                val token = Regex("native-\\d+").find(first)?.value ?: error(first)
                val native = collection + ("targetId" to token)
                val app = native + ("observed" to true)
                query(2, "watch", native)
                assertTrue(endpoint.next().contains("\"logicalIndex\":7"))
                observe(app, mapOf("type" to "register"))
                observe(app, mapOf("type" to "state", "values" to mapOf("logicalIndex" to 99)))
                query(3, "watch", app)
                assertTrue(endpoint.next().contains("\"logicalIndex\":99"))
                query(4, "list")
                assertTrue(endpoint.next().contains("\"value\":[{\"targetId\":\"$token\",\"observed\":true}]"))
                present.set(false)
                changed(EntityKind.CpuCore)
                val removed = endpoint.next()
                assertTrue(removed.contains("\"id\":2,") && removed.contains("EntityRemoved"), removed)
                observe(app, mapOf("type" to "state", "values" to mapOf("logicalIndex" to 100)))
                val stillObserved = endpoint.next()
                assertTrue(stillObserved.contains("\"id\":3,") && stillObserved.contains("\"logicalIndex\":100"), stillObserved)
                query(5, "get", native)
                assertTrue(endpoint.next().contains("EntityRemoved"))
                query(6, "get", app)
                assertTrue(endpoint.next().contains("\"logicalIndex\":100"))
                query(7, "list")
                assertTrue(endpoint.next().contains("\"value\":[{\"targetId\":\"$token\",\"observed\":true}]"))
            }
        } finally {endpoint.close()}
    }

    @Test fun collectorReportedCancellationIsAnInventoryFailureNotSilentObserverExit(): Unit = runBlocking {
        val registered = CompletableDeferred<(Throwable) -> Unit>()
        val released = CompletableDeferred<Unit>()
        val endpoint = NativeBindingEndpoint(DeviceAccess(object : DeviceCollector {
            override fun read(entity: EntityAddress): DeviceSnapshot = if (entity.kind == EntityKind.Ram)
                RamSnapshot(availableBytes = 42u) else CpuCoreSnapshot(logicalIndex = 7)
            override fun list(kind: EntityKind) = listOf("core")
            override fun observeInventory(changed: (EntityKind) -> Unit, fail: (Throwable) -> Unit): CollectorSubscription {
                registered.complete(fail)
                return object : CollectorSubscription {
                    override val pollingRequired = false
                    override fun close() {released.complete(Unit)}
                }
            }
        }))
        fun query(id: Int, operation: String, kind: String = "CpuCore", target: String? = null) = endpoint.send(mapOf(
            "id" to id, "operation" to operation, "entity" to mapOf("kind" to kind, "targetId" to target),
            "settings" to mapOf("readTimeoutMs" to 1000, "pollIntervalMs" to 100000)))
        try {
            withTimeout(5000) {
                query(1, "list")
                val fail = registered.await()
                val initial = endpoint.next()
                val target = Regex("native-\\d+").find(initial)?.value ?: error(initial)
                query(2, "watch", target = target)
                assertTrue(endpoint.next().contains("\"logicalIndex\":7"))
                fail(CancellationException("Native observer unexpectedly stopped."))
                val error = endpoint.next()
                assertTrue(error.contains("\"id\":2,") && error.contains("ReadFailed"), error)
                released.await()
                query(3, "get", "Ram")
                assertTrue(endpoint.next().contains("\"availableBytes\":\"42\""))
                query(4, "list")
                assertTrue(endpoint.next().contains("ReadFailed"), "A failed observation must not silently restart.")
            }
        } finally {endpoint.close()}
    }

    @Test fun synchronousInventoryObserverFailureRejectsTheInitialDiscovery(): Unit = runBlocking {
        val listed = java.util.concurrent.atomic.AtomicInteger()
        val released = CompletableDeferred<Unit>()
        val endpoint = NativeBindingEndpoint(DeviceAccess(object : DeviceCollector {
            override fun read(entity: EntityAddress): DeviceSnapshot = error("No read expected.")
            override fun list(kind: EntityKind): List<String> {listed.incrementAndGet();return listOf("motion")}
            override fun observeInventory(changed: (EntityKind) -> Unit, fail: (Throwable) -> Unit): CollectorSubscription {
                fail(DeviceReadoutException(ErrorCode.PermissionDenied, "Inventory access revoked during registration."))
                return object : CollectorSubscription {
                    override val pollingRequired = false
                    override fun close() {released.complete(Unit)}
                }
            }
        }))
        try {
            withTimeout(3000) {
                endpoint.send(mapOf("id" to 1, "operation" to "list", "entity" to mapOf("kind" to "Accelerometer"),
                    "settings" to mapOf("readTimeoutMs" to 1000, "pollIntervalMs" to 1000)))
                val response = endpoint.next()
                assertTrue(response.contains("\"type\":\"error\"") && response.contains("PermissionDenied"), response)
                assertEquals(0, listed.get(), "A failed registration must not publish a successful inventory.")
                released.await()
            }
        } finally {endpoint.close()}
    }

    @Test fun inventoryRegistrationDeadlineAndCloseDoNotWaitForBlockedNativeWork(): Unit = runBlocking {
        val entered = CompletableDeferred<Unit>()
        val released = CompletableDeferred<Thread>()
        val gate = CountDownLatch(1)
        val caller = Thread.currentThread()
        val endpoint = NativeBindingEndpoint(DeviceAccess(object : DeviceCollector {
            override fun read(entity: EntityAddress): DeviceSnapshot = error("No data collection expected.")
            override fun list(kind: EntityKind) = listOf("motion")
            override fun observeInventory(changed: (EntityKind) -> Unit, fail: (Throwable) -> Unit): CollectorSubscription {
                assertNotEquals(caller, Thread.currentThread())
                entered.complete(Unit)
                val limit = System.nanoTime() + TimeUnit.SECONDS.toNanos(3)
                while (gate.count != 0L && System.nanoTime() < limit) {
                    try {gate.await(20, TimeUnit.MILLISECONDS)} catch (_: InterruptedException) {}
                }
                return object : CollectorSubscription {
                    override val pollingRequired = false
                    override fun close() {released.complete(Thread.currentThread())}
                }
            }
        }))
        try {
            withTimeout(5000) {
                endpoint.send(mapOf("id" to 1, "operation" to "list", "entity" to mapOf("kind" to "Accelerometer"),
                    "settings" to mapOf("readTimeoutMs" to 100, "pollIntervalMs" to 1000)))
                entered.await()
                val response = withTimeout(1000) {endpoint.next()}
                assertTrue(response.contains("ReadTimeout"), response)
                assertFalse(released.isCompleted, "Native registration is still held by the fixture.")
                endpoint.close()
                assertFalse(released.isCompleted, "Close must return before native registration finishes.")
                gate.countDown()
                assertNotEquals(caller, released.await())
            }
        } finally {gate.countDown();endpoint.close()}
    }

    @Test fun failedInventoryRefreshPreservesTheHandleAndLeavesSingletonReadsAlive(): Unit = runBlocking {
        val invalid = AtomicBoolean(false)
        val registered = CompletableDeferred<(EntityKind) -> Unit>()
        val endpoint = NativeBindingEndpoint(DeviceAccess(object : DeviceCollector {
            override fun read(entity: EntityAddress): DeviceSnapshot = if (entity.kind == EntityKind.Ram)
                RamSnapshot(availableBytes = 42u) else CpuCoreSnapshot(logicalIndex = 7)
            override fun list(kind: EntityKind) = if (invalid.get()) listOf("core", "core") else listOf("core")
            override fun observeInventory(changed: (EntityKind) -> Unit, fail: (Throwable) -> Unit): CollectorSubscription {
                registered.complete(changed)
                return object : CollectorSubscription {
                    override val pollingRequired = false
                    override fun close() {}
                }
            }
        }))
        fun query(id: Int, operation: String, kind: String = "CpuCore", target: String? = null) = endpoint.send(mapOf(
            "id" to id, "operation" to operation, "entity" to mapOf("kind" to kind, "targetId" to target),
            "settings" to mapOf("readTimeoutMs" to 1000, "pollIntervalMs" to 100000)))
        try {
            withTimeout(5000) {
                query(1, "list")
                val changed = registered.await()
                val initial = endpoint.next()
                val target = Regex("native-\\d+").find(initial)?.value ?: error(initial)
                query(2, "watch", target = target)
                assertTrue(endpoint.next().contains("\"logicalIndex\":7"))
                invalid.set(true)
                changed(EntityKind.CpuCore)
                val failed = endpoint.next()
                assertTrue(failed.contains("\"id\":2,") && failed.contains("ReadFailed"), failed)
                assertFalse(failed.contains("EntityRemoved"), "Failed discovery is not evidence of removal.")
                query(3, "get", "Ram")
                assertTrue(endpoint.next().contains("\"availableBytes\":\"42\""))
                query(4, "get", target = target)
                assertTrue(endpoint.next().contains("ReadFailed"))
                invalid.set(false)
                query(5, "list")
                assertEquals(target, Regex("native-\\d+").find(endpoint.next())?.value)
                query(6, "get", target = target)
                assertTrue(endpoint.next().contains("\"logicalIndex\":7"))
            }
        } finally {endpoint.close()}
    }

    @Test fun nativeInventoryNotificationRetiresAnInactiveSensorWithoutAnotherList(): Unit = runBlocking {
        val caller = Thread.currentThread()
        val present = AtomicBoolean(true)
        val registered = CompletableDeferred<(EntityKind) -> Unit>()
        val released = CompletableDeferred<Thread>()
        val endpoint = NativeBindingEndpoint(DeviceAccess(object : DeviceCollector {
            override fun read(entity: EntityAddress): DeviceSnapshot {
                assertEquals(EntityKind.Ram, entity.kind)
                return RamSnapshot(availableBytes = 42u)
            }
            override fun list(kind: EntityKind) = if (present.get()) listOf("motion") else emptyList()
            override fun observeInventory(changed: (EntityKind) -> Unit, fail: (Throwable) -> Unit): CollectorSubscription {
                assertNotEquals(caller, Thread.currentThread())
                registered.complete(changed)
                return object : CollectorSubscription {
                    override val pollingRequired = false
                    override fun close() {released.complete(Thread.currentThread())}
                }
            }
        }))
        fun query(id: Int, operation: String, kind: String, target: String? = null) = endpoint.send(mapOf(
            "id" to id, "operation" to operation, "entity" to mapOf("kind" to kind, "targetId" to target),
            "settings" to mapOf("readTimeoutMs" to 1000, "pollIntervalMs" to 100000)))
        try {
            withTimeout(5000) {
                assertFalse(registered.isCompleted, "Construction must be inert.")
                query(1, "get", "Ram")
                assertTrue(endpoint.next().contains("\"availableBytes\":\"42\""))
                assertFalse(registered.isCompleted, "A singleton read must not observe inventories.")
                query(2, "list", "Accelerometer")
                val changed = registered.await()
                val response = endpoint.next()
                val target = Regex("native-\\d+").find(response)?.value ?: error(response)
                endpoint.send(mapOf("id" to 0, "operation" to "observer", "value" to mapOf("type" to "sensorActivity", "active" to false)))
                query(3, "watch", "Accelerometer", target)
                assertTrue(endpoint.next().contains("\"type\":\"suspended\""))
                present.set(false)
                changed(EntityKind.Accelerometer)
                val removed = endpoint.next()
                assertTrue(removed.contains("\"id\":3,") && removed.contains("EntityRemoved"), removed)
                query(4, "get", "Accelerometer", target)
                assertTrue(endpoint.next().contains("EntityRemoved"))
                query(5, "get", "Ram")
                assertTrue(endpoint.next().contains("\"availableBytes\":\"42\""))
                endpoint.close()
                assertNotEquals(caller, released.await(), "Native inventory cleanup must stay off the caller.")
            }
        } finally {endpoint.close()}
    }
}
