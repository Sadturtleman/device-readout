import DeviceReadout
import Foundation
import XCTest

final class SensorActivityTests: XCTestCase {
    @MainActor
    func testConfiguredConsumersKeepIndependentSessionsAndRatesAcrossSharedActivity() async throws {
        let access = DeviceAccess(collector: ActivityCollector())
        defer { access.close() }
        let ten = access.withSensorSamplingRate(try .hertz(10))
        let twenty = access.withSensorSamplingRate(try .hertz(20))
        let sensor = try access.observers.target(Entities.pressure, id: "shared")
        let sessions = ActivitySessions<PressureSnapshot>()
        let initial = expectation(description: "both consumers received first values")
        initial.expectedFulfillmentCount = 2
        let canceled = expectation(description: "only the ten hertz session canceled")
        let released = expectation(description: "three owned sessions released")
        released.expectedFulfillmentCount = 3
        let source = try access.observers.sensorSource(sensor) { session in
            _ = sessions.append(session)
            session.publish(PressureSnapshot(value: session.samplingRate.requestedHertz))
            return {
                if session.samplingRate.requestedHertz == 10 { canceled.fulfill() }
                released.fulfill()
            }
        }
        defer { source.close() }
        let first = Task {
            for try await value in ten.watch(sensor) {
                XCTAssertEqual(value.value, 10)
                initial.fulfill()
            }
        }
        let second = Task { () throws -> [Double?] in
            var values: [Double?] = []
            for try await value in twenty.watch(sensor) {
                values.append(value.value)
                if values.count == 1 { initial.fulfill() }
                if values.count == 2 { break }
            }
            return values
        }
        defer { first.cancel(); second.cancel() }
        let failSafe = Task.detached {
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { first.cancel(); second.cancel() }
        }
        defer { failSafe.cancel() }
        await fulfillment(of: [initial], timeout: 1)
        _ = twenty.withSensorSamplingRate(try .hertz(40))
        try access.observers.sensorActivity(true)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(sessions.count, 2, "Repeated active input must not restart existing sources")
        first.cancel()
        do { try await first.value; XCTFail("Cancellation must propagate") }
        catch is CancellationError { }
        await fulfillment(of: [canceled], timeout: 1)
        XCTAssertTrue(sessions.all.first { $0.samplingRate.requestedHertz == 10 }!.isStopped)
        XCTAssertFalse(sessions.all.first { $0.samplingRate.requestedHertz == 20 }!.isStopped)
        try ten.observers.sensorActivity(false)
        try twenty.observers.sensorActivity(false)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertTrue(sessions.all.allSatisfy(\.isStopped))
        XCTAssertEqual(sessions.count, 2)
        try access.observers.sensorActivity(true)
        try twenty.observers.sensorActivity(true)
        let values = try await second.value
        XCTAssertEqual(values, [20, 20], "The surviving consumer keeps its own rate and duplicate samples")
        XCTAssertEqual(sessions.count, 3)
        XCTAssertEqual(access.sensorSamplingRate, .platformDefault)
        await fulfillment(of: [released], timeout: 1)
    }

