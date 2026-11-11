package dev.devicereadout

import kotlinx.coroutines.CancellableContinuation
import kotlinx.coroutines.suspendCancellableCoroutine
import java.util.concurrent.*
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

internal class CollectionWorker : AutoCloseable {
    private val closed = AtomicBoolean()
    private val pending = ConcurrentHashMap<FutureTask<*>, (Throwable) -> Unit>()
    private val resources = ConcurrentHashMap.newKeySet<CollectorSubscription>()
    private val releases = ConcurrentHashMap.newKeySet<CollectorSubscription>()
    private val executor = object : ThreadPoolExecutor(1, 1, 0, TimeUnit.SECONDS, ArrayBlockingQueue(128), ThreadFactory { work ->
        Thread(work, "DeviceReadout collector").apply { isDaemon = true }
    }) {
        override fun afterExecute(task: Runnable, error: Throwable?) {drainReleases()}
        override fun terminated() {
            for (resource in resources) safelyClose(resource)
            resources.clear();releases.clear()
        }
    }

    suspend fun <T> call(collect: () -> T): T = suspendCancellableCoroutine { continuation ->
        if (closed.get()) {continuation.resumeWithException(removed());return@suspendCancellableCoroutine}
        val completed = AtomicBoolean()
        val allocated = AtomicReference<CollectorSubscription?>()
        fun fail(error: Throwable) {if (completed.compareAndSet(false, true)) continuation.resumeWithException(error)}
        lateinit var task: FutureTask<Unit>
        task = FutureTask {
            try {
                if (continuation.isActive) {
                    val value = collect()
                    if (value is CollectorSubscription) {
                        resources.add(value)
                        allocated.set(value)
                        if (!continuation.isActive || closed.get()) {resources.remove(value);safelyClose(value)}
                    }
                    if (completed.compareAndSet(false, true)) continuation.resume(value)
                }
            } catch (error: Throwable) {
                fail(when (error) {
                    is CancellationException -> error
                    is DeviceReadoutException -> error
                    is SecurityException -> DeviceReadoutException(ErrorCode.PermissionDenied, error.message ?: "Permission denied.", error)
                    else -> DeviceReadoutException(ErrorCode.ReadFailed, error.message ?: "Collection failed.", error)
                })
            } finally {pending.remove(task)}
        }
        pending[task] = ::fail
        continuation.invokeOnCancellation {completed.set(true);task.cancel(true);executor.remove(task);pending.remove(task);release(allocated.get())}
        try {executor.execute(task)} catch (error: RejectedExecutionException) {
            pending.remove(task)
            fail(if (closed.get()) removed() else DeviceReadoutException(ErrorCode.ReadFailed, "The collection queue is full.", error))
        }
    }
    fun release(resource: CollectorSubscription?) {
        if (resource == null) return
        releases.add(resource)
        try {executor.execute {drainReleases()}}
        catch (_: RejectedExecutionException) {
            // A full queue still has active tasks: afterExecute drains releases on the collection lane.
            // If shutdown has started, terminated owns every remaining resource.
            if (executor.isTerminated) releases.remove(resource)
        }
    }
    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        for ((task, fail) in pending) {
            fail(removed())
            task.cancel(true)
        }
        pending.clear();executor.shutdownNow()
    }
    private fun safelyClose(resource: CollectorSubscription) {try {resource.close()} catch (_: Throwable) {}}
    private fun drainReleases() {
        for (resource in releases) {
            if (releases.remove(resource) && resources.remove(resource)) safelyClose(resource)
        }
    }
    private fun removed() = DeviceReadoutException(ErrorCode.EntityRemoved, "DeviceAccess is closed.")
}
