import Foundation

/// Receives state already observed by the application. No UI getter or permission prompt runs here.
public struct ObserverInputs: Sendable {
    private let targets: TargetRegistry
    private let values: ObservedValues
    private let lifetime: ContextLifetime
    private let failures: ObservedFailures
    init(targets: TargetRegistry, values: ObservedValues, lifetime: ContextLifetime, failures: ObservedFailures) {
        self.targets = targets; self.values = values; self.lifetime = lifetime; self.failures = failures
    }

    public func target<Snapshot>(_ kind: Entity<Snapshot>, id: String) throws -> Entity<Snapshot> {
        try lifetime.withOpen { try targets.registerObserved(kind, id: id) }
    }

    public func current<Snapshot>(_ kind: Entity<Snapshot>, target: Entity<Snapshot>?) throws {
        try lifetime.withOpen { try targets.setObservedCurrent(kind, target: target) }
    }

    public func remove<Snapshot>(_ entity: Entity<Snapshot>) throws {
        let notify = try lifetime.withOpen {
            let removed = try targets.remove(entity)
            let ended = values.remove(entity)
            return { removed(); ended() }
        }
        notify()
    }

    public func failure<Snapshot>(_ entity: Entity<Snapshot>, error: DeviceReadoutError?) throws {
        let notify = try lifetime.withOpen {
            if !entity.requiresTarget || entity.binding != nil { _ = try targets.validate(entity) }
            let address = ObservedAddress(kind: entity.kind, binding: entity.binding)
            let failed = failures.change(address, error: error)
            let invalidated = error.map { values.invalidate(address, error: $0) } ?? {}
            return { failed(); invalidated() }
        }
        notify()
    }

    public func failureSource<Snapshot>(_ entity: Entity<Snapshot>) throws -> ObserverFailureSource {
        try lifetime.withOpen {
            if !entity.requiresTarget || entity.binding != nil { _ = try targets.validate(entity) }
            let address = ObservedAddress(kind: entity.kind, binding: entity.binding)
            let id = failures.createSource(address)
            return ObserverFailureSource(send: { [self] error in
                let notify = try lifetime.withOpen {
                    if !entity.requiresTarget || entity.binding != nil { _ = try targets.validate(entity) }
                    let failed = try failures.changeSource(id, error: error)
                    let invalidated = error.map { values.invalidate(address, error: $0) } ?? {}
                    return { failed(); invalidated() }
                }
                notify()
            }, dispose: { [self] in
                do { try lifetime.withOpen { failures.closeSource(id) } }
                catch { failures.closeSource(id) }
            })
        }
    }

    public func publish<Snapshot>(_ entity: Entity<Snapshot>, snapshot: Snapshot) throws {
        try lifetime.withOpen {
            guard entity.mode == .state else {
                throw DeviceReadoutError(.invalidConfiguration, "Sensor samples require a sensor source.")
            }
            do { _ = try targets.validate(entity) }
            catch let error as DeviceReadoutError where error.code == .entityRemoved { return }
            values.publish(entity, snapshot: snapshot)
        }
    }
}

struct ObservedAddress: Hashable, Sendable {
    let kind: EntityKind
    let binding: TargetBinding?
    func contains(_ other: ObservedAddress) -> Bool { kind == other.kind && (binding == nil || binding == other.binding) }
}

