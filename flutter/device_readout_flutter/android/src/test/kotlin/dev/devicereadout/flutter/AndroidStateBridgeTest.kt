package dev.devicereadout.flutter

import dev.devicereadout.*
import kotlinx.coroutines.*
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import kotlin.test.*

class AndroidStateBridgeTest {
    @Test fun capabilitiesProbeSupportWithoutReadingOrStartingObservation(): Unit = runBlocking {
        val reads = AtomicInteger()
        val present = AtomicBoolean(true)
        val bridge = AndroidStateBridge {
            DeviceAccess(object : DeviceCollector {
                override fun capabilities(entity: EntityAddress): EntityCapabilities = when (entity.kind) {
                    EntityKind.Ram -> EntityCapabilities(true, true)
                    EntityKind.CpuCore -> EntityCapabilities(entity.targetId == null || entity.targetId == "core", null)
                    else -> EntityCapabilities(null, null)
                }
                override fun list(kind: EntityKind) = if (present.get()) listOf("core") else emptyList()
                override fun read(entity: EntityAddress): DeviceSnapshot {
                    reads.incrementAndGet()
                    throw DeviceReadoutException(ErrorCode.PermissionDenied, "Test app denies reads.")
                }
                override fun observeReads(entity: EntityAddress, emit: (() -> DeviceSnapshot) -> Unit,
                    fail: (Throwable) -> Unit): CollectorSubscription = error("Capabilities must not observe.")
            })
        }
        try {
            withTimeout(5000) {
                val context = bridge.invoke("create", emptyMap<Any, Any>()) as Long
                val other = bridge.invoke("create", emptyMap<Any, Any>()) as Long
                val args = mapOf("context" to context, "entity" to "Ram", "request" to 1L,
                    "timeoutMicros" to 1_000_000L)
                assertEquals(mapOf("readable" to true, "watchable" to true), bridge.invoke("capabilities", args))
                assertEquals(mapOf("readable" to null, "watchable" to null),
                    bridge.invoke("capabilities", args + ("entity" to "NetworkPath")))
                for (kind in listOf("Display", "Accelerometer", "ProcessMemory")) {
                    assertEquals(mapOf("readable" to false, "watchable" to false),
                        bridge.invoke("capabilities", args + ("entity" to kind)))
                }
                val cores = args + ("entity" to "CpuCore")
                assertEquals(mapOf("readable" to true, "watchable" to null), bridge.invoke("capabilities", cores))
                val target = (bridge.invoke("list", cores) as List<*>).single()
                val selected = cores + ("target" to target)
                assertEquals(mapOf("readable" to true, "watchable" to null), bridge.invoke("capabilities", selected))
                assertEquals(ErrorCode.EntityRemoved, assertFailsWith<DeviceReadoutException> {
                    bridge.invoke("capabilities", selected + ("context" to other))
                }.code)
                assertEquals(ErrorCode.InvalidConfiguration, assertFailsWith<DeviceReadoutException> {
                    bridge.invoke("capabilities", selected + ("entity" to "Ram"))
                }.code)
                assertEquals(ErrorCode.InvalidConfiguration, assertFailsWith<DeviceReadoutException> {
                    bridge.invoke("capabilities", args + ("entity" to "InventedKind"))
                }.code)
                assertEquals(0, reads.get())
                assertEquals(ErrorCode.PermissionDenied, assertFailsWith<DeviceReadoutException> {
                    bridge.invoke("read", args)
                }.code)
                present.set(false)
                bridge.invoke("list", cores)
                assertEquals(ErrorCode.EntityRemoved, assertFailsWith<DeviceReadoutException> {
                    bridge.invoke("capabilities", selected)
                }.code)
            }
        } finally { bridge.close() }
    }

    @Test fun discoveredStateTargetsKeepSelectionAndRetireRemovedGenerations(): Unit = runBlocking {
        val present = AtomicBoolean(true)
        val bridge = AndroidStateBridge {
            DeviceAccess(object : DeviceCollector {
                override fun list(kind: EntityKind) = if (present.get()) listOf("core-a", "core-b") else emptyList()
                override fun current(kind: EntityKind) = if (present.get()) "core-b" else null
                override fun read(entity: EntityAddress): DeviceSnapshot = CpuCoreSnapshot(
                    logicalIndex = if (entity.targetId == "core-b") 7 else 4)
            })
        }
        try {
            withTimeout(5000) {
                val context = bridge.invoke("create", emptyMap<Any, Any>()) as Long
                val other = bridge.invoke("create", emptyMap<Any, Any>()) as Long
                val args = mapOf("context" to context, "entity" to "CpuCore", "request" to 1L,
                    "timeoutMicros" to 1_000_000L)
                val found = bridge.invoke("list", args) as List<*>
                assertEquals(2, found.size)
                assertEquals(found, bridge.invoke("list", args))
                assertEquals(found.last(), bridge.invoke("current", args))
                val selected = args + ("target" to found.last())
                assertTrue((bridge.invoke("read", selected) as String).contains("\"logicalIndex\":7"))
                assertEquals(ErrorCode.EntityRemoved, assertFailsWith<DeviceReadoutException> {
                    bridge.invoke("read", selected + ("context" to other))
                }.code)
                assertEquals(ErrorCode.InvalidConfiguration, assertFailsWith<DeviceReadoutException> {
                    bridge.invoke("read", selected + ("entity" to "Battery"))
                }.code)
                val session = bridge.invoke("open", selected + ("pollMicros" to 20_000L)) as Long
                val next = mapOf("context" to context, "session" to session)
                repeat(2) { assertTrue((bridge.invoke("next", next) as String).contains("\"logicalIndex\":7")) }
                bridge.invoke("close", next)
                present.set(false)
                assertEquals(emptyList<Any>(), bridge.invoke("list", args))
                assertNull(bridge.invoke("current", args))
                assertEquals(ErrorCode.EntityRemoved, assertFailsWith<DeviceReadoutException> {
                    bridge.invoke("read", selected)
                }.code)
                present.set(true)
                assertNotEquals(found, bridge.invoke("list", args))
                bridge.invoke("dispose", mapOf("context" to context))
            }
        } finally { bridge.close() }
    }

