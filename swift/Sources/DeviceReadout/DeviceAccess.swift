import Foundation

// Configured views share thread-safe worker, lifetime and target state; configuration is immutable.
public final class DeviceAccess: @unchecked Sendable {
    private let collector: any DeviceCollector
    private let worker: CollectionWorker
    private let targets: TargetRegistry
    private let lifetime: ContextLifetime
    private let observed: ObservedValues
    private let failures: ObservedFailures
    public var observers: ObserverInputs { ObserverInputs(targets: targets, values: observed, lifetime: lifetime, failures: failures) }
    public let readTimeout: Duration
    public let pollInterval: Duration

    public init(collector: any DeviceCollector) {
        self.collector = collector
        worker = CollectionWorker()
        targets = TargetRegistry()
        lifetime = ContextLifetime()
        observed = ObservedValues()
        failures = ObservedFailures()
        readTimeout = .seconds(5)
        pollInterval = .seconds(1)
    }

    private init(collector: any DeviceCollector, worker: CollectionWorker, targets: TargetRegistry, lifetime: ContextLifetime, observed: ObservedValues, failures: ObservedFailures, readTimeout: Duration, pollInterval: Duration) {
        self.collector = collector; self.worker = worker; self.readTimeout = readTimeout
        self.targets = targets
        self.lifetime = lifetime
        self.observed = observed
        self.failures = failures
        self.pollInterval = pollInterval
    }

    public func withReadTimeout(_ duration: Duration) throws -> DeviceAccess {
        guard duration > .zero else {
            throw DeviceReadoutError(.invalidConfiguration, "Read timeout must be positive.")
        }
        return DeviceAccess(collector: collector, worker: worker, targets: targets, lifetime: lifetime, observed: observed, failures: failures, readTimeout: duration, pollInterval: pollInterval)
    }

