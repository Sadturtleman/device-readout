import DeviceReadout
import Foundation
import XCTest

final class ObserverFailureTests: XCTestCase {
    @MainActor
    func testFailureSourcesRespectTargetGenerationsAndContextLifetime() async throws {
        let collector = FailureCollector()
        let access = DeviceAccess(collector: collector)
        defer { access.close() }
        let nativeList = try await access.displays.list()
        let native = try XCTUnwrap(nativeList.first)
        let original = try access.observers.target(Entities.display, id: "display-1")
        let oldSource = try access.observers.failureSource(original)
        defer { oldSource.close() }
        let denied = DeviceReadoutError(.permissionDenied, "Only the original app target failed")
        try oldSource.publish(denied)
        let nativeValue = try await access.get(native)
        XCTAssertEqual(nativeValue.label, "native")
        try access.observers.remove(original)
        let replacement = try access.observers.target(Entities.display, id: "display-1")
        try access.observers.publish(replacement, snapshot: DisplaySnapshot(label: "replacement"))
        let fresh = try await access.get(replacement)
        XCTAssertEqual(fresh.label, "replacement", "Old failure ownership cannot cross target generations")
        XCTAssertThrowsError(try oldSource.publish(denied)) { error in
            XCTAssertEqual((error as? DeviceReadoutError)?.code, .entityRemoved)
        }
        oldSource.close()
        let other = DeviceAccess(collector: collector)
        defer { other.close() }
        XCTAssertThrowsError(try other.observers.failureSource(replacement)) { error in
            XCTAssertEqual((error as? DeviceReadoutError)?.code, .invalidConfiguration)
        }
        let currentSource = try access.observers.failureSource(replacement)
        access.close()
        XCTAssertThrowsError(try currentSource.publish(denied)) { error in
            XCTAssertEqual((error as? DeviceReadoutError)?.code, .entityRemoved)
        }
        currentSource.close()
        currentSource.close()
    }

    @MainActor
    func testFailureSourceEndsIdleNativeWatchWithoutWaitingForPoll() async throws {
        let collector = FailureCollector()
        let access = try DeviceAccess(collector: collector).withPollInterval(.seconds(30))
        let source = try access.observers.failureSource(Entities.ram)
        defer { source.close(); access.close() }
        let first = expectation(description: "native state delivered before observation failure")
        let consumer = Task {
            for try await value in access.watch(Entities.ram) {
                XCTAssertEqual(value.physicalBytes, 999)
                first.fulfill()
            }
        }
        defer { consumer.cancel() }
        await fulfillment(of: [first], timeout: 1)
        let error = DeviceReadoutError(.permissionDenied, "Native observation permission lost")
        let start = ContinuousClock.now
        try source.publish(error)
        let failSafe = Task.detached {
            try? await Task.sleep(for: .milliseconds(400))
            if !Task.isCancelled { consumer.cancel() }
        }
        defer { failSafe.cancel() }
        do { try await consumer.value; XCTFail("Expected an independent observation failure") }
        catch let actual as DeviceReadoutError { XCTAssertEqual(actual, error) }
        XCTAssertLessThan(start.duration(to: .now), .milliseconds(300))
        XCTAssertEqual(collector.reads, 1)
        try source.publish(nil)
        let fresh = try await access.get(Entities.ram)
        XCTAssertEqual(fresh.physicalBytes, 999, "An error input alone must not take ownership of native state")
        XCTAssertEqual(collector.reads, 2)
    }

    @MainActor
    func testIndependentFailureSourcesCannotClearEachOtherOrAppPolicy() async throws {
        let collector = FailureCollector()
        let access = DeviceAccess(collector: collector)
        defer { access.close() }
        let first = try access.observers.failureSource(Entities.ram)
        let second = try access.observers.failureSource(Entities.ram)
        defer { first.close(); second.close() }
        XCTAssertEqual(collector.reads, 0, "Registering an error source must be inert")
        let native = try await access.get(Entities.ram)
        XCTAssertEqual(native.physicalBytes, 999, "Registering an error source must not replace the collector")
        try access.observers.publish(Entities.ram, snapshot: RamSnapshot(physicalBytes: 10))
        let firstError = DeviceReadoutError(.readFailed, "First observer failed")
        let secondError = DeviceReadoutError(.permissionDenied, "Second observer failed")
        try first.publish(firstError)
        try second.publish(secondError)
        try first.publish(nil)
        do { _ = try await access.get(Entities.ram); XCTFail("Clearing the first source cannot clear the second") }
        catch let error as DeviceReadoutError { XCTAssertEqual(error, secondError) }
        try first.publish(firstError)
        second.close()
        do { _ = try await access.get(Entities.ram); XCTFail("Closing the second source cannot clear the first") }
        catch let error as DeviceReadoutError { XCTAssertEqual(error, firstError) }
        let policy = DeviceReadoutError(.permissionDenied, "Application policy")
        try access.observers.failure(Entities.ram, error: policy)
        try first.publish(firstError)
        do { _ = try await access.get(Entities.ram); XCTFail("Provider updates cannot override a direct application failure") }
        catch let error as DeviceReadoutError { XCTAssertEqual(error, policy) }
        first.close()
        do { _ = try await access.get(Entities.ram); XCTFail("Closing a source cannot clear application policy") }
        catch let error as DeviceReadoutError { XCTAssertEqual(error, policy) }
        XCTAssertThrowsError(try first.publish(firstError)) { error in
            XCTAssertEqual((error as? DeviceReadoutError)?.code, .entityRemoved)
        }
        try access.observers.failure(Entities.ram, error: nil)
        do {
            _ = try await access.withReadTimeout(.milliseconds(60)).get(Entities.ram)
            XCTFail("Clearing all error slots cannot restore stale state")
        } catch let error as DeviceReadoutError { XCTAssertEqual(error.code, .readTimeout) }
        try access.observers.publish(Entities.ram, snapshot: RamSnapshot(physicalBytes: 20))
        let fresh = try await access.get(Entities.ram)
        XCTAssertEqual(fresh.physicalBytes, 20)
        XCTAssertEqual(collector.reads, 1)
    }

