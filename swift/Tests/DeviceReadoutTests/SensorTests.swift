import DeviceReadout
import Foundation
import XCTest

final class SensorTests: XCTestCase {
    @MainActor
    func testSensorBurstEndsWithExplicitOverflowAndReleasesItsSource() async throws {
        let access = DeviceAccess(collector: NoSensorGetter())
        defer { access.close() }
        let sensor = try access.observers.target(Entities.pressure, id: "burst")
        let cleaned = expectation(description: "overflow source released")
        let sessions = SensorSessionBox<PressureSnapshot>()
        let source = try access.observers.sensorSource(sensor) { session in
            sessions.set(session)
            // Worker normalization cannot run until this registration callback returns.
            for value in 1...4096 { session.publish(PressureSnapshot(value: Double(value))) }
            return { cleaned.fulfill() }
        }
        defer { source.close() }
        let consumer = Task { () throws -> Int in
            var received = 0
            do {
                for try await value in access.watch(sensor) {
                    received += 1
                    XCTAssertEqual(value.value, Double(received), "Accepted samples retain their order")
                }
                XCTFail("Burst overflow must be explicit")
            } catch let error as DeviceReadoutError {
                XCTAssertEqual(error.code, .readFailed)
                XCTAssertTrue(error.message.contains("queue is full"))
            }
            return received
        }
        defer { consumer.cancel() }
        let failSafe = Task.detached {
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { consumer.cancel() }
        }
        defer { failSafe.cancel() }
        let received = try await consumer.value
        XCTAssertGreaterThanOrEqual(received, 2048)
        XCTAssertLessThanOrEqual(received, 2049, "Only one sample may be awaiting normalization in addition to the bounded raw queue")
        await fulfillment(of: [cleaned], timeout: 1)
        XCTAssertEqual(sessions.get()?.isStopped, true)
    }

    @MainActor
    func testSensorErrorsRegistrationOwnershipAndRemovedGenerationsStayDistinct() async throws {
        let access = DeviceAccess(collector: NoSensorGetter())
        defer { access.close() }
        let sensor = try access.observers.target(Entities.pressure, id: "pressure")
        let starts = SensorCounter()
        let sessions = SensorSessionBox<PressureSnapshot>()
        let denied = DeviceReadoutError(.permissionDenied, "Sensor permission revoked")
        let source = try access.observers.sensorSource(sensor) { session in
            sessions.set(session)
            switch starts.next() {
            case 1: session.fail(denied)
            case 2: throw SensorTestError()
            default: session.publish(PressureSnapshot(value: 42))
            }
            return nil
        }
        defer { source.close() }
        XCTAssertThrowsError(try access.observers.sensorSource(sensor) { _ in nil }) { error in
            XCTAssertEqual((error as? DeviceReadoutError)?.code, .invalidConfiguration)
        }
        XCTAssertThrowsError(try access.observers.sensorSource(Entities.ram) { _ in nil }) { error in
            XCTAssertEqual((error as? DeviceReadoutError)?.code, .invalidConfiguration)
        }
        do { _ = try await access.get(sensor); XCTFail("Expected typed source failure") }
        catch let error as DeviceReadoutError { XCTAssertEqual(error, denied) }
        do { _ = try await access.get(sensor); XCTFail("Expected contained source exception") }
        catch let error as DeviceReadoutError { XCTAssertEqual(error.code, .readFailed) }
        let delivered = expectation(description: "watch received its only real sample")
        let consumer = Task {
            for try await value in access.watch(sensor) {
                XCTAssertEqual(value.value, 42)
                delivered.fulfill()
            }
        }
        defer { consumer.cancel() }
        await fulfillment(of: [delivered], timeout: 1)
        let oldSession = try XCTUnwrap(sessions.get())
        oldSession.fail(denied)
        do { try await consumer.value; XCTFail("Expected idle sensor failure") }
        catch let error as DeviceReadoutError { XCTAssertEqual(error, denied) }
        XCTAssertTrue(oldSession.isStopped)
        source.close()
        let empty = try await access.sensors.list(Entities.pressure)
        XCTAssertTrue(empty.isEmpty)
        do { _ = try await access.get(sensor); XCTFail("Closed source retires its target") }
        catch let error as DeviceReadoutError { XCTAssertEqual(error.code, .entityRemoved) }
        let replacement = try access.observers.target(Entities.pressure, id: "pressure")
        let replacementSource = try access.observers.sensorSource(replacement) { session in
            session.publish(PressureSnapshot(value: 100)); return nil
        }
        defer { replacementSource.close() }
        source.close()
        oldSession.publish(PressureSnapshot(value: 999))
        let fresh = try await access.get(replacement)
        XCTAssertEqual(fresh.value, 100)
        let other = DeviceAccess(collector: NoSensorGetter())
        defer { other.close() }
        XCTAssertThrowsError(try other.observers.sensorSource(replacement) { _ in nil }) { error in
            XCTAssertEqual((error as? DeviceReadoutError)?.code, .invalidConfiguration)
        }
    }

