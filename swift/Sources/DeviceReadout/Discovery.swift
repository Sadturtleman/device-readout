import Foundation

public struct EntityCollection<Snapshot: DeviceSnapshot>: Sendable {
    private let access: DeviceAccess
    private let kind: Entity<Snapshot>
    init(access: DeviceAccess, kind: Entity<Snapshot>) { self.access = access; self.kind = kind }
    public func list() async throws -> [Entity<Snapshot>] { try await access.list(kind) }
    public func current() async throws -> Entity<Snapshot>? { try await access.current(kind) }
}

public extension DeviceAccess {
    var displays: EntityCollection<DisplaySnapshot> { EntityCollection(access: self, kind: Entities.display) }
    var viewports: EntityCollection<ViewportSnapshot> { EntityCollection(access: self, kind: Entities.viewport) }
    var cpuCores: EntityCollection<CpuCoreSnapshot> { EntityCollection(access: self, kind: Entities.cpuCore) }
    var batteries: EntityCollection<BatterySnapshot> { EntityCollection(access: self, kind: Entities.battery) }
    var networkInterfaces: EntityCollection<NetworkInterfaceSnapshot> { EntityCollection(access: self, kind: Entities.networkInterface) }
    var wifiConnections: EntityCollection<WifiConnectionSnapshot> { EntityCollection(access: self, kind: Entities.wifiConnection) }
    var cellularSubscriptions: EntityCollection<CellularSubscriptionSnapshot> { EntityCollection(access: self, kind: Entities.cellularSubscription) }
    var telephonyIdentities: EntityCollection<TelephonyIdentitySnapshot> { EntityCollection(access: self, kind: Entities.telephonyIdentity) }
    var storageVolumes: EntityCollection<StorageVolumeSnapshot> { EntityCollection(access: self, kind: Entities.storageVolume) }
    var sensors: SensorCollection { SensorCollection(access: self) }
}

public struct SensorCollection: Sendable {
    private let access: DeviceAccess
    init(access: DeviceAccess) { self.access = access }
    public func list<Snapshot>(_ kind: Entity<Snapshot>) async throws -> [Entity<Snapshot>] {
        guard kind.mode != .state else {
            throw DeviceReadoutError(.invalidConfiguration, "Expected an unbound sensor kind.")
        }
        return try await access.list(kind)
    }
}

struct TargetBinding: Sendable, Hashable {
    let owner: UUID
    let id: String
    let generation: UUID
    let observed: Bool
    init(owner: UUID, id: String, generation: UUID, observed: Bool = false) {
        self.owner = owner; self.id = id; self.generation = generation; self.observed = observed
    }
}

// Inventory construction runs on the collection worker. The lock covers only immutable-map
// snapshots, pointer replacement and individual validation, never native calls or callbacks.
final class TargetRegistry: @unchecked Sendable {
    private let owner = UUID()
    private let lock = NSLock()
    private var inventories: [EntityKind: [String: TargetBinding]] = [:]
    private var observedInventories: [EntityKind: [String: TargetBinding]] = [:]
    private var removalListeners: [TargetBinding: [UUID: @Sendable () -> Void]] = [:]

    func validate<Snapshot>(_ entity: Entity<Snapshot>) throws -> EntityRequest {
        if !entity.requiresTarget { return EntityRequest(kind: entity.kind, targetId: nil) }
        guard let binding = entity.binding else {
            throw DeviceReadoutError(.invalidConfiguration, "Discover or observe a target before reading this entity.")
        }
        guard binding.owner == owner else {
            throw DeviceReadoutError(.invalidConfiguration, "Entity handle belongs to another DeviceAccess context.")
        }
        lock.lock()
        let current = binding.observed ? observedInventories[entity.kind]?[binding.id] : inventories[entity.kind]?[binding.id]
        lock.unlock()
        guard current == binding else {
            throw DeviceReadoutError(.entityRemoved, "The selected target is no longer available.")
        }
        return EntityRequest(kind: entity.kind, targetId: binding.id)
    }

    func registerObserved<Snapshot>(_ kind: Entity<Snapshot>, id: String) throws -> Entity<Snapshot> {
        guard kind.requiresTarget, kind.binding == nil, !id.isEmpty else {
            throw DeviceReadoutError(.invalidConfiguration, "Expected an unbound multi-target kind and nonempty ID.")
        }
        lock.lock(); defer { lock.unlock() }
        let binding = observedInventories[kind.kind]?[id] ?? TargetBinding(owner: owner, id: id, generation: UUID(), observed: true)
        observedInventories[kind.kind, default: [:]][id] = binding
        return Entity(kind: kind.kind, requiresTarget: true, mode: kind.mode, binding: binding)
    }

    func observedList<Snapshot>(_ kind: Entity<Snapshot>) -> [Entity<Snapshot>]? {
        lock.lock(); let inventory = observedInventories[kind.kind]; lock.unlock()
        return inventory?.values.map { Entity(kind: kind.kind, requiresTarget: true, mode: kind.mode, binding: $0) }
    }

