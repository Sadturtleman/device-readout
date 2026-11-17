import DeviceReadout
import Foundation
import XCTest

final class TargetTests: XCTestCase {
    @MainActor
    func testHeldCurrentSelectionHasIndependentDeadlineAndCancellation() async throws {
        for cancel in [false, true] {
            let started = expectation(description: "held selection entered, cancel=\(cancel)")
            let collector = HeldInventoryCollector(started: started, holdCurrent: true)
            let access = try DeviceAccess(collector: collector)
                .withReadTimeout(cancel ? .seconds(5) : .milliseconds(60))
            let original = try await access.storageVolumes.list()
            let pending = Task { try await access.storageVolumes.current() }
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) { collector.release.signal() }
            defer { collector.release.signal(); pending.cancel() }
            await fulfillment(of: [started], timeout: 2)
            let start = ContinuousClock.now
            if cancel { pending.cancel() }
            do { _ = try await pending.value; XCTFail("Expected deadline or cancellation") }
            catch is CancellationError { XCTAssertTrue(cancel) }
            catch let error as DeviceReadoutError {
                XCTAssertFalse(cancel)
                XCTAssertEqual(error.code, .readTimeout)
            }
            XCTAssertLessThan(start.duration(to: .now), .milliseconds(500))
            XCTAssertFalse(collector.returned)
            collector.release.signal()
            let preserved = try await access.get(original[0])
            XCTAssertEqual(preserved.totalBytes, 100)
            let current = try await access.storageVolumes.current()
            let selected = try XCTUnwrap(current)
            let fresh = try await access.get(selected)
            XCTAssertEqual(fresh.totalBytes, 200)
        }
    }

    func testInvalidInventoryAndSelectionDoNotEraseAcceptedTargets() async throws {
        let collector = VolumeCollector()
        let access = DeviceAccess(collector: collector)
        let original = try await access.storageVolumes.list()
        for invalid in [["volume-a", "volume-a"], ["", "volume-b"]] {
            collector.setInventory(invalid)
            do { _ = try await access.storageVolumes.list(); XCTFail("Expected invalid native inventory") }
            catch let error as DeviceReadoutError { XCTAssertEqual(error.code, .readFailed) }
            let preserved = try await access.get(original[0])
            XCTAssertEqual(preserved.totalBytes, 100)
        }
        collector.select("")
        do { _ = try await access.storageVolumes.current(); XCTFail("Expected invalid current ID") }
        catch let error as DeviceReadoutError { XCTAssertEqual(error.code, .readFailed) }
        let preserved = try await access.get(original[1])
        XCTAssertEqual(preserved.totalBytes, 200)
        collector.setInventory(["volume-a", "volume-b"])
        let restored = try await access.storageVolumes.list()
        XCTAssertEqual(restored, original)
        do { _ = try await access.list(original[0]); XCTFail("Bound handles cannot be used as collections") }
        catch let error as DeviceReadoutError { XCTAssertEqual(error.code, .invalidConfiguration) }
        do { _ = try await access.current(Entities.ram); XCTFail("Singleton entities have no current target") }
        catch let error as DeviceReadoutError { XCTAssertEqual(error.code, .invalidConfiguration) }
    }

    @MainActor
    func testHeldInventoryKeepsCallerDeadlinesAndCannotRetireTargetsAfterCancellation() async throws {
        for cancel in [false, true] {
            let started = expectation(description: "held inventory entered, cancel=\(cancel)")
            let collector = HeldInventoryCollector(started: started)
            let access = try DeviceAccess(collector: collector)
                .withReadTimeout(cancel ? .seconds(5) : .milliseconds(60))
            let original = try await access.storageVolumes.list()
            let pending = Task { try await access.storageVolumes.list() }
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) { collector.release.signal() }
            defer { collector.release.signal(); pending.cancel() }
            await fulfillment(of: [started], timeout: 2)
            let start = ContinuousClock.now
            if cancel { pending.cancel() }
            do { _ = try await pending.value; XCTFail("Expected deadline or cancellation") }
            catch is CancellationError { XCTAssertTrue(cancel) }
            catch let error as DeviceReadoutError {
                XCTAssertFalse(cancel)
                XCTAssertEqual(error.code, .readTimeout)
            }
            XCTAssertLessThan(start.duration(to: .now), .milliseconds(500))
            XCTAssertFalse(collector.returned)
            collector.release.signal()
            let surviving = try await access.get(original[0])
            XCTAssertEqual(surviving.totalBytes, 100, "late empty inventory must not retire the accepted handle")
            let refreshed = try await access.storageVolumes.list()
            XCTAssertEqual(refreshed, original)
        }
    }

    func testSuccessfulInventoryRemovalEndsExistingWatchBeforeItsNextPoll() async throws {
        let collector = VolumeCollector()
        let access = try DeviceAccess(collector: collector).withPollInterval(.seconds(30))
        let original = try await access.storageVolumes.list()
        let first = expectation(description: "target watch started")
        let consumer = Task {
            for try await value in access.watch(original[0]) {
                XCTAssertEqual(value.totalBytes, 100)
                first.fulfill()
            }
        }
        defer { consumer.cancel() }
        await fulfillment(of: [first], timeout: 1)
        collector.setInventory(["volume-b"])
        _ = try await access.storageVolumes.list()
        let start = ContinuousClock.now
        let failSafe = Task.detached {
            try? await Task.sleep(for: .milliseconds(500))
            if !Task.isCancelled { consumer.cancel() }
        }
        defer { failSafe.cancel() }
        do { try await consumer.value; XCTFail("Expected removed target error") }
        catch let error as DeviceReadoutError { XCTAssertEqual(error.code, .entityRemoved) }
        catch { XCTFail("Expected removal before fail-safe cancellation, got \(error)") }
        XCTAssertLessThan(start.duration(to: .now), .milliseconds(400))
        collector.setInventory(["volume-a", "volume-b"])
        let replacement = try await access.storageVolumes.list()
        XCTAssertNotEqual(replacement[0], original[0])
        XCTAssertEqual(replacement[1], original[1])
    }

    func testReadTimeRemovalPermanentlyRetiresTheOldHandle() async throws {
        let collector = VolumeCollector()
        let access = DeviceAccess(collector: collector)
        let original = try await access.storageVolumes.list()
        collector.setRemoved(true)
        do { _ = try await access.get(original[0]); XCTFail("Expected removal") }
        catch let error as DeviceReadoutError { XCTAssertEqual(error.code, .entityRemoved) }
        collector.setRemoved(false)
        let replacement = try await access.storageVolumes.list()
        XCTAssertNotEqual(original[0], replacement[0], "a reused native ID must produce a new handle")
        XCTAssertEqual(original[1], replacement[1], "unaffected targets retain their identity")
        do { _ = try await access.get(original[0]); XCTFail("An old handle must remain retired") }
        catch let error as DeviceReadoutError { XCTAssertEqual(error.code, .entityRemoved) }
        let fresh = try await access.get(replacement[0])
        XCTAssertEqual(fresh.totalBytes, 100)
    }

    func testCurrentUsesTheNativeSelectionWithoutChoosingTheFirstTarget() async throws {
        let collector = VolumeCollector()
        let access = DeviceAccess(collector: collector)
        collector.select("volume-b")
        let current = try await access.storageVolumes.current()
        let selected = try XCTUnwrap(current)
        let volumes = try await access.storageVolumes.list()
        XCTAssertEqual(selected, volumes[1])
        collector.select(nil)
        let absent = try await access.current(Entities.storageVolume)
        XCTAssertNil(absent, "no selection must not become the first inventory item")
        let stillPresent = try await access.get(selected)
        XCTAssertEqual(stillPresent.totalBytes, 200, "selection loss is not device removal")
    }

    func testDiscoveredTargetsPreserveTypeIdentityAndConfiguredContext() async throws {
        let collector = VolumeCollector()
        let access = DeviceAccess(collector: collector)
        let volumes: [Entity<StorageVolumeSnapshot>] = try await access.storageVolumes.list()
        XCTAssertEqual(volumes.count, 2)
        XCTAssertNotEqual(volumes[0], volumes[1])
        let again = try await access.list(Entities.storageVolume)
        XCTAssertEqual(volumes, again)
        XCTAssertEqual(Set(volumes).count, 2)
        let configured = try access.withReadTimeout(.seconds(1))
        let first: StorageVolumeSnapshot = try await configured.get(volumes[0])
        let second = try await access.get(volumes[1])
        XCTAssertEqual(first.totalBytes, 100)
        XCTAssertEqual(second.totalBytes, 200)
        let stranger = DeviceAccess(collector: collector)
        do { _ = try await stranger.get(volumes[0]); XCTFail("Expected context mismatch") }
        catch let error as DeviceReadoutError { XCTAssertEqual(error.code, .invalidConfiguration) }
    }
}

