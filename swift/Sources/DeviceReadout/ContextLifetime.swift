import Foundation

// Shared by immutable configured views. No native calls, continuation resumption or notification
// callbacks execute under this lock. Acceptance holds it only while claiming a prepared result.
final class ContextLifetime: @unchecked Sendable {
    private let lock = NSLock()
    private var closed = false
    private var listeners: [UUID: @Sendable () -> Void] = [:]

    // Register SDK cancellation/delivery signals only. Native cleanup belongs on CollectionWorker.
    func register(_ onClose: @escaping @Sendable () -> Void) throws -> ContextRegistration {
        let id = UUID()
        lock.lock()
        guard !closed else {
            lock.unlock()
            throw DeviceReadoutError(.entityRemoved, "DeviceAccess is closed.")
        }
        listeners[id] = onClose
        lock.unlock()
        return ContextRegistration { [self] in
            lock.lock(); listeners[id] = nil; lock.unlock()
        }
    }

    func accept(_ claim: () -> (() -> Void)?) -> (() -> Void)? {
        lock.lock(); defer { lock.unlock() }
        guard !closed else { return nil }
        return claim()
    }

    // Only short SDK-state mutations belong here. Return notification work and run it after unlocking.
    func withOpen<Value>(_ action: () throws -> Value) throws -> Value {
        lock.lock(); defer { lock.unlock() }
        guard !closed else { throw DeviceReadoutError(.entityRemoved, "DeviceAccess is closed.") }
        return try action()
    }

    func close() -> Bool {
        lock.lock()
        guard !closed else { lock.unlock(); return false }
        closed = true
        let callbacks = listeners
        listeners.removeAll()
        lock.unlock()
        for callback in callbacks.values { callback() }
        return true
    }
}

struct ContextRegistration: Sendable {
    private let dispose: @Sendable () -> Void
    init(dispose: @escaping @Sendable () -> Void) { self.dispose = dispose }
    func cancel() { dispose() }
}