    @MainActor
    func testHeldSensorCleanupDoesNotDelayReadCompletionQueuedDeadlinesOrContextClose() async throws {
        let access = DeviceAccess(collector: NoSensorGetter())
        defer { access.close() }
        let sensor = try access.observers.target(Entities.pressure, id: "cleanup")
        let entered = expectation(description: "sensor cleanup is held")
        let returned = expectation(description: "sensor cleanup returned")
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let starts = SensorCounter()
        let finished = SensorCounter()
        let source = try access.observers.sensorSource(sensor) { session in
            _ = starts.next()
            session.publish(PressureSnapshot(value: 42))
            return {
                XCTAssertFalse(Thread.isMainThread)
                entered.fulfill()
                release.wait()
                _ = finished.next()
                returned.fulfill()
            }
        }
        defer { source.close() }
        let failSafe = Task.detached {
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { release.signal() }
        }
        defer { failSafe.cancel() }
        let value = try await access.get(sensor)
        XCTAssertEqual(value.value, 42)
        await fulfillment(of: [entered], timeout: 1)
        let quick = try access.withReadTimeout(.milliseconds(60))
        do { _ = try await quick.describe(sensor); XCTFail("Queued metadata deadline") }
        catch let error as DeviceReadoutError { XCTAssertEqual(error.code, .readTimeout) }
        do { _ = try await quick.get(sensor); XCTFail("Queued sensor start deadline") }
        catch let error as DeviceReadoutError { XCTAssertEqual(error.code, .readTimeout) }
        XCTAssertEqual(starts.count, 1)
        let start = ContinuousClock.now
        access.close()
        XCTAssertLessThan(start.duration(to: .now), .milliseconds(200))
        XCTAssertEqual(finished.count, 0)
        release.signal()
        await fulfillment(of: [returned], timeout: 1)
        XCTAssertEqual(starts.count, 1, "Timed-out or closed work must not start after cleanup returns")
    }

    @MainActor
    func testFalseOrMissingEventPayloadCannotBecomeAFabricatedOccurrence() async throws {
        for value in [false, nil] as [Bool?] {
            try await invalidEvent(Entities.stepDetected, snapshot: StepDetectedSnapshot(value: value))
            try await invalidEvent(Entities.significantMotion, snapshot: SignificantMotionSnapshot(value: value))
        }
    }

    @MainActor
    private func invalidEvent<Snapshot>(_ kind: Entity<Snapshot>, snapshot: Snapshot) async throws {
        let access = DeviceAccess(collector: NoSensorGetter())
        defer { access.close() }
        let sensor = try access.observers.target(kind, id: "invalid")
        let source = try access.observers.sensorSource(sensor) { session in session.publish(snapshot); return nil }
        defer { source.close() }
        do { _ = try await access.get(sensor); XCTFail("An occurrence must be true") }
        catch let error as DeviceReadoutError { XCTAssertEqual(error.code, .readFailed) }
        var iterator = access.watch(sensor).makeAsyncIterator()
        do { _ = try await iterator.next(); XCTFail("An invalid payload cannot be an initial event") }
        catch let error as DeviceReadoutError { XCTAssertEqual(error.code, .readFailed) }
    }

