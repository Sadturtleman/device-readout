package dev.devicereadout

/** All collector calls are dispatched to the dedicated SDK collection lane. */
interface DeviceCollector {
    fun read(entity: EntityAddress): DeviceSnapshot
    fun list(kind: EntityKind): List<String> = throw DeviceReadoutException(ErrorCode.UnsupportedEntity, "Discovery unavailable.")
    fun current(kind: EntityKind): String? = null
    fun describe(sensor: EntityAddress): SensorDescription = throw DeviceReadoutException(ErrorCode.UnsupportedEntity, "Sensor metadata unavailable.")
    fun capabilities(entity: EntityAddress): EntityCapabilities = EntityCapabilities(null, null)
    fun observe(entity: EntityAddress, rate: SensorSamplingRate, emit: (DeviceSnapshot) -> Unit, fail: (Throwable) -> Unit): CollectorSubscription? = null
    /** State updates capture callback data and defer any remaining work to the runtime's read deadline/worker. */
    fun observeReads(entity: EntityAddress, emit: (() -> DeviceSnapshot) -> Unit, fail: (Throwable) -> Unit): CollectorSubscription? = null
    /** Optional native inventory invalidation. Registration/cleanup use the collection lane; callbacks only identify dirty kinds. */
    fun observeInventory(changed: (EntityKind) -> Unit, fail: (Throwable) -> Unit): CollectorSubscription? = null
}
interface CollectorSubscription : AutoCloseable { val pollingRequired: Boolean }
