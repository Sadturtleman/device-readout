import DeviceReadout
import Foundation
import XCTest

final class WatchHandoffTests: XCTestCase {
    @MainActor
    func testLateNativeValuesAndErrorsCannotFollowAppHandoff() async throws {
        for outcome in [LatePollOutcome.value, .permissionDenied, .removed] {
            let entered = expectation(description: "second native poll held")
            let returned = expectation(description: "second native poll returned")
            let collector = LatePollCollector(outcome: outcome, entered: entered, returned: returned)
            let access = try DeviceAccess(collector: collector)
                .withPollInterval(.milliseconds(1)).withReadTimeout(.milliseconds(300))
            let consumer = Task { () throws -> [UInt64?] in
                var values: [UInt64?] = []
                for try await value in access.watch(Entities.ram) {
                    values.append(value.physicalBytes)
                    if values.count == 4 { break }
                }
                return values
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) { collector.release.signal() }
            defer { collector.release.signal(); consumer.cancel(); access.close() }
            await fulfillment(of: [entered], timeout: 1)
            for value: UInt64 in [2, 2, 3] {
                try access.observers.publish(Entities.ram, snapshot: RamSnapshot(physicalBytes: value))
            }
            try await Task.sleep(for: .milliseconds(30))
            collector.release.signal()
            await fulfillment(of: [returned], timeout: 1)
            let failSafe = Task.detached {
                try? await Task.sleep(for: .milliseconds(500))
                if !Task.isCancelled { consumer.cancel() }
            }
            defer { failSafe.cancel() }
            let values = try await consumer.value
            XCTAssertEqual(values, [1, 2, 2, 3])
            XCTAssertEqual(collector.reads, 2)
            let cached = try await access.get(Entities.ram)
            XCTAssertEqual(cached.physicalBytes, 3)
        }
    }

    @MainActor
    func testHandoffCancellationAndCloseDoNotJoinTheBlockedNativeCall() async throws {
        for close in [false, true] {
            let entered = expectation(description: "native call held during handoff")
            let returned = expectation(description: "native call released after handoff ends")
            let collector = BlockedHandoffCollector(entered: entered, returned: returned)
            let access = DeviceAccess(collector: collector)
            let consumer = Task {
                for try await _ in access.watch(Entities.ram) { XCTFail("The normalization worker is held") }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) { collector.release.signal() }
            defer { collector.release.signal(); consumer.cancel(); access.close() }
            await fulfillment(of: [entered], timeout: 1)
            try access.observers.publish(Entities.ram, snapshot: RamSnapshot(physicalBytes: 2))
            try await Task.sleep(for: .milliseconds(30))
            let start = ContinuousClock.now
            if close { access.close() } else { consumer.cancel() }
            do { try await consumer.value; XCTFail("Expected handoff termination") }
            catch is CancellationError { XCTAssertFalse(close) }
            catch let error as DeviceReadoutError { XCTAssertTrue(close); XCTAssertEqual(error.code, .entityRemoved) }
            XCTAssertLessThan(start.duration(to: .now), .milliseconds(300))
            XCTAssertFalse(collector.didReturn)
            collector.release.signal()
            await fulfillment(of: [returned], timeout: 1)
            if !close {
                let cached = try await access.get(Entities.ram)
                XCTAssertEqual(cached.physicalBytes, 2)
            }
        }
    }

    @MainActor
    func testHandoffDuringFirstReadKeepsTheOriginalDeadline() async throws {
        let entered = expectation(description: "first native read held")
        let returned = expectation(description: "first native read returned")
        let collector = BlockedHandoffCollector(entered: entered, returned: returned)
        let access = try DeviceAccess(collector: collector).withReadTimeout(.milliseconds(200))
        let consumer = Task {
            for try await _ in access.watch(Entities.ram) { XCTFail("Normalization is behind a held native call") }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) { collector.release.signal() }
        defer { collector.release.signal(); consumer.cancel(); access.close() }
        await fulfillment(of: [entered], timeout: 1)
        let start = ContinuousClock.now
        try await Task.sleep(for: .milliseconds(140))
        try access.observers.publish(Entities.ram, snapshot: RamSnapshot(physicalBytes: 2))
        let failSafe = Task.detached {
            try? await Task.sleep(for: .milliseconds(600))
            if !Task.isCancelled { consumer.cancel() }
        }
        defer { failSafe.cancel() }
        do { try await consumer.value; XCTFail("Expected the original first-value deadline") }
        catch let error as DeviceReadoutError { XCTAssertEqual(error.code, .readTimeout) }
        XCTAssertLessThan(start.duration(to: .now), .milliseconds(300), "Source handoff must not restart the first read timeout")
        XCTAssertFalse(collector.didReturn)
        collector.release.signal()
        await fulfillment(of: [returned], timeout: 1)
        let fresh = try await access.get(Entities.ram)
        XCTAssertEqual(fresh.physicalBytes, 2)
    }

