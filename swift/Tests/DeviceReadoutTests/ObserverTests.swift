import DeviceReadout
import Foundation
import XCTest

final class ObserverTests: XCTestCase {
    @MainActor
    func testObservedRemovalFinishesAnExecutingNativeReadAndPreservesAppState() async throws {
        let entered = expectation(description: "native getter held")
        let returned = expectation(description: "native getter returned")
        let collector = PausedDisplayCollector(entered: entered, returned: returned)
        let access = DeviceAccess(collector: collector)
        let targets = try await access.displays.list()
        let native = try XCTUnwrap(targets.first)
        let app = try access.observers.target(Entities.display, id: "display-1")
        try access.observers.publish(app, snapshot: DisplaySnapshot(label: "app"))
        collector.pause(.read)
        let pending = Task { try await access.get(native) }
        defer { collector.release.signal(); pending.cancel(); access.close() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) { collector.release.signal() }
        await fulfillment(of: [entered], timeout: 1)
        let start = ContinuousClock.now
        try access.observers.remove(native)
        let failSafe = Task.detached {
            try? await Task.sleep(for: .milliseconds(400))
            if !Task.isCancelled { pending.cancel() }
        }
        defer { failSafe.cancel() }
        do { _ = try await pending.value; XCTFail("A removed native result cannot be accepted") }
        catch let error as DeviceReadoutError { XCTAssertEqual(error.code, .entityRemoved) }
        XCTAssertLessThan(start.duration(to: .now), .milliseconds(300))
        XCTAssertFalse(collector.didReturn)
        collector.release.signal()
        await fulfillment(of: [returned], timeout: 1)
        let appValue = try await access.get(app)
        XCTAssertEqual(appValue.label, "app")
        let inventory = try await access.displays.list()
        XCTAssertEqual(inventory, [app])
    }