    @MainActor
    func testHeldSensorRegistrationCannotDelayDeadlineCancellationRemovalOrCloseAndReleasesLateResources() async throws {
        for end in [SensorEnd.timeout, .cancel, .remove, .close] {
            try await heldRegistration(Entities.pressure, watch: false, end: end)
            try await heldRegistration(Entities.pressure, watch: true, end: end)
            try await heldRegistration(Entities.stepDetected, watch: true, end: end)
        }
    }

    @MainActor
    private func heldRegistration<Snapshot>(_ kind: Entity<Snapshot>, watch: Bool, end: SensorEnd) async throws {
        let access = try DeviceAccess(collector: NoSensorGetter()).withReadTimeout(end == .timeout ? .milliseconds(80) : .seconds(5))
        defer { access.close() }
        let sensor = try access.observers.target(kind, id: "held")
        let entered = expectation(description: "sensor registration entered")
        let cleaned = expectation(description: "late sensor resource released once")
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let returned = SensorCounter()
        let sessions = SensorSessionBox<Snapshot>()
        let source = try access.observers.sensorSource(sensor) { session in
            XCTAssertFalse(Thread.isMainThread)
            sessions.set(session)
            entered.fulfill()
            release.wait()
            _ = returned.next()
            return {
                XCTAssertFalse(Thread.isMainThread)
                cleaned.fulfill()
                throw SensorTestError()
            }
        }
        defer { source.close() }
        let request = Task {
            if watch {
                for try await _ in access.watch(sensor) { XCTFail("No sensor sample was published") }
            } else { _ = try await access.get(sensor) }
        }
        defer { request.cancel() }
        await fulfillment(of: [entered], timeout: 1)
        let failSafe = Task.detached {
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled { release.signal() }
        }
        defer { failSafe.cancel() }
        let start = ContinuousClock.now
        switch end {
        case .timeout: break
        case .cancel: request.cancel()
        case .remove: source.close()
        case .close: access.close()
        }
        do { try await request.value; XCTFail("Expected sensor operation termination") }
        catch is CancellationError { XCTAssertEqual(end, .cancel) }
        catch let error as DeviceReadoutError {
            XCTAssertNotEqual(end, .cancel)
            XCTAssertEqual(error.code, end == .timeout ? .readTimeout : .entityRemoved)
        }
        XCTAssertLessThan(start.duration(to: .now), .milliseconds(400))
        XCTAssertEqual(returned.count, 0)
        let stopDeadline = ContinuousClock.now.advanced(by: .milliseconds(200))
        while sessions.get()?.isStopped == false && ContinuousClock.now < stopDeadline {
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTAssertEqual(sessions.get()?.isStopped, true)
        release.signal()
        await fulfillment(of: [cleaned], timeout: 1)
        XCTAssertEqual(returned.count, 1)
    }

    @MainActor
    func testSamplingConfigurationIsImmutableAndAppliesOnlyToSampleWatches() async throws {
        let access = DeviceAccess(collector: NoSensorGetter())
        defer { access.close() }
        let sensor = try access.observers.target(Entities.pressure, id: "barometer")
        let source = try access.observers.sensorSource(sensor) { session in
            session.publish(PressureSnapshot(value: session.samplingRate.requestedHertz ?? 0))
            return nil
        }
        defer { source.close() }
        let configured = access.withSensorSamplingRate(try .hertz(60))
        let second = try configured.withReadTimeout(.seconds(1)).withPollInterval(.seconds(30))
        XCTAssertEqual(access.sensorSamplingRate, .platformDefault)
        XCTAssertEqual(second.sensorSamplingRate, try .hertz(60))
        func first(_ access: DeviceAccess) async throws -> Double? {
            var iterator = access.watch(sensor).makeAsyncIterator()
            return try await iterator.next()?.value
        }
        let standard = try await first(access)
        let requested = try await first(second)
        let single = try await second.get(sensor)
        XCTAssertEqual(standard, 0)
        XCTAssertEqual(requested, 60)
        XCTAssertEqual(single.value, 0, "get does not request a watch sampling rate")
        let event = try access.observers.target(Entities.stepDetected, id: "step")
        let eventSource = try access.observers.sensorSource(event) { session in
            XCTAssertEqual(session.samplingRate, .platformDefault)
            session.publish(StepDetectedSnapshot(value: true))
            return nil
        }
        defer { eventSource.close() }
        var events = second.watch(event).makeAsyncIterator()
        let occurrence = try await events.next()
        XCTAssertEqual(occurrence?.value, true)
        for invalid in [0, -1, Double.nan, .infinity] {
            XCTAssertThrowsError(try SensorSamplingRate.hertz(invalid)) { error in
                XCTAssertEqual((error as? DeviceReadoutError)?.code, .invalidConfiguration)
            }
        }
    }

    @MainActor
    func testSensorDescriptionIsPassiveTypedAndNormalizedWithoutStartingSource() async throws {
        let access = DeviceAccess(collector: NoSensorGetter())
        defer { access.close() }
        let sensor = try access.observers.target(Entities.pressure, id: "barometer")
        let source = try access.observers.sensorSource(sensor, description: SensorDescription(
            kind: .accelerometer, name: "Pressure sensor", vendor: "Test vendor", version: "2",
            reportingMode: .continuous, minimumInterval: .milliseconds(-1), maximumInterval: .seconds(1),
            maximumRange: .infinity, resolution: 0.01, powerMilliamps: 0, fifoCapacity: 64
        )) { _ in
            XCTFail("Describing a sensor must not start measurement")
            return nil
        }
        defer { source.close() }
        let before = Date()
        let description = try await access.describe(sensor)
        XCTAssertEqual(description.kind, .pressure, "The typed entity determines its sensor kind")
        XCTAssertEqual(description.name, "Pressure sensor")
        XCTAssertEqual(description.vendor, "Test vendor")
        XCTAssertEqual(description.version, "2")
        XCTAssertEqual(description.reportingMode, .continuous)
        XCTAssertNil(description.minimumInterval)
        XCTAssertEqual(description.maximumInterval, .seconds(1))
        XCTAssertNil(description.maximumRange)
        XCTAssertEqual(description.resolution, 0.01)
        XCTAssertEqual(description.powerMilliamps, 0)
        XCTAssertEqual(description.fifoCapacity, 64)
        XCTAssertGreaterThanOrEqual(description.collectedAt, before)
        do { _ = try await access.describe(Entities.ram); XCTFail("A state entity has no sensor description") }
        catch let error as DeviceReadoutError { XCTAssertEqual(error.code, .unsupportedEntity) }
    }

    @MainActor
    func testEventWatchWaitsForRealOccurrenceBeyondReadTimeoutWhileGetHasDeadline() async throws {
        let access = try DeviceAccess(collector: NoSensorGetter()).withReadTimeout(.milliseconds(40))
        defer { access.close() }
        let sensor = try access.observers.target(Entities.stepDetected, id: "step")
        let starts = SensorCounter()
        let sessions = SensorSessionBox<StepDetectedSnapshot>()
        let watching = expectation(description: "event watch subscribed")
        let released = expectation(description: "event get and watch released")
        released.expectedFulfillmentCount = 2
        let source = try access.observers.sensorSource(sensor) { session in
            sessions.set(session)
            if starts.next() == 2 { watching.fulfill() }
            return { released.fulfill() }
        }
        defer { source.close() }
        do { _ = try await access.get(sensor); XCTFail("Event get must have a read deadline") }
        catch let error as DeviceReadoutError { XCTAssertEqual(error.code, .readTimeout) }
        let consumer = Task { () throws -> StepDetectedSnapshot? in
            var iterator = access.watch(sensor).makeAsyncIterator()
            return try await iterator.next()
        }
        defer { consumer.cancel() }
        await fulfillment(of: [watching], timeout: 1)
        try await Task.sleep(for: .milliseconds(120))
        let before = Date()
        try XCTUnwrap(sessions.get()).publish(StepDetectedSnapshot(value: true))
        let actual = try await consumer.value
        XCTAssertEqual(actual?.value, true)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(actual).collectedAt, before)
        await fulfillment(of: [released], timeout: 1)
    }