    @MainActor
    func testInactiveGetAndWatchEndOnCancellationFailureRemovalAndContextCloseWithoutResuming() async throws {
        for watching in [false, true] {
            for ending in ActivityEnding.allCases {
                let access = try DeviceAccess(collector: ActivityCollector()).withReadTimeout(.seconds(2))
                defer { access.close() }
                let sensor = try access.observers.target(Entities.pressure, id: ending.rawValue)
                let sessions = ActivitySessions<PressureSnapshot>()
                let started = expectation(description: "source started before suspension")
                let released = expectation(description: "suspended source released once")
                let source = try access.observers.sensorSource(sensor) { session in
                    _ = sessions.append(session)
                    started.fulfill()
                    return { released.fulfill() }
                }
                defer { source.close() }
                let failure = try access.observers.failureSource(sensor)
                defer { failure.close() }
                let coordinator = try access.observers.onPermissionRequest { _ in
                    XCTFail("Observing lifecycle and failures must not request permission")
                }
                defer { coordinator.close() }
                let pending = Task {
                    if watching {
                        for try await _ in access.watch(sensor) { XCTFail("No sample was supplied") }
                    } else { _ = try await access.get(sensor) }
                    XCTFail("Expected termination to propagate as an error")
                }
                defer { pending.cancel() }
                await fulfillment(of: [started], timeout: 1)
                try access.observers.sensorActivity(false)
                await fulfillment(of: [released], timeout: 1)
                XCTAssertEqual(sessions.first?.isStopped, true)
                let failSafe = Task.detached {
                    try? await Task.sleep(for: .milliseconds(500))
                    if !Task.isCancelled { pending.cancel() }
                }
                defer { failSafe.cancel() }
                let start = ContinuousClock.now
                switch ending {
                case .cancel: pending.cancel()
                case .failure:
                    try access.observers.permission(sensor, status: .denied)
                    try failure.publish(DeviceReadoutError(.permissionDenied, "Authorization lost while inactive"))
                    try failure.publish(nil) // Recovery cannot erase an already-observed terminal error.
                case .remove: source.close()
                case .close: access.close()
                }
                do { try await pending.value }
                catch is CancellationError { XCTAssertEqual(ending, .cancel) }
                catch let error as DeviceReadoutError {
                    XCTAssertEqual(error.code, ending == .failure ? .permissionDenied : .entityRemoved)
                    XCTAssertNotEqual(ending, .cancel)
                }
                XCTAssertLessThan(start.duration(to: .now), .milliseconds(200))
                if ending == .close {
                    XCTAssertThrowsError(try access.observers.sensorActivity(true)) { error in
                        XCTAssertEqual((error as? DeviceReadoutError)?.code, .entityRemoved)
                    }
                } else {
                    try access.observers.sensorActivity(true)
                    try await Task.sleep(for: .milliseconds(20))
                }
                XCTAssertEqual(sessions.count, 1, "An ended demand must not restart on activity")
            }
        }
    }

    @MainActor
    func testOldSampleWaitingBehindNativeWorkCannotFollowResumedSession() async throws {
        let nativeEntered = expectation(description: "collection worker held by native read")
        let nativeReturned = expectation(description: "native read returned")
        let collector = HeldActivityCollector(entered: nativeEntered, returned: nativeReturned)
        let access = try DeviceAccess(collector: collector).withReadTimeout(.seconds(1))
        defer { collector.release.signal(); access.close() }
        let sensor = try access.observers.target(Entities.pressure, id: "pressure")
        let sessions = ActivitySessions<PressureSnapshot>()
        let initial = expectation(description: "first pressure sample")
        let released = expectation(description: "both pressure sessions released")
        released.expectedFulfillmentCount = 2
        let source = try access.observers.sensorSource(sensor) { session in
            session.publish(PressureSnapshot(value: Double(sessions.append(session))))
            return { released.fulfill() }
        }
        defer { source.close() }
        let consumer = Task { () throws -> [Double?] in
            var values: [Double?] = []
            for try await value in access.watch(sensor) {
                values.append(value.value)
                if values.count == 1 { initial.fulfill() }
                if values.count == 2 { break }
            }
            return values
        }
        defer { consumer.cancel() }
        await fulfillment(of: [initial], timeout: 1)
        let native = Task { try await access.get(Entities.ram) }
        defer { native.cancel() }
        await fulfillment(of: [nativeEntered], timeout: 1)
        let failSafe = Task.detached {
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { collector.release.signal(); consumer.cancel() }
        }
        defer { failSafe.cancel() }
        let old = try XCTUnwrap(sessions.first)
        old.publish(PressureSnapshot(value: 999))
        try await Task.sleep(for: .milliseconds(20))
        let start = ContinuousClock.now
        try access.observers.sensorActivity(false)
        try access.observers.sensorActivity(true)
        XCTAssertLessThan(start.duration(to: .now), .milliseconds(200))
        XCTAssertTrue(old.isStopped)
        collector.release.signal()
        let ram = try await native.value
        XCTAssertEqual(ram.physicalBytes, 42)
        let values = try await consumer.value
        XCTAssertEqual(values, [1, 2])
        await fulfillment(of: [nativeReturned, released], timeout: 1)
    }

