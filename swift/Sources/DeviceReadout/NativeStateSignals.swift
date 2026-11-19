import Foundation

// Only invalidations cross this boundary. Native reads and snapshot preparation
// remain serial on CollectionWorker; an idle subscription has no read deadline.
final class NativeStateSignals: @unchecked Sendable {
    enum Wake: Sendable { case change, poll }
    let stream: AsyncThrowingStream<Wake, Error>
    private let continuation: AsyncThrowingStream<Wake, Error>.Continuation
    private let worker: CollectionWorker
    private let lock = NSLock()
    private var closed = false
    private var cleanup: NativeStateCleanup?
    private var timer: Task<Void, Never>?
    private var timerGeneration: UInt64 = 0
    private var pollQueued = false

    init(worker: CollectionWorker) {
        self.worker = worker
        var output: AsyncThrowingStream<Wake, Error>.Continuation!
        stream = AsyncThrowingStream(bufferingPolicy: .bufferingOldest(2048)) { output = $0 }
        continuation = output
    }

    // Called on the worker. If registration returns after close/timeout, release
    // its resources here before the worker can execute collector.close().
    func installOnWorker(_ cleanup: NativeStateCleanup?) {
        lock.lock()
        if !closed { self.cleanup = cleanup; lock.unlock(); return }
        lock.unlock()
        do { try cleanup?() } catch { /* Cleanup cannot escape into the caller. */ }
    }

    func notify() { emit(.change) }

    private func emit(_ wake: Wake, generation: UInt64? = nil) {
        lock.lock()
        guard !closed else { lock.unlock(); return }
        if let generation {
            guard generation == timerGeneration, !pollQueued else { lock.unlock(); return }
            pollQueued = true
        }
        let result = continuation.yield(wake)
        lock.unlock()
        if case .dropped = result {
            continuation.finish(throwing: DeviceReadoutError(.readFailed, "The native invalidation queue is full."))
        }
    }

    func armPoll(_ interval: Duration) {
        lock.lock()
        guard !closed else { lock.unlock(); return }
        timerGeneration &+= 1
        let generation = timerGeneration, previous = timer
        timer = Task.detached(priority: .utility) { [weak self] in
            do { try await Task.sleep(for: interval); self?.emit(.poll, generation: generation) }
            catch { /* A native change or stop cancels this poll delay. */ }
        }
        lock.unlock()
        previous?.cancel()
    }

    func consumed(_ wake: Wake) {
        lock.lock()
        if case .poll = wake { pollQueued = false }
        timerGeneration &+= 1
        let previous = timer; timer = nil
        lock.unlock()
        previous?.cancel()
    }

    func close() {
        lock.lock()
        guard !closed else { lock.unlock(); return }
        closed = true
        let cleanup = self.cleanup, timer = self.timer
        self.cleanup = nil; self.timer = nil
        // Admit cleanup before another close can observe closed=true and let
        // collector.close overtake it. This only queues work; it never joins it.
        if let cleanup {
            worker.cleanup {
                do { try cleanup() } catch { /* Never unwind through the host. */ }
            }
        }
        lock.unlock()
        timer?.cancel()
        continuation.finish()
    }
}
