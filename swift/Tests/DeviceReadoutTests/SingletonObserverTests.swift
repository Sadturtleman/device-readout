import DeviceReadout
import Foundation
import XCTest

final class SingletonObserverTests: XCTestCase {
    @MainActor
    func testSingletonRemovalFinishesHeldGetAndHandoffWatchBeforeNativeReturn() async throws {
        let entered = expectation(description: "singleton getter held")
        let returned = expectation(description: "singleton getter returned")
        let collector = HeldSingletonCollector(entered: entered, returned: returned)
        let access = DeviceAccess(collector: collector)
        let get = Task { try await access.get(Entities.ram) }
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) { collector.release.signal() }
        defer { collector.release.signal(); get.cancel(); access.close() }
        await fulfillment(of: [entered], timeout: 1)
        let watch = Task {
            for try await _ in access.watch(Entities.ram) { XCTFail("The collection worker is held") }
        }
        defer { watch.cancel() }
        try await Task.sleep(for: .milliseconds(30))
        try access.observers.publish(Entities.ram, snapshot: RamSnapshot(physicalBytes: 10))
        try await Task.sleep(for: .milliseconds(30))
        let start = ContinuousClock.now
        try access.observers.remove(Entities.ram)
        let failSafe = Task.detached {
            try? await Task.sleep(for: .milliseconds(400))
            if !Task.isCancelled { get.cancel(); watch.cancel() }
        }
        defer { failSafe.cancel() }
        do { _ = try await get.value; XCTFail("Expected removal of the held singleton get") }
        catch let error as DeviceReadoutError { XCTAssertEqual(error.code, .entityRemoved) }
        do { try await watch.value; XCTFail("Expected removal of the handoff watch") }
        catch let error as DeviceReadoutError { XCTAssertEqual(error.code, .entityRemoved) }
        XCTAssertLessThan(start.duration(to: .now), .milliseconds(300))
        XCTAssertFalse(collector.didReturn)
        collector.release.signal()
        await fulfillment(of: [returned], timeout: 1)
        try access.observers.publish(Entities.ram, snapshot: RamSnapshot(physicalBytes: 20))
        do { _ = try await access.get(Entities.ram); XCTFail("Native return and late publication cannot revive removal") }
        catch let error as DeviceReadoutError { XCTAssertEqual(error.code, .entityRemoved) }
        XCTAssertEqual(collector.reads, 1)
    }

    @MainActor
    func testSingletonRemovalIsContextScopedAndRejectsLatePublications() async throws {
        let collector = SingletonCollector()
        let access = DeviceAccess(collector: collector)
        defer { access.close() }
        try access.observers.publish(Entities.ram, snapshot: RamSnapshot(physicalBytes: 10))
        let initial = expectation(description: "observed singleton delivered")
        let consumer = Task {
            for try await value in access.watch(Entities.ram) {
                XCTAssertEqual(value.physicalBytes, 10)
                initial.fulfill()
            }
        }
        defer { consumer.cancel() }
        await fulfillment(of: [initial], timeout: 1)
        try access.observers.remove(Entities.ram)
        let failSafe = Task.detached {
            try? await Task.sleep(for: .milliseconds(400))
            if !Task.isCancelled { consumer.cancel() }
        }
        defer { failSafe.cancel() }
        do { try await consumer.value; XCTFail("Expected singleton removal") }
        catch let error as DeviceReadoutError { XCTAssertEqual(error.code, .entityRemoved) }
        try access.observers.publish(Entities.ram, snapshot: RamSnapshot(physicalBytes: 20))
        try access.observers.remove(Entities.ram)
        do { _ = try await access.get(Entities.ram); XCTFail("Late publication cannot revive a removed singleton") }
        catch let error as DeviceReadoutError { XCTAssertEqual(error.code, .entityRemoved) }
        let otherEntity = try await access.get(Entities.deviceInfo)
        XCTAssertEqual(otherEntity.manufacturer, "native")
        let otherContext = DeviceAccess(collector: collector)
        defer { otherContext.close() }
        let independent = try await otherContext.get(Entities.ram)
        XCTAssertEqual(independent.physicalBytes, 99)
        XCTAssertEqual(collector.reads, 2)
    }
}

private final class HeldSingletonCollector: DeviceCollector, @unchecked Sendable {
    let release = DispatchSemaphore(value: 0)
    private let entered: XCTestExpectation
    private let returned: XCTestExpectation
    private let lock = NSLock()
    private var count = 0
    private var finished = false
    var reads: Int { lock.lock(); defer { lock.unlock() }; return count }
    var didReturn: Bool { lock.lock(); defer { lock.unlock() }; return finished }
    init(entered: XCTestExpectation, returned: XCTestExpectation) { self.entered = entered; self.returned = returned }
    func read(_ request: EntityRequest) throws -> any DeviceSnapshot {
        XCTAssertFalse(Thread.isMainThread)
        lock.lock(); count += 1; let call = count; lock.unlock()
        XCTAssertEqual(call, 1, "Queued reads must be canceled before entering the source")
        entered.fulfill(); release.wait()
        lock.lock(); finished = true; lock.unlock()
        returned.fulfill()
        return RamSnapshot(physicalBytes: 99)
    }
}

private final class SingletonCollector: DeviceCollector, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var reads: Int { lock.lock(); defer { lock.unlock() }; return count }
    func read(_ request: EntityRequest) throws -> any DeviceSnapshot {
        XCTAssertFalse(Thread.isMainThread)
        lock.lock(); count += 1; lock.unlock()
        if request.kind == .ram { return RamSnapshot(physicalBytes: 99) }
        return DeviceInfoSnapshot(manufacturer: "native")
    }
}
