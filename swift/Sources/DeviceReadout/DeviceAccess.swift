import Foundation

// Configured views share thread-safe worker, lifetime and target state; configuration is immutable.
public final class DeviceAccess: @unchecked Sendable {
    private let collector: any DeviceCollector
    private let worker: CollectionWorker
    private let targets: TargetRegistry
    private let lifetime: ContextLifetime
    private let observed: ObservedValues
    public var observers: ObserverInputs { ObserverInputs(targets: targets, values: observed, lifetime: lifetime) }
    public let readTimeout: Duration
    public let pollInterval: Duration

    public init(collector: any DeviceCollector) {
        self.collector = collector
        worker = CollectionWorker()
        targets = TargetRegistry()
        lifetime = ContextLifetime()
        observed = ObservedValues()
        readTimeout = .seconds(5)
        pollInterval = .seconds(1)
    }

    private init(collector: any DeviceCollector, worker: CollectionWorker, targets: TargetRegistry, lifetime: ContextLifetime, observed: ObservedValues, readTimeout: Duration, pollInterval: Duration) {
        self.collector = collector; self.worker = worker; self.readTimeout = readTimeout
        self.targets = targets
        self.lifetime = lifetime
        self.observed = observed
        self.pollInterval = pollInterval
    }

    public func withReadTimeout(_ duration: Duration) throws -> DeviceAccess {
        guard duration > .zero else {
            throw DeviceReadoutError(.invalidConfiguration, "Read timeout must be positive.")
        }
        return DeviceAccess(collector: collector, worker: worker, targets: targets, lifetime: lifetime, observed: observed, readTimeout: duration, pollInterval: pollInterval)
    }

    public func withPollInterval(_ duration: Duration) throws -> DeviceAccess {
        guard duration > .zero else {
            throw DeviceReadoutError(.invalidConfiguration, "Poll interval must be positive.")
        }
        return DeviceAccess(collector: collector, worker: worker, targets: targets, lifetime: lifetime, observed: observed, readTimeout: readTimeout, pollInterval: duration)
    }

    /// Ends the shared context without waiting for native work or cleanup to finish.
    public func close() {
        guard lifetime.close() else { return }
        worker.cleanup { [collector, observed] in
            observed.close()
            do { try collector.close() }
            catch { /* Native cleanup failure must not escape the worker into the host. */ }
        }
    }

    public func watch<Snapshot>(_ entity: Entity<Snapshot>) -> DeviceStream<Snapshot> {
        DeviceStream { [self] continuation in
            let closure = try lifetime.register {
                continuation.finish(throwing: DeviceReadoutError(.entityRemoved, "DeviceAccess is closed."))
            }
            defer { closure.cancel() }
            guard entity.mode == .state else {
                throw DeviceReadoutError(.unsupportedEntity, "Sensor streaming requires a native or app-owned source.")
            }
            let removal = try targets.observeRemoval(entity) {
                continuation.finish(throwing: DeviceReadoutError(.entityRemoved, "The selected target was removed."))
            }
            defer { removal?.cancel() }
            if entity.binding?.observed == true || observed.value(entity) != nil {
                let subscription = observed.subscribe(entity)
                defer { subscription.cancel() }
                for try await raw in subscription.stream {
                    try Task.checkCancellation()
                    let value: Snapshot = try await perform { [self] active in
                        guard active() else { throw CancellationError() }
                        _ = try targets.validate(entity)
                        guard let snapshot = raw as? any CollectibleSnapshot,
                              let value = snapshot.collected(at: Date()) as? Snapshot else {
                            throw DeviceReadoutError(.readFailed, "Observed state has the wrong snapshot type.")
                        }
                        return PreparedRead(value: value)
                    }
                    switch continuation.yield(value) {
                    case .enqueued: break
                    case .terminated: return
                    case .dropped:
                        throw DeviceReadoutError(.readFailed, "The snapshot delivery queue is full.")
                    @unknown default:
                        throw DeviceReadoutError(.readFailed, "Unknown snapshot delivery result.")
                    }
                }
                return
            }
            while true {
                try Task.checkCancellation()
                let value = try await get(entity)
                try Task.checkCancellation()
                switch continuation.yield(value) {
                case .enqueued: break
                case .terminated: return
                case .dropped:
                    throw DeviceReadoutError(.readFailed, "The snapshot delivery queue is full.")
                @unknown default:
                    throw DeviceReadoutError(.readFailed, "Unknown snapshot delivery result.")
                }
                try await Task.sleep(for: pollInterval)
            }
        }
    }

