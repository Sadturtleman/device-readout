package dev.devicereadout

class EntityCollection<S : DeviceSnapshot> internal constructor(private val access: DeviceAccess, private val kind: Entity<S>) {
    suspend fun list(): List<Entity<S>> = access.list(kind)
    suspend fun current(): Entity<S>? = access.current(kind)
}
class SensorCollection internal constructor(private val access: DeviceAccess) {
    suspend fun <S : DeviceSnapshot> list(kind: Entity<S>): List<Entity<S>> {
        if (kind.mode == EntityMode.State) throw DeviceReadoutException(ErrorCode.InvalidConfiguration, "Expected a sensor kind.")
        return access.list(kind)
    }
}
class CapabilityAccess internal constructor(private val access: DeviceAccess) {
    suspend fun <S : DeviceSnapshot> get(entity: Entity<S>): EntityCapabilities = access.getCapabilities(entity)
}
