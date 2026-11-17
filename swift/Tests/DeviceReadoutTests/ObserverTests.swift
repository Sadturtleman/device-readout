import DeviceReadout
import Foundation
import XCTest

final class ObserverTests: XCTestCase {
    @MainActor
    func testInitialObservedReadsWaitForPublicationAndKeepTheirDeadline() async throws {
        let collector = DisplayCollector()
        let access = DeviceAccess(collector: collector)
        defer { access.close() }
        let app = try access.observers.target(Entities.display, id: "pending-screen")
        let pending = Task { try await access.get(app) }
        defer { pending.cancel() }
        try await Task.sleep(for: .milliseconds(30))
        try access.observers.publish(app, snapshot: DisplaySnapshot(scaleFactor: 2))
        do {
            let value = try await pending.value
            XCTAssertEqual(value.scaleFactor, 2)
        } catch { XCTFail("An initial app-state read must wait for publication: \(error)") }

        let bounded = try access.withReadTimeout(.milliseconds(70))
        let empty = try access.observers.target(Entities.display, id: "empty-screen")
        for watch in [false, true] {
            let attempt = Task { () throws -> Void in
                if watch {
                    for try await _ in bounded.watch(empty) { XCTFail("No initial state was published") }
                } else { _ = try await bounded.get(empty) }
            }
            let failSafe = Task.detached {
                try? await Task.sleep(for: .milliseconds(500))
                if !Task.isCancelled { attempt.cancel() }
            }
            defer { failSafe.cancel(); attempt.cancel() }
            do { try await attempt.value; XCTFail("Expected first-state deadline") }
            catch let error as DeviceReadoutError { XCTAssertEqual(error.code, .readTimeout) }
            catch { XCTFail("Expected ReadTimeout before cancellation fail-safe: \(error)") }
        }
        XCTAssertEqual(collector.reads, 0)
    }

    @MainActor
    func testObservedWatchDeliversEveryPublishedStateWithoutPollingOrDeduplication() async throws {
        let collector = DisplayCollector()
        let access = try DeviceAccess(collector: collector)
            .withPollInterval(.seconds(30)).withReadTimeout(.milliseconds(60))
        defer { access.close() }
        let app = try access.observers.target(Entities.display, id: "screen")
        try access.observers.publish(app, snapshot: DisplaySnapshot(scaleFactor: 1))
        let first = expectation(description: "first observed snapshot delivered")
        let consumer = Task { () throws -> [Double?] in
            var values: [Double?] = []
            for try await value in access.watch(app) {
                values.append(value.scaleFactor)
                if values.count == 1 { first.fulfill() }
                if values.count == 4 { break }
            }
            return values
        }
        defer { consumer.cancel() }
        await fulfillment(of: [first], timeout: 1)
        try await Task.sleep(for: .milliseconds(90))
        for scale in [2.0, 2.0, 3.0] {
            try access.observers.publish(app, snapshot: DisplaySnapshot(scaleFactor: scale))
        }
        let failSafe = Task.detached {
            try? await Task.sleep(for: .milliseconds(500))
            if !Task.isCancelled { consumer.cancel() }
        }
        defer { failSafe.cancel() }
        do {
            let values = try await consumer.value
            XCTAssertEqual(values, [1, 2, 2, 3])
        } catch { XCTFail("Observed changes must arrive without waiting for a poll: \(error)") }
        XCTAssertEqual(collector.reads, 0)
    }

    @MainActor
    func testAppStateAndNativeTargetWithSameIdKeepIndependentIdentityAndValues() async throws {
        let collector = DisplayCollector()
        let access = DeviceAccess(collector: collector)
        defer { access.close() }
        let nativeTargets = try await access.displays.list()
        let native = try XCTUnwrap(nativeTargets.first)
        let app = try access.observers.target(Entities.display, id: "display-1")
        try access.observers.publish(app, snapshot: DisplaySnapshot(label: "app", primary: true, scaleFactor: 2))
        XCTAssertNotEqual(app, native)
        XCTAssertEqual(Set([app, native]).count, 2)
        let configured = try access.withReadTimeout(.seconds(1))
        let appValue: DisplaySnapshot = try await configured.get(app)
        let nativeValue = try await access.get(native)
        XCTAssertEqual(appValue.label, "app")
        XCTAssertEqual(appValue.scaleFactor, 2)
        XCTAssertEqual(nativeValue.label, "native")
        XCTAssertEqual(collector.reads, 1, "reading app state must not invoke a platform getter")
        let discovered = try await access.displays.list()
        XCTAssertEqual(discovered, [app], "an app-owned inventory must not be merged with native discovery")
    }
}

private final class DisplayCollector: DeviceCollector, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var reads: Int { lock.lock(); defer { lock.unlock() }; return count }
    func list(_ kind: EntityKind) throws -> [String] {
        XCTAssertFalse(Thread.isMainThread)
        return ["display-1"]
    }
    func read(_ request: EntityRequest) throws -> any DeviceSnapshot {
        XCTAssertFalse(Thread.isMainThread)
        XCTAssertEqual(request.kind, .display)
        lock.lock(); count += 1; lock.unlock()
        return DisplaySnapshot(label: "native", primary: false, scaleFactor: 1)
    }
}
