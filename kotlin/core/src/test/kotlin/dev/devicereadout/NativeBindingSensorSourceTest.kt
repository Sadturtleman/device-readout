package dev.devicereadout

import kotlinx.coroutines.*
import org.junit.Test
import kotlin.test.*

class NativeBindingSensorSourceTest {
    private class Fixture : AutoCloseable {
        val endpoint = NativeBindingEndpoint(DeviceAccess(object : DeviceCollector {
            override fun read(entity: EntityAddress): DeviceSnapshot = RamSnapshot(availableBytes = 42u)
        }))
        val entity = mapOf("kind" to "Accelerometer", "targetId" to "app-motion", "observed" to true)
        fun observe(value: Map<String, Any?>) = endpoint.send(mapOf("id" to 0, "operation" to "observer", "entity" to entity, "value" to value))
        fun register() = observe(mapOf("type" to "sensorSource", "description" to mapOf(
            "name" to "App accelerometer", "minimumInterval" to 12.5, "reportingMode" to "FutureMode")))
        fun query(id: Int, operation: String, hertz: Int? = 60, timeout: Int = 1000, address: Map<String, Any?> = entity) = endpoint.send(mapOf(
            "id" to id, "operation" to operation, "entity" to address,
            "settings" to mapOf("readTimeoutMs" to timeout, "pollIntervalMs" to 1000, "sensorHertz" to hertz)))
        fun sample(session: Int, x: Double) = endpoint.send(mapOf("id" to 0, "operation" to "sensor", "value" to mapOf(
            "sessionId" to session, "values" to mapOf("value" to mapOf("x" to x, "y" to 0, "z" to 0), "collectedAt" to "1970-01-01T00:00:00Z"))))
        fun cancel(id: Int) = endpoint.send(mapOf("id" to id, "operation" to "cancel"))
        suspend fun next() = endpoint.next()
        suspend fun start(): Pair<Int, String> {
            var message = next()
            while (message.contains("\"type\":\"reading\"")) message = next()
            assertTrue(message.contains("\"type\":\"sensorStart\""), message)
            return session(message) to message
        }
        fun session(message: String) = Regex("\"sessionId\":(\\d+)").find(message)?.groupValues?.get(1)?.toInt() ?: error(message)
        override fun close() = endpoint.close()
    }

    @Test fun sourceMetadataIsInertAndGetWatchOwnSeparateSessions(): Unit = runBlocking {
        Fixture().use { fixture -> withTimeout(5000) { with(fixture) {
            register()
            query(1, "describe")
            val description = next()
            assertTrue(description.contains("\"name\":\"App accelerometer\""), description)
            assertTrue(description.contains("\"kind\":\"Accelerometer\""), description)
            assertTrue(description.contains("\"minimumInterval\":12.5"), description)
            assertTrue(description.contains("\"reportingMode\":null"), description)
            query(2, "capabilities")
            assertTrue(next().contains("\"readable\":true"))
            query(3, "watch")
            val watch = start()
            assertTrue(watch.second.contains("\"sensorHertz\":60.0"), watch.second)
            assertTrue(watch.second.contains("\"observed\":true"), watch.second)
            query(4, "get")
            val get = start()
            assertNotEquals(watch.first, get.first)
            assertTrue(get.second.contains("\"sensorHertz\":null"), get.second)
            sample(watch.first, 1.0)
            assertTrue(next().contains("\"x\":1.0"))
            sample(get.first, 2.0)
            val readAndStop = listOf(next(), next())
            assertTrue(readAndStop.any {it.contains("\"id\":4,") && it.contains("\"x\":2.0") && !it.contains("1970-01-01")}, readAndStop.toString())
            assertTrue(readAndStop.any {it.contains("\"type\":\"sensorStop\"") && session(it) == get.first}, readAndStop.toString())
            // A finished read's late sample must not affect its surviving sibling watch.
            sample(get.first, 99.0);sample(watch.first, 3.0)
            val surviving = next()
            assertTrue(surviving.contains("\"id\":3,") && surviving.contains("\"x\":3.0"), surviving)
            cancel(3)
            val stopped = next()
            assertTrue(stopped.contains("\"type\":\"sensorStop\"") && session(stopped) == watch.first, stopped)
        }}}
    }

