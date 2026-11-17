import Foundation

/// An independently owned error input. Closing it clears only this source's active error.
public final class ObserverFailureSource: Sendable {
    private let send: @Sendable (DeviceReadoutError?) throws -> Void
    private let dispose: @Sendable () -> Void
    init(send: @escaping @Sendable (DeviceReadoutError?) throws -> Void, dispose: @escaping @Sendable () -> Void) {
        self.send = send; self.dispose = dispose
    }
    public func publish(_ error: DeviceReadoutError?) throws { try send(error) }
    public func close() { dispose() }
    deinit { dispose() }
}

// Only SDK completion signals are registered here. Native work and callbacks run elsewhere.
final class ObservedFailures: @unchecked Sendable {
    private struct Entry {
        let error: DeviceReadoutError
        let revision: UInt64
    }
    private struct Listener {
        let address: ObservedAddress
        let fail: @Sendable (DeviceReadoutError) -> Void
    }
    private struct SourceEntry {
        let failure: Entry
        let activation: UInt64
    }
    private let lock = NSLock()
    private var revision: UInt64 = 0
    private var direct: [ObservedAddress: Entry] = [:]
    private var history: [ObservedAddress: Entry] = [:]
    private var sources: [UUID: ObservedAddress] = [:]
    private var activeSources: [ObservedAddress: [UUID: SourceEntry]] = [:]
    private var listeners: [UUID: Listener] = [:]

    var version: UInt64 { lock.lock(); defer { lock.unlock() }; return revision }

    func createSource(_ address: ObservedAddress) -> UUID {
        lock.lock(); defer { lock.unlock() }
        let id = UUID(); sources[id] = address; return id
    }

    func closeSource(_ id: UUID) {
        lock.lock(); defer { lock.unlock() }
        guard let address = sources.removeValue(forKey: id) else { return }
        activeSources[address]?[id] = nil
        if activeSources[address]?.isEmpty == true { activeSources[address] = nil }
    }

    func changeSource(_ id: UUID, error: DeviceReadoutError?) throws -> () -> Void {
        lock.lock(); defer { lock.unlock() }
        guard let address = sources[id] else { throw DeviceReadoutError(.entityRemoved, "The failure source is closed.") }
        return changeLocked(address, source: id, error: error)
    }

    func change(_ address: ObservedAddress, error: DeviceReadoutError?) -> () -> Void {
        lock.lock(); defer { lock.unlock() }
        return changeLocked(address, source: nil, error: error)
    }

    private func changeLocked(_ address: ObservedAddress, source: UUID?, error: DeviceReadoutError?) -> () -> Void {
        guard let error = error else {
            if let source = source {
                activeSources[address]?[source] = nil
                if activeSources[address]?.isEmpty == true { activeSources[address] = nil }
            } else { direct[address] = nil }
            return {}
        }
        revision += 1
        let entry = Entry(error: error, revision: revision)
        if let source = source {
            let activation = activeSources[address]?[source]?.activation ?? revision
            activeSources[address, default: [:]][source] = SourceEntry(failure: entry, activation: activation)
        }
        else { direct[address] = entry }
        history[address] = entry
        let affected = listeners.filter { address.contains($0.value.address) }
        for id in affected.keys { listeners[id] = nil }
        return { for listener in affected.values { listener.fail(error) } }
    }

    func observe(_ address: ObservedAddress, startingAt requested: UInt64? = nil, fail: @escaping @Sendable (DeviceReadoutError) -> Void) throws -> FailureObservation {
        let id = UUID()
        lock.lock()
        if let error = failureLocked(address, since: requested) { lock.unlock(); throw error }
        let start = requested ?? revision
        listeners[id] = Listener(address: address, fail: fail)
        lock.unlock()
        return FailureObservation(errorSinceStart: { [self] in
            lock.lock(); defer { lock.unlock() }
            return failureLocked(address, since: start)
        }, dispose: { [self] in
            lock.lock(); listeners[id] = nil; lock.unlock()
        })
    }

    // The caller holds the lock. A query crosses both its exact address and any kind-wide failure.
    private func failureLocked(_ address: ObservedAddress, since start: UInt64?) -> DeviceReadoutError? {
        let family = ObservedAddress(kind: address.kind, binding: nil)
        let scopes = address.binding == nil ? [family] : [address, family]
        // Match the other bindings: direct app policy precedes provider state, and exact
        // target scope precedes kind scope within each group. Provider updates keep their place.
        for scope in scopes { if let entry = direct[scope] { return entry.error } }
        for scope in scopes {
            if let entry = activeSources[scope]?.values.min(by: { $0.activation < $1.activation }) { return entry.failure.error }
        }
        guard let start = start else { return nil }
        return scopes.compactMap { history[$0] }.filter { $0.revision > start }.max { $0.revision < $1.revision }?.error
    }
}

struct FailureObservation: Sendable {
    let errorSinceStart: @Sendable () -> DeviceReadoutError?
    let dispose: @Sendable () -> Void
    func cancel() { dispose() }
}
