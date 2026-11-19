#if os(macOS)
// Temporary public-API replay of the stalled XCTest scenario; remove after diagnosis.
import DeviceReadout
import Foundation

enum PermissionReplay {
    @MainActor
    static func run() async throws {
        for iteration in 1...1000 {
            try await cycle(iteration)
        }
        print("SWIFT_PERMISSION_REPLAY {\"passed\":true,\"iterations\":1000}")
    }

    private static func mark(_ iteration: Int, _ phase: String) {
        FileHandle.standardError.write(Data("[DEBUG-permission-replay] \(iteration) \(phase)\n".utf8))
    }

    @MainActor
    private static func cycle(_ iteration: Int) async throws {
        let access = DeviceAccess(collector: ReplayCollector())
        defer { access.close() }
        let policy = DeviceReadoutError(.permissionDenied, "Application refused this request")
        let old = try access.observers.onPermissionRequest { _ in throw policy }
        mark(iteration, "typed-request")
        do { _ = try await access.permissions.request(Entities.display); throw Failure.unexpectedSuccess }
        catch let error as DeviceReadoutError { guard error == policy else { throw Failure.incorrectError } }
        old.close()
        let failed = try access.observers.onPermissionRequest { _ in throw Failure.foreignError }
        old.close()
        mark(iteration, "foreign-request")
        do { _ = try await access.permissions.request(Entities.display); throw Failure.unexpectedSuccess }
        catch let error as DeviceReadoutError { guard error.code == .readFailed else { throw Failure.incorrectError } }
        failed.close()
        let successful = try access.observers.onPermissionRequest { request in
            guard request.kind == .display, request.targetId == nil, !request.observed else {
                throw Failure.unexpectedRequest
            }
            mark(iteration, "coordinator-publish")
            try access.observers.permission(Entities.display, status: .unavailable)
            mark(iteration, "coordinator-published")
            throw Failure.foreignError // The accepted publication must remain final.
        }
        defer { successful.close() }
        failed.close()
        guard try await access.permissions.check(Entities.display) == nil else { throw Failure.unexpectedStatus }
        mark(iteration, "list")
        _ = try await access.displays.list()
        mark(iteration, "current")
        _ = try await access.displays.current()
        try access.observers.publish(Entities.ram, snapshot: RamSnapshot(physicalBytes: 42))
        mark(iteration, "get-observed")
        let value = try await access.get(Entities.ram)
        guard value.physicalBytes == 42 else { throw Failure.incorrectRam }
        var stream = access.watch(Entities.ram).makeAsyncIterator()
        mark(iteration, "watch-observed")
        guard try await stream.next()?.physicalBytes == 42 else { throw Failure.incorrectRam }
        mark(iteration, "observed-request")
        guard try await access.permissions.request(Entities.display) == .unavailable else {
            throw Failure.unexpectedStatus
        }
        mark(iteration, "complete")
    }

    private struct ReplayCollector: DeviceCollector {
        func list(_ kind: EntityKind) throws -> [String] { ["screen"] }
        func read(_ request: EntityRequest) throws -> any DeviceSnapshot {
            throw Failure.unexpectedNativeRead
        }
    }

    private enum Failure: Error {
        case unexpectedSuccess, incorrectError, foreignError, unexpectedRequest
        case unexpectedStatus, incorrectRam, unexpectedNativeRead
    }
}
#endif
