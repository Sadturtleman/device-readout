package dev.devicereadout

import kotlinx.coroutines.*
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.test.*

class NativeBindingContractTest {
    @Test fun observedNativeRemovalEndsOnlyTheOldTargetStream(): Unit = runBlocking {
        val present = java.util.concurrent.atomic.AtomicBoolean(true)
        val observations = kotlinx.coroutines.channels.Channel<Pair<String, (DeviceSnapshot) -> Unit>>(4)
        val releases = kotlinx.coroutines.channels.Channel<String>(4)
        val endpoint = NativeBindingEndpoint(DeviceAccess(object : DeviceCollector {
            override fun list(kind: EntityKind) = if (present.get()) listOf("first", "sibling") else listOf("sibling")
            override fun read(entity: EntityAddress): DeviceSnapshot = CpuCoreSnapshot(logicalIndex = if (entity.targetId == "first") 7 else 8)
            override fun observe(entity: EntityAddress, rate: SensorSamplingRate, emit: (DeviceSnapshot) -> Unit, fail: (Throwable) -> Unit): CollectorSubscription {
                observations.trySend(requireNotNull(entity.targetId) to emit)
                return object : CollectorSubscription {
                    override val pollingRequired = false
                    override fun close() {releases.trySend(requireNotNull(entity.targetId))}
                }
            }
        }))
        fun query(id: Int, operation: String, target: String? = null) = endpoint.send(mapOf(
            "id" to id, "operation" to operation, "entity" to mapOf("kind" to "CpuCore", "targetId" to target),
            "settings" to mapOf("readTimeoutMs" to 1000, "pollIntervalMs" to 100000)))
        fun targets(json: String) = Regex("native-\\d+").findAll(json).map {it.value}.toList()
        try {
            withTimeout(5000) {
                query(1, "list")
                val initial = targets(endpoint.next())
                assertEquals(2, initial.size)
                query(2, "watch", initial[0])
                val old = observations.receive()
                assertEquals("first", old.first)
                assertTrue(endpoint.next().contains("\"logicalIndex\":7"))
                query(3, "watch", initial[1])
                val sibling = observations.receive()
                assertTrue(endpoint.next().contains("\"logicalIndex\":8"))

                present.set(false)
                query(4, "list")
                val removed = listOf(endpoint.next(), endpoint.next())
                assertTrue(removed.any {it.contains("\"id\":2,") && it.contains("EntityRemoved")}, removed.toString())
                assertTrue(removed.any {it.contains("\"id\":4,") && targets(it) == listOf(initial[1])}, removed.toString())
                assertEquals("first", releases.receive())

                // A late callback cannot resurrect a removed stream or affect its sibling.
                old.second(CpuCoreSnapshot(logicalIndex = 99))
                sibling.second(CpuCoreSnapshot(logicalIndex = 9))
                val surviving = endpoint.next()
                assertTrue(surviving.contains("\"id\":3,") && surviving.contains("\"logicalIndex\":9"), surviving)
                present.set(true)
                query(5, "list")
                val replacement = targets(endpoint.next())
                assertEquals(initial[1], replacement[1])
                assertNotEquals(initial[0], replacement[0])
                query(6, "get", initial[0])
                assertTrue(endpoint.next().contains("EntityRemoved"))
                query(7, "get", replacement[0])
                assertTrue(endpoint.next().contains("\"logicalIndex\":7"))
            }
        } finally {endpoint.close()}
    }

