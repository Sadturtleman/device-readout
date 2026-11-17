import Foundation

/// A cold, independently collected sequence of snapshots. Each iterator owns its collection task.
public struct DeviceStream<Element: DeviceSnapshot>: AsyncSequence, Sendable {
    private let produce: @Sendable (AsyncThrowingStream<Element, Error>.Continuation) async throws -> Void

    init(produce: @escaping @Sendable (AsyncThrowingStream<Element, Error>.Continuation) async throws -> Void) {
        self.produce = produce
    }

    public func makeAsyncIterator() -> Iterator {
        let control = ProducerControl()
        let stream = AsyncThrowingStream<Element, Error>(bufferingPolicy: .bufferingOldest(2048)) { continuation in
            continuation.onTermination = { _ in control.cancel() }
            let task = Task.detached(priority: .utility) { [produce] in
                do {
                    try Task.checkCancellation()
                    try await produce(continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            control.install(task)
        }
        return Iterator(base: stream.makeAsyncIterator(), lifetime: IterationLifetime(control: control))
    }

    public struct Iterator: AsyncIteratorProtocol {
        private var base: AsyncThrowingStream<Element, Error>.Iterator
        private let lifetime: IterationLifetime

        fileprivate init(base: AsyncThrowingStream<Element, Error>.Iterator, lifetime: IterationLifetime) {
            self.base = base; self.lifetime = lifetime
        }

        public mutating func next() async throws -> Element? {
            do {
                try Task.checkCancellation()
                let value = try await base.next()
                try Task.checkCancellation()
                if value == nil { lifetime.control.cancel() }
                return value
            } catch {
                lifetime.control.cancel()
                throw error
            }
        }
    }
}

// Kept only by the iterator, never by the producer or continuation. Dropping an iterator cancels
// its task even when the reusable sequence itself remains alive after a for-await break.
private final class IterationLifetime {
    let control: ProducerControl
    init(control: ProducerControl) { self.control = control }
    deinit { control.cancel() }
}

// Cancellation and task installation can race. Never cancel a task while holding the lock.
private final class ProducerControl: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void, Never>?
    private var cancelled = false

    func install(_ task: Task<Void, Never>) {
        lock.lock()
        if cancelled { lock.unlock(); task.cancel() }
        else { self.task = task; lock.unlock() }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let task = self.task
        self.task = nil
        lock.unlock()
        task?.cancel()
    }
}