    @MainActor
    func testLateNativeDiscoveryCannotReviveAnObservedRemoval() async throws {
        for query in [PausedDisplayQuery.list, .current] {
            let entered = expectation(description: "native discovery paused")
            let returned = expectation(description: "native discovery returned")
            let collector = PausedDisplayCollector(entered: entered, returned: returned)
            let access = DeviceAccess(collector: collector)
            defer { collector.release.signal(); access.close() }
            let originalList = try await access.displays.list()
            let original = try XCTUnwrap(originalList.first)
            collector.pause(query)
            let pending = Task { () throws -> [Entity<DisplaySnapshot>] in
                if query == .list { return try await access.displays.list() }
                if let current = try await access.displays.current() { return [current] }
                return []
            }
            defer { pending.cancel() }
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) { collector.release.signal() }
            await fulfillment(of: [entered], timeout: 1)
            try access.observers.remove(original)
            collector.release.signal()
            let stale = try await pending.value
            XCTAssertTrue(stale.isEmpty, "A discovery started before removal cannot recreate that target")
            await fulfillment(of: [returned], timeout: 1)
            let refreshedList = try await access.displays.list()
            let refreshed = try XCTUnwrap(refreshedList.first)
            XCTAssertNotEqual(refreshed, original)
            let freshValue = try await access.get(refreshed)
            XCTAssertEqual(freshValue.label, "native")
            do { _ = try await access.get(original); XCTFail("An old native generation cannot be revived") }
            catch let error as DeviceReadoutError { XCTAssertEqual(error.code, .entityRemoved) }
        }
    }

    @MainActor
    func testRemovingTargetFinishesQueuedReadWithoutJoiningNativeWork() async throws {
        for appOwned in [false, true] {
            let entered = expectation(description: "worker blocked for target removal")
            let returned = expectation(description: "worker released after target removal")
            let collector = HeldObserverCollector(entered: entered, returned: returned)
            let access = DeviceAccess(collector: collector)
            let discovered = try await access.displays.list()
            let native = try XCTUnwrap(discovered.first)
            let entity = appOwned ? try access.observers.target(Entities.display, id: "display-1") : native
            if appOwned { try access.observers.publish(entity, snapshot: DisplaySnapshot(label: "queued")) }
            let held = Task { try await access.get(Entities.ram) }
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) { collector.release.signal() }
            defer { collector.release.signal(); held.cancel(); access.close() }
            await fulfillment(of: [entered], timeout: 1)
            let pending = Task { try await access.get(entity) }
            defer { pending.cancel() }
            try await Task.sleep(for: .milliseconds(30))
            let start = ContinuousClock.now
            try access.observers.remove(entity)
            let failSafe = Task.detached {
                try? await Task.sleep(for: .milliseconds(400))
                if !Task.isCancelled { pending.cancel() }
            }
            defer { failSafe.cancel() }
            do { _ = try await pending.value; XCTFail("Removed queued reads cannot succeed") }
            catch let error as DeviceReadoutError { XCTAssertEqual(error.code, .entityRemoved) }
            catch { XCTFail("Expected removal before the cancellation fail-safe: \(error)") }
            XCTAssertLessThan(start.duration(to: .now), .milliseconds(300))
            XCTAssertFalse(collector.didReturn)
            collector.release.signal()
            await fulfillment(of: [returned], timeout: 1)
            do { _ = try await access.get(entity); XCTFail("Removal cannot be undone by a queued read") }
            catch let error as DeviceReadoutError { XCTAssertEqual(error.code, .entityRemoved) }
        }
    }

    @MainActor
    func testRemovingAppTargetEndsItsReadersAndPreservesSameIdNativeTarget() async throws {
        let collector = DisplayCollector()
        let access = try DeviceAccess(collector: collector).withPollInterval(.seconds(30))
        defer { access.close() }
        let nativeList = try await access.displays.list()
        let native = try XCTUnwrap(nativeList.first)
        let app = try access.observers.target(Entities.display, id: "display-1")
        try access.observers.current(Entities.display, target: app)
        let get = Task { try await access.get(app) }
        let watch = Task {
            for try await _ in access.watch(app) { XCTFail("The app did not publish a value") }
        }
        defer { get.cancel(); watch.cancel() }
        try await Task.sleep(for: .milliseconds(30))
        let start = ContinuousClock.now
        try access.observers.remove(app)
        let failSafe = Task.detached {
            try? await Task.sleep(for: .milliseconds(400))
            if !Task.isCancelled { get.cancel(); watch.cancel() }
        }
        defer { failSafe.cancel() }
        do { _ = try await get.value; XCTFail("Expected removal of pending get") }
        catch let error as DeviceReadoutError { XCTAssertEqual(error.code, .entityRemoved) }
        catch { XCTFail("Unexpected pending-get error: \(error)") }
        do { try await watch.value; XCTFail("Expected removal of pending watch") }
        catch let error as DeviceReadoutError { XCTAssertEqual(error.code, .entityRemoved) }
        catch { XCTFail("Unexpected pending-watch error: \(error)") }
        XCTAssertLessThan(start.duration(to: .now), .milliseconds(300))
        let list = try await access.displays.list()
        let selected = try await access.displays.current()
        XCTAssertTrue(list.isEmpty)
        XCTAssertNil(selected)
        let nativeValue = try await access.get(native)
        XCTAssertEqual(nativeValue.label, "native")

        let replacement = try access.observers.target(Entities.display, id: "display-1")
        XCTAssertNotEqual(replacement, app)
        try access.observers.publish(replacement, snapshot: DisplaySnapshot(label: "replacement"))
        // A late callback and duplicate removal from the old observer must not affect its replacement.
        try access.observers.publish(app, snapshot: DisplaySnapshot(label: "late"))
        try access.observers.remove(app)
        let fresh = try await access.get(replacement)
        XCTAssertEqual(fresh.label, "replacement")
        do { _ = try await access.get(app); XCTFail("Old handles cannot be revived") }
        catch let error as DeviceReadoutError { XCTAssertEqual(error.code, .entityRemoved) }
    }

    @MainActor
    func testAppOwnsCurrentSelectionWithoutCallingNativeUiGetters() async throws {
        let collector = DisplayCollector()
        let access = DeviceAccess(collector: collector)
        defer { access.close() }
        let nativeSelection = try await access.displays.current()
        let native = try XCTUnwrap(nativeSelection)
        XCTAssertEqual(collector.currentReads, 1)
        let app = try access.observers.target(Entities.display, id: "display-1")
        let beforeSelection = try await access.displays.current()
        XCTAssertNil(beforeSelection, "App inventory must not fall back to a native current getter")
        try access.observers.current(Entities.display, target: app)
        let selected = try await access.withReadTimeout(.seconds(1)).displays.current()
        XCTAssertEqual(selected, app)
        try access.observers.current(Entities.display, target: nil)
        let cleared = try await access.displays.current()
        XCTAssertNil(cleared)
        try access.observers.current(Entities.display, target: native)
        let selectedNative = try await access.displays.current()
        XCTAssertEqual(selectedNative, native, "Explicit native handles retain their own namespace")
        XCTAssertEqual(collector.currentReads, 1)

        let other = DeviceAccess(collector: collector)
        defer { other.close() }
        let foreign = try other.observers.target(Entities.display, id: "display-1")
        XCTAssertThrowsError(try access.observers.current(Entities.display, target: foreign)) { error in
            XCTAssertEqual((error as? DeviceReadoutError)?.code, .invalidConfiguration)
        }
        try other.observers.current(Entities.display, target: nil)
        let empty = DeviceAccess(collector: collector)
        defer { empty.close() }
        try empty.observers.current(Entities.display, target: nil)
        let emptyList = try await empty.displays.list()
        let emptyCurrent = try await empty.displays.current()
        XCTAssertTrue(emptyList.isEmpty, "An explicit empty app inventory cannot discover native devices")
        XCTAssertNil(emptyCurrent)
        XCTAssertEqual(collector.currentReads, 1)
    }

    @MainActor
    func testWaitingForAppPublicationDoesNotOccupyTheNativeWorker() async throws {
        let collector = DisplayCollector()
        let access = try DeviceAccess(collector: collector).withReadTimeout(.milliseconds(300))
        defer { access.close() }
        let app = try access.observers.target(Entities.display, id: "waiting")
        // A native singleton read is available on the same worker even while app state is absent.
        let pending = Task { try await access.get(app) }
        defer { pending.cancel() }
        try await Task.sleep(for: .milliseconds(30))
        let native = try await access.get(Entities.deviceInfo)
        XCTAssertEqual(native.manufacturer, "native")
        try access.observers.publish(app, snapshot: DisplaySnapshot(scaleFactor: 4))
        let observed = try await pending.value
        XCTAssertEqual(observed.scaleFactor, 4)
        XCTAssertEqual(collector.reads, 1)
    }

    @MainActor
    func testPendingObservedReadsFinishWhileTheNativeWorkerIsBlocked() async throws {
        for watch in [false, true] {
            for completion in [PendingCompletion.cancel, .close, .timeout] {
                let entered = expectation(description: "held collector entered")
                let returned = expectation(description: "held collector returned")
                let collector = HeldObserverCollector(entered: entered, returned: returned)
                let access = DeviceAccess(collector: collector)
                let native = Task { try await access.get(Entities.ram) }
                DispatchQueue.global().asyncAfter(deadline: .now() + 1) { collector.release.signal() }
                defer { collector.release.signal(); native.cancel(); access.close() }
                await fulfillment(of: [entered], timeout: 1)
                let configured = try access.withReadTimeout(completion == .timeout ? .milliseconds(70) : .seconds(5))
                let app = try access.observers.target(Entities.display, id: "pending")
                let pending = Task { () throws -> Void in
                    if watch {
                        for try await _ in configured.watch(app) { XCTFail("No state was published") }
                    } else { _ = try await configured.get(app) }
                }
                defer { pending.cancel() }
                try await Task.sleep(for: .milliseconds(30))
                let start = ContinuousClock.now
                if completion == .cancel { pending.cancel() }
                if completion == .close { configured.close() }
                let failSafe = Task.detached {
                    try? await Task.sleep(for: .milliseconds(400))
                    if !Task.isCancelled { pending.cancel() }
                }
                defer { failSafe.cancel() }
                do { try await pending.value; XCTFail("Expected an independent terminal result") }
                catch is CancellationError { XCTAssertEqual(completion, .cancel) }
                catch let error as DeviceReadoutError {
                    XCTAssertEqual(error.code, completion == .close ? .entityRemoved : .readTimeout)
                    XCTAssertNotEqual(completion, .cancel)
                }
                XCTAssertLessThan(start.duration(to: .now), .milliseconds(300))
                XCTAssertFalse(collector.didReturn, "Control completion must not wait for native work")
                collector.release.signal()
                await fulfillment(of: [returned], timeout: 1)
                if completion != .close {
                    try access.observers.publish(app, snapshot: DisplaySnapshot(scaleFactor: 5))
                    let fresh = try await access.get(app)
                    XCTAssertEqual(fresh.scaleFactor, 5, "A completed reader must not cancel the shared app source")
                }
            }
        }
    }

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
    private var currentCount = 0
    var reads: Int { lock.lock(); defer { lock.unlock() }; return count }
    var currentReads: Int { lock.lock(); defer { lock.unlock() }; return currentCount }
    func current(_ kind: EntityKind) throws -> String? {
        XCTAssertFalse(Thread.isMainThread)
        lock.lock(); currentCount += 1; lock.unlock()
        return "display-1"
    }
    func list(_ kind: EntityKind) throws -> [String] {
        XCTAssertFalse(Thread.isMainThread)
        return ["display-1"]
    }
    func read(_ request: EntityRequest) throws -> any DeviceSnapshot {
        XCTAssertFalse(Thread.isMainThread)
        lock.lock(); count += 1; lock.unlock()
        if request.kind == .deviceInfo { return DeviceInfoSnapshot(manufacturer: "native") }
        XCTAssertEqual(request.kind, .display)
        return DisplaySnapshot(label: "native", primary: false, scaleFactor: 1)
    }
}