private final class HeldInventoryCollector: DeviceCollector, @unchecked Sendable {
    let started: XCTestExpectation
    let release = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var calls = 0
    private var didReturn = false
    private var selections = 0
    private let holdCurrent: Bool
    var returned: Bool { lock.lock(); defer { lock.unlock() }; return didReturn }
    init(started: XCTestExpectation, holdCurrent: Bool = false) {
        self.started = started; self.holdCurrent = holdCurrent
    }
    func list(_ kind: EntityKind) throws -> [String] {
        XCTAssertFalse(Thread.isMainThread)
        lock.lock(); calls += 1; let call = calls; lock.unlock()
        if call == 2, !holdCurrent {
            started.fulfill()
            release.wait()
            lock.lock(); didReturn = true; lock.unlock()
            return []
        }
        return ["volume-a"]
    }
    func current(_ kind: EntityKind) throws -> String? {
        XCTAssertFalse(Thread.isMainThread)
        lock.lock(); selections += 1; let call = selections; lock.unlock()
        if call == 1, holdCurrent {
            started.fulfill()
            release.wait()
            lock.lock(); didReturn = true; lock.unlock()
        }
        return "volume-b"
    }
    func read(_ request: EntityRequest) throws -> any DeviceSnapshot {
        XCTAssertFalse(Thread.isMainThread)
        return StorageVolumeSnapshot(totalBytes: request.targetId == "volume-b" ? 200 : 100)
    }
}

