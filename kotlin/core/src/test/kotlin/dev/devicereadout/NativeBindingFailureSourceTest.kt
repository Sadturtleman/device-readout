package dev.devicereadout

import kotlinx.coroutines.*
import org.junit.Test
import kotlin.test.*

class NativeBindingFailureSourceTest {
    @Test fun ownedFailuresPreserveApplicationPolicyAndTerminatePausedSensors(): Unit = runBlocking {
        val endpoint = NativeBindingEndpoint(DeviceAccess(object : DeviceCollector {
            override fun read(entity: EntityAddress): DeviceSnapshot = RamSnapshot(availableBytes = 42u)
        }))
        val display = mapOf("kind" to "Display", "targetId" to "app-screen", "observed" to true)
        val sensor = mapOf("kind" to "Accelerometer", "targetId" to "app-sensor", "observed" to true)
        fun observe(entity: Map<String, Any?>, value: Map<String, Any?>) = endpoint.send(mapOf(
            "id" to 0, "operation" to "observer", "entity" to entity, "value" to value))
        fun failure(owner: Int?, code: String?, entity: Map<String, Any?> = display) = observe(entity, mapOf(
            "type" to if (owner == null) "failure" else "failureSource", "ownerId" to owner,
            "error" to code?.let {mapOf("code" to it, "message" to "Failure from $owner")}))
        fun query(id: Int, operation: String = "get", entity: Map<String, Any?> = display) = endpoint.send(mapOf(
            "id" to id, "operation" to operation, "entity" to entity,
            "settings" to mapOf("readTimeoutMs" to 100, "pollIntervalMs" to 10000)))
        suspend fun expect(id: Int, content: String) {
            val reply = endpoint.next()
            assertTrue(reply.contains("\"id\":$id,") && reply.contains(content), reply)
        }
        try {withTimeout(5000) {
            observe(display, mapOf("type" to "state", "values" to mapOf("label" to "stale")))
            failure(1, "ReadFailed");failure(2, "UnsupportedEntity")
            query(1);expect(1, "ReadFailed")
            failure(null, "PermissionDenied");failure(1, null)
            query(2);expect(2, "PermissionDenied")
            failure(null, null);query(3);expect(3, "UnsupportedEntity")
            failure(2, null);query(4);expect(4, "ReadTimeout")
            observe(display, mapOf("type" to "state", "values" to mapOf("label" to "fresh")))
            query(5);expect(5, "\"label\":\"fresh\"")
            failure(3, "ReadFailed");failure(1, null);failure(2, null)
            query(6);expect(6, "ReadFailed")
            query(7, entity = mapOf("kind" to "Ram"));expect(7, "\"availableBytes\":\"42\"")

            observe(sensor, mapOf("type" to "register"))
            observe(sensor, mapOf("type" to "sensorActivity", "active" to false))
            query(8, "watch", sensor);expect(8, "\"type\":\"suspended\"")
            failure(4, "PermissionDenied", sensor);expect(8, "PermissionDenied")
            failure(4, null, sensor)
            observe(sensor, mapOf("type" to "failureSource", "ownerId" to 1.5, "error" to mapOf("code" to "ReadFailed")))
            expect(0, "InvalidConfiguration")
            query(9);expect(9, "ReadFailed")
        }} finally {endpoint.close()}
    }
}
