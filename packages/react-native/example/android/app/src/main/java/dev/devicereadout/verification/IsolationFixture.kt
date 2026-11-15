package dev.devicereadout.verification

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import com.facebook.react.BaseReactPackage
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.module.model.ReactModuleInfo
import com.facebook.react.module.model.ReactModuleInfoProvider
import dev.devicereadout.*
import dev.devicereadout.reactnative.NativeDeviceReadoutModule
import org.json.JSONObject
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/** Verification-app fixture only. The shipping SDK has no delay switch or broadcast receiver. */
object IsolationFixture {
    const val RELEASE = "dev.devicereadout.verification.RELEASE_ISOLATION"
    private val gate = CountDownLatch(1)
    private val entered = AtomicBoolean()
    private val returned = AtomicBoolean()
    @Volatile private var collectorThread: Thread? = null

    private fun report(type: String, values: Map<String, Any?> = emptyMap()) {
        Log.i("DRIsolation", "DEVICE_READOUT_ISOLATION_NATIVE " + JSONObject(values + mapOf("type" to type, "uptimeMs" to SystemClock.elapsedRealtime())))
    }
    fun startUiHeartbeat() {
        val handler = Handler(Looper.getMainLooper())
        var ticks = 0
        handler.post(object : Runnable {
            override fun run() {
                ticks++
                if (entered.get() && !returned.get()) report("ui", mapOf("ticks" to ticks))
                if (!returned.get()) handler.postDelayed(this, 50)
            }
        })
    }
    fun createAccess(): DeviceAccess {
        check(BuildConfig.ISOLATION_FIXTURE)
        report("factory", mapOf("mainThread" to (Looper.myLooper() === Looper.getMainLooper())))
        return DeviceAccess(object : DeviceCollector {
            override fun read(entity: EntityAddress): DeviceSnapshot {
                if (entity.kind == EntityKind.Runtime) return RuntimeSnapshot(processBitness = 64)
                check(entity.kind == EntityKind.Ram)
                check(entered.compareAndSet(false, true)) {"Unexpected duplicate blocking read."}
                collectorThread = Thread.currentThread()
                report("entered", mapOf("mainThread" to (Looper.myLooper() === Looper.getMainLooper())))
                val limit = SystemClock.elapsedRealtime() + 15000
                while (gate.count != 0L && SystemClock.elapsedRealtime() < limit) {
                    try {gate.await(20, TimeUnit.MILLISECONDS)} catch (_: InterruptedException) {}
                }
                if (gate.count != 0L) {report("expired");error("Collector fixture safety deadline exceeded.")}
                returned.set(true)
                report("returned")
                return RamSnapshot(availableBytes = 42u)
            }
        })
    }
    fun release() {
        if (!BuildConfig.ISOLATION_FIXTURE) return
        report("released")
        gate.countDown()
        val thread = collectorThread
        Thread({
            thread?.join(4000)
            report("workerStopped", mapOf("stopped" to (thread != null && !thread.isAlive)))
        }, "DeviceReadout isolation verifier").apply {isDaemon = true;start()}
    }
}

class IsolationPackage : BaseReactPackage() {
    override fun getModule(name: String, context: ReactApplicationContext): NativeModule? =
        if (name == NativeDeviceReadoutModule.NAME) NativeDeviceReadoutModule(context, IsolationFixture::createAccess) else null
    override fun getReactModuleInfoProvider() = ReactModuleInfoProvider {
        mapOf(NativeDeviceReadoutModule.NAME to ReactModuleInfo(
            NativeDeviceReadoutModule.NAME, NativeDeviceReadoutModule.NAME, false, false, false, true
        ))
    }
}

class IsolationReleaseReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (BuildConfig.ISOLATION_FIXTURE && intent.action == IsolationFixture.RELEASE) IsolationFixture.release()
    }
}
