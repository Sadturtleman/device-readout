import DeviceReadout
import Foundation
import XCTest

final class PermissionTests: XCTestCase {
    @MainActor
    func testCoordinatorErrorsReplacementAndSynchronousPublicationHaveExplicitRequestSemantics() async throws {
        permissionPhase("start")
        let access = DeviceAccess(collector: PermissionCollector())
        defer { permissionPhase("close-context"); access.close(); permissionPhase("closed-context") }
        let policy = DeviceReadoutError(.permissionDenied, "App refused this permission request")
        let old = try access.observers.onPermissionRequest { _ in permissionPhase("typed-callback"); throw policy }
        permissionPhase("typed-request")
        do { _ = try await access.permissions.request(Entities.display); XCTFail("Typed application error") }
        catch let error as DeviceReadoutError { XCTAssertEqual(error, policy) }
        permissionPhase("typed-response")
        old.close()
        let failed = try access.observers.onPermissionRequest { _ in permissionPhase("foreign-callback"); throw PermissionTestError() }
        old.close()
        permissionPhase("foreign-request")
        do { _ = try await access.permissions.request(Entities.display); XCTFail("Unexpected application error") }
        catch let error as DeviceReadoutError { XCTAssertEqual(error.code, .readFailed) }
        permissionPhase("foreign-response")
        failed.close()
        let called = expectation(description: "Only explicit request calls the coordinator")
        let successful = try access.observers.onPermissionRequest { request in
            permissionPhase("observed-callback")
            XCTAssertEqual(request.kind, .display)
            XCTAssertNil(request.targetId)
            XCTAssertFalse(request.observed)
            called.fulfill()
            permissionPhase("observer-publish")
            try access.observers.permission(Entities.display, status: .unavailable)
            permissionPhase("observer-published")
            throw PermissionTestError() // An accepted observer response is already final.
        }
        defer { permissionPhase("close-coordinator"); successful.close(); permissionPhase("closed-coordinator") }
        failed.close()
        permissionPhase("passive-check")
        let before = try await access.permissions.check(Entities.display)
        XCTAssertNil(before)
        permissionPhase("list")
        _ = try await access.displays.list()
        permissionPhase("current")
        _ = try await access.displays.current()
        permissionPhase("publish-ram")
        try access.observers.publish(Entities.ram, snapshot: RamSnapshot(physicalBytes: 42))
        permissionPhase("get-ram")
        let value = try await access.get(Entities.ram)
        XCTAssertEqual(value.physicalBytes, 42)
        permissionPhase("watch-ram")
        var stream = access.watch(Entities.ram).makeAsyncIterator()
        let streamed = try await stream.next()
        XCTAssertEqual(streamed?.physicalBytes, 42)
        permissionPhase("observed-request")
        let result = try await access.permissions.request(Entities.display)
        XCTAssertEqual(result, .unavailable)
        permissionPhase("fulfillment")
        await fulfillment(of: [called], timeout: 1)
        permissionPhase("completed")
    }

    @MainActor
    func testPermissionRequestAndUiDispatchRemainIndependentOfHeldNativeCollection() async throws {
        let entered = expectation(description: "native collection held")
        let returned = expectation(description: "native collection released")
        let held = HeldPermissionWork(entered: entered, returned: returned)
        let access = DeviceAccess(collector: HeldPermissionCollector(work: held))
        defer { held.release.signal(); access.close() }
        let target = try access.observers.target(Entities.display, id: "screen")
        let native = Task { try await access.get(Entities.ram) }
        defer { native.cancel() }
        await fulfillment(of: [entered], timeout: 1)
        let registration = try access.observers.onPermissionRequest { _ in
            // An app can choose its UI executor. DeviceAccess does not invoke UI APIs itself.
            try await MainActor.run { try access.observers.permission(target, status: .granted) }
        }
        defer { registration.close() }
        let failSafe = Task.detached {
            try? await Task.sleep(for: .milliseconds(800))
            if !Task.isCancelled { held.release.signal() }
        }
        defer { failSafe.cancel() }
        let start = ContinuousClock.now
        let result = try await access.permissions.request(target)
        XCTAssertEqual(result, .granted)
        XCTAssertLessThan(start.duration(to: .now), .milliseconds(300))
        XCTAssertFalse(held.didReturn, "Permission response handling must not queue behind native collection")
        held.release.signal()
        await fulfillment(of: [returned], timeout: 1)
        let snapshot = try await native.value
        XCTAssertEqual(snapshot.physicalBytes, 100)
    }

