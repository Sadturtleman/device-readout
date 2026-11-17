import Foundation

public struct SensorSamplingRate: Equatable, Sendable {
    public let requestedHertz: Double?
    private init(_ value: Double?) { requestedHertz = value }
    public static let platformDefault = SensorSamplingRate(nil)
    public static func hertz(_ value: Double) throws -> SensorSamplingRate {
        guard value.isFinite, value > 0 else { throw DeviceReadoutError(.invalidConfiguration, "Sampling frequency must be positive and finite.") }
        return SensorSamplingRate(value)
    }
}

public typealias SensorCleanup = @Sendable () throws -> Void

/// One demanded observation. Publish sample data; normalization and timestamping run on the worker.
public struct SensorObserverSession<Snapshot: DeviceSnapshot>: Sendable {
    private let core: SensorSession
    init(core: SensorSession) { self.core = core }
    public var isStopped: Bool { core.isStopped }
    public var samplingRate: SensorSamplingRate { core.samplingRate }
    public func publish(_ snapshot: Snapshot) { core.publish(snapshot) }
    public func fail(_ error: DeviceReadoutError) { core.fail(error) }
}

public final class SensorSourceRegistration: Sendable {
    private let dispose: @Sendable () -> Void
    init(dispose: @escaping @Sendable () -> Void) { self.dispose = dispose }
    public func close() { dispose() }
    deinit { dispose() }
}

struct ObservedSensorSource: Sendable {
    let id: UUID
    let description: SensorDescription
    let subscribe: @Sendable (SensorSession) throws -> SensorCleanup?
}

final class ObservedSensorSources: @unchecked Sendable {
    let activity = SensorActivity()
    private let lock = NSLock()
    private var sources: [ObservedAddress: ObservedSensorSource] = [:]
    private var counts: [EntityKind: Int] = [:]

    func register<Snapshot>(_ entity: Entity<Snapshot>, description: SensorDescription, subscribe: @escaping @Sendable (SensorObserverSession<Snapshot>) throws -> SensorCleanup?) throws -> UUID {
        guard entity.mode != .state, entity.binding?.observed == true else {
            throw DeviceReadoutError(.invalidConfiguration, "Expected an app-owned sensor target.")
        }
        let address = ObservedAddress(kind: entity.kind, binding: entity.binding)
        lock.lock(); defer { lock.unlock() }
        guard sources[address] == nil else { throw DeviceReadoutError(.invalidConfiguration, "A sensor source is already registered for this target.") }
        let id = UUID()
        sources[address] = ObservedSensorSource(id: id, description: description, subscribe: { core in try subscribe(SensorObserverSession(core: core)) })
        counts[entity.kind, default: 0] += 1
        return id
    }

    func supports<Snapshot>(_ entity: Entity<Snapshot>) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if entity.binding == nil { return counts[entity.kind, default: 0] > 0 }
        return sources[ObservedAddress(kind: entity.kind, binding: entity.binding)] != nil
    }

    func source<Snapshot>(_ entity: Entity<Snapshot>) throws -> ObservedSensorSource {
        lock.lock(); defer { lock.unlock() }
        guard let source = sources[ObservedAddress(kind: entity.kind, binding: entity.binding)] else {
            throw DeviceReadoutError(.unsupportedEntity, "Register a sensor source for this target.")
        }
        return source
    }

    func remove<Snapshot>(_ entity: Entity<Snapshot>, expected: UUID? = nil) -> ObservedSensorSource? {
        let address = ObservedAddress(kind: entity.kind, binding: entity.binding)
        lock.lock(); defer { lock.unlock() }
        guard let source = sources[address], expected == nil || source.id == expected else { return nil }
        counts[entity.kind, default: 0] -= 1
        return sources.removeValue(forKey: address)
    }

    func close() {
        lock.lock(); let previous = sources; sources.removeAll(); counts.removeAll(); lock.unlock()
        withExtendedLifetime(previous) { }
    }
}

