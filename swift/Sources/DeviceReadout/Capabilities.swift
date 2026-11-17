/// Operation support, independent of permission and individual field availability.
/// False means unavailable; nil means support is not determined by the adapter.
public struct EntityCapabilities: Equatable, Sendable {
    public let readable: Bool?
    public let watchable: Bool?
    public init(readable: Bool?, watchable: Bool?) {
        self.readable = readable; self.watchable = watchable
    }
    static let available = EntityCapabilities(readable: true, watchable: true)
    static let unavailable = EntityCapabilities(readable: false, watchable: false)
}

public struct CapabilityAccess: Sendable {
    private let access: DeviceAccess
    init(access: DeviceAccess) { self.access = access }
    public func get<Snapshot>(_ entity: Entity<Snapshot>) async throws -> EntityCapabilities {
        try await access.getCapabilities(entity)
    }
}