    @MainActor
    func testRunningNativeWatchSwitchesToEveryAppPublicationWithoutWaitingForPoll() async throws {
        let collector = HandoffCollector()
        let access = try DeviceAccess(collector: collector)
            .withPollInterval(.seconds(30)).withReadTimeout(.milliseconds(70))
        defer { access.close() }
        let first = expectation(description: "native first value")
        let consumer = Task { () throws -> [UInt64?] in
            var values: [UInt64?] = []
            for try await value in access.watch(Entities.ram) {
                values.append(value.physicalBytes)
                if values.count == 1 { first.fulfill() }
                if values.count == 4 { break }
            }
            return values
        }
        defer { consumer.cancel() }
        await fulfillment(of: [first], timeout: 1)
        try await Task.sleep(for: .milliseconds(90))
        for value: UInt64 in [2, 2, 3] {
            try access.observers.publish(Entities.ram, snapshot: RamSnapshot(physicalBytes: value))
        }
        let failSafe = Task.detached {
            try? await Task.sleep(for: .milliseconds(500))
            if !Task.isCancelled { consumer.cancel() }
        }
        defer { failSafe.cancel() }
        do {
            let values = try await consumer.value
            XCTAssertEqual(values, [1, 2, 2, 3])
        } catch { XCTFail("App state must interrupt native polling: \(error)") }
        XCTAssertEqual(collector.reads, 1)
    }
}

private enum LatePollOutcome { case value, permissionDenied, removed }

private final class LatePollCollector: DeviceCollector, @unchecked Sendable {
    let release = DispatchSemaphore(value: 0)
    private let outcome: LatePollOutcome
    private let entered: XCTestExpectation
    private let returned: XCTestExpectation
    private let lock = NSLock()
    private var count = 0
    var reads: Int { lock.lock(); defer { lock.unlock() }; return count }
    init(outcome: LatePollOutcome, entered: XCTestExpectation, returned: XCTestExpectation) {
        self.outcome = outcome; self.entered = entered; self.returned = returned
    }
    func read(_ request: EntityRequest) throws -> any DeviceSnapshot {
        XCTAssertFalse(Thread.isMainThread)
        lock.lock(); count += 1; let call = count; lock.unlock()
        if call == 1 { return RamSnapshot(physicalBytes: 1) }
        XCTAssertEqual(call, 2, "The replaced source must not be polled again")
        entered.fulfill(); release.wait(); returned.fulfill()
        switch outcome {
        case .value: return RamSnapshot(physicalBytes: 999)
        case .permissionDenied: throw DeviceReadoutError(.permissionDenied, "Late permission failure")
        case .removed: throw DeviceReadoutError(.entityRemoved, "Late removal failure")
        }
    }
}

private final class BlockedHandoffCollector: DeviceCollector, @unchecked Sendable {
    let release = DispatchSemaphore(value: 0)
    private let entered: XCTestExpectation
    private let returned: XCTestExpectation
    private let lock = NSLock()
    private var finished = false
    var didReturn: Bool { lock.lock(); defer { lock.unlock() }; return finished }
    init(entered: XCTestExpectation, returned: XCTestExpectation) { self.entered = entered; self.returned = returned }
    func read(_ request: EntityRequest) throws -> any DeviceSnapshot {
        XCTAssertFalse(Thread.isMainThread)
        entered.fulfill(); release.wait()
        lock.lock(); finished = true; lock.unlock()
        returned.fulfill()
        return RamSnapshot(physicalBytes: 1)
    }
}

private final class HandoffCollector: DeviceCollector, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var reads: Int { lock.lock(); defer { lock.unlock() }; return count }
    func read(_ request: EntityRequest) throws -> any DeviceSnapshot {
        XCTAssertFalse(Thread.isMainThread)
        XCTAssertEqual(request.kind, .ram)
        lock.lock(); count += 1; let value = count; lock.unlock()
        return RamSnapshot(physicalBytes: UInt64(value))
    }
}
