import Foundation

struct SensorActivityState: Sendable {
    let active: Bool
    let generation: UInt64
}

// Only application-supplied policy is observed. No foreground/window getter belongs here.
final class SensorActivity: @unchecked Sendable {
    private let lock = NSLock()
    private var state = SensorActivityState(active: true, generation: 0)
    private var listeners: [UUID: SensorActivityControl] = [:]

    func change(_ active: Bool) -> () -> Void {
        lock.lock()
        guard state.active != active else { lock.unlock(); return {} }
        state = SensorActivityState(active: active, generation: state.generation + 1)
        let next = state
        let listeners = Array(listeners.values)
        lock.unlock()
        return { for listener in listeners { listener.change(next) } }
    }

    func isCurrent(_ value: SensorActivityState) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return state.active && state.generation == value.generation
    }

    // Serialize SDK-owned output acceptance with activity changes; never invoke application code.
    func accept<Value>(_ value: SensorActivityState, _ action: () throws -> Value) rethrows -> Value? {
        lock.lock(); defer { lock.unlock() }
        guard state.active && state.generation == value.generation else { return nil }
        return try action()
    }

    func observe() -> SensorActivityObservation {
        let id = UUID()
        let control = SensorActivityControl()
        lock.lock()
        listeners[id] = control
        let initial = state
        lock.unlock()
        control.change(initial)
        return SensorActivityObservation(control: control, dispose: { [self] in
            lock.lock(); listeners[id] = nil; lock.unlock()
            control.close()
        })
    }
}

struct SensorActivityObservation: Sendable {
    let control: SensorActivityControl
    let dispose: @Sendable () -> Void
    func cancel() { dispose() }
}

// Activity notifications and installation may race. Only SDK tasks/sessions are canceled here.
final class SensorActivityControl: @unchecked Sendable {
    let stream: AsyncThrowingStream<SensorActivityState, Error>
    private let continuation: AsyncThrowingStream<SensorActivityState, Error>.Continuation
    private let lock = NSLock()
    private var latest: UInt64?
    private var closed = false
    private var session: SensorSession?
    private var task: Task<Void, Error>?

    init() {
        var continuation: AsyncThrowingStream<SensorActivityState, Error>.Continuation!
        stream = AsyncThrowingStream(bufferingPolicy: .bufferingOldest(64)) { continuation = $0 }
        self.continuation = continuation
    }

    func change(_ state: SensorActivityState) {
        lock.lock()
        guard !closed, latest == nil || state.generation > latest! else { lock.unlock(); return }
        latest = state.generation
        let session = self.session; self.session = nil
        let task = self.task; self.task = nil
        lock.unlock()
        session?.stop()
        task?.cancel()
        lock.lock()
        guard !closed, latest == state.generation else { lock.unlock(); return }
        let result = continuation.yield(state)
        if case .dropped = result { closed = true }
        lock.unlock()
        if case .dropped = result {
            continuation.finish(throwing: DeviceReadoutError(.readFailed, "The sensor activity queue is full."))
        }
    }

    func install(_ session: SensorSession, for state: SensorActivityState) -> Bool {
        lock.lock()
        guard !closed, latest == state.generation else { lock.unlock(); session.stop(); return false }
        self.session = session
        lock.unlock()
        return true
    }

    func install(_ task: Task<Void, Error>, for state: SensorActivityState) {
        lock.lock()
        guard !closed, latest == state.generation else { lock.unlock(); task.cancel(); return }
        self.task = task
        lock.unlock()
    }

    func close() {
        lock.lock()
        closed = true
        let session = self.session; self.session = nil
        let task = self.task; self.task = nil
        lock.unlock()
        session?.stop()
        task?.cancel()
        continuation.finish()
    }
}