    @MainActor
    func testPausingHeldRegistrationCancelsItsFirstDeadlineAndRejectsItsLateSampleOnResume() async throws {
        let access = try DeviceAccess(collector: ActivityCollector()).withReadTimeout(.milliseconds(80))
        defer { access.close() }
        let sensor = try access.observers.target(Entities.pressure, id: "held-setup")
        let sessions = ActivitySessions<PressureSnapshot>()
        let entered = expectation(description: "old registration held")
        let released = expectation(description: "both sensor generations released")
        released.expectedFulfillmentCount = 2
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let source = try access.observers.sensorSource(sensor) { session in
            let count = sessions.append(session)
            if count == 1 {
                entered.fulfill(); release.wait()
                session.publish(PressureSnapshot(value: 999))
                session.fail(DeviceReadoutError(.readFailed, "Late old setup failure"))
            } else { session.publish(PressureSnapshot(value: 2)) }
            return { released.fulfill() }
        }
        defer { source.close() }
        let consumer = Task { () throws -> PressureSnapshot? in
            var iterator = access.watch(sensor).makeAsyncIterator()
            return try await iterator.next()
        }
        defer { consumer.cancel() }
        await fulfillment(of: [entered], timeout: 1)
        let failSafe = Task.detached {
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled { release.signal(); consumer.cancel() }
        }
        defer { failSafe.cancel() }
        let start = ContinuousClock.now
        try access.observers.sensorActivity(false)
        XCTAssertLessThan(start.duration(to: .now), .milliseconds(200))
        XCTAssertEqual(sessions.first?.isStopped, true)
        try await Task.sleep(for: .milliseconds(150))
        try access.observers.sensorActivity(true)
        release.signal()
        let value = try await consumer.value
        XCTAssertEqual(value?.value, 2)
        await fulfillment(of: [released], timeout: 1)
        XCTAssertEqual(sessions.count, 2)
    }

    @MainActor
    func testGetDeadlineIsNotRestartedWhenAnUnmeasuredSessionPausesAndResumes() async throws {
        let access = try DeviceAccess(collector: ActivityCollector()).withReadTimeout(.milliseconds(220))
        defer { access.close() }
        let sensor = try access.observers.target(Entities.pressure, id: "pressure")
        let sessions = ActivitySessions<PressureSnapshot>()
        let initial = expectation(description: "get's first session started")
        let resumed = expectation(description: "get's resumed session started")
        let released = expectation(description: "both unmeasured sessions released")
        released.expectedFulfillmentCount = 2
        let source = try access.observers.sensorSource(sensor) { session in
            if sessions.append(session) == 1 { initial.fulfill() } else { resumed.fulfill() }
            return { released.fulfill() }
        }
        defer { source.close() }
        let start = ContinuousClock.now
        let pending = Task { try await access.get(sensor) }
        defer { pending.cancel() }
        await fulfillment(of: [initial], timeout: 1)
        try await Task.sleep(for: .milliseconds(90))
        try access.observers.sensorActivity(false)
        try await Task.sleep(for: .milliseconds(40))
        try access.observers.sensorActivity(true)
        await fulfillment(of: [resumed], timeout: 1)
        do { _ = try await pending.value; XCTFail("No measurement was supplied") }
        catch let error as DeviceReadoutError { XCTAssertEqual(error.code, .readTimeout) }
        XCTAssertLessThan(start.duration(to: .now), .milliseconds(310), "A resume cannot restart get's original 220ms limit")
        await fulfillment(of: [released], timeout: 1)
        XCTAssertEqual(sessions.count, 2)
    }

    @MainActor
    func testInactiveGetWaitsWithinOriginalDeadlineWithoutStartingSensorsOrBlockingStateReads() async throws {
        let access = DeviceAccess(collector: ActivityCollector())
        defer { access.close() }
        let sensor = try access.observers.target(Entities.pressure, id: "pressure")
        let sessions = ActivitySessions<PressureSnapshot>()
        let source = try access.observers.sensorSource(sensor, description: SensorDescription(name: "Pressure")) { session in
            let count = sessions.append(session)
            XCTAssertEqual(session.samplingRate, .platformDefault)
            session.publish(PressureSnapshot(value: Double(count)))
            return nil
        }
        defer { source.close() }
        try access.observers.sensorActivity(false)
        let quick = try access.withReadTimeout(.milliseconds(60))
        do { _ = try await quick.get(sensor); XCTFail("Inactive get must wait for activity or its original deadline") }
        catch let error as DeviceReadoutError { XCTAssertEqual(error.code, .readTimeout) }
        XCTAssertEqual(sessions.count, 0)
        let description = try await access.describe(sensor)
        XCTAssertEqual(description.name, "Pressure")
        let ram = try await access.get(Entities.ram)
        XCTAssertEqual(ram.physicalBytes, 42, "Activity policy applies only to sensor measurement")
        let start = ContinuousClock.now
        let pending = Task { try await access.withReadTimeout(.milliseconds(300)).get(sensor) }
        defer { pending.cancel() }
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(sessions.count, 0)
        try access.observers.sensorActivity(true)
        let value = try await pending.value
        XCTAssertEqual(value.value, 1)
        XCTAssertGreaterThanOrEqual(start.duration(to: .now), .milliseconds(60))
        XCTAssertLessThan(start.duration(to: .now), .milliseconds(300))
    }