    @MainActor
    func testSensorWatchIsColdKeepsEqualSamplesAndReleasesWhenIterationEnds() async throws {
        let access = try DeviceAccess(collector: NoSensorGetter()).withPollInterval(.seconds(30))
        defer { access.close() }
        let sensor = try access.observers.target(Entities.pressure, id: "barometer")
        let starts = SensorCounter()
        let released = expectation(description: "watch sensor session released")
        let source = try access.observers.sensorSource(sensor) { session in
            XCTAssertFalse(Thread.isMainThread)
            _ = starts.next()
            for value in [1.0, 2.0, 2.0, .nan] { session.publish(PressureSnapshot(value: value)) }
            return { XCTAssertFalse(Thread.isMainThread); released.fulfill() }
        }
        defer { source.close() }
        let stream = access.watch(sensor)
        XCTAssertEqual(starts.count, 0)
        var values: [Double?] = []
        let start = ContinuousClock.now
        for try await snapshot in stream {
            values.append(snapshot.value)
            XCTAssertGreaterThan(snapshot.collectedAt, Date(timeIntervalSince1970: 0))
            if values.count == 4 { break }
        }
        XCTAssertEqual(values, [1, 2, 2, nil])
        XCTAssertLessThan(start.duration(to: .now), .seconds(1))
        await fulfillment(of: [released], timeout: 1)
        withExtendedLifetime(stream) { }
        XCTAssertEqual(starts.count, 1)
    }

