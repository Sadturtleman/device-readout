package dev.devicereadout

import java.time.Instant
import kotlin.time.Duration

interface DeviceSnapshot { val collectedAt: Instant }
data class Size<T>(val width: T, val height: T)
data class Rect(val x: Double, val y: Double, val width: Double, val height: Double)
data class Insets(val top: Double, val right: Double, val bottom: Double, val left: Double)
data class Vector3(val x: Double, val y: Double, val z: Double)
data class Quaternion(val x: Double, val y: Double, val z: Double, val w: Double)
data class DisplayMode(val pixelSize: Size<Int>?, val refreshRateHz: Double?)
data class IpAddressInfo(val address: String, val prefixLength: Int?)
data class NetworkRoute(val destination: String, val prefixLength: Int?, val gateway: String?)
enum class ErrorCode { UnsupportedEntity, PermissionDenied, EntityRemoved, ReadTimeout, ReadFailed, InvalidConfiguration }
class DeviceReadoutException(val code: ErrorCode, message: String, cause: Throwable? = null) : Exception(message, cause)
internal enum class EntityMode { State, Sample, Event }
data class EntityAddress(val kind: EntityKind, val targetId: String? = null, val observed: Boolean = false)
class Entity<S : DeviceSnapshot> internal constructor(
    val kind: EntityKind,
    internal val targeted: Boolean,
    internal val mode: EntityMode,
    internal val snapshotType: Class<S>,
    internal val owner: Any? = null,
    internal val targetId: String? = null,
    internal val observed: Boolean = false,
) {
    internal fun address(context: Any, collection: Boolean = false): EntityAddress {
        if (owner != null && owner !== context) throw DeviceReadoutException(ErrorCode.InvalidConfiguration, "Entity belongs to another context.")
        if (targeted && targetId == null && !collection) throw DeviceReadoutException(ErrorCode.InvalidConfiguration, "Discover a target first.")
        return EntityAddress(kind, targetId, observed)
    }
    internal fun bind(context: Any, id: String, observed: Boolean = false): Entity<S> = Entity(kind, true, mode, snapshotType, context, id, observed)
}
data class EntityCapabilities(val readable: Boolean?, val watchable: Boolean?)
sealed class SensorSamplingRate {
    data object PlatformDefault : SensorSamplingRate()
    class Hertz(val value: Double) : SensorSamplingRate() {
        init { if (!value.isFinite() || value <= 0) throw DeviceReadoutException(ErrorCode.InvalidConfiguration, "Frequency must be positive and finite.") }
    }
}
val Int.hertz: SensorSamplingRate get() = SensorSamplingRate.Hertz(toDouble())
internal fun positive(value: Duration): Duration {
    if (!value.isFinite() || value <= Duration.ZERO) throw DeviceReadoutException(ErrorCode.InvalidConfiguration, "Duration must be positive and finite.")
    return value
}
