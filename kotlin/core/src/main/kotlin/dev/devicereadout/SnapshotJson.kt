package dev.devicereadout

import java.time.Instant
import kotlin.time.Duration
import kotlin.time.DurationUnit

/** JSON preserves 64-bit byte/counter values as decimal strings. No collection or UI work occurs. */
fun serializeSnapshot(snapshot: DeviceSnapshot): String = JsonWriter.encode(snapshotFields(normalizeSnapshot(snapshot)))
internal fun encodeBindingResponse(value: Map<String, Any?>): String = JsonWriter.encode(value)

private object JsonWriter {
    fun encode(value: Any?): String = when (value) {
        null -> "null"
        is DeviceSnapshot -> encode(snapshotFields(normalizeSnapshot(value)))
        is String -> quote(value)
        is ULong, is Long -> quote(value.toString())
        is Int, is Boolean -> value.toString()
        is Double -> if (value.isFinite()) value.toString() else "null"
        is Instant -> quote(value.toString())
        is Duration -> if (value.isFinite()) value.toDouble(DurationUnit.MILLISECONDS).toString() else "null"
        is AndroidThermalState -> quote("AndroidThermalState.${value.name}")
        is AppleThermalState -> quote("AppleThermalState.${value.name}")
        is Enum<*> -> quote(value.name)
        is Map<*, *> -> value.entries.joinToString(",", "{", "}") { (key, item) -> quote(if (key is Enum<*>) key.name else key as String) + ":" + encode(item) }
        is Iterable<*> -> value.joinToString(",", "[", "]") {encode(it)}
        is Size<*> -> encode(linkedMapOf("width" to value.width, "height" to value.height))
        is Rect -> encode(linkedMapOf("x" to value.x, "y" to value.y, "width" to value.width, "height" to value.height))
        is Insets -> encode(linkedMapOf("top" to value.top, "right" to value.right, "bottom" to value.bottom, "left" to value.left))
        is Vector3 -> encode(linkedMapOf("x" to value.x, "y" to value.y, "z" to value.z))
        is Quaternion -> encode(linkedMapOf("x" to value.x, "y" to value.y, "z" to value.z, "w" to value.w))
        is DisplayMode -> encode(linkedMapOf("pixelSize" to value.pixelSize, "refreshRateHz" to value.refreshRateHz))
        is IpAddressInfo -> encode(linkedMapOf("address" to value.address, "prefixLength" to value.prefixLength))
        is NetworkRoute -> encode(linkedMapOf("destination" to value.destination, "prefixLength" to value.prefixLength, "gateway" to value.gateway))
        else -> throw DeviceReadoutException(ErrorCode.ReadFailed, "Unrecognized snapshot value type.")
    }
    private fun quote(value: String): String = buildString {
        append('"')
        for (character in value) when (character) {
            '"' -> append("\\\"")
            '\\' -> append("\\\\")
            '\n' -> append("\\n")
            '\r' -> append("\\r")
            '\t' -> append("\\t")
            else -> if (character.code < 32 || character.isSurrogate()) append("\\u" + character.code.toString(16).padStart(4, '0')) else append(character)
        }
        append('"')
    }
}