    @MainActor
    func testConcurrentPermissionRequestsKeepNativeAppAndGenerationScopesSeparate() async throws {
        let access = DeviceAccess(collector: PermissionCollector())
        defer { access.close() }
        let nativeList = try await access.displays.list()
        let native = try XCTUnwrap(nativeList.first)
        let app = try access.observers.target(Entities.display, id: "screen")
        try access.observers.permission(app, status: nil)
        let nativeCalled = expectation(description: "native permission route")
        let appCalled = expectation(description: "app permission route")
        let registration = try access.observers.onPermissionRequest { request in
            XCTAssertEqual(request.targetId, "screen")
            if request.observed { appCalled.fulfill() } else { nativeCalled.fulfill() }
        }
        defer { registration.close() }
        let nativeRequest = Task { try await access.permissions.request(native) }
        let appRequest = Task { try await access.permissions.request(app) }
        defer { nativeRequest.cancel(); appRequest.cancel() }
        await fulfillment(of: [nativeCalled, appCalled], timeout: 1)
        try access.observers.permission(Entities.display, status: .granted)
        let nativeResult = try await nativeRequest.value
        XCTAssertEqual(nativeResult, .granted)
        let appUnknown = try await access.permissions.check(app)
        XCTAssertNil(appUnknown)
        try access.observers.permission(app, status: .denied)
        let appResult = try await appRequest.value
        XCTAssertEqual(appResult, .denied, "An explicit target override excludes kind response delivery")
        try access.observers.remove(app)
        let replacement = try access.observers.target(Entities.display, id: "screen")
        let replacementStatus = try await access.permissions.check(replacement)
        XCTAssertEqual(replacementStatus, .granted, "Permission state cannot cross target generations")
        do { _ = try await access.permissions.check(app); XCTFail("Removed permission target") }
        catch let error as DeviceReadoutError { XCTAssertEqual(error.code, .entityRemoved) }
        XCTAssertThrowsError(try access.observers.permission(app, status: .granted)) { error in
            XCTAssertEqual((error as? DeviceReadoutError)?.code, .entityRemoved)
        }
        let other = DeviceAccess(collector: PermissionCollector())
        defer { other.close() }
        do { _ = try await other.permissions.request(replacement); XCTFail("Foreign permission target") }
        catch let error as DeviceReadoutError { XCTAssertEqual(error.code, .invalidConfiguration) }
        access.close()
        do { _ = try await access.permissions.check(Entities.display); XCTFail("Closed permission context") }
        catch let error as DeviceReadoutError { XCTAssertEqual(error.code, .entityRemoved) }
    }

    @MainActor
    func testClosingContextReleasesUnusedCoordinatorWhileRegistrationHandleRemainsAlive() async throws {
        let access = DeviceAccess(collector: PermissionCollector())
        let released = expectation(description: "application coordinator capture released on context close")
        var probe: PermissionLifetimeProbe? = PermissionLifetimeProbe(released: released)
        let registration = try access.observers.onPermissionRequest { [owned = try XCTUnwrap(probe)] _ in
            withExtendedLifetime(owned) { }
        }
        probe = nil
        access.close()
        await fulfillment(of: [released], timeout: 1)
        withExtendedLifetime(registration) { }
        registration.close()
        registration.close()
    }

    @MainActor
    func testCancellationRemovalAndContextClosureDoNotJoinAppCancellationHandlers() async throws {
        for action in [PermissionEnd.cancel, .remove, .close] {
            let access = DeviceAccess(collector: PermissionCollector())
            defer { access.close() }
            let target = try access.observers.target(Entities.display, id: "screen")
            let invoked = expectation(description: "coordinator ready for \(action)")
            let entered = expectation(description: "app cancellation handler entered for \(action)")
            let returned = expectation(description: "app cancellation handler released for \(action)")
            let held = HeldPermissionWork(entered: entered, returned: returned)
            defer { held.release.signal() }
            let registration = try access.observers.onPermissionRequest { _ in
                try await withTaskCancellationHandler {
                    invoked.fulfill()
                    try await Task.sleep(for: .seconds(60))
                } onCancel: { held.block() }
            }
            defer { registration.close() }
            let request = Task { try await access.permissions.request(target) }
            defer { request.cancel() }
            await fulfillment(of: [invoked], timeout: 1)
            let failSafe = Task.detached {
                try? await Task.sleep(for: .milliseconds(800))
                if !Task.isCancelled { held.release.signal() }
            }
            defer { failSafe.cancel() }
            let start = ContinuousClock.now
            switch action {
            case .cancel: request.cancel()
            case .remove: try access.observers.remove(target)
            case .close: access.close()
            }
            XCTAssertLessThan(start.duration(to: .now), .milliseconds(250))
            do { _ = try await request.value; XCTFail("Expected independent request termination") }
            catch is CancellationError { XCTAssertEqual(action, .cancel) }
            catch let error as DeviceReadoutError {
                XCTAssertNotEqual(action, .cancel)
                XCTAssertEqual(error.code, .entityRemoved)
            }
            XCTAssertLessThan(start.duration(to: .now), .milliseconds(300))
            await fulfillment(of: [entered], timeout: 1)
            XCTAssertFalse(held.didReturn, "Caller completion must not join application cancellation work")
            held.release.signal()
            await fulfillment(of: [returned], timeout: 1)
        }
    }