    @Test fun inactiveBindingSensorsStillReceiveObserverFailureAndRemoval(): Unit = runBlocking {
        for (removed in listOf(false, true)) {
            val endpoint = NativeBindingEndpoint(DeviceAccess(object : DeviceCollector {
                override fun read(entity: EntityAddress): DeviceSnapshot = error("Inactive sensor must not collect.")
            }))
            val entity = mapOf("kind" to "Accelerometer", "targetId" to "motion", "observed" to true)
            fun observe(value: Map<String, Any?>) = endpoint.send(mapOf("id" to 0, "operation" to "observer", "entity" to entity, "value" to value))
            try {
                withTimeout(1500) {
                    observe(mapOf("type" to "register"))
                    observe(mapOf("type" to "sensorActivity", "active" to false))
                    endpoint.send(mapOf("id" to 1, "operation" to "watch", "entity" to entity, "settings" to mapOf("readTimeoutMs" to 50, "pollIntervalMs" to 1000)))
                    assertTrue(endpoint.next().contains("\"type\":\"suspended\""))
                    if (removed) observe(mapOf("type" to "remove"))
                    else observe(mapOf("type" to "failure", "error" to mapOf("code" to "PermissionDenied", "message" to "Permission revoked while hidden.")))
                    val response = endpoint.next()
                    assertTrue(response.contains(if (removed) "EntityRemoved" else "PermissionDenied"), response)
                }
            } finally {endpoint.close()}
        }
    }

    @Test fun bindingLifecycleSuspendsSampleDeadlinesAndReleasesNativeObservations(): Unit = runBlocking {
        val started = kotlinx.coroutines.channels.Channel<(DeviceSnapshot) -> Unit>(4)
        val released = kotlinx.coroutines.channels.Channel<Unit>(4)
        val endpoint = NativeBindingEndpoint(DeviceAccess(object : DeviceCollector {
            override fun list(kind: EntityKind) = listOf("motion")
            override fun read(entity: EntityAddress): DeviceSnapshot = error("Sensors need an observation.")
            override fun observe(entity: EntityAddress, rate: SensorSamplingRate, emit: (DeviceSnapshot) -> Unit, fail: (Throwable) -> Unit): CollectorSubscription {
                started.trySend(emit)
                return object : CollectorSubscription {
                    override val pollingRequired = false
                    override fun close() {released.trySend(Unit)}
                }
            }
        }))
        fun activity(active: Boolean) = endpoint.send(mapOf("id" to 0, "operation" to "observer", "value" to mapOf("type" to "sensorActivity", "active" to active)))
        val settings = mapOf("readTimeoutMs" to 250, "pollIntervalMs" to 1000)
        try {
            withTimeout(5000) {
                endpoint.send(mapOf("id" to 1, "operation" to "list", "entity" to mapOf("kind" to "Accelerometer"), "settings" to settings))
                val inventory = endpoint.next()
                val target = Regex("\"value\":\\[\"([^\"]+)\"\\]").find(inventory)?.groupValues?.get(1) ?: error(inventory)
                activity(false)
                endpoint.send(mapOf("id" to 2, "operation" to "watch", "entity" to mapOf("kind" to "Accelerometer", "targetId" to target), "settings" to settings))
                assertTrue(endpoint.next().contains("\"type\":\"suspended\""))
                delay(300)
                assertTrue(started.tryReceive().isFailure)
                activity(true)
                assertTrue(endpoint.next().contains("\"type\":\"reading\""))
                val first = started.receive()
                first(AccelerometerSnapshot(value = Vector3(1.0, 0.0, 0.0)))
                assertTrue(endpoint.next().contains("\"x\":1.0"))
                activity(false)
                assertTrue(endpoint.next().contains("\"type\":\"suspended\""))
                released.receive()
                first(AccelerometerSnapshot(value = Vector3(99.0, 0.0, 0.0)))
                delay(300)
                activity(true)
                assertTrue(endpoint.next().contains("\"type\":\"reading\""))
                started.receive()(AccelerometerSnapshot(value = Vector3(2.0, 0.0, 0.0)))
                assertTrue(endpoint.next().contains("\"x\":2.0"))
                endpoint.send(mapOf("id" to 2, "operation" to "cancel"))
                released.receive()
            }
        } finally {endpoint.close()}
    }

