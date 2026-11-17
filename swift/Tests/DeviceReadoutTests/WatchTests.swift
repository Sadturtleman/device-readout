import DeviceReadout
import Foundation
import XCTest

final class WatchTests: XCTestCase {
    func testSlowConsumerReceivesExplicitOverflowInsteadOfSilentSampleLoss() async throws {
        let filled = expectation(description: "source produced more than the delivery capacity")
        let collector = OverflowCollector(filled: filled)
        let access = try DeviceAccess(collector: collector).withPollInterval(.nanoseconds(1))
        var iterator = access.watch(Entities.ram).makeAsyncIterator()
        let first = try await iterator.next()
        XCTAssertEqual(first?.physicalBytes, 1)
        collector.resume.signal()
        defer { collector.resume.signal() }
        await fulfillment(of: [filled], timeout: 5)
        // Leave the already full queue unconsumed while the last source result reaches delivery.
        try await Task.sleep(for: .milliseconds(80))
        var received = 1
        do {
            while let value = try await iterator.next() {
                received += 1
                XCTAssertEqual(value.physicalBytes, UInt64(received))
            }
            XCTFail("Expected explicit queue overflow")
        } catch let error as DeviceReadoutError { XCTAssertEqual(error.code, .readFailed) }
        XCTAssertEqual(received, 2049, "accepted snapshots remain ordered; loss is reported as an error")
        XCTAssertEqual(collector.reads, 2050, "overflow stops further collection")
    }