    public func get<Snapshot>(_ entity: Entity<Snapshot>) async throws -> Snapshot {
        _ = try targets.validate(entity)
        return try await perform { [self] active in
            let request = try targets.validate(entity)
            let raw: any DeviceSnapshot
            do {
                if let cached = observed.value(entity) { raw = cached }
                else if entity.binding?.observed == true {
                    throw DeviceReadoutError(.readFailed, "The app has not supplied a state snapshot yet.")
                } else { raw = try collector.read(request) }
            }
            catch let error as DeviceReadoutError where error.code == .entityRemoved {
                return targets.prepareRemoval(entity, error: error)
            }
            guard active() else { throw CancellationError() }
            _ = try targets.validate(entity)
            guard let snapshot = (observed.value(entity) ?? raw) as? any CollectibleSnapshot,
                  let value = snapshot.collected(at: Date()) as? Snapshot else {
                throw DeviceReadoutError(.readFailed, "Collector returned the wrong snapshot type.")
            }
            return PreparedRead(value: value)
        }
    }

    public func list<Snapshot>(_ kind: Entity<Snapshot>) async throws -> [Entity<Snapshot>] {
        guard kind.requiresTarget, kind.binding == nil else {
            throw DeviceReadoutError(.invalidConfiguration, "Expected an unbound multi-target entity kind.")
        }
        return try await perform { [self] active in
            if let appTargets = targets.observedList(kind) { return PreparedRead(value: appTargets) }
            let ids = try collector.list(kind.kind)
            guard active() else { throw CancellationError() }
            if let appTargets = targets.observedList(kind) { return PreparedRead(value: appTargets) }
            return try targets.prepare(kind, ids: ids)
        }
    }

    public func current<Snapshot>(_ kind: Entity<Snapshot>) async throws -> Entity<Snapshot>? {
        guard kind.requiresTarget, kind.binding == nil else {
            throw DeviceReadoutError(.invalidConfiguration, "Expected an unbound multi-target entity kind.")
        }
        return try await perform { [self] active in
            let id = try collector.current(kind.kind)
            guard active() else { throw CancellationError() }
            return try targets.prepareCurrent(kind, id: id)
        }
    }

    private func perform<Value: Sendable>(
        _ collect: @escaping @Sendable (@Sendable () -> Bool) throws -> PreparedRead<Value>
    ) async throws -> Value {
        try Task.checkCancellation()
        let operation = ReadOperation<Value>()
        let registration = try lifetime.register {
            operation.resolve(.failure(DeviceReadoutError(.entityRemoved, "DeviceAccess is closed.")))
        }
        defer { registration.cancel() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                operation.bind(continuation)
                guard !operation.isFinished else { return }
                let timer = Task.detached(priority: .utility) { [readTimeout] in
                    do {
                        try await Task.sleep(for: readTimeout)
                        operation.resolve(.failure(DeviceReadoutError(.readTimeout, "Read deadline exceeded.")))
                    } catch { /* A completed read cancels its deadline task. */ }
                }
                operation.installTimer(timer)
                let accepted = worker.enqueue { [lifetime] in
                    guard !operation.isFinished else { return }
                    do {
                        let prepared = try collect { !operation.isFinished }
                        if let finish = lifetime.accept({ operation.claim(prepared.result, commit: prepared.commit) }) {
                            finish()
                            prepared.didCommit()
                        }
                    } catch let error as DeviceReadoutError {
                        lifetime.accept { operation.claim(.failure(error)) }?()
                    } catch {
                        lifetime.accept {
                            operation.claim(.failure(DeviceReadoutError(.readFailed, "Collector read failed: \(error)")))
                        }?()
                    }
                }
                if !accepted {
                    lifetime.accept {
                        operation.claim(.failure(DeviceReadoutError(.readFailed, "The collection queue is full.")))
                    }?()
                }
            }
        } onCancel: {
            operation.resolve(.failure(CancellationError()))
        }
    }
}

// The lock protects completion and acceptance of a prepared registry map. Native work, validation,
// map construction, notification callbacks and continuation resumption all run outside it.
private final class ReadOperation<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var result: Result<Value, Error>?
    private var timer: Task<Void, Never>?

    var isFinished: Bool { lock.lock(); defer { lock.unlock() }; return result != nil }

    func bind(_ continuation: CheckedContinuation<Value, Error>) {
        lock.lock()
        if let result = result {
            lock.unlock(); continuation.resume(with: result)
        } else {
            self.continuation = continuation; lock.unlock()
        }
    }

    func installTimer(_ timer: Task<Void, Never>) {
        lock.lock()
        if result != nil { lock.unlock(); timer.cancel() }
        else { self.timer = timer; lock.unlock() }
    }

    @discardableResult
    func resolve(_ result: Result<Value, Error>, commit: () -> Void = {}) -> Bool {
        guard let finish = claim(result, commit: commit) else { return false }
        finish()
        return true
    }

    func claim(_ result: Result<Value, Error>, commit: () -> Void = {}) -> (() -> Void)? {
        lock.lock()
        guard self.result == nil else { lock.unlock(); return nil }
        commit()
        self.result = result
        let continuation = self.continuation
        let timer = self.timer
        self.continuation = nil; self.timer = nil
        lock.unlock()
        return {
            timer?.cancel()
            continuation?.resume(with: result)
        }
    }
}
