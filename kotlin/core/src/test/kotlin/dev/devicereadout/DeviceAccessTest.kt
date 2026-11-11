package dev.devicereadout

import kotlinx.coroutines.*
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.flow.first
import org.junit.Test
import java.util.concurrent.atomic.AtomicInteger
import kotlin.test.*
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds

class DeviceAccessTest {
    @Test fun nativeDiscoveryAndDescriptionDiscardResultsAcrossObserverFailure() = runBlocking {
        for (operation in 0..2) {
            val started = CompletableDeferred<Unit>()
            val release = java.util.concurrent.CountDownLatch(1)
            val armed = java.util.concurrent.atomic.AtomicBoolean()
            fun gate() {if (armed.compareAndSet(true, false)) {started.complete(Unit);check(release.await(2, java.util.concurrent.TimeUnit.SECONDS))}}
            DeviceAccess(object : DeviceCollector {
                override fun read(entity: EntityAddress): DeviceSnapshot = error("Unexpected read.")
                override fun list(kind: EntityKind): List<String> {gate();return listOf("native-sensor")}
                override fun current(kind: EntityKind): String? {gate();return "native-sensor"}
                override fun describe(sensor: EntityAddress): SensorDescription {gate();return SensorDescription(kind = SensorKind.Accelerometer)}
            }).use {access ->
                withTimeout(3000) {
                    val sensor = access.list(AccelerometerEntity).single()
                    suspend fun query(): Any? = when(operation) {0 -> access.list(AccelerometerEntity);1 -> access.current(AccelerometerEntity);else -> access.describe(sensor)}
                    armed.set(true)
                    val pending = async {runCatching {query()}.exceptionOrNull()}
                    try {
                        started.await()
                        access.observers.failure(AccelerometerEntity, DeviceReadoutException(ErrorCode.PermissionDenied, "Discovery permission changed."))
                        access.observers.failure(AccelerometerEntity, null)
                    } finally {release.countDown()}
                    assertEquals(ErrorCode.PermissionDenied, assertIs<DeviceReadoutException>(pending.await()).code)
                    assertNotNull(query())
                }
            }
        }
    }
    @Test fun failureAndRecoveryDuringNativeReadDoNotReturnThePreFailureResult() = runBlocking {
        val started = CompletableDeferred<Unit>()
        val release = java.util.concurrent.CountDownLatch(1)
        val reads = AtomicInteger()
        DeviceAccess(object : DeviceCollector {
            override fun read(entity: EntityAddress): DeviceSnapshot {
                val count = reads.incrementAndGet()
                if (count == 1) {started.complete(Unit);check(release.await(2, java.util.concurrent.TimeUnit.SECONDS))}
                return RamSnapshot(availableBytes = count.toULong())
            }
        }).use {access ->
            withTimeout(3000) {
                val pending = async {runCatching {access.get(RamEntity)}.exceptionOrNull()}
                try {
                    started.await()
                    access.observers.failure(RamEntity, DeviceReadoutException(ErrorCode.PermissionDenied, "Permission changed during read."))
                    access.observers.failure(RamEntity, null)
                } finally {release.countDown()}
                assertEquals(ErrorCode.PermissionDenied, assertIs<DeviceReadoutException>(pending.await()).code)
                assertEquals(2uL, access.get(RamEntity).availableBytes)
            }
        }
    }
    @Test fun nativeEventWaitReceivesAppFailureAndReleasesOnTheWorker() = runBlocking {
        val registered = CompletableDeferred<Thread>()
        val released = CompletableDeferred<Thread>()
        DeviceAccess(object : DeviceCollector {
            override fun read(entity: EntityAddress): DeviceSnapshot = error("Event sensors do not read state.")
            override fun list(kind: EntityKind): List<String> = listOf("native-step")
            override fun observe(entity: EntityAddress, rate: SensorSamplingRate, emit: (DeviceSnapshot) -> Unit, fail: (Throwable) -> Unit): CollectorSubscription {
                registered.complete(Thread.currentThread())
                return object : CollectorSubscription {
                    override val pollingRequired = false
                    override fun close() {released.complete(Thread.currentThread())}
                }
            }
        }).use {access ->
            withTimeout(1500) {
                val sensor = access.list(StepDetectedEntity).single()
                val ended = async {runCatching {access.watch(sensor).first()}.exceptionOrNull()}
                val worker = registered.await()
                assertNotEquals(Thread.currentThread(), worker)
                access.observers.failure(StepDetectedEntity, DeviceReadoutException(ErrorCode.PermissionDenied, "Sensor permission revoked."))
                assertEquals(ErrorCode.PermissionDenied, (ended.await() as DeviceReadoutException).code)
                assertEquals(worker, released.await())
                assertEquals(ErrorCode.PermissionDenied, assertFailsWith<DeviceReadoutException> {access.describe(sensor)}.code)
            }
        }
    }
    @Test fun appFailureEndsNativePollingWithoutWaitingForTheNextPoll() = runBlocking {
        DeviceAccess(object : DeviceCollector {
            override fun read(entity: EntityAddress): DeviceSnapshot = RamSnapshot(availableBytes = 12uL)
        }).use {access ->
            withTimeout(1500) {
                val initial = CompletableDeferred<Unit>()
                val ended = async {runCatching {access.withPollInterval(30.seconds).watch(RamEntity).collect {initial.complete(Unit)}}.exceptionOrNull()}
                initial.await()
                access.observers.failure(RamEntity, DeviceReadoutException(ErrorCode.PermissionDenied, "Host-observed denial."))
                assertEquals(ErrorCode.PermissionDenied, (ended.await() as DeviceReadoutException).code)
                access.observers.failure(RamEntity, null)
                assertEquals(12uL, access.get(RamEntity).availableBytes)
            }
        }
    }
    @Test fun observerFailuresInvalidateStateAndPreserveTargetRemoval() = runBlocking {
        DeviceAccess(object : DeviceCollector {
            override fun read(entity: EntityAddress): DeviceSnapshot = throw DeviceReadoutException(ErrorCode.UnsupportedEntity, "No native fixture.")
        }).use { access ->
            withTimeout(3000) {
                val first = access.observers.target(DisplayEntity, "first")
                val second = access.observers.target(DisplayEntity, "second")
                access.observers.publish(first, DisplaySnapshot(label = "First"))
                access.observers.publish(second, DisplaySnapshot(label = "Second"))
                access.observers.current(DisplayEntity, second)
                val initial = CompletableDeferred<Unit>()
                val ended = async {runCatching {access.watch(first).collect {initial.complete(Unit)}}.exceptionOrNull()}
                initial.await()
                access.observers.failure(first, DeviceReadoutException(ErrorCode.PermissionDenied, "Observer lost permission."))
                assertEquals(ErrorCode.PermissionDenied, (ended.await() as DeviceReadoutException).code)
                assertEquals(ErrorCode.PermissionDenied, assertFailsWith<DeviceReadoutException> {access.get(first)}.code)
                assertEquals("Second", access.get(second).label)
                access.observers.failure(DisplayEntity, DeviceReadoutException(ErrorCode.ReadFailed, "Inventory unavailable."))
                assertEquals(ErrorCode.ReadFailed, assertFailsWith<DeviceReadoutException> {access.displays.list()}.code)
                assertEquals(ErrorCode.ReadFailed, assertFailsWith<DeviceReadoutException> {access.displays.current()}.code)
                assertEquals(ErrorCode.ReadFailed, assertFailsWith<DeviceReadoutException> {access.get(second)}.code)
                access.observers.permission(DisplayEntity, PermissionStatus.Denied)
                assertEquals(PermissionStatus.Denied, access.permissions.check(DisplayEntity))
                access.observers.failure(DisplayEntity, null)
                access.observers.failure(first, null)
                assertEquals(ErrorCode.ReadTimeout, assertFailsWith<DeviceReadoutException> {access.withReadTimeout(80.milliseconds).get(first)}.code)
                access.observers.publish(first, DisplaySnapshot(label = "Fresh"))
                assertEquals("Fresh", access.get(first).label)
                access.observers.remove(first)
                access.observers.failure(first, DeviceReadoutException(ErrorCode.ReadFailed, "Late failure."))
                access.observers.publish(first, DisplaySnapshot(label = "Late value"))
                assertEquals(ErrorCode.EntityRemoved, assertFailsWith<DeviceReadoutException> {access.get(first)}.code)
            }
        }
    }
    @Test fun nativeChangeReadsKeepEqualValuesAndHaveIndependentWorkerDeadlines() = runBlocking {
        val notify = CompletableDeferred<() -> Unit>()
        val initial = CompletableDeferred<Unit>()
        val second = CompletableDeferred<Unit>()
        val released = CompletableDeferred<Unit>()
        val reads = AtomicInteger()
        DeviceAccess(object : DeviceCollector {
            override fun read(entity: EntityAddress): DeviceSnapshot {
                if (reads.incrementAndGet() >= 3) {
                    val until = System.nanoTime() + 800_000_000
                    while (System.nanoTime() < until) { /* Event-triggered OS read ignores interruption. */ }
                }
                return RamSnapshot(availableBytes = 0uL)
            }
            override fun observeReads(entity: EntityAddress, emit: (() -> DeviceSnapshot) -> Unit, fail: (Throwable) -> Unit): CollectorSubscription {
                notify.complete {emit {read(entity)}}
                return object : CollectorSubscription {
                    override val pollingRequired = false
                    override fun close() {released.complete(Unit)}
                }
            }
        }).use { access ->
            withTimeout(2000) {
                var count = 0
                val ended = async {
                    runCatching {
                        access.withPollInterval(30.seconds).withReadTimeout(80.milliseconds).watch(RamEntity).collect {
                            assertEquals(0uL, it.availableBytes)
                            if (++count == 1) initial.complete(Unit) else second.complete(Unit)
                        }
                    }.exceptionOrNull()
                }
                initial.await()
                notify.await().invoke()
                second.await()
                assertEquals(2, reads.get())
                val start = System.nanoTime()
                notify.await().invoke()
                val error = ended.await()
                assertTrue(error is DeviceReadoutException && error.code == ErrorCode.ReadTimeout)
                assertTrue(System.nanoTime() - start < 500_000_000)
                released.await()
            }
        }
    }
    @Test fun configurationIsInertAndImmutable() = runBlocking {
        val reads = AtomicInteger()
        DeviceAccess(object : DeviceCollector {
            override fun read(entity: EntityAddress): DeviceSnapshot {reads.incrementAndGet();return RamSnapshot()}
        }).use { access ->
            val configured = access.withPollInterval(20.milliseconds)
            assertEquals(1.seconds, access.pollInterval)
            assertEquals(5.seconds, access.readTimeout)
            assertSame(SensorSamplingRate.PlatformDefault, access.sensorSamplingRate)
            assertEquals(20.milliseconds, configured.pollInterval)
            assertEquals(0, reads.get())
            assertEquals(ErrorCode.InvalidConfiguration, assertFailsWith<DeviceReadoutException> {access.withPollInterval(0.milliseconds)}.code)
        }
    }
    @Test fun ramPreservesPrecisionAndCollectionRunsOffTheCallerThread() = runBlocking {
        val caller = Thread.currentThread()
        var readThread: Thread? = null
        DeviceAccess(object : DeviceCollector {
            override fun read(entity: EntityAddress): DeviceSnapshot {
                readThread = Thread.currentThread()
                return RamSnapshot(physicalBytes = 9007199254740993uL, availableBytes = 0uL, lowMemory = false)
            }
        }).use { access ->
            val ram: RamSnapshot = access.get(RamEntity)
            assertNotEquals(caller, readThread)
            assertEquals(9007199254740993uL, ram.physicalBytes)
            assertEquals(0uL, ram.availableBytes)
            assertEquals(false, ram.lowMemory)
            assertNull(ram.freeBytes)
            assertTrue(ram.collectedAt.toEpochMilli() > 0)
        }
    }
    @Test fun anUncooperativeCollectorDoesNotDelayTheReadTimeout() = runBlocking {
        DeviceAccess(object : DeviceCollector {
            override fun read(entity: EntityAddress): DeviceSnapshot {
                val until = System.nanoTime() + 800_000_000
                while (System.nanoTime() < until) { /* Intentionally ignore interruption. */ }
                return RamSnapshot()
            }
        }).use { access ->
            val started = System.nanoTime()
            val error = assertFailsWith<DeviceReadoutException> {access.withReadTimeout(80.milliseconds).get(RamEntity)}
            assertEquals(ErrorCode.ReadTimeout, error.code)
            assertTrue((System.nanoTime() - started) / 1_000_000 < 500)
        }
    }
    @Test fun watchIsAColdFlowAndPollsEqualValuesWithoutOverlapping() = runBlocking {
        val reads = AtomicInteger()
        DeviceAccess(object : DeviceCollector {
            override fun read(entity: EntityAddress): DeviceSnapshot {reads.incrementAndGet();return RamSnapshot(availableBytes = 0uL)}
        }).use { access ->
            val flow = access.withPollInterval(15.milliseconds).watch(RamEntity)
            assertEquals(0, reads.get())
            val values = flow.take(2).toList()
            assertEquals(2, reads.get())
            assertEquals(values[0].availableBytes, values[1].availableBytes)
            assertTrue(values[1].collectedAt > values[0].collectedAt)
        }
    }
    @Test fun eventWatchWaitsWithoutAReadTimeoutAndReleasesItsNativeSubscription() = runBlocking {
        val emitter = CompletableDeferred<(DeviceSnapshot) -> Unit>()
        val released = CompletableDeferred<Unit>()
        DeviceAccess(object : DeviceCollector {
            override fun read(entity: EntityAddress): DeviceSnapshot = error("An event watch must not perform an initial read.")
            override fun list(kind: EntityKind): List<String> = listOf("steps")
            override fun observe(entity: EntityAddress, rate: SensorSamplingRate, emit: (DeviceSnapshot) -> Unit, fail: (Throwable) -> Unit): CollectorSubscription {
                assertSame(SensorSamplingRate.PlatformDefault, rate)
                emitter.complete(emit)
                return object : CollectorSubscription {
                    override val pollingRequired = false
                    override fun close() {released.complete(Unit)}
                }
            }
        }).use { access ->
            val step = access.list(StepDetectedEntity).single()
            val event = async {access.withReadTimeout(30.milliseconds).withSensorSamplingRate(60.hertz).watch(step).first()}
            val emit = emitter.await()
            delay(90)
            assertFalse(event.isCompleted)
            emit(StepDetectedSnapshot(value = true))
            assertEquals(true, event.await().value)
            withTimeout(1000) {released.await()}
        }
    }
    @Test fun cancellationStillReleasesNativeResourcesWhenTheCollectionQueueIsFull() = runBlocking {
        val watching = CompletableDeferred<Unit>()
        val blocked = CompletableDeferred<Unit>()
        val released = CompletableDeferred<Unit>()
        val gate = java.util.concurrent.CountDownLatch(1)
        val reads = AtomicInteger()
        DeviceAccess(object : DeviceCollector {
            override fun read(entity: EntityAddress): DeviceSnapshot {
                if (reads.getAndIncrement() == 0) {
                    blocked.complete(Unit)
                    gate.await()
                }
                return RamSnapshot()
            }
            override fun list(kind: EntityKind) = listOf("steps")
            override fun observe(entity: EntityAddress, rate: SensorSamplingRate, emit: (DeviceSnapshot) -> Unit, fail: (Throwable) -> Unit): CollectorSubscription {
                watching.complete(Unit)
                return object : CollectorSubscription {
                    override val pollingRequired = false
                    override fun close() {released.complete(Unit)}
                }
            }
        }).use { access ->
            val sensor = access.sensors.list(StepDetectedEntity).single()
            val watch = launch {access.watch(sensor).collect {}}
            watching.await()
            val first = async {access.get(RamEntity)}
            blocked.await()
            val queued = List(150) {async {runCatching {access.get(RamEntity)}}}
            yield()
            try {
                watch.cancelAndJoin()
                gate.countDown()
                first.await()
                val results = queued.awaitAll()
                assertTrue(results.any {(it.exceptionOrNull() as? DeviceReadoutException)?.code == ErrorCode.ReadFailed})
                withTimeout(1000) {released.await()}
            } finally {gate.countDown()}
        }
    }
}
