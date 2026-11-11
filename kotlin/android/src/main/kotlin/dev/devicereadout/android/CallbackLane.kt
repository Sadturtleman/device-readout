package dev.devicereadout.android

import android.os.Handler
import android.os.HandlerThread
import dev.devicereadout.*
import java.util.concurrent.atomic.AtomicBoolean

/** Native callbacks use their own Looper; closing never joins a thread on the application's UI path. */
internal class CallbackLane(name: String, private val fail: (Throwable) -> Unit) : AutoCloseable {
    private val closed = AtomicBoolean()
    private val thread = HandlerThread(name).apply {isDaemon = true;start()}
    val handler = Handler(thread.looper)
    fun deliver(work: () -> Unit) {
        if (closed.get()) return
        try {work()} catch (error: Exception) {
            fail(when (error) {
                is DeviceReadoutException -> error
                is SecurityException -> DeviceReadoutException(ErrorCode.PermissionDenied, "Native callback requires permission.", error)
                else -> DeviceReadoutException(ErrorCode.ReadFailed, "Native callback failed.", error)
            })
        }
    }
    fun post(work: () -> Unit) {
        if (!closed.get() && !handler.post {deliver(work)}) fail(DeviceReadoutException(ErrorCode.ReadFailed, "The native callback lane stopped."))
    }
    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        handler.removeCallbacksAndMessages(null);thread.quitSafely()
    }
}
