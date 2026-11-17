import Foundation

// DispatchQueue owns execution; the lock only bounds waiting work. Cleanup of already owned
// native resources has a separate admission path so saturation cannot suppress cleanup.
final class CollectionWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "DeviceReadout collector", qos: .utility)
    private let lock = NSLock()
    private var waiting = 0

    func enqueue(_ work: @escaping @Sendable () -> Void) -> Bool {
        lock.lock()
        guard waiting < 128 else { lock.unlock(); return false }
        waiting += 1
        queue.async { [self] in
            lock.lock(); waiting -= 1; lock.unlock()
            work()
        }
        lock.unlock()
        return true
    }

    func cleanup(_ work: @escaping @Sendable () -> Void) { queue.async(execute: work) }
}
