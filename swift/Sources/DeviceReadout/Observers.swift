import Foundation

/// Receives state already observed by the application. No UI getter or permission prompt runs here.
public struct ObserverInputs: Sendable {
    private let targets: TargetRegistry
    private let values: ObservedValues
    private let lifetime: ContextLifetime
    init(targets: TargetRegistry, values: ObservedValues, lifetime: ContextLifetime) {
        self.targets = targets; self.values = values; self.lifetime = lifetime
    }

    public func target<Snapshot>(_ kind: Entity<Snapshot>, id: String) throws -> Entity<Snapshot> {
        try lifetime.withOpen { try targets.registerObserved(kind, id: id) }
    }

    public func publish<Snapshot>(_ entity: Entity<Snapshot>, snapshot: Snapshot) throws {
        try lifetime.withOpen {
            guard entity.mode == .state else {
                throw DeviceReadoutError(.invalidConfiguration, "Sensor samples require a sensor source.")
            }
            _ = try targets.validate(entity)
            values.publish(entity, snapshot: snapshot)
        }
    }
}

private struct ObservedAddress: Hashable {
    let kind: EntityKind
    let binding: TargetBinding?
}

// Snapshot values are immutable and Sendable. Publication only exchanges a reference/value;
// normalization and timestamp assembly happen when the collection worker consumes it.
final class ObservedValues: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [ObservedAddress: any DeviceSnapshot] = [:]
    private var listeners: [ObservedAddress: [UUID: AsyncThrowingStream<any DeviceSnapshot, Error>.Continuation]] = [:]

    func publish<Snapshot>(_ entity: Entity<Snapshot>, snapshot: Snapshot) {
        let address = ObservedAddress(kind: entity.kind, binding: entity.binding)
        lock.lock()
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

    func close() {
        lock.lock()
        values.removeAll()
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