// Snapshot values are immutable and Sendable. Publication only exchanges a reference/value;
// normalization and timestamp assembly happen when the collection worker consumes it.
final class ObservedValues: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [ObservedAddress: any DeviceSnapshot] = [:]
    private var owned: Set<ObservedAddress> = []
    private var listeners: [ObservedAddress: [UUID: AsyncThrowingStream<any DeviceSnapshot, Error>.Continuation]] = [:]

    func publish<Snapshot>(_ entity: Entity<Snapshot>, snapshot: Snapshot) {
        let address = ObservedAddress(kind: entity.kind, binding: entity.binding)
        lock.lock()
        owned.insert(address)
        values[address] = snapshot
        var ended: [UUID] = []
        // These owned streams have no onTermination callbacks. Buffering under the state lock
        // preserves publication order; consumers normalize asynchronously on the collection worker.
        for (id, continuation) in listeners[address, default: [:]] {
            switch continuation.yield(snapshot) {
            case .enqueued: break
            case .terminated: ended.append(id)
            case .dropped:
                continuation.finish(throwing: DeviceReadoutError(.readFailed, "The observed-state queue is full."))
                ended.append(id)
            @unknown default:
                continuation.finish(throwing: DeviceReadoutError(.readFailed, "Unknown observed-state delivery result."))
                ended.append(id)
            }
        }
        for id in ended { listeners[address]?[id] = nil }
        lock.unlock()
    }

    func value<Snapshot>(_ entity: Entity<Snapshot>) -> (any DeviceSnapshot)? {
        lock.lock(); defer { lock.unlock() }
        return values[ObservedAddress(kind: entity.kind, binding: entity.binding)]
    }

    func owns<Snapshot>(_ entity: Entity<Snapshot>) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return owned.contains(ObservedAddress(kind: entity.kind, binding: entity.binding))
    }

    // Only SDK-owned stream delivery belongs here. Serializing it with publication prevents
    // a completed native poll or error from following state already accepted from the app.
    @discardableResult
    func whileUnpublished<Snapshot, Value>(_ entity: Entity<Snapshot>, _ accept: () throws -> Value) rethrows -> Value? {
        lock.lock(); defer { lock.unlock() }
        guard !owned.contains(ObservedAddress(kind: entity.kind, binding: entity.binding)) else { return nil }
        return try accept()
    }

    func subscribe<Snapshot>(_ entity: Entity<Snapshot>) -> ObservedSubscription {
        let address = ObservedAddress(kind: entity.kind, binding: entity.binding)
        let id = UUID()
        let stream = AsyncThrowingStream<any DeviceSnapshot, Error>(bufferingPolicy: .bufferingOldest(2048)) { continuation in
            lock.lock()
            listeners[address, default: [:]][id] = continuation
            if let value = values[address] { continuation.yield(value) }
            lock.unlock()
        }
        return ObservedSubscription(stream: stream, dispose: { [self] in
            lock.lock()
            let continuation = listeners[address]?.removeValue(forKey: id)
            if listeners[address]?.isEmpty == true { listeners[address] = nil }
            lock.unlock()
            continuation?.finish()
        })
    }

    // Detach owned buffers under the lifetime gate; terminal signals run after it is released.
    func remove<Snapshot>(_ entity: Entity<Snapshot>) -> () -> Void {
        let address = ObservedAddress(kind: entity.kind, binding: entity.binding)
        lock.lock()
        owned.remove(address)
        let previous = values.removeValue(forKey: address)
        let subscriptions = listeners.removeValue(forKey: address)
        lock.unlock()
        return {
            withExtendedLifetime(previous) { }
            for continuation in subscriptions?.values ?? [:].values {
                continuation.finish(throwing: DeviceReadoutError(.entityRemoved, "The selected target was removed."))
            }
        }
    }

    func invalidate(_ scope: ObservedAddress, error: DeviceReadoutError) -> () -> Void {
        lock.lock()
        let stale = values.filter { scope.contains($0.key) }
        for address in stale.keys { values[address] = nil }
        let affected = listeners.filter { scope.contains($0.key) }
        for address in affected.keys { listeners[address] = nil }
        lock.unlock()
        return {
            withExtendedLifetime(stale) { }
            for group in affected.values { for continuation in group.values { continuation.finish(throwing: error) } }
        }
    }

    func close() {
        lock.lock()
        values.removeAll()
        owned.removeAll()
        let subscriptions = listeners
        listeners.removeAll()
        lock.unlock()
        for group in subscriptions.values {
            for continuation in group.values { continuation.finish(throwing: DeviceReadoutError(.entityRemoved, "DeviceAccess is closed.")) }
        }
    }
}

struct ObservedSubscription: Sendable {
    let stream: AsyncThrowingStream<any DeviceSnapshot, Error>
    let dispose: @Sendable () -> Void
    func cancel() { dispose() }
}

// One collection task owns this iterator. Its first next() may run in deadline preparation,
// but it finishes before the watch starts another next(); iterator calls never overlap.
final class ObservedReader: @unchecked Sendable {
    private var iterator: AsyncThrowingStream<any DeviceSnapshot, Error>.Iterator
    init(_ stream: AsyncThrowingStream<any DeviceSnapshot, Error>) { iterator = stream.makeAsyncIterator() }
    func next() async throws -> (any DeviceSnapshot)? { try await iterator.next() }
    func requireNext() async throws -> any DeviceSnapshot {
        guard let value = try await next() else {
            try Task.checkCancellation()
            throw DeviceReadoutError(.readFailed, "Observed state ended before its first value.")
        }
        return value
    }
}
