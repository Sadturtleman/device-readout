package dev.devicereadout

import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import org.junit.Test
import kotlin.test.*

class RotationContractTest {
    @Test fun getAndWatchReturnUnitRotationsWithoutChangingAxesOrSigns() = runBlocking {
        verify(RelativeOrientationEntity, {RelativeOrientationSnapshot(value = it)}, {it.value})
        verify(AbsoluteOrientationEntity, {AbsoluteOrientationSnapshot(value = it)}, {it.value})
    }

    private suspend fun <S : DeviceSnapshot> verify(kind: Entity<S>, make: (Quaternion?) -> S, value: (S) -> Quaternion?) {
        val samples = listOf(
            Quaternion(Double.NaN, 0.0, 0.0, 1.0), Quaternion(0.0, Double.POSITIVE_INFINITY, 0.0, 1.0),
            Quaternion(0.0, 0.0, Double.NEGATIVE_INFINITY, 1.0), Quaternion(0.0, 0.0, 0.0, Double.NaN), null,
            Quaternion(0.0, 0.0, 0.0, 0.0), Quaternion(0.0, 0.0, 0.0, 1.0), Quaternion(0.0, 0.0, 0.0, -1.0),
            Quaternion(0.0, 0.0, 3.0, 4.0), Quaternion(0.0, 0.0, -3.0, -4.0),
            Quaternion(Double.MAX_VALUE, Double.MAX_VALUE, 0.0, 0.0), Quaternion(Double.MIN_VALUE, 0.0, 0.0, 0.0))
        val expected = listOf(null, null, null, null, null, null,
            Quaternion(0.0, 0.0, 0.0, 1.0), Quaternion(0.0, 0.0, 0.0, -1.0),
            Quaternion(0.0, 0.0, 0.6, 0.8), Quaternion(0.0, 0.0, -0.6, -0.8),
            Quaternion(0.7071067811865475, 0.7071067811865475, 0.0, 0.0), Quaternion(1.0, 0.0, 0.0, 0.0))
        val caller = Thread.currentThread().id
        DeviceAccess(object : DeviceCollector {
            override fun list(kind: EntityKind) = listOf("rotation")
            override fun read(entity: EntityAddress): DeviceSnapshot = error("Sensors must observe actual samples")
            override fun observe(entity: EntityAddress, rate: SensorSamplingRate, emit: (DeviceSnapshot) -> Unit, fail: (Throwable) -> Unit): CollectorSubscription {
                assertNotEquals(caller, Thread.currentThread().id)
                samples.forEach {emit(make(it))}
                return object : CollectorSubscription {
                    override val pollingRequired = false
                    override fun close() { }
                }
            }
        }).use { access ->
            val target = access.list(kind).single()
            assertNull(value(access.get(target)))
            val actual = withTimeout(3000) {access.watch(target).take(samples.size).toList()}.map(value)
            assertEquals(12, actual.size)
            actual.zip(expected).forEach { (result, wanted) ->
                if (wanted == null) assertNull(result) else {
                    val q = assertNotNull(result)
                    assertEquals(wanted.x, q.x, 1e-15);assertEquals(wanted.y, q.y, 1e-15)
                    assertEquals(wanted.z, q.z, 1e-15);assertEquals(wanted.w, q.w, 1e-15)
                }
            }
        }
    }
}
