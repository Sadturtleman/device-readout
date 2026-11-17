import DeviceReadout
import Foundation
import XCTest

final class ContextTests: XCTestCase {
    @MainActor
    func testSaturatedWorkerStillCleansUpWhenContextCloses() async throws {
        let entered = expectation(description: "native read held before saturation")
        let cleaned = expectation(description: "saturated collector cleaned up")
        let overloaded = expectation(description: "native work queue saturated")
        let collector = ClosingCollector(entered: entered, cleaned: cleaned)
        let access = DeviceAccess(collector: collector)
        let first = Task { try await access.get(Entities.ram) }
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) { collector.release.signal() }
        defer { collector.release.signal(); first.cancel(); access.close() }
        await fulfillment(of: [entered], timeout: 2)
        var overloads = 0
        var closures = 0
        let pending = (0..<256).map { _ in Task { @MainActor in
            do { _ = try await access.get(Entities.ram); XCTFail("Queued reads cannot survive context closure") }
            catch let error as DeviceReadoutError {
                if error.code == .readFailed {
                    overloads += 1
                    if overloads == 1 { overloaded.fulfill() }
                } else if error.code == .entityRemoved { closures += 1 }
                else { XCTFail("Unexpected error: \(error)") }
            } catch { XCTFail("Unexpected error: \(error)") }
        } }
        await fulfillment(of: [overloaded], timeout: 0.5)
        let start = ContinuousClock.now
        access.close()
        do { _ = try await first.value; XCTFail("Expected closure of held read") }
        catch let error as DeviceReadoutError { XCTAssertEqual(error.code, .entityRemoved) }
        for task in pending { await task.value }
        XCTAssertLessThan(start.duration(to: .now), .milliseconds(500))
        XCTAssertFalse(collector.returned)
        XCTAssertGreaterThan(closures, 0)
        XCTAssertEqual(closures + overloads, 256)
        collector.release.signal()
        await fulfillment(of: [cleaned], timeout: 2)
        XCTAssertEqual(collector.closeCalls, 1, "full read capacity must not reject native cleanup")
        XCTAssertEqual(collector.readCalls, 1)
    }

    @MainActor
    func testCloseFinishesHeldListAndCurrentWithoutWaitingForNativeReturn() async throws {
        for queryCurrent in [false, true] {
            let entered = expectation(description: "discovery entered, current=\(queryCurrent)")
            let cleaned = expectation(description: "discovery collector closed")
            let collector = ClosingCollector(entered: entered, cleaned: cleaned)
            let access = DeviceAccess(collector: collector)
            let configured = try access.withReadTimeout(.seconds(10))
            let pending = Task { () throws -> [Entity<StorageVolumeSnapshot>] in
                if queryCurrent {
                    if let selected = try await configured.storageVolumes.current() { return [selected] }
                    return []
                }
                return try await configured.storageVolumes.list()
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) { collector.release.signal() }
            defer { collector.release.signal(); pending.cancel(); access.close() }
            await fulfillment(of: [entered], timeout: 2)
            let start = ContinuousClock.now
            access.close()
            do { _ = try await pending.value; XCTFail("Expected closed discovery context") }
            catch let error as DeviceReadoutError { XCTAssertEqual(error.code, .entityRemoved) }
            XCTAssertLessThan(start.duration(to: .now), .milliseconds(500))
            XCTAssertFalse(collector.returned)
            collector.release.signal()
            await fulfillment(of: [cleaned], timeout: 2)
            XCTAssertEqual(collector.closeCalls, 1)
        }
    }

    @MainActor
    func testOverloadedWorkerFailsExplicitlyAndCanceledQueuedReadsNeverRun() async throws {
        let entered = expectation(description: "first native read held")
        let overloaded = expectation(description: "bounded native work queue reports overload")
        let collector = QueuedCollector(entered: entered)
        let access = DeviceAccess(collector: collector)
        let first = Task { try await access.get(Entities.ram) }
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) { collector.release.signal() }
        defer { collector.release.signal(); first.cancel(); access.close() }
        await fulfillment(of: [entered], timeout: 2)
        var overloads = 0
        let pending = (0..<256).map { _ in Task { @MainActor in
            do { _ = try await access.get(Entities.ram) }
            catch let error as DeviceReadoutError where error.code == .readFailed {
                overloads += 1
                if overloads == 1 { overloaded.fulfill() }
            } catch is CancellationError { }
            catch { XCTFail("Unexpected queued read error: \(error)") }
        } }
        await fulfillment(of: [overloaded], timeout: 0.5)
        XCTAssertFalse(collector.returned)
        XCTAssertGreaterThan(overloads, 0)
        for task in pending { task.cancel() }
        for task in pending { await task.value }
        collector.release.signal()
        _ = try await first.value
        let fresh = try await access.get(Entities.ram)
        XCTAssertEqual(fresh.physicalBytes, 2, "canceled queued operations must not reach the native source")
        XCTAssertEqual(collector.readCalls, 2)
    }

    @MainActor
    func testCloseEndsSleepingWatchWhileNativeCleanupIsHeld() async throws {
        let cleanupEntered = expectation(description: "native cleanup entered")
        let cleanupFinished = expectation(description: "native cleanup finished")
        let first = expectation(description: "initial watch value")
        let collector = HeldCleanupCollector(entered: cleanupEntered, finished: cleanupFinished)
        let access = DeviceAccess(collector: collector)
        let configured = try access.withPollInterval(.seconds(30))
        let cold = configured.watch(Entities.ram)
        let consumer = Task {
            for try await value in configured.watch(Entities.ram) {
                XCTAssertEqual(value.physicalBytes, 100)
                first.fulfill()
            }
        }
        defer { consumer.cancel(); collector.release.signal() }
        await fulfillment(of: [first], timeout: 1)
        let start = ContinuousClock.now
        configured.close()
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) { collector.release.signal() }
        await fulfillment(of: [cleanupEntered], timeout: 1)
        let failSafe = Task.detached {
            try? await Task.sleep(for: .milliseconds(500))
            if !Task.isCancelled { consumer.cancel() }
        }
        defer { failSafe.cancel() }
        do { try await consumer.value; XCTFail("Expected closed context") }
        catch let error as DeviceReadoutError { XCTAssertEqual(error.code, .entityRemoved) }
        catch { XCTFail("Expected closure before cancellation fail-safe, got \(error)") }
        XCTAssertLessThan(start.duration(to: .now), .milliseconds(400))
        XCTAssertFalse(collector.returned)
        do {
            for try await _ in cold { XCTFail("A stream created before closure cannot start afterward") }
            XCTFail("Expected closed context on deferred iteration")
        } catch let error as DeviceReadoutError { XCTAssertEqual(error.code, .entityRemoved) }
        collector.release.signal()
        await fulfillment(of: [cleanupFinished], timeout: 2)
    }

    @MainActor
    func testClosingSharedContextFinishesHeldReadAndCleansUpOnceOffMain() async throws {
        let entered = expectation(description: "native read entered")
        let cleaned = expectation(description: "native collector closed")
        let collector = ClosingCollector(entered: entered, cleaned: cleaned)
        let access = DeviceAccess(collector: collector)
        let configured = try access.withReadTimeout(.seconds(10)).withPollInterval(.milliseconds(20))
        let pending = Task { try await configured.get(Entities.ram) }
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) { collector.release.signal() }
        defer { collector.release.signal(); pending.cancel() }
        await fulfillment(of: [entered], timeout: 2)
        let start = ContinuousClock.now
        access.close()
        configured.close()
        do { _ = try await pending.value; XCTFail("Expected closed context") }
        catch let error as DeviceReadoutError { XCTAssertEqual(error.code, .entityRemoved) }
        XCTAssertLessThan(start.duration(to: .now), .milliseconds(500))
        XCTAssertFalse(collector.returned, "close must not wait for native return")
        do { _ = try await access.get(Entities.ram); XCTFail("Closed context cannot read") }
        catch let error as DeviceReadoutError { XCTAssertEqual(error.code, .entityRemoved) }
        do { _ = try await configured.storageVolumes.list(); XCTFail("Configured context cannot discover after close") }
        catch let error as DeviceReadoutError { XCTAssertEqual(error.code, .entityRemoved) }
        do { _ = try await access.storageVolumes.current(); XCTFail("Closed context cannot query current selection") }
        catch let error as DeviceReadoutError { XCTAssertEqual(error.code, .entityRemoved) }
        collector.release.signal()
        await fulfillment(of: [cleaned], timeout: 2)
        XCTAssertEqual(collector.closeCalls, 1)
        XCTAssertEqual(collector.readCalls, 1)
        access.close()
        XCTAssertEqual(collector.closeCalls, 1)
    }
}