    @Test fun lifecycleReleasesAndReacquiresSourcesAndPausedFailuresStillTerminate(): Unit = runBlocking {
        Fixture().use { fixture -> withTimeout(5000) { with(fixture) {
            register();query(1, "watch", timeout = 100)
            val initial = start().first
            sample(initial, 1.0);assertTrue(next().contains("\"x\":1.0"))
            observe(mapOf("type" to "sensorActivity", "active" to false))
            val paused = listOf(next(), next())
            assertTrue(paused.any {it.contains("\"type\":\"suspended\"")}, paused.toString())
            assertTrue(paused.any {it.contains("\"type\":\"sensorStop\"") && session(it) == initial}, paused.toString())
            delay(150)
            query(2, "get", address = mapOf("kind" to "Ram"))
            assertTrue(next().contains("\"availableBytes\":\"42\""))
            observe(mapOf("type" to "sensorActivity", "active" to true))
            val resumed = start().first
            assertNotEquals(initial, resumed)
            sample(initial, 99.0);sample(resumed, 2.0)
            assertTrue(next().contains("\"x\":2.0"))
            observe(mapOf("type" to "sensorActivity", "active" to false))
            val stopped = listOf(next(), next())
            assertTrue(stopped.any {it.contains("\"type\":\"sensorStop\"") && session(it) == resumed}, stopped.toString())
            observe(mapOf("type" to "failure", "error" to mapOf("code" to "PermissionDenied", "message" to "App permission revoked.")))
            val failed = next()
            assertTrue(failed.contains("\"id\":1,") && failed.contains("PermissionDenied"), failed)
        }}}
    }

    @Test fun sessionErrorsAndTimeoutsAreScopedAndRemovalEndsTheSurvivor(): Unit = runBlocking {
        Fixture().use { fixture -> withTimeout(5000) { with(fixture) {
            register();query(1, "watch")
            val surviving = start().first
            sample(surviving, 1.0);next()
            query(2, "get", timeout = 100)
            val timed = start().first
            val timeout = listOf(next(), next())
            assertTrue(timeout.any {it.contains("\"id\":2,") && it.contains("ReadTimeout")}, timeout.toString())
            assertTrue(timeout.any {it.contains("\"type\":\"sensorStop\"") && session(it) == timed}, timeout.toString())
            query(3, "get")
            val denied = start().first
            endpoint.send(mapOf("id" to 0, "operation" to "sensor", "value" to mapOf("sessionId" to denied,
                "error" to mapOf("code" to "PermissionDenied", "message" to "Source rejected read."))))
            val failure = listOf(next(), next())
            assertTrue(failure.any {it.contains("\"id\":3,") && it.contains("PermissionDenied")}, failure.toString())
            assertTrue(failure.any {it.contains("\"type\":\"sensorStop\"") && session(it) == denied}, failure.toString())
            query(4, "get")
            val malformed = start().first
            endpoint.send(mapOf("id" to 0, "operation" to "sensor", "value" to mapOf("sessionId" to malformed, "values" to "not a snapshot")))
            val invalid = listOf(next(), next())
            assertTrue(invalid.any {it.contains("\"id\":4,") && it.contains("ReadFailed")}, invalid.toString())
            sample(surviving, 4.0)
            assertTrue(next().contains("\"x\":4.0"))
            observe(mapOf("type" to "remove"))
            val removed = listOf(next(), next())
            assertTrue(removed.any {it.contains("\"id\":1,") && it.contains("EntityRemoved")}, removed.toString())
            assertTrue(removed.any {it.contains("\"type\":\"sensorStop\"") && session(it) == surviving}, removed.toString())
        }}}
    }

    @Test fun eventSourcesWaitForOccurrenceAndIgnoreRequestedSamplingRate(): Unit = runBlocking {
        Fixture().use { fixture -> withTimeout(5000) { with(fixture) {
            val event = mapOf("kind" to "StepDetected", "targetId" to "steps", "observed" to true)
            endpoint.send(mapOf("id" to 0, "operation" to "observer", "entity" to event, "value" to mapOf("type" to "sensorSource")))
            query(1, "watch", timeout = 75, address = event)
            val started = start()
            assertTrue(started.second.contains("\"sensorHertz\":null"), started.second)
            delay(150)
            query(2, "get", address = mapOf("kind" to "Ram"))
            // No fake event or first-occurrence deadline may precede this independent result.
            assertTrue(next().contains("\"id\":2,"))
            endpoint.send(mapOf("id" to 0, "operation" to "sensor", "value" to mapOf("sessionId" to started.first, "values" to mapOf("value" to true))))
            val eventValue = next()
            assertTrue(eventValue.contains("\"id\":1,") && eventValue.contains("\"value\":true"), eventValue)
            cancel(1)
            assertTrue(next().contains("\"type\":\"sensorStop\""))
            query(3, "get", timeout = 75, address = event)
            val oneShot = start().first
            val timeout = listOf(next(), next())
            assertTrue(timeout.any {it.contains("\"id\":3,") && it.contains("ReadTimeout")}, timeout.toString())
            assertTrue(timeout.any {it.contains("\"type\":\"sensorStop\"") && session(it) == oneShot}, timeout.toString())
        }}}
    }
}