    func prepare<Snapshot>(_ kind: Entity<Snapshot>, ids: [String]) throws -> PreparedRead<[Entity<Snapshot>]> {
        guard ids.allSatisfy({ !$0.isEmpty }), Set(ids).count == ids.count else {
            throw DeviceReadoutError(.readFailed, "Native inventory contains an empty or duplicate target ID.")
        }
        lock.lock(); let previous = inventories; lock.unlock()
        let bindings = ids.map { id in
            previous[kind.kind]?[id] ?? TargetBinding(owner: owner, id: id, generation: UUID())
        }
        let nextKind = Dictionary(uniqueKeysWithValues: bindings.map { ($0.id, $0) })
        var next = previous
        next[kind.kind] = nextKind
        let replacement = next
        let removed = previous[kind.kind, default: [:]].values.filter { nextKind[$0.id] != $0 }
        let values = bindings.map { Entity<Snapshot>(kind: kind.kind, requiresTarget: true, mode: kind.mode, binding: $0) }
        return PreparedRead(value: values, commit: { [self, previous] in
            lock.lock(); inventories = replacement; lock.unlock()
            // Keep the previous dictionary alive until the prepared result is released off the control lock.
            withExtendedLifetime(previous) { }
        }, didCommit: { [self] in notifyRemoved(removed) })
    }

    func prepareCurrent<Snapshot>(_ kind: Entity<Snapshot>, id: String?) throws -> PreparedRead<Entity<Snapshot>?> {
        guard let id = id else { return PreparedRead(value: nil) }
        guard !id.isEmpty else {
            throw DeviceReadoutError(.readFailed, "Native current selection has an empty target ID.")
        }
        lock.lock(); let previous = inventories; lock.unlock()
        let binding = previous[kind.kind]?[id] ?? TargetBinding(owner: owner, id: id, generation: UUID())
        var next = previous
        next[kind.kind, default: [:]][id] = binding
        let replacement = next
        let value = Entity<Snapshot>(kind: kind.kind, requiresTarget: true, mode: kind.mode, binding: binding)
        return PreparedRead(value: value, commit: { [self, previous] in
            lock.lock(); inventories = replacement; lock.unlock()
            withExtendedLifetime(previous) { }
        })
    }

    func prepareRemoval<Snapshot>(_ entity: Entity<Snapshot>, error: DeviceReadoutError) -> PreparedRead<Snapshot> {
        guard let binding = entity.binding else { return PreparedRead(error: error) }
        lock.lock(); let previous = inventories; lock.unlock()
        guard previous[entity.kind]?[binding.id] == binding else { return PreparedRead(error: error) }
        var next = previous
        next[entity.kind]?[binding.id] = nil
        let replacement = next
        return PreparedRead(error: error, commit: { [self, previous] in
            lock.lock(); inventories = replacement; lock.unlock()
            withExtendedLifetime(previous) { }
        }, didCommit: { [self] in notifyRemoved([binding]) })
    }

    func observeRemoval<Snapshot>(_ entity: Entity<Snapshot>, removed: @escaping @Sendable () -> Void) throws -> TargetObservation? {
        _ = try validate(entity)
        guard let binding = entity.binding else { return nil }
        let id = UUID()
        lock.lock()
        let current = binding.observed ? observedInventories[entity.kind]?[binding.id] : inventories[entity.kind]?[binding.id]
        guard current == binding else {
            lock.unlock()
            throw DeviceReadoutError(.entityRemoved, "The selected target is no longer available.")
        }
        removalListeners[binding, default: [:]][id] = removed
        lock.unlock()
        return TargetObservation { [self] in
            lock.lock()
            removalListeners[binding]?[id] = nil
            if removalListeners[binding]?.isEmpty == true { removalListeners[binding] = nil }
            lock.unlock()
        }
    }

    private func notifyRemoved(_ bindings: [TargetBinding]) {
        lock.lock()
        var callbacks: [@Sendable () -> Void] = []
        for binding in bindings {
            if let listeners = removalListeners.removeValue(forKey: binding) { callbacks.append(contentsOf: listeners.values) }
        }
        lock.unlock()
        for callback in callbacks { callback() }
    }
}

final class TargetObservation: Sendable {
    private let dispose: @Sendable () -> Void
    init(dispose: @escaping @Sendable () -> Void) { self.dispose = dispose }
    func cancel() { dispose() }
    deinit { dispose() }
}

struct PreparedRead<Value: Sendable> {
    let result: Result<Value, Error>
    let commit: () -> Void
    let didCommit: () -> Void
    init(value: Value, commit: @escaping () -> Void = {}, didCommit: @escaping () -> Void = {}) {
        result = .success(value); self.commit = commit; self.didCommit = didCommit
    }
    init(error: DeviceReadoutError, commit: @escaping () -> Void = {}, didCommit: @escaping () -> Void = {}) {
        result = .failure(error); self.commit = commit; self.didCommit = didCommit
    }
}
