import DeviceReadout
import Foundation
import XCTest

final class NativeStateObservationTests: XCTestCase {
    @MainActor
    func testCancellationAndCloseDoNotWaitForHeldObservationCleanup() async throws {
        let entered = expectation(description: "native cleanup entered")
        let closed = expectation(description: "collector closes after cleanup returns")
        let collector = HeldStateCleanup(entered: entered, closed: closed)
        let access = DeviceAccess(collector: collector)
        let initial = expectation(description: "watch initial value")
        let consumer = Task {
            for try await _ in access.watch(Entities.ram) { initial.fulfill() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) { collector.release.signal() }
        defer { collector.release.signal(); consumer.cancel(); access.close() }
        await fulfillment(of: [initial], timeout: 1)
        let start = ContinuousClock.now
        consumer.cancel()
        do { try await consumer.value; XCTFail("Expected cancellation") }
        catch is CancellationError { }
        await fulfillment(of: [entered], timeout: 1)
        access.close()
        let independent = DeviceAccess()
        defer { independent.close() }
        let runtime = try await independent.get(Entities.runtime)
        XCTAssertNotNil(runtime.processBitness)
        let pulse = await Task { @MainActor in 11 }.value
        XCTAssertEqual(pulse, 11)
        XCTAssertLessThan(start.duration(to: .now), .milliseconds(500))
        XCTAssertFalse(collector.returned)
        collector.release.signal()
        await fulfillment(of: [closed], timeout: 1)
    }

    @MainActor
    func testRegistrationDeadlineAndContextCloseDoNotJoinHeldSetup() async throws {
        let entered = expectation(description: "native registration entered")
        let cleaned = expectation(description: "late registration cleaned")
        let closed = expectation(description: "collector closed after registration cleanup")
        let collector = HeldStateRegistration(entered: entered, cleaned: cleaned, closed: closed)
        let access = try DeviceAccess(collector: collector).withReadTimeout(.milliseconds(60))
        let pending = Task {
            var iterator = access.watch(Entities.ram).makeAsyncIterator()
            return try await iterator.next()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) { collector.release.signal() }
        defer { collector.release.signal(); pending.cancel(); access.close() }
        await fulfillment(of: [entered], timeout: 1)
        let start = ContinuousClock.now
        let pulse = await Task { @MainActor in 9 }.value
        XCTAssertEqual(pulse, 9)
        do { _ = try await pending.value; XCTFail("Expected registration deadline") }
        catch let error as DeviceReadoutError { XCTAssertEqual(error.code, .readTimeout) }
        XCTAssertLessThan(start.duration(to: .now), .milliseconds(500))
        XCTAssertFalse(collector.returned)
        access.close()
        XCTAssertTrue(collector.cleanupOrder.isEmpty)
        collector.release.signal()
        await fulfillment(of: [cleaned, closed], timeout: 1, enforceOrder: true)
        XCTAssertEqual(collector.cleanupOrder, ["observation", "collector"])
        XCTAssertEqual(collector.reads, 0, "Expired registration cannot start a state read.")
    }

    @MainActor
    func testAppHandoffClosesNativeObservationAndIgnoresLateInvalidations() async throws {
        let cleaned = expectation(description: "native observation released at handoff")
        let collector = StateEventCollector(cleaned: cleaned)
        let access = try DeviceAccess(collector: collector).withPollInterval(.seconds(3600))
        defer { access.close() }
        let first = expectation(description: "native initial value")
        let second = expectation(description: "first app value")
        let consumer = Task { () throws -> [UInt64?] in
            var values: [UInt64?] = []
            for try await value in access.watch(Entities.ram) {
                values.append(value.physicalBytes)
                if values.count == 1 { first.fulfill() }
                if values.count == 2 { second.fulfill() }
                if values.count == 3 { break }
            }
            return values
        }
        defer { consumer.cancel() }
        await fulfillment(of: [first], timeout: 1)
        try access.observers.publish(Entities.ram, snapshot: RamSnapshot(physicalBytes: 7))
        await fulfillment(of: [second, cleaned], timeout: 1)
        collector.publishLate(99)
        let observed = try await access.get(Entities.ram)
        XCTAssertEqual(observed.physicalBytes, 7)
        try access.observers.publish(Entities.ram, snapshot: RamSnapshot(physicalBytes: 8))
        let values = try await consumer.value
        XCTAssertEqual(values, [1, 7, 8])
        XCTAssertEqual(collector.cleanups, 1)
    }

    @MainActor
    func testNativeChangesInterruptPollingAndKeepEqualEvents() async throws {
        let cleaned = XCTestExpectation(description: "native observation cleaned off the caller")
        let collector = StateEventCollector(cleaned: cleaned)
        let access = try DeviceAccess(collector: collector).withPollInterval(.seconds(3600))
        defer { access.close() }
        let first = expectation(description: "immediate read")
        let changed = XCTestExpectation(description: "native change before poll")
        let repeated = XCTestExpectation(description: "equal native change")
        let consumer = Task { () throws -> [RamSnapshot] in
            var values: [RamSnapshot] = []
            for try await value in access.watch(Entities.ram) {
                values.append(value)
                if values.count == 1 { first.fulfill() }
                if values.count == 2 { changed.fulfill() }
                if values.count == 3 { repeated.fulfill(); break }
            }
            return values
        }
        defer { consumer.cancel() }
        await fulfillment(of: [first], timeout: 1)
        XCTAssertEqual(collector.registrations, 1, "A watch registers native invalidations before its first read.")
        guard collector.registrations == 1 else { return }
        collector.publish(2)
        await fulfillment(of: [changed], timeout: 1)
        collector.publish(2)
        await fulfillment(of: [repeated], timeout: 1)
        let values = try await consumer.value
        XCTAssertEqual(values.map(\.physicalBytes), [1, 2, 2])
        XCTAssertGreaterThan(values[2].collectedAt, values[1].collectedAt)
        await fulfillment(of: [cleaned], timeout: 1)
        XCTAssertEqual(collector.cleanups, 1)
    }
}

private final class HeldStateCleanup: DeviceCollector, @unchecked Sendable {
    let release = DispatchSemaphore(value: 0)
    private let entered, closed: XCTestExpectation
    private let lock = NSLock()
    private var didReturn = false
    init(entered: XCTestExpectation, closed: XCTestExpectation) { self.entered = entered; self.closed = closed }
    var returned: Bool { lock.lock(); defer { lock.unlock() }; return didReturn }
    func read(_ request: EntityRequest) throws -> any DeviceSnapshot { RamSnapshot(physicalBytes: 1) }
    func observeChanges(_ request: EntityRequest, notify: @escaping @Sendable () -> Void) throws -> NativeStateCleanup? {
        return { [self] in
            XCTAssertFalse(Thread.isMainThread)
            entered.fulfill(); release.wait()
            lock.lock(); didReturn = true; lock.unlock()
        }
    }
    func close() throws {
        XCTAssertFalse(Thread.isMainThread)
        XCTAssertTrue(returned)
        closed.fulfill()
    }
}

private final class StateEventCollector: DeviceCollector, @unchecked Sendable {
    private let lock = NSLock()
    private var callback: (@Sendable () -> Void)?
    private var lateCallback: (@Sendable () -> Void)?
    private var value: UInt64 = 1
    private var opened = 0, closed = 0
    private let cleaned: XCTestExpectation
    init(cleaned: XCTestExpectation) { self.cleaned = cleaned }
    var registrations: Int { lock.lock(); defer { lock.unlock() }; return opened }
    var cleanups: Int { lock.lock(); defer { lock.unlock() }; return closed }
    func read(_ request: EntityRequest) throws -> any DeviceSnapshot {
        XCTAssertFalse(Thread.isMainThread)
        lock.lock(); defer { lock.unlock() }
        return RamSnapshot(physicalBytes: value)
    }
    func observeChanges(_ request: EntityRequest, notify: @escaping @Sendable () -> Void) throws -> (@Sendable () throws -> Void)? {
        XCTAssertFalse(Thread.isMainThread)
        lock.lock(); callback = notify; lateCallback = notify; opened += 1; lock.unlock()
        return { [self] in
            XCTAssertFalse(Thread.isMainThread)
            lock.lock(); callback = nil; closed += 1; lock.unlock()
            cleaned.fulfill()
        }
    }
    func publish(_ value: UInt64) {
        lock.lock(); self.value = value; let callback = self.callback; lock.unlock()
        callback?()
    }
    func publishLate(_ value: UInt64) {
        lock.lock(); self.value = value; let callback = lateCallback; lock.unlock()
        callback?()
    }
}

private final class HeldStateRegistration: DeviceCollector, @unchecked Sendable {
    let release = DispatchSemaphore(value: 0)
    private let entered, cleaned, closed: XCTestExpectation
    private let lock = NSLock()
    private var didReturn = false, readCount = 0
    private var order: [String] = []
    init(entered: XCTestExpectation, cleaned: XCTestExpectation, closed: XCTestExpectation) {
        self.entered = entered; self.cleaned = cleaned; self.closed = closed
    }
    var returned: Bool { lock.lock(); defer { lock.unlock() }; return didReturn }
    var reads: Int { lock.lock(); defer { lock.unlock() }; return readCount }
    var cleanupOrder: [String] { lock.lock(); defer { lock.unlock() }; return order }
    func read(_ request: EntityRequest) throws -> any DeviceSnapshot {
        lock.lock(); readCount += 1; lock.unlock()
        return RamSnapshot(physicalBytes: 1)
    }
    func observeChanges(_ request: EntityRequest, notify: @escaping @Sendable () -> Void) throws -> NativeStateCleanup? {
        XCTAssertFalse(Thread.isMainThread)
        entered.fulfill(); release.wait()
        lock.lock(); didReturn = true; lock.unlock()
        return { [self] in
            XCTAssertFalse(Thread.isMainThread)
            lock.lock(); order.append("observation"); lock.unlock()
            cleaned.fulfill()
        }
    }
    func close() throws {
        XCTAssertFalse(Thread.isMainThread)
        lock.lock(); order.append("collector"); lock.unlock()
        closed.fulfill()
    }
}