    @MainActor
    func testExplicitRequestUsesAppCoordinatorAndWaitsForObservedStateWithoutReadDeadline() async throws {
        let access = try DeviceAccess(collector: PermissionCollector()).withReadTimeout(.milliseconds(1))
        defer { access.close() }
        let target = try access.observers.target(Entities.display, id: "screen")
        do { _ = try await access.permissions.request(target); XCTFail("A request needs an app coordinator") }
        catch let error as DeviceReadoutError { XCTAssertEqual(error.code, .unsupportedEntity) }
        let invoked = expectation(description: "explicit application permission request")
        let registration = try access.observers.onPermissionRequest { request in
            XCTAssertFalse(Thread.isMainThread, "The SDK must not dispatch arbitrary coordinator work onto the UI thread")
            XCTAssertEqual(request.kind, .display)
            XCTAssertEqual(request.targetId, "screen")
            XCTAssertTrue(request.observed)
            invoked.fulfill()
        }
        defer { registration.close() }
        XCTAssertThrowsError(try access.observers.onPermissionRequest { _ in }) { error in
            XCTAssertEqual((error as? DeviceReadoutError)?.code, .invalidConfiguration)
        }
        let request = Task { try await access.permissions.request(target) }
        defer { request.cancel() }
        await fulfillment(of: [invoked], timeout: 1)
        try await Task.sleep(for: .milliseconds(80))
        let before = try await access.permissions.check(target)
        XCTAssertNil(before, "Returning from the coordinator does not imply authorization")
        try access.observers.permission(target, status: .granted)
        let result = try await request.value
        XCTAssertEqual(result, .granted)
        registration.close()
        let alreadyGranted = try await access.permissions.request(target)
        XCTAssertEqual(alreadyGranted, .granted, "Granted state requires no coordinator or prompt")
    }

    @MainActor
    func testPermissionChecksUseAppStateWithKindDefaultsAndExplicitTargetOverrides() async throws {
        let access = DeviceAccess(collector: PermissionCollector())
        defer { access.close() }
        let configured = try access.withReadTimeout(.milliseconds(1))
        let target = try access.observers.target(Entities.display, id: "screen")
        let initial = try await access.permissions.check(target)
        XCTAssertNil(initial)
        try access.observers.permission(Entities.display, status: .granted)
        let inherited = try await configured.permissions.check(target)
        XCTAssertEqual(inherited, .granted)
        try access.observers.permission(target, status: .denied)
        let overridden = try await access.permissions.check(target)
        XCTAssertEqual(overridden, .denied)
        let family = try await access.permissions.check(Entities.display)
        XCTAssertEqual(family, .granted)
        try access.observers.permission(target, status: nil)
        try access.observers.permission(Entities.display, status: .restricted)
        let unknown = try await configured.permissions.check(target)
        XCTAssertNil(unknown, "An explicit unreadable target status cannot inherit a kind default")
        for status in [PermissionStatus.notDetermined, .unavailable, .granted] {
            try configured.observers.permission(target, status: status)
            let actual = try await access.permissions.check(target)
            XCTAssertEqual(actual, status)
        }
    }
}

// Temporary diagnostics at the existing public test seam; remove after the stall is located.
private func permissionPhase(_ value: String) {
    FileHandle.standardError.write(Data(("[DEBUG-permission-phase] " + value + "\n").utf8))
}

private enum PermissionEnd { case cancel, remove, close }
private struct PermissionTestError: Error {}

private final class PermissionLifetimeProbe: @unchecked Sendable {
    private let released: XCTestExpectation
    init(released: XCTestExpectation) { self.released = released }
    deinit { released.fulfill() }
}

private final class HeldPermissionWork: @unchecked Sendable {
    let release = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var finished = false
    private let entered: XCTestExpectation
    private let returned: XCTestExpectation
    var didReturn: Bool { lock.lock(); defer { lock.unlock() }; return finished }
    init(entered: XCTestExpectation, returned: XCTestExpectation) { self.entered = entered; self.returned = returned }
    func block() {
        XCTAssertFalse(Thread.isMainThread)
        entered.fulfill()
        release.wait()
        lock.lock(); finished = true; lock.unlock()
        returned.fulfill()
    }
}

private struct PermissionCollector: DeviceCollector {
    func list(_ kind: EntityKind) throws -> [String] { ["screen"] }
    func read(_ request: EntityRequest) throws -> any DeviceSnapshot {
        XCTFail("Permission inspection must not invoke a native getter")
        throw DeviceReadoutError(.readFailed, "Unexpected native read")
    }
}

private struct HeldPermissionCollector: DeviceCollector {
    let work: HeldPermissionWork
    func read(_ request: EntityRequest) throws -> any DeviceSnapshot {
        work.block()
        return RamSnapshot(physicalBytes: 100)
    }
}