    public func withPollInterval(_ duration: Duration) throws -> DeviceAccess {
        guard duration > .zero else {
            throw DeviceReadoutError(.invalidConfiguration, "Poll interval must be positive.")
        }
        return DeviceAccess(collector: collector, worker: worker, targets: targets, lifetime: lifetime, observed: observed, failures: failures, readTimeout: readTimeout, pollInterval: duration)
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
            let failure = try failures.observe(ObservedAddress(kind: entity.kind, binding: entity.binding)) { error in
                continuation.finish(throwing: error)
            }
            defer { failure.cancel() }
            let firstDeadline = ContinuousClock.now.advanced(by: readTimeout)
            // Open the app input before starting native work so a later publication cannot
            // be missed between source selection and the first native read.
            let subscription = observed.subscribe(entity)
            defer { subscription.cancel() }
            let reader = ObservedReader(subscription.stream)
            var value: Snapshot
            if entity.binding?.observed == true || observed.owns(entity) {
                // The first publication and its normalization share one read deadline.
                value = try await readObserved(entity, source: { try await reader.requireNext() })
            } else {
                let polling = Task.detached(priority: .utility) { [self] in
                    var delivered = false
                    do {
                        while true {
                            try Task.checkCancellation()
                            let native = try await get(entity)
                            try Task.checkCancellation()
                            guard try observed.whileUnpublished(entity, {
                                try deliver(native, to: continuation)
                            }) == true else { return delivered }
                            delivered = true
                            try await Task.sleep(for: pollInterval)
                        }
                    } catch {
                        if !Task.isCancelled {
                            observed.whileUnpublished(entity) { continuation.finish(throwing: error) }
                        }
                    }
                    return delivered
                }
                defer { polling.cancel() }
                guard let raw = try await reader.next() else { return }
                polling.cancel()
                // get cancellation ends the SDK task independently of its native worker.
                // Join only that SDK polling task before delivering the app's ordered buffer.
                let alreadyDelivered = await polling.value
                let readAccess: DeviceAccess
                if alreadyDelivered { readAccess = self }
                else {
                    let remaining = ContinuousClock.now.duration(to: firstDeadline)
                    guard remaining > .zero else {
                        throw DeviceReadoutError(.readTimeout, "Read deadline exceeded.")
                    }
                    readAccess = try withReadTimeout(remaining)
                }
                value = try await readAccess.readObserved(entity, source: { raw })
            }
            while true {
                try Task.checkCancellation()
                guard try deliver(value, to: continuation) else { return }
                // Waiting for the next real event has no read deadline.
                guard let raw = try await reader.next() else { return }
                value = try await perform { [self] active, _ in
                    guard active() else { throw CancellationError() }
                    return try prepareObserved(entity, raw: raw)
                }
            }
        }
    }

    private func deliver<Snapshot>(_ value: Snapshot, to continuation: AsyncThrowingStream<Snapshot, Error>.Continuation) throws -> Bool {
        switch continuation.yield(value) {
        case .enqueued: return true
        case .terminated: return false
        case .dropped:
            throw DeviceReadoutError(.readFailed, "The snapshot delivery queue is full.")
        @unknown default:
            throw DeviceReadoutError(.readFailed, "Unknown snapshot delivery result.")
        }
    }

    public func get<Snapshot>(_ entity: Entity<Snapshot>) async throws -> Snapshot {
        let revision = failures.version
        _ = try targets.validate(entity)
        if entity.binding?.observed == true || observed.owns(entity) {
            let subscription = observed.subscribe(entity)
            defer { subscription.cancel() }
            let reader = ObservedReader(subscription.stream)
            return try await readObserved(entity, startingAt: revision, source: { try await reader.requireNext() })
        }
        return try await perform(target: (entity.kind, entity.binding), startingAt: revision) { [self] active, _ in
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
        let revision = failures.version
        guard kind.requiresTarget, kind.binding == nil else {
            throw DeviceReadoutError(.invalidConfiguration, "Expected an unbound multi-target entity kind.")
        }
        return try await perform(failureScope: (kind.kind, nil), startingAt: revision) { [self] active, _ in
            if let appTargets = targets.observedList(kind) { return PreparedRead(value: appTargets) }
            let version = targets.nativeRemovalVersion()
            let ids = try collector.list(kind.kind)
            guard active() else { throw CancellationError() }
            if let appTargets = targets.observedList(kind) { return PreparedRead(value: appTargets) }
            return try targets.prepare(kind, ids: ids, since: version)
        }
    }

    public func current<Snapshot>(_ kind: Entity<Snapshot>) async throws -> Entity<Snapshot>? {
        let revision = failures.version
        guard kind.requiresTarget, kind.binding == nil else {
            throw DeviceReadoutError(.invalidConfiguration, "Expected an unbound multi-target entity kind.")
        }
        return try await perform(failureScope: (kind.kind, nil), startingAt: revision) { [self] active, _ in
            if let selection = targets.observedCurrent(kind) { return PreparedRead(value: selection.value) }
            let version = targets.nativeRemovalVersion()
            let id = try collector.current(kind.kind)
            guard active() else { throw CancellationError() }
            if let selection = targets.observedCurrent(kind) { return PreparedRead(value: selection.value) }
            return try targets.prepareCurrent(kind, id: id, since: version)
        }
    }

    private func readObserved<Snapshot>(
        _ entity: Entity<Snapshot>, startingAt revision: UInt64? = nil, source: @escaping @Sendable () async throws -> any DeviceSnapshot
    ) async throws -> Snapshot {
        try await perform(source: source, target: (entity.kind, entity.binding), startingAt: revision) { [self] active, raw in
            guard active() else { throw CancellationError() }
            guard let raw = raw else {
                throw DeviceReadoutError(.readFailed, "No observed state was supplied.")
            }
            return try prepareObserved(entity, raw: raw)
        }
    }

    private func prepareObserved<Snapshot>(_ entity: Entity<Snapshot>, raw: any DeviceSnapshot) throws -> PreparedRead<Snapshot> {
        _ = try targets.validate(entity)
        guard let snapshot = raw as? any CollectibleSnapshot,
              let value = snapshot.collected(at: Date()) as? Snapshot else {
            throw DeviceReadoutError(.readFailed, "Observed state has the wrong snapshot type.")
        }
        return PreparedRead(value: value)
    }

    private func perform<Value: Sendable>(
        source: (@Sendable () async throws -> any DeviceSnapshot)? = nil,
        target: (EntityKind, TargetBinding?)? = nil,
        failureScope: (EntityKind, TargetBinding?)? = nil,
        startingAt revision: UInt64? = nil,
        _ collect: @escaping @Sendable (@Sendable () -> Bool, (any DeviceSnapshot)?) throws -> PreparedRead<Value>
    ) async throws -> Value {
        try Task.checkCancellation()
        let operation = ReadOperation<Value>()
        let registration = try lifetime.register {
            operation.resolve(.failure(DeviceReadoutError(.entityRemoved, "DeviceAccess is closed.")))
        }
        defer { registration.cancel() }
        let removal = try target.map { kind, binding in
            try targets.observeRemoval(kind: kind, binding: binding) {
                operation.resolve(.failure(DeviceReadoutError(.entityRemoved, "The selected target was removed.")))
            }
        }
        defer { removal?.cancel() }
        let failure = try (failureScope ?? target).map { kind, binding in
            try failures.observe(ObservedAddress(kind: kind, binding: binding), startingAt: revision) { error in operation.resolve(.failure(error)) }
        }
        defer { failure?.cancel() }
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
                let submit: @Sendable ((any DeviceSnapshot)?) -> Void = { [worker, lifetime] raw in
                    let accepted = worker.enqueue {
                        guard !operation.isFinished else { return }
                        do {
                            let prepared = try collect({ !operation.isFinished }, raw)
                            var committed = false
                            if let finish = lifetime.accept({
                                if let error = failure?.errorSinceStart() { return operation.claim(.failure(error)) }
                                committed = true
                                return operation.claim(prepared.result, commit: prepared.commit)
                            }) {
                                finish()
                                if committed { prepared.didCommit() }
                            }
                        } catch let error as DeviceReadoutError {
                            lifetime.accept { operation.claim(.failure(failure?.errorSinceStart() ?? error)) }?()
                        } catch {
                            lifetime.accept {
                                operation.claim(.failure(failure?.errorSinceStart() ?? DeviceReadoutError(.readFailed, "Collector read failed: \(error)")))
                            }?()
                        }
                    }
                    if !accepted {
                        lifetime.accept {
                            operation.claim(.failure(failure?.errorSinceStart() ?? DeviceReadoutError(.readFailed, "The collection queue is full.")))
                        }?()
                    }
                }
                if let source = source {
                    let preparation = Task.detached(priority: .utility) { [lifetime] in
                        do {
                            let raw = try await source()
                            guard !operation.isFinished else { return }
                            submit(raw)
                        } catch let error as DeviceReadoutError {
                            lifetime.accept { operation.claim(.failure(failure?.errorSinceStart() ?? error)) }?()
                        } catch {
                            lifetime.accept {
                                operation.claim(.failure(failure?.errorSinceStart() ?? DeviceReadoutError(.readFailed, "Observed state read failed: \(error)")))
                            }?()
                        }
                    }
                    operation.installPreparation(preparation)
                } else { submit(nil) }
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
    private var preparation: Task<Void, Never>?

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

    func installPreparation(_ preparation: Task<Void, Never>) {
        lock.lock()
        if result != nil { lock.unlock(); preparation.cancel() }
        else { self.preparation = preparation; lock.unlock() }
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
        let preparation = self.preparation
        self.continuation = nil; self.timer = nil; self.preparation = nil
        lock.unlock()
        return {
            timer?.cancel()
            preparation?.cancel()
            continuation?.resume(with: result)
        }
    }
}
