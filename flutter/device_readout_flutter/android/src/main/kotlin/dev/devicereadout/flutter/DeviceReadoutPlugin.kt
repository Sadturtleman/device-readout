package dev.devicereadout.flutter

import dev.devicereadout.*
import dev.devicereadout.android.AndroidDeviceAccess
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import kotlinx.coroutines.*
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean

/** Attaching registers only a background message handler; no sensor or permission UI is opened. */
class DeviceReadoutPlugin : FlutterPlugin {
    private var channel: MethodChannel? = null
    private var stateChannel: MethodChannel? = null
    private var bridge: AndroidSensorBridge? = null
    private var stateBridge: AndroidStateBridge? = null
    private var scope: CoroutineScope? = null
    private var attached = AtomicBoolean()
    private val replies = ConcurrentHashMap.newKeySet<Reply>()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val application = binding.applicationContext
        val owner = AndroidSensorBridge { AndroidDeviceAccess.create(application) }
        val stateOwner = AndroidStateBridge { AndroidDeviceAccess.create(application) }
        val jobs = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        val active = AtomicBoolean(true)
        attached = active
        bridge = owner; stateBridge = stateOwner; scope = jobs
        fun endpoint(name: String, invoke: suspend (String, Map<*, *>) -> Any?) = MethodChannel(binding.binaryMessenger, name,
            StandardMethodCodec.INSTANCE, binding.binaryMessenger.makeBackgroundTaskQueue()).also { endpoint ->
            endpoint.setMethodCallHandler { call, result ->
                val reply = Reply(result)
                replies.add(reply)
                if (!active.get()) {
                    replies.remove(reply)
                    reply.failure(DeviceReadoutException(ErrorCode.EntityRemoved, "Plugin detached."))
                    return@setMethodCallHandler
                }
                jobs.launch {
                    try { reply.success(invoke(call.method, call.arguments as? Map<*, *> ?: emptyMap<Any, Any>())) }
                    catch (error: Throwable) { reply.failure(error) }
                    finally { replies.remove(reply) }
                }.invokeOnCompletion { error ->
                    // Cancellation can prevent the coroutine body from starting.
                    if (error != null) reply.failure(error)
                    replies.remove(reply)
                }
            }
        }
        channel = endpoint("dev.devicereadout/sensors.v1", owner::invoke)
        stateChannel = endpoint("dev.devicereadout/state.v1", stateOwner::invoke)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        attached.set(false)
        channel?.setMethodCallHandler(null); channel = null
        stateChannel?.setMethodCallHandler(null); stateChannel = null
        replies.forEach { it.failure(DeviceReadoutException(ErrorCode.EntityRemoved, "Plugin detached.")) }
        replies.clear()
        bridge?.close(); bridge = null
        stateBridge?.close(); stateBridge = null
        scope?.cancel(); scope = null
    }

    private class Reply(private val result: MethodChannel.Result) {
        private val completed = AtomicBoolean()
        fun success(value: Any?) {
            if (completed.compareAndSet(false, true)) runCatching { result.success(value) }
        }
        fun failure(error: Throwable) {
            val failure = when (error) {
                is DeviceReadoutException -> error
                is SecurityException -> DeviceReadoutException(ErrorCode.PermissionDenied, error.message ?: "Permission denied.")
                is CancellationException -> DeviceReadoutException(ErrorCode.EntityRemoved, "Native operation cancelled.")
                else -> DeviceReadoutException(ErrorCode.ReadFailed, error.message ?: "Native operation failed.")
            }
            if (completed.compareAndSet(false, true)) runCatching { result.error(failure.code.name, failure.message, null) }
        }
    }
}