    @MainActor
    func testFailureAndImmediateRecoveryRejectHeldNativeWork() async throws {
        for (query, usingSource) in [(HeldFailureQuery.read, false), (.list, false), (.current, false), (.read, true), (.list, true), (.current, true)] {
            let entered = expectation(description: "native query held during observation failure")
            let returned = expectation(description: "native query released after failure")
            let collector = HeldFailureCollector(entered: entered, returned: returned)
            let access = DeviceAccess(collector: collector)
            let originals = try await access.displays.list()
            let original = try XCTUnwrap(originals.first)
            collector.pause(query)
            let pending = Task {
                switch query {
                case .read: _ = try await access.get(original)
                case .list: _ = try await access.displays.list()
                case .current: _ = try await access.displays.current()
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) { collector.release.signal() }
            defer { collector.release.signal(); pending.cancel(); access.close() }
            await fulfillment(of: [entered], timeout: 1)
            let error = DeviceReadoutError(.permissionDenied, "Observation failed while native work was held")
            let scope = query == .read ? original : Entities.display
            let start = ContinuousClock.now
            if usingSource {
                let source = try access.observers.failureSource(scope)
                try source.publish(error)
                source.close()
            } else {
                try access.observers.failure(scope, error: error)
                try access.observers.failure(scope, error: nil)
            }
            let failSafe = Task.detached {
                try? await Task.sleep(for: .milliseconds(400))
                if !Task.isCancelled { pending.cancel() }
            }
            defer { failSafe.cancel() }
            do { try await pending.value; XCTFail("Immediate recovery cannot accept work crossing the failure") }
            catch let actual as DeviceReadoutError { XCTAssertEqual(actual, error) }
            XCTAssertLessThan(start.duration(to: .now), .milliseconds(300))
            XCTAssertFalse(collector.didReturn)
            collector.release.signal()
            await fulfillment(of: [returned], timeout: 1)
            let stillValid = try await access.get(original)
            let refreshed = try await access.displays.list()
            XCTAssertEqual(stillValid.label, "native")
            XCTAssertEqual(refreshed, [original], "A late empty inventory must not retire accepted handles")
        }
    }

    @MainActor
    func testTargetAndKindFailuresPreserveIdentityAndCoverDiscovery() async throws {
        let collector = FailureCollector()
        let access = DeviceAccess(collector: collector)
        defer { access.close() }
        let nativeList = try await access.displays.list()
        let native = try XCTUnwrap(nativeList.first)
        let app = try access.observers.target(Entities.display, id: "display-1")
        let sibling = try access.observers.target(Entities.display, id: "display-2")
        try access.observers.publish(app, snapshot: DisplaySnapshot(label: "app"))
        try access.observers.publish(sibling, snapshot: DisplaySnapshot(label: "sibling"))
        try access.observers.current(Entities.display, target: app)
        let targetError = DeviceReadoutError(.permissionDenied, "Only the app target failed")
        try access.observers.failure(app, error: targetError)
        do { _ = try await access.get(app); XCTFail("Expected scoped target failure") }
        catch let error as DeviceReadoutError { XCTAssertEqual(error, targetError) }
        let nativeValue = try await access.get(native)
        let siblingValue = try await access.get(sibling)
        XCTAssertEqual(nativeValue.label, "native")
        XCTAssertEqual(siblingValue.label, "sibling")
        let familyError = DeviceReadoutError(.readFailed, "The display observer failed")
        try access.observers.failure(Entities.display, error: familyError)
        for target in [native, app, sibling] {
            do { _ = try await access.get(target); XCTFail("Expected kind-wide failure") }
            catch let error as DeviceReadoutError {
                XCTAssertEqual(error, target == app ? targetError : familyError, "An exact application error takes precedence over kind policy")
            }
        }
        do { _ = try await access.displays.list(); XCTFail("Kind failure must reject list") }
        catch let error as DeviceReadoutError { XCTAssertEqual(error, familyError) }
        do { _ = try await access.displays.current(); XCTFail("Kind failure must reject current") }
        catch let error as DeviceReadoutError { XCTAssertEqual(error, familyError) }
        try access.observers.failure(Entities.display, error: nil)
        do { _ = try await access.get(app); XCTFail("Clearing kind failure must preserve target failure") }
        catch let error as DeviceReadoutError { XCTAssertEqual(error, targetError) }
        try access.observers.publish(sibling, snapshot: DisplaySnapshot(label: "fresh"))
        let recovered = try await access.get(sibling)
        XCTAssertEqual(recovered.label, "fresh")
        let preserved = try await access.displays.list()
        let current = try await access.displays.current()
        XCTAssertEqual(Set(preserved), Set([app, sibling]))
        XCTAssertEqual(current, app, "A transient error must not retire target generations")
        XCTAssertEqual(collector.reads, 1)
    }

    @MainActor
    func testFailureEndsObservedWatchAndRecoveryRequiresFreshState() async throws {
        let collector = FailureCollector()
        let access = DeviceAccess(collector: collector)
        defer { access.close() }
        try access.observers.publish(Entities.ram, snapshot: RamSnapshot(physicalBytes: 10))
        let first = expectation(description: "observed state delivered")
        let consumer = Task {
            for try await value in access.watch(Entities.ram) {
                XCTAssertEqual(value.physicalBytes, 10)
                first.fulfill()
            }
        }
        defer { consumer.cancel() }
        await fulfillment(of: [first], timeout: 1)
        let denied = DeviceReadoutError(.permissionDenied, "App observation was denied")
        try access.observers.failure(Entities.ram, error: denied)
        let failSafe = Task.detached {
            try? await Task.sleep(for: .milliseconds(400))
            if !Task.isCancelled { consumer.cancel() }
        }
        defer { failSafe.cancel() }
        do { try await consumer.value; XCTFail("Expected the supplied observation failure") }
        catch let error as DeviceReadoutError { XCTAssertEqual(error, denied) }
        do { _ = try await access.get(Entities.ram); XCTFail("Failure must reject a new get") }
        catch let error as DeviceReadoutError { XCTAssertEqual(error, denied) }
        try access.observers.failure(Entities.ram, error: nil)
        do {
            _ = try await access.withReadTimeout(.milliseconds(60)).get(Entities.ram)
            XCTFail("Recovery requires a new app publication, not cached or native state")
        } catch let error as DeviceReadoutError { XCTAssertEqual(error.code, .readTimeout) }
        try access.observers.publish(Entities.ram, snapshot: RamSnapshot(physicalBytes: 20))
        let recovered = try await access.get(Entities.ram)
        XCTAssertEqual(recovered.physicalBytes, 20)
        XCTAssertEqual(collector.reads, 0)
    }
}

private enum HeldFailureQuery { case read, list, current }

private final class HeldFailureCollector: DeviceCollector, @unchecked Sendable {
    let release = DispatchSemaphore(value: 0)
    private let entered: XCTestExpectation
    private let returned: XCTestExpectation
    private let lock = NSLock()
    private var paused: HeldFailureQuery?
    private var finished = false
    var didReturn: Bool { lock.lock(); defer { lock.unlock() }; return finished }
    init(entered: XCTestExpectation, returned: XCTestExpectation) { self.entered = entered; self.returned = returned }
    func pause(_ query: HeldFailureQuery) { lock.lock(); paused = query; lock.unlock() }
    private func awaitRelease(_ query: HeldFailureQuery) -> Bool {
        XCTAssertFalse(Thread.isMainThread)
        lock.lock(); let held = paused == query
        if held { paused = nil }
        lock.unlock()
        if held {
            entered.fulfill(); release.wait()
            lock.lock(); finished = true; lock.unlock()
            returned.fulfill()
        }
        return held
    }
    func read(_ request: EntityRequest) throws -> any DeviceSnapshot {
        let held = awaitRelease(.read)
        return DisplaySnapshot(label: held ? "late" : "native")
    }
    func list(_ kind: EntityKind) throws -> [String] { awaitRelease(.list) ? [] : ["display-1"] }
    func current(_ kind: EntityKind) throws -> String? { awaitRelease(.current) ? "late-display" : "display-1" }
}

private final class FailureCollector: DeviceCollector, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var reads: Int { lock.lock(); defer { lock.unlock() }; return count }
    func list(_ kind: EntityKind) throws -> [String] { ["display-1"] }
    func current(_ kind: EntityKind) throws -> String? { "display-1" }
    func read(_ request: EntityRequest) throws -> any DeviceSnapshot {
        XCTAssertFalse(Thread.isMainThread)
        lock.lock(); count += 1; lock.unlock()
        if request.kind == .display { return DisplaySnapshot(label: "native") }
        return RamSnapshot(physicalBytes: 999)
    }
}
