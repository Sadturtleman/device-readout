import DeviceReadout
import Foundation
import XCTest

final class DeviceAccessTests: XCTestCase {
    @MainActor
    func testCallerCancellationDoesNotWaitForNativeReturn() async throws {
        let started = expectation(description: "collector entered before cancellation")
        let collector = HeldCollector(started: started)
        let access = DeviceAccess(collector: collector)
        let pending = Task { try await access.get(Entities.ram) }
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) { collector.release.signal() }
        defer { collector.release.signal() }
        await fulfillment(of: [started], timeout: 2)
        let start = ContinuousClock.now
        pending.cancel()
        do { _ = try await pending.value; XCTFail("Expected CancellationError") }
        catch is CancellationError { }
        XCTAssertLessThan(start.duration(to: .now), .milliseconds(500))
        XCTAssertFalse(collector.returned)
        collector.release.signal()
        let fresh = try await access.get(Entities.ram)
        XCTAssertEqual(fresh.physicalBytes, 2)
    }

    @MainActor
    func testReadTimeoutIsImmutableAndDoesNotWaitForNativeReturn() async throws {
        let started = expectation(description: "collector entered")
        let collector = HeldCollector(started: started)
        let access = DeviceAccess(collector: collector)
        let bounded = try access.withReadTimeout(.milliseconds(60))
        XCTAssertEqual(access.readTimeout, .seconds(5))
        XCTAssertEqual(bounded.readTimeout, .milliseconds(60))
        let start = ContinuousClock.now
        let pending = Task { try await bounded.get(Entities.ram) }
        // Test fail-safe only: a runtime that joins its worker must still finish this failing test.
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) { collector.release.signal() }
        defer { collector.release.signal() }
        await fulfillment(of: [started], timeout: 2)
        let hostPulse = Task { @MainActor in 7 }
        let pulse = await hostPulse.value
        XCTAssertEqual(pulse, 7)
        do {
            _ = try await pending.value
            XCTFail("Expected a caller deadline before the native return")
        } catch let error as DeviceReadoutError {
            XCTAssertEqual(error.code, .readTimeout)
        }
        XCTAssertLessThan(start.duration(to: .now), .milliseconds(500))
        XCTAssertFalse(collector.returned, "caller timeout must not wait for native completion")
        collector.release.signal()
        let fresh = try await access.get(Entities.ram)
        XCTAssertEqual(fresh.physicalBytes, 2, "late timed-out result cannot satisfy the next read")
    }

    @MainActor
    func testRamReadReturnsTypedNullableSnapshotFromWorker() async throws {
        let access = DeviceAccess(collector: RamCollector())
        let before = Date()
        let snapshot: RamSnapshot = try await access.get(Entities.ram)
        XCTAssertEqual(snapshot.physicalBytes, 17_179_869_184)
        XCTAssertEqual(snapshot.availableBytes, 7_516_192_768)
        XCTAssertEqual(snapshot.freeBytes, 0)
        XCTAssertEqual(snapshot.lowMemory, false)
        XCTAssertNil(snapshot.kernelAccessibleBytes)
        XCTAssertNil(snapshot.advertisedBytes)
        XCTAssertGreaterThanOrEqual(snapshot.collectedAt, before)
        XCTAssertLessThanOrEqual(snapshot.collectedAt, Date())
    }
}

private final class HeldCollector: DeviceCollector, @unchecked Sendable {
    let started: XCTestExpectation
    let release = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var calls = 0
    private var didReturn = false
    var returned: Bool { lock.lock(); defer { lock.unlock() }; return didReturn }
    init(started: XCTestExpectation) { self.started = started }
    func read(_ request: EntityRequest) throws -> any DeviceSnapshot {
        lock.lock(); calls += 1; let call = calls; lock.unlock()
        if call == 1 {
            started.fulfill()
            release.wait()
            lock.lock(); didReturn = true; lock.unlock()
        }
        return RamSnapshot(physicalBytes: UInt64(call))
    }
}

private struct RamCollector: DeviceCollector {
    func read(_ request: EntityRequest) throws -> any DeviceSnapshot {
        XCTAssertFalse(Thread.isMainThread, "native collection must leave the main thread")
        XCTAssertEqual(request.kind, .ram)
        return RamSnapshot(physicalBytes: 17_179_869_184, availableBytes: 7_516_192_768,
                           freeBytes: 0, lowMemory: false, collectedAt: Date(timeIntervalSince1970: 0))
    }
}