    @Test fun observedJsonSnapshotsKeepExactValuesAndNullUnknownEnums(): Unit = runBlocking {
        val endpoint = NativeBindingEndpoint(DeviceAccess(object : DeviceCollector {
            override fun read(entity: EntityAddress): DeviceSnapshot = error("Read must use observed state.")
        }))
        var sequence = 0
        suspend fun read(kind: String, values: Map<String, Any?>): String {
            val entity = mapOf("kind" to kind)
            endpoint.send(mapOf("id" to 0, "operation" to "observer", "entity" to entity, "value" to mapOf("type" to "state", "values" to values)))
            endpoint.send(mapOf("id" to ++sequence, "operation" to "get", "entity" to entity, "settings" to mapOf("readTimeoutMs" to 1000, "pollIntervalMs" to 1000)))
            return endpoint.next()
        }
        try {
            withTimeout(5000) {
                val ram = read("Ram", mapOf("physicalBytes" to "9007199254740993", "availableBytes" to "0", "lowMemory" to false, "collectedAt" to "1970-01-01T00:00:00Z"))
                assertTrue(ram.contains("\"physicalBytes\":\"9007199254740993\""), ram)
                assertTrue(ram.contains("\"availableBytes\":\"0\""), ram)
                assertTrue(ram.contains("\"lowMemory\":false"), ram)
                assertFalse(ram.contains("1970-01-01"), ram)
                assertTrue(read("Ram", mapOf("physicalBytes" to 9007199254740992.0)).contains("\"physicalBytes\":null"))
                assertTrue(read("NetworkPath", mapOf("transports" to listOf("Wifi", "FutureTransport"))).contains("\"transports\":null"))
                assertTrue(read("NetworkPath", mapOf("transports" to emptyList<String>())).contains("\"transports\":[]"))
                assertTrue(read("Power", mapOf("thermalState" to "AndroidThermalState.Severe")).contains("\"thermalState\":\"AndroidThermalState.Severe\""))
                val storage = read("OriginStorage", mapOf("usageByCategory" to mapOf("IndexedDB" to "9007199254740993", "Caches" to "0")))
                assertTrue(storage.contains("\"usageByCategory\":{\"IndexedDB\":\"9007199254740993\",\"Caches\":\"0\"}"), storage)
            }
        } finally {endpoint.close()}
    }

    @Test fun nativeBindingSeparatesAppAliasesAndCoordinatesObservedPermissionState(): Unit = runBlocking {
        val endpoint = NativeBindingEndpoint(DeviceAccess(object : DeviceCollector {
            override fun list(kind: EntityKind) = listOf("shared-name")
            override fun read(entity: EntityAddress): DeviceSnapshot = CpuCoreSnapshot(logicalIndex = 7)
        }))
        var sequence = 0
        val collection = mapOf("kind" to "CpuCore")
        fun query(operation: String, entity: Map<String, Any?> = collection): Int {
            val id = ++sequence
            endpoint.send(mapOf("id" to id, "operation" to operation, "entity" to entity,
                "settings" to mapOf("readTimeoutMs" to 50, "pollIntervalMs" to 100000)))
            return id
        }
        fun observe(entity: Map<String, Any?>, value: Map<String, Any?>) = endpoint.send(mapOf("id" to 0, "operation" to "observer", "entity" to entity, "value" to value))
        try {
            withTimeout(5000) {
                query("list")
                val inventory = endpoint.next()
                val id = Regex("\"value\":\\[\"([^\"]+)\"\\]").find(inventory)?.groupValues?.get(1) ?: error(inventory)
                val native = collection + ("targetId" to id)
                val app = native + ("observed" to true)
                observe(app, mapOf("type" to "register"))
                observe(app, mapOf("type" to "state", "values" to mapOf("logicalIndex" to 99)))
                observe(collection, mapOf("type" to "current", "targetId" to id, "observed" to true))
                query("current")
                assertTrue(endpoint.next().contains("\"value\":{\"targetId\":\"$id\",\"observed\":true}"))
                query("list")
                assertTrue(endpoint.next().contains("\"value\":[{\"targetId\":\"$id\",\"observed\":true}]"))
                query("get", native)
                assertTrue(endpoint.next().contains("\"logicalIndex\":7"))
                query("get", app)
                assertTrue(endpoint.next().contains("\"logicalIndex\":99"))
                observe(app, mapOf("type" to "permission", "status" to "NotDetermined"))
                query("permissions.check", app)
                assertTrue(endpoint.next().contains("\"value\":\"NotDetermined\""))
                val permissionId = query("permissions.request", app)
                assertTrue(endpoint.next().contains("\"type\":\"permissionRequest\""))
                val waiting = async {endpoint.next()}
                delay(100)
                assertFalse(waiting.isCompleted, "App permission response has no read deadline.")
                observe(app, mapOf("type" to "permission", "status" to "Granted"))
                val granted = waiting.await()
                assertTrue(granted.contains("\"id\":$permissionId,"), granted)
                assertTrue(granted.contains("\"value\":\"Granted\""), granted)
                query("permissions.check", native)
                assertTrue(endpoint.next().contains("\"value\":null"))
                observe(app, mapOf("type" to "failure", "error" to mapOf("code" to "PermissionDenied", "message" to "App observation failed.")))
                query("get", app)
                assertTrue(endpoint.next().contains("PermissionDenied"))
                query("get", native)
                assertTrue(endpoint.next().contains("\"logicalIndex\":7"))
            }
        } finally {endpoint.close()}
    }

