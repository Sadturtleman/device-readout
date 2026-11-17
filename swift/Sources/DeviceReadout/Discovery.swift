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
    private struct Selection { let binding: TargetBinding? }
    private var currentSelections: [EntityKind: Selection] = [:]
    private var removalListeners: [TargetBinding: [UUID: @Sendable () -> Void]] = [:]
    private var singletonRemovalListeners: [EntityKind: [UUID: @Sendable () -> Void]] = [:]
    private var removedSingletons: Set<EntityKind> = []
    private var retired: Set<TargetBinding> = []
    private var removalSerial: UInt64 = 0
    private var nativeRemovalSerials: [EntityKind: [String: UInt64]] = [:]

    func nativeRemovalVersion() -> UInt64 { lock.lock(); defer { lock.unlock() }; return removalSerial }

    func validate<Snapshot>(_ entity: Entity<Snapshot>) throws -> EntityRequest {
        if !entity.requiresTarget {
            lock.lock(); let removed = removedSingletons.contains(entity.kind); lock.unlock()
            guard !removed else { throw DeviceReadoutError(.entityRemoved, "The entity was removed from this context.") }
            return EntityRequest(kind: entity.kind, targetId: nil)
        }
        guard let binding = entity.binding else {
            throw DeviceReadoutError(.invalidConfiguration, "Discover or observe a target before reading this entity.")
        }
        guard binding.owner == owner else {
            throw DeviceReadoutError(.invalidConfiguration, "Entity handle belongs to another DeviceAccess context.")
        }
        lock.lock()
        let current = binding.observed ? observedInventories[entity.kind]?[binding.id] : inventories[entity.kind]?[binding.id]
        let removed = retired.contains(binding)
        lock.unlock()
        guard current == binding, !removed else {
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

    func observedCount(_ kind: EntityKind) -> Int? {
        lock.lock(); defer { lock.unlock() }; return observedInventories[kind]?.count
    }

    func setObservedCurrent<Snapshot>(_ kind: Entity<Snapshot>, target: Entity<Snapshot>?) throws {
        guard kind.requiresTarget, kind.binding == nil else {
            throw DeviceReadoutError(.invalidConfiguration, "Expected an unbound multi-target entity kind.")
        }
        if let target = target {
            guard target.kind == kind.kind else {
                throw DeviceReadoutError(.invalidConfiguration, "Expected a target of the same kind.")
            }
            _ = try validate(target)
        }
        lock.lock(); defer { lock.unlock() }
        currentSelections[kind.kind] = Selection(binding: target?.binding)
        if target == nil, observedInventories[kind.kind] == nil { observedInventories[kind.kind] = [:] }
    }

    func observedCurrent<Snapshot>(_ kind: Entity<Snapshot>) -> CurrentSelection<Snapshot>? {
        lock.lock(); defer { lock.unlock() }
        if let selection = currentSelections[kind.kind] {
            guard let binding = selection.binding else { return CurrentSelection(value: nil) }
            let current = binding.observed ? observedInventories[kind.kind]?[binding.id] : inventories[kind.kind]?[binding.id]
            guard current == binding, !retired.contains(binding) else { return CurrentSelection(value: nil) }
            return CurrentSelection(value: Entity(kind: kind.kind, requiresTarget: true, mode: kind.mode, binding: binding))
        }
        return observedInventories[kind.kind] == nil ? nil : CurrentSelection(value: nil)
    }

    func remove<Snapshot>(_ entity: Entity<Snapshot>) throws -> () -> Void {
        if !entity.requiresTarget {
            lock.lock(); defer { lock.unlock() }
            guard removedSingletons.insert(entity.kind).inserted else { return {} }
            let callbacks = singletonRemovalListeners.removeValue(forKey: entity.kind)
            return { for callback in callbacks?.values ?? [:].values { callback() } }
        }
        guard let binding = entity.binding, binding.owner == owner else {
            throw DeviceReadoutError(.invalidConfiguration, "Expected a bound target from this DeviceAccess context.")
        }
        lock.lock(); defer { lock.unlock() }
        let current = binding.observed ? observedInventories[entity.kind]?[binding.id] : inventories[entity.kind]?[binding.id]
        guard current == binding, !retired.contains(binding) else { return {} }
        retired.insert(binding)
        if binding.observed { observedInventories[entity.kind]?[binding.id] = nil }
        else {
            removalSerial += 1
            nativeRemovalSerials[entity.kind, default: [:]][binding.id] = removalSerial
        }
        // Native maps can still be referenced by a read in progress; the retired generation
        // remains invalid even if that read accepts a previously prepared inventory later.
        let callbacks = removalListeners.removeValue(forKey: binding)
        return { for callback in callbacks?.values ?? [:].values { callback() } }
    }

    func prepare<Snapshot>(_ kind: Entity<Snapshot>, ids: [String], since version: UInt64) throws -> PreparedRead<[Entity<Snapshot>]> {
        guard ids.allSatisfy({ !$0.isEmpty }), Set(ids).count == ids.count else {
            throw DeviceReadoutError(.readFailed, "Native inventory contains an empty or duplicate target ID.")
        }
        lock.lock()
        let previous = inventories
        let removedGenerations = retired
        let removals = nativeRemovalSerials[kind.kind, default: [:]]
        lock.unlock()
        // A later removal wins over a native query already in progress. Only discovery begun
        // after that signal may create a new generation for the same source ID.
        let bindings = ids.filter { removals[$0, default: 0] <= version }.map { id in
            if let binding = previous[kind.kind]?[id], !removedGenerations.contains(binding) { return binding }
            return TargetBinding(owner: owner, id: id, generation: UUID())
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

    func prepareCurrent<Snapshot>(_ kind: Entity<Snapshot>, id: String?, since version: UInt64) throws -> PreparedRead<Entity<Snapshot>?> {
        guard let id = id else { return PreparedRead(value: nil) }
        guard !id.isEmpty else {
            throw DeviceReadoutError(.readFailed, "Native current selection has an empty target ID.")
        }
        lock.lock()
        let previous = inventories
        let removedGenerations = retired
        let removedSinceStart = nativeRemovalSerials[kind.kind]?[id] ?? 0 > version
        lock.unlock()
        if removedSinceStart { return PreparedRead(value: nil) }
        let existing = previous[kind.kind]?[id].flatMap { removedGenerations.contains($0) ? nil : $0 }
        let binding = existing ?? TargetBinding(owner: owner, id: id, generation: UUID())
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
        return try observeRemoval(kind: entity.kind, binding: entity.binding, removed: removed)
    }

    func observeRemoval(kind: EntityKind, binding: TargetBinding?, removed: @escaping @Sendable () -> Void) throws -> TargetObservation {
        guard let binding = binding else { return try observeSingletonRemoval(kind, removed: removed) }
        guard binding.owner == owner else {
            throw DeviceReadoutError(.invalidConfiguration, "Entity handle belongs to another DeviceAccess context.")
        }
        let id = UUID()
        lock.lock()
        let current = binding.observed ? observedInventories[kind]?[binding.id] : inventories[kind]?[binding.id]
        guard current == binding, !retired.contains(binding) else {
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

    private func observeSingletonRemoval(_ kind: EntityKind, removed: @escaping @Sendable () -> Void) throws -> TargetObservation {
        let id = UUID()
        lock.lock()
        guard !removedSingletons.contains(kind) else {
            lock.unlock()
            throw DeviceReadoutError(.entityRemoved, "The entity was removed from this context.")
        }
        singletonRemovalListeners[kind, default: [:]][id] = removed
        lock.unlock()
        return TargetObservation { [self] in
            lock.lock()
            singletonRemovalListeners[kind]?[id] = nil
            if singletonRemovalListeners[kind]?.isEmpty == true { singletonRemovalListeners[kind] = nil }
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

// A present selection with a nil value means the application explicitly owns an empty selection.
struct CurrentSelection<Snapshot: DeviceSnapshot> { let value: Entity<Snapshot>? }

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
