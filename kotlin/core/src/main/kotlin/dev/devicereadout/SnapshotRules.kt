package dev.devicereadout

import java.util.Collections
import kotlin.time.Duration

internal object SnapshotRules {
    fun finite(value: Double?): Double? = value?.takeIf {it.isFinite()}
    fun ratio(value: Double?): Double? = value?.takeIf {it.isFinite() && it in 0.0..1.0}
    fun duration(value: Duration?): Duration? = value?.takeIf {it.isFinite() && it >= Duration.ZERO}
    fun vector(value: Vector3?): Vector3? = value?.takeIf {listOf(it.x, it.y, it.z).all(Double::isFinite)}
    fun rotation(value: Quaternion?): Quaternion? {
        val q = value?.takeIf {it.x.isFinite() && it.y.isFinite() && it.z.isFinite() && it.w.isFinite()} ?: return null
        val scale = maxOf(kotlin.math.abs(q.x), kotlin.math.abs(q.y), kotlin.math.abs(q.z), kotlin.math.abs(q.w))
        if (scale == 0.0) return null
        val x = q.x / scale;val y = q.y / scale;val z = q.z / scale;val w = q.w / scale
        val length = kotlin.math.sqrt(x * x + y * y + z * z + w * w)
        return Quaternion(x / length, y / length, z / length, w / length)
    }
    fun rectangle(value: Rect?): Rect? = value?.takeIf {listOf(it.x, it.y, it.width, it.height).all(Double::isFinite)}
    fun insets(value: Insets?): Insets? = value?.takeIf {listOf(it.top, it.right, it.bottom, it.left).all(Double::isFinite)}
    fun size(value: Size<Double>?): Size<Double>? = value?.takeIf {it.width.isFinite() && it.height.isFinite()}

    private fun <T> list(value: List<T>?, type: Class<T>, transform: (T) -> T = {it}): List<T>? {
        val raw: List<*> = value ?: return null
        if (raw.any {!type.isInstance(it)}) return null
        return Collections.unmodifiableList(raw.map {transform(type.cast(it))})
    }
    fun strings(value: List<String>?): List<String>? = list(value, String::class.java)
    fun addresses(value: List<IpAddressInfo>?): List<IpAddressInfo>? = list(value, IpAddressInfo::class.java)
    fun routes(value: List<NetworkRoute>?): List<NetworkRoute>? = list(value, NetworkRoute::class.java)
    fun displayModes(value: List<DisplayMode>?): List<DisplayMode>? = list(value, DisplayMode::class.java) {it.copy(refreshRateHz = finite(it.refreshRateHz))}
    fun <T : Enum<T>> knownSet(value: Set<T>?, type: Class<T>): Set<T>? {
        val raw: Set<*> = value ?: return null
        if (raw.any {!type.isInstance(it)}) return null
        return Collections.unmodifiableSet(raw.mapTo(LinkedHashSet()) {type.cast(it)})
    }
    fun <T : Enum<T>> knownMap(value: Map<T, ULong>?, type: Class<T>): Map<T, ULong>? {
        val raw: Map<*, *> = value ?: return null
        if (raw.any {!type.isInstance(it.key) || it.value !is ULong}) return null
        return Collections.unmodifiableMap(raw.entries.associate {type.cast(it.key) to it.value as ULong})
    }
}