    @Test fun observedScreenSnapshotsAndRemovalNeverReadTheNativeScreen(): Unit = runBlocking {
        val endpoint = NativeBindingEndpoint(DeviceAccess(object : DeviceCollector {
            override fun read(entity: EntityAddress): DeviceSnapshot = error("A screen read must use the app observer.")
        }))
        val entity = mapOf("kind" to "Display", "targetId" to "app-screen", "observed" to true)
        fun observe(value: Map<String, Any?>) = endpoint.send(mapOf("id" to 0, "operation" to "observer", "entity" to entity, "value" to value))
        fun query(id: Int, operation: String) = endpoint.send(mapOf("id" to id, "operation" to operation, "entity" to entity,
            "settings" to mapOf("readTimeoutMs" to 1000, "pollIntervalMs" to 100000)))
        try {
            withTimeout(5000) {
                observe(mapOf("type" to "register"))
                observe(mapOf("type" to "state", "values" to mapOf("label" to "First", "pixelSize" to mapOf("width" to 1920, "height" to 1080))))
                query(1, "get")
                val first = endpoint.next()
                assertTrue(first.contains("\"label\":\"First\""), first)
                assertTrue(first.contains("\"pixelSize\":{\"width\":1920,\"height\":1080}"), first)
                query(2, "watch")
                assertTrue(endpoint.next().contains("First"))
                observe(mapOf("type" to "state", "values" to mapOf("label" to "Changed")))
                assertTrue(endpoint.next().contains("Changed"))
                observe(mapOf("type" to "remove"))
                assertTrue(endpoint.next().contains("EntityRemoved"))
                query(3, "get")
                assertTrue(endpoint.next().contains("EntityRemoved"))
            }
        } finally {endpoint.close()}
    }