// No application callback runs under this lock or on the caller's execution path.
final class SensorSession: @unchecked Sendable {
    let samplingRate: SensorSamplingRate
    let stream: AsyncThrowingStream<any DeviceSnapshot, Error>
    private let continuation: AsyncThrowingStream<any DeviceSnapshot, Error>.Continuation
    private let readiness: AsyncThrowingStream<Bool, Error>
    private let ready: AsyncThrowingStream<Bool, Error>.Continuation
    private let worker: CollectionWorker
    private let current: @Sendable () -> Bool
    private let lock = NSLock()
    private var stopped = false
    private var cleanup: SensorCleanup?

    init(worker: CollectionWorker, samplingRate: SensorSamplingRate = .platformDefault, current: @escaping @Sendable () -> Bool = { true }) {
        self.worker = worker
        self.current = current
        self.samplingRate = samplingRate
        var continuation: AsyncThrowingStream<any DeviceSnapshot, Error>.Continuation!
        stream = AsyncThrowingStream(bufferingPolicy: .bufferingOldest(2048)) { continuation = $0 }
        self.continuation = continuation
        var ready: AsyncThrowingStream<Bool, Error>.Continuation!
        readiness = AsyncThrowingStream(bufferingPolicy: .bufferingOldest(1)) { ready = $0 }
        self.ready = ready
    }

    var isStopped: Bool { lock.lock(); let stopped = stopped; lock.unlock(); return stopped || !current() }

    func start(_ source: ObservedSensorSource) {
        let accepted = worker.enqueue { [self] in
            guard !isStopped else { return }
            do { install(try source.subscribe(self)) }
            catch let error as DeviceReadoutError { fail(error) }
            catch { fail(DeviceReadoutError(.readFailed, "Sensor source registration failed.")) }
        }
        if !accepted { fail(DeviceReadoutError(.readFailed, "The collection queue is full.")) }
    }

    private func install(_ cleanup: SensorCleanup?) {
        lock.lock()
        if stopped { lock.unlock(); release(cleanup) }
        else {
            self.cleanup = cleanup; lock.unlock()
            ready.yield(true); ready.finish()
        }
    }

    func waitUntilReady() async throws {
        var iterator = readiness.makeAsyncIterator()
        guard try await iterator.next() == true else {
            try Task.checkCancellation()
            throw DeviceReadoutError(.readFailed, "Sensor subscription ended before registration completed.")
        }
    }

    func publish(_ snapshot: any DeviceSnapshot) {
        guard current() else { return }
        lock.lock()
        guard !stopped else { lock.unlock(); return }
        let error: DeviceReadoutError
        switch continuation.yield(snapshot) {
        case .enqueued: lock.unlock(); return
        case .terminated: lock.unlock(); stop(); return
        case .dropped: error = DeviceReadoutError(.readFailed, "The sensor sample queue is full.")
        @unknown default: error = DeviceReadoutError(.readFailed, "Unknown sensor sample delivery result.")
        }
        // Stop accepting concurrent publications at the first overflow, before releasing the gate.
        stopped = true
        let cleanup = self.cleanup; self.cleanup = nil
        lock.unlock()
        continuation.finish(throwing: error)
        ready.finish(throwing: error)
        release(cleanup)
    }

    func fail(_ error: DeviceReadoutError) { if current() { finish(error: error) } }
    func stop() { finish(error: nil) }

    private func finish(error: DeviceReadoutError?) {
        lock.lock()
        guard !stopped else { lock.unlock(); return }
        stopped = true
        let cleanup = self.cleanup; self.cleanup = nil
        lock.unlock()
        if let error = error { continuation.finish(throwing: error); ready.finish(throwing: error) }
        else { continuation.finish(); ready.finish() }
        release(cleanup)
    }

    private func release(_ cleanup: SensorCleanup?) {
        guard let cleanup = cleanup else { return }
        worker.cleanup { do { try cleanup() } catch { /* Cleanup errors cannot escape into the application. */ } }
    }
}