    @MainActor
    func testOneShotSensorDemandStartsAndReleasesOnWorkerWithFreshSampleAndTimestamp() async throws {
        let access = DeviceAccess(collector: NoSensorGetter())
        defer { access.close() }
        let sensor = try access.observers.target(Entities.pressure, id: "barometer")
        let starts = SensorCounter()
        let released = expectation(description: "both one-shot sensor sessions released")
        released.expectedFulfillmentCount = 2
        let source = try access.observers.sensorSource(sensor) { session in
            XCTAssertFalse(Thread.isMainThread)
            let count = starts.next()
            session.publish(PressureSnapshot(value: count == 1 ? 101325 : 101320))
            return { XCTAssertFalse(Thread.isMainThread); released.fulfill() }
        }
        defer { source.close() }
        XCTAssertEqual(starts.count, 0, "Source registration must not start collection")
        let before = Date()
        let first = try await access.get(sensor)
        let second = try await access.get(sensor)
        XCTAssertEqual(first.value, 101325)
        XCTAssertEqual(second.value, 101320, "Each get waits for its own actual sample")
        XCTAssertGreaterThanOrEqual(first.collectedAt, before)
        XCTAssertGreaterThanOrEqual(second.collectedAt, first.collectedAt)
        await fulfillment(of: [released], timeout: 1)
        XCTAssertEqual(starts.count, 2)
    }
}

private struct NoSensorGetter: DeviceCollector {
    func read(_ request: EntityRequest) throws -> any DeviceSnapshot {
        XCTFail("A registered sensor source must not call a state getter")
        throw DeviceReadoutError(.unsupportedEntity, "No native sensor getter")
    }
}

private enum SensorEnd { case timeout, cancel, remove, close }
private struct SensorTestError: Error {}

private final class SensorCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    func next() -> Int { lock.lock(); defer { lock.unlock() }; value += 1; return value }
}

private final class SensorSessionBox<Snapshot: DeviceSnapshot>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: SensorObserverSession<Snapshot>?
    func set(_ value: SensorObserverSession<Snapshot>) { lock.lock(); self.value = value; lock.unlock() }
    func get() -> SensorObserverSession<Snapshot>? { lock.lock(); defer { lock.unlock() }; return value }
}