    @MainActor
    func testInactiveWatchReleasesSessionAndResumesFreshWithoutOldSamplesOrErrors() async throws {
        let access = try DeviceAccess(collector: ActivityCollector()).withReadTimeout(.milliseconds(50))
            .withSensorSamplingRate(.hertz(60))
        defer { access.close() }
        let sensor = try access.observers.target(Entities.pressure, id: "pressure")
        let sessions = ActivitySessions<PressureSnapshot>()
        let first = expectation(description: "initial sample")
        let paused = expectation(description: "inactive session released")
        let ended = expectation(description: "resumed session released")
        let source = try access.observers.sensorSource(sensor) { session in
            XCTAssertFalse(Thread.isMainThread)
            XCTAssertEqual(session.samplingRate, try .hertz(60))
            let count = sessions.append(session)
            session.publish(PressureSnapshot(value: Double(count)))
            return {
                XCTAssertFalse(Thread.isMainThread)
                if count == 1 { paused.fulfill() } else { ended.fulfill() }
            }
        }
        defer { source.close() }
        let consumer = Task { () throws -> [Double?] in
            var values: [Double?] = []
            for try await value in access.watch(sensor) {
                values.append(value.value)
                if values.count == 1 { first.fulfill() }
                if values.count == 2 { break }
            }
            return values
        }
        defer { consumer.cancel() }
        await fulfillment(of: [first], timeout: 1)
        try access.observers.sensorActivity(false)
        await fulfillment(of: [paused], timeout: 1)
        let old = try XCTUnwrap(sessions.first)
        XCTAssertTrue(old.isStopped)
        old.publish(PressureSnapshot(value: 999))
        old.fail(DeviceReadoutError(.readFailed, "Late inactive session error"))
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(sessions.count, 1)
        try access.observers.sensorActivity(true)
        let values = try await consumer.value
        XCTAssertEqual(values, [1, 2])
        await fulfillment(of: [ended], timeout: 1)
        XCTAssertEqual(sessions.count, 2)
    }
}

private struct ActivityCollector: DeviceCollector {
    func read(_ request: EntityRequest) throws -> any DeviceSnapshot {
        XCTAssertFalse(Thread.isMainThread)
        guard request.kind == .ram else {
            XCTFail("A sensor uses its registered source, not a state getter")
            throw DeviceReadoutError(.unsupportedEntity, "Unexpected state getter")
        }
        return RamSnapshot(physicalBytes: 42)
    }
}

private enum ActivityEnding: String, CaseIterable { case cancel, failure, remove, close }

private final class HeldActivityCollector: DeviceCollector, @unchecked Sendable {
    let release = DispatchSemaphore(value: 0)
    private let entered: XCTestExpectation
    private let returned: XCTestExpectation
    init(entered: XCTestExpectation, returned: XCTestExpectation) { self.entered = entered; self.returned = returned }
    func read(_ request: EntityRequest) throws -> any DeviceSnapshot {
        XCTAssertFalse(Thread.isMainThread)
        XCTAssertEqual(request.kind, .ram)
        entered.fulfill(); release.wait(); returned.fulfill()
        return RamSnapshot(physicalBytes: 42)
    }
}

private final class ActivitySessions<Snapshot: DeviceSnapshot>: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [SensorObserverSession<Snapshot>] = []
    var count: Int { lock.lock(); defer { lock.unlock() }; return values.count }
    var first: SensorObserverSession<Snapshot>? { lock.lock(); defer { lock.unlock() }; return values.first }
    var all: [SensorObserverSession<Snapshot>] { lock.lock(); defer { lock.unlock() }; return values }
    func append(_ session: SensorObserverSession<Snapshot>) -> Int {
        lock.lock(); defer { lock.unlock() }; values.append(session); return values.count
    }
}