    @MainActor
    func testEachPollHasItsOwnDeadlineAndFailureDoesNotRetry() async throws {
        let started = expectation(description: "second poll entered")
        let collector = BlockedPollCollector(started: started)
        let access = try DeviceAccess(collector: collector)
            .withPollInterval(.milliseconds(20)).withReadTimeout(.milliseconds(70))
        let consumer = Task { () throws -> Void in
            var count = 0
            for try await value in access.watch(Entities.ram) {
                count += 1
                XCTAssertEqual(count, 1, "a blocked poll must not manufacture a sample")
                XCTAssertEqual(value.physicalBytes, 1)
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) { collector.release.signal() }
        defer { collector.release.signal(); consumer.cancel() }
        await fulfillment(of: [started], timeout: 2)
        let start = ContinuousClock.now
        do { try await consumer.value; XCTFail("Expected the second poll to time out") }
        catch let error as DeviceReadoutError { XCTAssertEqual(error.code, .readTimeout) }
        XCTAssertLessThan(start.duration(to: .now), .milliseconds(500))
        XCTAssertFalse(collector.returned)
        collector.release.signal()
        let fresh = try await access.get(Entities.ram)
        XCTAssertEqual(fresh.physicalBytes, 3)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(collector.reads, 3, "a failed stream must not automatically retry")
    }

    @MainActor
    func testStateWatchCancellationDoesNotJoinItsBlockedRead() async throws {
        let started = expectation(description: "second stream read entered")
        let collector = BlockedPollCollector(started: started)
        let access = try DeviceAccess(collector: collector).withPollInterval(.milliseconds(40))
        let initial = expectation(description: "initial snapshot delivered")
        let consumer = Task {
            for try await value in access.watch(Entities.ram) {
                XCTAssertEqual(value.physicalBytes, 1)
                initial.fulfill()
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) { collector.release.signal() }
        defer { collector.release.signal(); consumer.cancel() }
        await fulfillment(of: [initial, started], timeout: 2, enforceOrder: true)
        let start = ContinuousClock.now
        consumer.cancel()
        do { try await consumer.value; XCTFail("Expected cancellation") }
        catch is CancellationError { }
        XCTAssertLessThan(start.duration(to: .now), .milliseconds(500))
        XCTAssertFalse(collector.returned)
        collector.release.signal()
        let fresh = try await access.get(Entities.ram)
        XCTAssertEqual(fresh.physicalBytes, 3)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(collector.reads, 3, "canceled polling must not restart after native return")
    }

    func testConfiguredStreamsKeepIndependentCadenceAndNoWholeStreamDeadline() async throws {
        let collector = PollingCollector()
        let slow = try DeviceAccess(collector: collector)
            .withPollInterval(.seconds(30)).withReadTimeout(.milliseconds(60))
        let stream = slow.watch(Entities.ram)
        let first = expectation(description: "immediate first snapshot despite thirty-second interval")
        let ended = expectation(description: "slow stream must remain subscribed")
        ended.isInverted = true
        let slowConsumer = Task {
            defer { if !Task.isCancelled { ended.fulfill() } }
            for try await _ in stream { first.fulfill() }
        }
        defer { slowConsumer.cancel() }
        await fulfillment(of: [first], timeout: 1)
        let fast = try slow.withPollInterval(.milliseconds(20)).withReadTimeout(.seconds(1))
        XCTAssertEqual(slow.pollInterval, .seconds(30))
        XCTAssertEqual(slow.readTimeout, .milliseconds(60))
        XCTAssertEqual(fast.pollInterval, .milliseconds(20))
        XCTAssertEqual(fast.readTimeout, .seconds(1))
        let fastConsumer = Task { () throws -> Int in
            var count = 0
            for try await _ in fast.watch(Entities.ram) {
                count += 1
                if count == 3 { break }
            }
            return count
        }
        let failSafe = Task.detached {
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { fastConsumer.cancel() }
        }
        defer { failSafe.cancel(); fastConsumer.cancel() }
        let received = try await fastConsumer.value
        XCTAssertEqual(received, 3)
        await fulfillment(of: [ended], timeout: 0.15)
        XCTAssertEqual(collector.reads, 4, "new settings and another subscriber cannot speed up the existing stream")
        slowConsumer.cancel()
        do { try await slowConsumer.value; XCTFail("Expected cancellation") }
        catch is CancellationError { }
    }

    func testStateWatchIsColdAndDeliversEqualSnapshotsUntilIterationEnds() async throws {
        let collector = PollingCollector()
        let original = DeviceAccess(collector: collector)
        let access = try original.withPollInterval(.milliseconds(80))
        XCTAssertEqual(original.pollInterval, .seconds(1))
        XCTAssertEqual(access.pollInterval, .milliseconds(80))
        let stream = access.watch(Entities.ram)
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(collector.reads, 0, "creating a stream must not acquire collection resources")

        let consumer = Task { () throws -> [RamSnapshot] in
            var values: [RamSnapshot] = []
            for try await value in stream {
                values.append(value)
                if values.count == 3 { break }
            }
            return values
        }
        let failSafe = Task.detached {
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { consumer.cancel() }
        }
        defer { failSafe.cancel(); consumer.cancel() }
        let values = try await consumer.value
        XCTAssertEqual(values.count, 3)
        for value in values {
            XCTAssertEqual(value.freeBytes, 0)
            XCTAssertEqual(value.lowMemory, false)
        }
        XCTAssertGreaterThan(values[1].collectedAt, values[0].collectedAt)
        XCTAssertGreaterThan(values[2].collectedAt, values[1].collectedAt)
        try await Task.sleep(for: .milliseconds(180))
        XCTAssertEqual(collector.reads, 3, "breaking iteration must stop its polling resources")
    }
}

private final class OverflowCollector: DeviceCollector, @unchecked Sendable {
    let filled: XCTestExpectation
    let resume = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var count = 0
    var reads: Int { lock.lock(); defer { lock.unlock() }; return count }
    init(filled: XCTestExpectation) { self.filled = filled }
    func read(_ request: EntityRequest) throws -> any DeviceSnapshot {
        lock.lock(); count += 1; let call = count; lock.unlock()
        if call == 2 { _ = resume.wait(timeout: .now() + 2) }
        if call == 2050 { filled.fulfill() }
        if call > 2050 { throw DeviceReadoutError(.permissionDenied, "test source limit reached") }
        return RamSnapshot(physicalBytes: UInt64(call))
    }
}

private final class BlockedPollCollector: DeviceCollector, @unchecked Sendable {
    let started: XCTestExpectation
    let release = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var count = 0
    private var didReturn = false
    var reads: Int { lock.lock(); defer { lock.unlock() }; return count }
    var returned: Bool { lock.lock(); defer { lock.unlock() }; return didReturn }
    init(started: XCTestExpectation) { self.started = started }
    func read(_ request: EntityRequest) throws -> any DeviceSnapshot {
        lock.lock(); count += 1; let call = count; lock.unlock()
        if call == 2 {
            started.fulfill()
            release.wait()
            lock.lock(); didReturn = true; lock.unlock()
        }
        return RamSnapshot(physicalBytes: UInt64(call))
    }
}

private final class PollingCollector: DeviceCollector, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var reads: Int { lock.lock(); defer { lock.unlock() }; return count }
    func read(_ request: EntityRequest) throws -> any DeviceSnapshot {
        XCTAssertFalse(Thread.isMainThread)
        lock.lock(); count += 1; lock.unlock()
        return RamSnapshot(freeBytes: 0, lowMemory: false)
    }
}