    @Test fun bindingDeadlineAndCloseDoNotJoinBlockedNativeCollection(): Unit = runBlocking {
        val entered = CompletableDeferred<Unit>()
        val completed = CompletableDeferred<Unit>()
        val gate = CountDownLatch(1)
        val endpoint = NativeBindingEndpoint(DeviceAccess(object : DeviceCollector {
            override fun read(entity: EntityAddress): DeviceSnapshot {
                entered.complete(Unit)
                val limit = System.nanoTime() + TimeUnit.SECONDS.toNanos(3)
                while (gate.count != 0L && System.nanoTime() < limit) {
                    try {gate.await(20, TimeUnit.MILLISECONDS)} catch (_: InterruptedException) {}
                }
                completed.complete(Unit)
                return RamSnapshot(availableBytes = 0u)
            }
        }))
        try {
            withTimeout(5000) {
                endpoint.send(mapOf("id" to 1, "operation" to "get", "entity" to mapOf("kind" to "Ram"),
                    "settings" to mapOf("readTimeoutMs" to 80, "pollIntervalMs" to 1000)))
                entered.await()
                assertTrue(withTimeout(1000) {endpoint.next()}.contains("ReadTimeout"))
                assertFalse(completed.isCompleted)
                endpoint.close()
                assertFalse(completed.isCompleted)
                gate.countDown();completed.await()
            }
        } finally {gate.countDown();endpoint.close()}
    }

    @Test fun nativeDiscoveryKeepsLiveHandlesAndRetiresObservedGenerations(): Unit = runBlocking {
        var present = true
        val endpoint = NativeBindingEndpoint(DeviceAccess(object : DeviceCollector {
            override fun read(entity: EntityAddress): DeviceSnapshot = CpuCoreSnapshot(logicalIndex = 7)
            override fun list(kind: EntityKind) = if (present) listOf("cpu-seven") else emptyList()
            override fun current(kind: EntityKind) = if (present) "cpu-seven" else null
        }))
        var sequence = 0
        suspend fun request(operation: String, target: String? = null): String {
            endpoint.send(mapOf("id" to ++sequence, "operation" to operation,
                "entity" to mapOf("kind" to "CpuCore", "targetId" to target),
                "settings" to mapOf("readTimeoutMs" to 1000, "pollIntervalMs" to 20)))
            return endpoint.next()
        }
        fun target(json: String): String = Regex("\"value\":\\[\"([^\"]+)\"\\]").find(json)?.groupValues?.get(1) ?: error(json)
        try {
            withTimeout(5000) {
                val first = target(request("list"))
                assertEquals(first, target(request("list")))
                assertTrue(request("current").contains("\"value\":\"$first\""))
                assertTrue(request("get", first).contains("\"logicalIndex\":7"))
                present = false
                assertTrue(request("list").contains("\"value\":[]"))
                assertTrue(request("get", first).contains("EntityRemoved"))
                assertTrue(request("capabilities", first).contains("\"readable\":false"))
                present = true
                assertNotEquals(first, target(request("list")))
            }
        } finally {endpoint.close()}
    }

    @Test fun nativeBindingReadsAndPollsWithoutRunningCollectorOnCaller(): Unit = runBlocking {
        val caller = Thread.currentThread()
        val endpoint = NativeBindingEndpoint(DeviceAccess(object : DeviceCollector {
            override fun read(entity: EntityAddress): DeviceSnapshot {
                assertNotEquals(caller, Thread.currentThread())
                return RamSnapshot(physicalBytes = 9007199254740993u, availableBytes = 0u, lowMemory = false)
            }
        }))
        val settings = mapOf("readTimeoutMs" to 1000.0, "pollIntervalMs" to 20.0, "sensorHertz" to null)
        try {
            withTimeout(5000) {
                endpoint.send(mapOf("id" to 1, "operation" to "get", "entity" to mapOf("kind" to "Ram"), "settings" to settings))
                val value = endpoint.next()
                assertTrue(value.contains("\"physicalBytes\":\"9007199254740993\""))
                assertTrue(value.contains("\"id\":1"))
                endpoint.send(mapOf("id" to 2, "operation" to "watch", "entity" to mapOf("kind" to "Ram"), "settings" to settings))
                repeat(2) {assertTrue(endpoint.next().contains("\"physicalBytes\":\"9007199254740993\""))}
                endpoint.send(mapOf("id" to 2, "operation" to "cancel"))
            }
        } finally {endpoint.close()}
    }
}