private enum PendingCompletion { case cancel, close, timeout }

private enum PausedDisplayQuery { case list, current, read }

private final class PausedDisplayCollector: DeviceCollector, @unchecked Sendable {
    let release = DispatchSemaphore(value: 0)
    private let entered: XCTestExpectation
    private let returned: XCTestExpectation
    private let lock = NSLock()
    private var paused: PausedDisplayQuery?
    private var finished = false
    var didReturn: Bool { lock.lock(); defer { lock.unlock() }; return finished }
    init(entered: XCTestExpectation, returned: XCTestExpectation) { self.entered = entered; self.returned = returned }
    func pause(_ query: PausedDisplayQuery) { lock.lock(); paused = query; lock.unlock() }
    private func awaitRelease(_ query: PausedDisplayQuery) {
        XCTAssertFalse(Thread.isMainThread)
        lock.lock()
        let shouldPause = paused == query
        if shouldPause { paused = nil }
        lock.unlock()
        if shouldPause {
            entered.fulfill(); release.wait()
            lock.lock(); finished = true; lock.unlock()
            returned.fulfill()
        }
    }
    func list(_ kind: EntityKind) throws -> [String] { awaitRelease(.list); return ["display-1"] }
    func current(_ kind: EntityKind) throws -> String? { awaitRelease(.current); return "display-1" }
    func read(_ request: EntityRequest) throws -> any DeviceSnapshot {
        awaitRelease(.read); return DisplaySnapshot(label: "native")
    }
}

private final class HeldObserverCollector: DeviceCollector, @unchecked Sendable {
    let release = DispatchSemaphore(value: 0)
    private let entered: XCTestExpectation
    private let returned: XCTestExpectation
    private let lock = NSLock()
    private var finished = false
    var didReturn: Bool { lock.lock(); defer { lock.unlock() }; return finished }
    init(entered: XCTestExpectation, returned: XCTestExpectation) {
        self.entered = entered; self.returned = returned
    }
    func list(_ kind: EntityKind) throws -> [String] { ["display-1"] }
    func read(_ request: EntityRequest) throws -> any DeviceSnapshot {
        XCTAssertFalse(Thread.isMainThread)
        XCTAssertEqual(request.kind, .ram)
        entered.fulfill()
        release.wait()
        lock.lock(); finished = true; lock.unlock()
        returned.fulfill()
        return RamSnapshot(physicalBytes: 100)
    }
}