private final class VolumeCollector: DeviceCollector, @unchecked Sendable {
    private let lock = NSLock()
    private var selected: String?
    private var removed = false
    private var inventory = ["volume-a", "volume-b"]
    func setInventory(_ ids: [String]) { lock.lock(); inventory = ids; lock.unlock() }
    func setRemoved(_ value: Bool) { lock.lock(); removed = value; lock.unlock() }
    func select(_ id: String?) { lock.lock(); selected = id; lock.unlock() }
    func current(_ kind: EntityKind) throws -> String? {
        XCTAssertFalse(Thread.isMainThread)
        lock.lock(); defer { lock.unlock() }; return selected
    }
    func list(_ kind: EntityKind) throws -> [String] {
        XCTAssertFalse(Thread.isMainThread)
        XCTAssertEqual(kind, .storageVolume)
        lock.lock(); defer { lock.unlock() }; return inventory
    }
    func read(_ request: EntityRequest) throws -> any DeviceSnapshot {
        XCTAssertFalse(Thread.isMainThread)
        XCTAssertEqual(request.kind, .storageVolume)
        lock.lock(); let unavailable = removed; lock.unlock()
        if request.targetId == "volume-a", unavailable {
            throw DeviceReadoutError(.entityRemoved, "Volume was removed")
        }
        switch request.targetId {
        case "volume-a": return StorageVolumeSnapshot(totalBytes: 100)
        case "volume-b": return StorageVolumeSnapshot(totalBytes: 200)
        default: throw DeviceReadoutError(.entityRemoved, "Unknown test volume")
        }
    }
}