private final class QueuedCollector: DeviceCollector, @unchecked Sendable {
    let entered: XCTestExpectation
    let release = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var count = 0
    private var didReturn = false
    var returned: Bool { lock.lock(); defer { lock.unlock() }; return didReturn }
    var readCalls: Int { lock.lock(); defer { lock.unlock() }; return count }
    init(entered: XCTestExpectation) { self.entered = entered }
    func read(_ request: EntityRequest) throws -> any DeviceSnapshot {
        lock.lock(); count += 1; let call = count; lock.unlock()
        if call == 1 {
            entered.fulfill()
            release.wait()
            lock.lock(); didReturn = true; lock.unlock()
        }
        return RamSnapshot(physicalBytes: UInt64(call))
    }
}

private final class HeldCleanupCollector: DeviceCollector, @unchecked Sendable {
    let entered: XCTestExpectation
    let finished: XCTestExpectation
    let release = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var didReturn = false
    var returned: Bool { lock.lock(); defer { lock.unlock() }; return didReturn }
    init(entered: XCTestExpectation, finished: XCTestExpectation) { self.entered = entered; self.finished = finished }
    func read(_ request: EntityRequest) throws -> any DeviceSnapshot { RamSnapshot(physicalBytes: 100) }
    func close() throws {
        XCTAssertFalse(Thread.isMainThread)
        entered.fulfill()
        release.wait()
        lock.lock(); didReturn = true; lock.unlock()
        finished.fulfill()
        throw DeviceReadoutError(.readFailed, "Controlled native cleanup failure")
    }
}

