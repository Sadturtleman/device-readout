import Foundation

// All stored state is immutable; DispatchQueue serializes the collector and is safe to submit from any task.
public final class DeviceAccess: @unchecked Sendable {
    private let collector: any DeviceCollector
    private let worker: DispatchQueue
    public let readTimeout: Duration

    public init(collector: any DeviceCollector) {
        self.collector = collector
        worker = DispatchQueue(label: "DeviceReadout collector", qos: .utility)
        readTimeout = .seconds(5)
    }

    private init(collector: any DeviceCollector, worker: DispatchQueue, readTimeout: Duration) {
        self.collector = collector; self.worker = worker; self.readTimeout = readTimeout
    }

    public func withReadTimeout(_ duration: Duration) throws -> DeviceAccess {
        guard duration > .zero else {
            throw DeviceReadoutError(.invalidConfiguration, "Read timeout must be positive.")
        }
        return DeviceAccess(collector: collector, worker: worker, readTimeout: duration)
    }

    public func get<Snapshot>(_ entity: Entity<Snapshot>) async throws -> Snapshot {
        if entity.requiresTarget {
            throw DeviceReadoutError(.invalidConfiguration, "Discover or observe a target before reading this entity.")
        }
        let operation = ReadOperation<Snapshot>()
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
                worker.async { [collector] in
                    guard !operation.isFinished else { return }
                    do {
                        let raw = try collector.read(EntityRequest(kind: entity.kind))
                        guard !operation.isFinished else { return }
                        guard let snapshot = raw as? any CollectibleSnapshot,
                              let value = snapshot.collected(at: Date()) as? Snapshot else {
                            throw DeviceReadoutError(.readFailed, "Collector returned the wrong snapshot type.")
                        }
                        operation.resolve(.success(value))
                    } catch let error as DeviceReadoutError {
                        operation.resolve(.failure(error))
                    } catch {
                        operation.resolve(.failure(DeviceReadoutError(.readFailed, "Collector read failed: \(error)")))
                    }
                }
            }
        } onCancel: {
            operation.resolve(.failure(CancellationError()))
        }
    }
}

// The lock protects only result/continuation ownership; it never surrounds collector work or callbacks.
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

    func resolve(_ result: Result<Value, Error>) {
        lock.lock()
        guard self.result == nil else { lock.unlock(); return }
        self.result = result
        let continuation = self.continuation
        let timer = self.timer
        self.continuation = nil; self.timer = nil
        lock.unlock()
        timer?.cancel()
        continuation?.resume(with: result)
    }
}
