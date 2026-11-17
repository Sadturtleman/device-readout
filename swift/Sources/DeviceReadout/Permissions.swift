import Foundation

public enum PermissionStatus: String, Sendable {
    case granted, denied, notDetermined, restricted, unavailable
}

public struct PermissionRequest: Sendable {
    public let kind: EntityKind
    public let targetId: String?
    public let observed: Bool
}

/// The app owns UI dispatch and publishes the resulting status through ObserverInputs.permission.
public typealias PermissionCoordinator = @Sendable (PermissionRequest) async throws -> Void

public final class PermissionCoordinatorRegistration: Sendable {
    private let dispose: @Sendable () -> Void
    init(dispose: @escaping @Sendable () -> Void) { self.dispose = dispose }
    /// Unregisters future requests. Requests already dispatched retain their captured coordinator.
    public func close() { dispose() }
    deinit { dispose() }
}

/// Reads application-observed authorization. No native permission query or prompt is performed.
public struct PermissionAccess: Sendable {
    private let targets: TargetRegistry
    private let lifetime: ContextLifetime
    private let state: ObservedPermissions
    init(targets: TargetRegistry, lifetime: ContextLifetime, state: ObservedPermissions) {
        self.targets = targets; self.lifetime = lifetime; self.state = state
    }

    public func check<Snapshot>(_ entity: Entity<Snapshot>) async throws -> PermissionStatus? {
        try Task.checkCancellation()
        return try lifetime.withOpen {
            if !entity.requiresTarget || entity.binding != nil { _ = try targets.validate(entity) }
            return state.check(ObservedAddress(kind: entity.kind, binding: entity.binding))
        }
    }

    /// Explicit app-mediated request. User response waiting has no read timeout.
    public func request<Snapshot>(_ entity: Entity<Snapshot>) async throws -> PermissionStatus? {
        try Task.checkCancellation()
        let operation = PermissionOperation()
        let id = UUID()
        let closure = try lifetime.register {
            operation.resolve(.failure(DeviceReadoutError(.entityRemoved, "DeviceAccess is closed.")))
        }
        defer { closure.cancel(); state.removeRequest(id) }
        let removal = try (!entity.requiresTarget || entity.binding != nil) ? targets.observeRemoval(entity) {
            operation.resolve(.failure(DeviceReadoutError(.entityRemoved, "The selected target was removed.")))
        } : nil
        defer { removal?.cancel() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                operation.bind(continuation)
                guard !operation.isFinished else { return }
                do {
                    let plan = try lifetime.withOpen {
                        if !entity.requiresTarget || entity.binding != nil { _ = try targets.validate(entity) }
                        return try state.prepare(ObservedAddress(kind: entity.kind, binding: entity.binding), id: id, operation: operation) {
                            if !entity.requiresTarget || entity.binding != nil { _ = try targets.validate(entity) }
                        }
                    }
                    plan.finish?()
                    guard let coordinator = plan.coordinator, !operation.isFinished else { return }
                    let request = PermissionRequest(kind: entity.kind, targetId: entity.binding?.id, observed: entity.binding?.observed ?? false)
                    let task = Task.detached(priority: .utility) {
                        guard !operation.isFinished else { return }
                        do {
                            try Task.checkCancellation()
                            try await coordinator(request)
                        } catch let error as DeviceReadoutError { operation.resolve(.failure(error)) }
                        catch is CancellationError { operation.resolve(.failure(CancellationError())) }
                        catch { operation.resolve(.failure(DeviceReadoutError(.readFailed, "Application permission coordinator failed."))) }
                    }
                    operation.install(task)
                } catch { operation.resolve(.failure(error)) }
            }
        } onCancel: { operation.resolve(.failure(CancellationError())) }
    }
}

final class ObservedPermissions: @unchecked Sendable {
    private struct Value { let status: PermissionStatus? }
    private struct Listener {
        let address: ObservedAddress
        let operation: PermissionOperation
        let validate: @Sendable () throws -> Void
    }
    private struct Coordinator { let id: UUID; let invoke: PermissionCoordinator }
    private let lock = NSLock()
    private var values: [ObservedAddress: Value] = [:]
    private var listeners: [UUID: Listener] = [:]
    private var coordinator: Coordinator?

