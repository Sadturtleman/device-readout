package dev.devicereadout.reactnative

import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.module.annotations.ReactModule
import dev.devicereadout.*
import dev.devicereadout.android.AndroidDeviceAccess
import kotlinx.coroutines.*
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

/** TurboModule entrypoints only schedule work. No Activity, screen getter or permission prompt is used. */
@ReactModule(name = NativeDeviceReadoutModule.NAME)
class NativeDeviceReadoutModule(
    application: ReactApplicationContext,
    private val accessFactory: () -> DeviceAccess = {AndroidDeviceAccess.create(application.applicationContext)}
) : NativeDeviceReadoutSpec(application) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val contexts = ConcurrentHashMap<String, NativeBindingEndpoint>()
    private val sequence = AtomicLong()
    private val closed = AtomicBoolean()
    override fun getName() = NAME

    override fun create(promise: Promise) = execute(promise) {
        val endpoint = NativeBindingEndpoint(accessFactory())
        val id = sequence.incrementAndGet().toString()
        contexts[id] = endpoint
        if (closed.get()) {contexts.remove(id)?.close();removed()}
        id
    }
    override fun send(context: String, request: String, promise: Promise) = execute(promise) {
        if (request.length > 262144) throw DeviceReadoutException(ErrorCode.InvalidConfiguration, "Native request is too large.")
        val value = decode(JSONObject(request), 0) as Map<String, Any?>
        endpoint(context).send(value)
        null
    }
    override fun next(context: String, promise: Promise) = execute(promise) {endpoint(context).next()}
    override fun dispose(context: String, promise: Promise) = execute(promise) {contexts.remove(context)?.close();null}

    private fun endpoint(id: String) = contexts[id] ?: removed()
    private fun execute(promise: Promise, operation: suspend () -> Any?) {
        if (closed.get()) {promise.reject(ErrorCode.EntityRemoved.name, "Native module detached.");return}
        scope.launch {
            try {promise.resolve(operation())}
            catch (error: Throwable) {
                val code = (error as? DeviceReadoutException)?.code ?: if (error is CancellationException) ErrorCode.EntityRemoved else ErrorCode.ReadFailed
                promise.reject(code.name, error.message ?: "Native operation failed.", error)
            }
        }
    }
    override fun invalidate() {
        if (closed.compareAndSet(false, true)) {
            scope.launch {contexts.values.forEach {it.close()};contexts.clear();scope.cancel()}
        }
        super.invalidate()
    }
    private fun decode(value: Any?, depth: Int): Any? {
        if (depth > 32) throw DeviceReadoutException(ErrorCode.InvalidConfiguration, "Native request nesting is too deep.")
        return when (value) {
            JSONObject.NULL -> null
            is JSONObject -> value.keys().asSequence().associateWith {decode(value.get(it), depth + 1)}
            is JSONArray -> (0 until value.length()).map {decode(value.get(it), depth + 1)}
            else -> value
        }
    }
    private fun removed(): Nothing = throw DeviceReadoutException(ErrorCode.EntityRemoved, "Native context removed.")
    companion object {const val NAME = "NativeDeviceReadout"}
}