    @Test fun stateRequestsCancellationAndDeadlineDoNotJoinNativeWork(): Unit = runBlocking {
        for (method in listOf("read", "list", "current", "capabilities")) for (cancelExplicitly in listOf(true, false)) {
            val gate = CountDownLatch(1)
            val entered = CompletableDeferred<Thread>()
            val returned = CompletableDeferred<Unit>()
            val bridge = AndroidStateBridge {
                DeviceAccess(object : DeviceCollector {
                    private fun waitForNative() {
                        entered.complete(Thread.currentThread())
                        // A native read can outlive both cancellation and its deadline.
                        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(3)
                        while (gate.count != 0L && System.nanoTime() < deadline) {
                            try { gate.await(20, TimeUnit.MILLISECONDS) }
                            catch (_: InterruptedException) { /* Native work is still pending. */ }
                        }
                        check(gate.count == 0L)
                        returned.complete(Unit)
                    }
                    override fun read(entity: EntityAddress): DeviceSnapshot {
                        waitForNative(); return RamSnapshot(availableBytes = 7uL)
                    }
                    override fun list(kind: EntityKind): List<String> { waitForNative(); return listOf("core") }
                    override fun current(kind: EntityKind): String? { waitForNative(); return "core" }
                    override fun capabilities(entity: EntityAddress): EntityCapabilities {
                        waitForNative(); return EntityCapabilities(true, true)
                    }
                })
            }
            try {
                withTimeout(5000) {
                    val context = bridge.invoke("create", emptyMap<Any, Any>()) as Long
                    val args = mapOf("context" to context, "entity" to if (method == "read") "Ram" else "CpuCore", "request" to 1L,
                        "timeoutMicros" to if (cancelExplicitly) 2_000_000L else 80_000L)
                    val pending = async { runCatching { bridge.invoke(method, args) }.exceptionOrNull() }
                    assertNotEquals(Thread.currentThread(), entered.await())
                    if (cancelExplicitly) {
                        withTimeout(200) { bridge.invoke("cancelRead", args) }
                        withTimeout(200) { assertFailsWith<CancellationException> { pending.await() } }
                    } else {
                        val error = withTimeout(300) { pending.await() }
                        assertEquals(ErrorCode.ReadTimeout, assertIs<DeviceReadoutException>(error).code)
                    }
                    assertFalse(returned.isCompleted, "Caller completion cannot wait for the native read.")
                    withTimeout(200) { bridge.invoke("dispose", mapOf("context" to context)) }
                    assertFalse(returned.isCompleted, "Context disposal cannot join native work either.")
                    gate.countDown()
                    returned.await()
                    assertEquals(ErrorCode.EntityRemoved,
                        assertFailsWith<DeviceReadoutException> { bridge.invoke(method, args) }.code)
                }
            } finally { gate.countDown(); bridge.close() }
        }
    }

    @Test fun stateReadAndNativeEventsKeepTheirSettingsAndFailures(): Unit = runBlocking {
        val changes = CompletableDeferred<((() -> DeviceSnapshot) -> Unit)>()
        val failure = CompletableDeferred<(Throwable) -> Unit>()
        val released = CompletableDeferred<Unit>()
        val bridge = AndroidStateBridge {
            DeviceAccess(object : DeviceCollector {
                override fun read(entity: EntityAddress): DeviceSnapshot = RamSnapshot(availableBytes = 7uL)
                override fun observeReads(entity: EntityAddress, emit: (() -> DeviceSnapshot) -> Unit,
                    fail: (Throwable) -> Unit): CollectorSubscription {
                    changes.complete(emit); failure.complete(fail)
                    return object : CollectorSubscription {
                        override val pollingRequired = false
                        override fun close() { released.complete(Unit) }
                    }
                }
            })
        }
        try {
            withTimeout(5000) {
                val context = bridge.invoke("create", emptyMap<Any, Any>()) as Long
                val parameters = mapOf("context" to context, "entity" to "Ram", "timeoutMicros" to 80_000L)
                assertTrue((bridge.invoke("read", parameters + ("request" to 1L)) as String).contains("\"availableBytes\":\"7\""))
                val session = bridge.invoke("open", parameters + ("pollMicros" to 10_000_000L)) as Long
                val nextArgs = mapOf("context" to context, "session" to session)
                assertTrue((bridge.invoke("next", nextArgs) as String).contains("\"availableBytes\":\"7\""))
                val next = async { bridge.invoke("next", nextArgs) as String }
                delay(130)
                assertFalse(next.isCompleted, "Waiting for a native state change has no idle read timeout or forced poll.")
                changes.await().invoke { RamSnapshot(availableBytes = 7uL) }
                assertTrue(next.await().contains("\"availableBytes\":\"7\""))
                failure.await().invoke(DeviceReadoutException(ErrorCode.PermissionDenied, "App policy changed."))
                assertEquals(ErrorCode.PermissionDenied,
                    assertFailsWith<DeviceReadoutException> { bridge.invoke("next", nextArgs) }.code)
                bridge.invoke("close", nextArgs)
                released.await()
                bridge.invoke("dispose", mapOf("context" to context))
            }
        } finally { bridge.close() }
    }
}