    func check(_ address: ObservedAddress) -> PermissionStatus? {
        lock.lock(); defer { lock.unlock() }
        return checkLocked(address)
    }

    private func checkLocked(_ address: ObservedAddress) -> PermissionStatus? {
        (values[address] ?? values[ObservedAddress(kind: address.kind, binding: nil)])?.status
    }

    // Claim SDK results under the state/lifetime gates, resume callers after unlocking.
    func publish(_ address: ObservedAddress, status: PermissionStatus?) -> () -> Void {
        lock.lock()
        values[address] = Value(status: status)
        let affected = listeners.filter { _, listener in
            listener.address == address || (address.binding == nil && listener.address.kind == address.kind && values[listener.address] == nil)
        }
        var completions: [() -> Void] = []
        for (id, listener) in affected {
            listeners[id] = nil
            // Target removal retires its generation before sending terminal notifications.
            // A kind publication in that gap must not accept a removed target's response.
            do {
                try listener.validate()
                if let complete = listener.operation.claim(.success(status)) { completions.append(complete) }
            } catch {
                if let complete = listener.operation.claim(.failure(error)) { completions.append(complete) }
            }
        }
        lock.unlock()
        return { for complete in completions { complete() } }
    }

    func coordinate(_ invoke: @escaping PermissionCoordinator) throws -> PermissionCoordinatorRegistration {
        lock.lock()
        guard coordinator == nil else {
            lock.unlock()
            throw DeviceReadoutError(.invalidConfiguration, "A permission coordinator is already registered.")
        }
        let id = UUID()
        coordinator = Coordinator(id: id, invoke: invoke)
        lock.unlock()
        return PermissionCoordinatorRegistration { [self] in
            lock.lock()
            let previous = coordinator?.id == id ? coordinator : nil
            if previous != nil { coordinator = nil }
            lock.unlock()
            withExtendedLifetime(previous) { }
        }
    }

    fileprivate func prepare(_ address: ObservedAddress, id: UUID, operation: PermissionOperation, validate: @escaping @Sendable () throws -> Void) throws -> (coordinator: PermissionCoordinator?, finish: (() -> Void)?) {
        lock.lock(); defer { lock.unlock() }
        if checkLocked(address) == .granted { return (nil, operation.claim(.success(.granted))) }
        guard let coordinator = coordinator else {
            throw DeviceReadoutError(.unsupportedEntity, "Register the application's permission coordinator.")
        }
        listeners[id] = Listener(address: address, operation: operation, validate: validate)
        return (coordinator.invoke, nil)
    }

    func removeRequest(_ id: UUID) {
        lock.lock(); listeners[id] = nil; lock.unlock()
    }

    func close() {
        lock.lock()
        let previous = coordinator
        coordinator = nil
        values.removeAll()
        listeners.removeAll()
        lock.unlock()
        withExtendedLifetime(previous) { }
    }
}

// Caller completion never joins application work, including application cancellation handlers.
private final class PermissionOperation: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<PermissionStatus?, Error>?
    private var continuation: CheckedContinuation<PermissionStatus?, Error>?
    private var coordinator: Task<Void, Never>?
    var isFinished: Bool { lock.lock(); defer { lock.unlock() }; return result != nil }

    func bind(_ continuation: CheckedContinuation<PermissionStatus?, Error>) {
        lock.lock()
        if let result = result { lock.unlock(); continuation.resume(with: result) }
        else { self.continuation = continuation; lock.unlock() }
    }

    func install(_ task: Task<Void, Never>) {
        lock.lock()
        if result != nil { lock.unlock(); cancel(task) }
        else { coordinator = task; lock.unlock() }
    }

    func resolve(_ result: Result<PermissionStatus?, Error>) { claim(result)?() }

    func claim(_ result: Result<PermissionStatus?, Error>) -> (() -> Void)? {
        lock.lock()
        guard self.result == nil else { lock.unlock(); return nil }
        self.result = result
        let continuation = self.continuation
        let coordinator = self.coordinator
        self.continuation = nil; self.coordinator = nil
        lock.unlock()
        return { [self] in
            if let coordinator = coordinator { cancel(coordinator) }
            continuation?.resume(with: result)
        }
    }

    private func cancel(_ task: Task<Void, Never>) {
        DispatchQueue.global(qos: .utility).async { task.cancel() }
    }
}