private final class ClosingCollector: DeviceCollector, @unchecked Sendable {
    let entered: XCTestExpectation
    let cleaned: XCTestExpectation
    let release = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var reads = 0
    private var closes = 0
    private var didReturn = false
    var returned: Bool { lock.lock(); defer { lock.unlock() }; return didReturn }
    var readCalls: Int { lock.lock(); defer { lock.unlock() }; return reads }
    var closeCalls: Int { lock.lock(); defer { lock.unlock() }; return closes }
    init(entered: XCTestExpectation, cleaned: XCTestExpectation) { self.entered = entered; self.cleaned = cleaned }
    func read(_ request: EntityRequest) throws -> any DeviceSnapshot {
        XCTAssertFalse(Thread.isMainThread)
        lock.lock(); reads += 1; lock.unlock()
        hold()
        return RamSnapshot(physicalBytes: 100)
    }
    func list(_ kind: EntityKind) throws -> [String] {
        XCTAssertFalse(Thread.isMainThread)
        hold()
        return ["volume-a"]
    }
    func current(_ kind: EntityKind) throws -> String? {
        XCTAssertFalse(Thread.isMainThread)
        hold()
        return "volume-a"
    }
    private func hold() {
        entered.fulfill()
        release.wait()
        lock.lock(); didReturn = true; lock.unlock()
    }
    func close() throws {
        XCTAssertFalse(Thread.isMainThread, "native cleanup must leave the caller's execution path")
        lock.lock(); closes += 1; lock.unlock()
        cleaned.fulfill()
    }
}
