package dev.devicereadout

import kotlin.time.Duration.Companion.milliseconds

/** JSON value decoding on the binding worker. Snapshot normalization remains in DeviceAccess. */
internal object BindingValues {
    fun string(value: Any?) = value as? String
    fun boolean(value: Any?) = value as? Boolean
    fun number(value: Any?) = (value as? Number)?.toDouble()?.takeIf {it.isFinite()}
    fun integer(value: Any?) = number(value)?.takeIf {it in Int.MIN_VALUE.toDouble()..Int.MAX_VALUE.toDouble() && it % 1.0 == 0.0}?.toInt()
    private fun safeInteger(value: Any?) = number(value)?.takeIf {it in -9007199254740991.0..9007199254740991.0 && it % 1.0 == 0.0}?.toLong()
    fun bytes(value: Any?): ULong? = if (value is String) value.takeIf {it.length <= 20 && it.matches(Regex("[0-9]+"))}?.toULongOrNull() else safeInteger(value)?.takeIf {it >= 0}?.toULong()
    fun counter(value: Any?): Long? = if (value is String) value.takeIf {it.length <= 20 && it.matches(Regex("-?[0-9]+"))}?.toLongOrNull() else safeInteger(value)
    fun duration(value: Any?) = number(value)?.takeIf {it >= 0}?.milliseconds
    fun <T : Enum<T>> enum(value: Any?, values: List<T>) = values.firstOrNull {it.name == value}
    fun thermal(value: Any?): ThermalState? {
        val name = value as? String ?: return null
        return when {
            name.startsWith("AndroidThermalState.") -> enum(name.removePrefix("AndroidThermalState."), AndroidThermalState.entries)
            name.startsWith("AppleThermalState.") -> enum(name.removePrefix("AppleThermalState."), AppleThermalState.entries)
            else -> null
        }
    }
    fun <T : Any> list(value: Any?, decode: (Any?) -> T?): List<T>? {
        val values = value as? List<*> ?: return null
        val result = ArrayList<T>(values.size)
        for (item in values) result.add(decode(item) ?: return null)
        return result
    }
    fun <K : Any, V : Any> map(value: Any?, key: (Any?) -> K?, item: (Any?) -> V?): Map<K, V>? {
        val values = value as? Map<*, *> ?: return null
        val result = LinkedHashMap<K, V>()
        for ((k, v) in values) result[key(k) ?: return null] = item(v) ?: return null
        return result
    }
    fun pixelSize(value: Any?): Size<Int>? {
        val v = value as? Map<*, *> ?: return null
        return Size(integer(v["width"]) ?: return null, integer(v["height"]) ?: return null)
    }
    fun size(value: Any?): Size<Double>? {
        val v = value as? Map<*, *> ?: return null
        return Size(number(v["width"]) ?: return null, number(v["height"]) ?: return null)
    }
    fun rect(value: Any?): Rect? {
        val v = value as? Map<*, *> ?: return null
        return Rect(number(v["x"]) ?: return null, number(v["y"]) ?: return null, number(v["width"]) ?: return null, number(v["height"]) ?: return null)
    }
    fun insets(value: Any?): Insets? {
        val v = value as? Map<*, *> ?: return null
        return Insets(number(v["top"]) ?: return null, number(v["right"]) ?: return null, number(v["bottom"]) ?: return null, number(v["left"]) ?: return null)
    }
    fun vector(value: Any?): Vector3? {
        val v = value as? Map<*, *> ?: return null
        return Vector3(number(v["x"]) ?: return null, number(v["y"]) ?: return null, number(v["z"]) ?: return null)
    }
    fun rotation(value: Any?): Quaternion? {
        val v = value as? Map<*, *> ?: return null
        return Quaternion(number(v["x"]) ?: return null, number(v["y"]) ?: return null, number(v["z"]) ?: return null, number(v["w"]) ?: return null)
    }
    fun displayMode(value: Any?): DisplayMode? {
        val v = value as? Map<*, *> ?: return null
        return DisplayMode(pixelSize(v["pixelSize"]), number(v["refreshRateHz"]))
    }
    fun address(value: Any?): IpAddressInfo? {
        val v = value as? Map<*, *> ?: return null
        return IpAddressInfo(string(v["address"]) ?: return null, integer(v["prefixLength"]))
    }
    fun route(value: Any?): NetworkRoute? {
        val v = value as? Map<*, *> ?: return null
        return NetworkRoute(string(v["destination"]) ?: return null, integer(v["prefixLength"]), string(v["gateway"]))
    }
}
