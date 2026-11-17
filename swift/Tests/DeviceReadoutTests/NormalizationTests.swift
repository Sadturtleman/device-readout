import DeviceReadout
import Foundation
import XCTest

final class NormalizationTests: XCTestCase {
    @MainActor
    func testObservedBulkNormalizationKeepsPublicationAndQueuedReadDeadlinesIndependentOfHeldNativeWork() async throws {
        let entered = expectation(description: "native collector held")
        let returned = expectation(description: "native collector returned")
        let collector = HeldNormalizationCollector(entered: entered, returned: returned)
        let access = DeviceAccess(collector: collector)
        defer { collector.release.signal(); access.close() }
        let pending = Task { try await access.get(Entities.ram) }
        defer { pending.cancel() }
        await fulfillment(of: [entered], timeout: 1)
        let failSafe = Task.detached {
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { collector.release.signal() }
        }
        defer { failSafe.cancel() }
        let screen = try access.observers.target(Entities.display, id: "bulk-modes")
        let raw = DisplaySnapshot(supportedModes: Array(repeating:
            DisplayMode(pixelSize: Size(width: 1920, height: 1080), refreshRateHz: .infinity), count: 10_000), brightness: 2)
        let publication = ContinuousClock.now
        try access.observers.publish(screen, snapshot: raw)
        XCTAssertLessThan(publication.duration(to: .now), .milliseconds(200))
        let bounded = try access.withReadTimeout(.milliseconds(60))
        let start = ContinuousClock.now
        let read = Task { try await bounded.get(screen) }
        defer { read.cancel() }
        let heartbeat = Task { @MainActor in 7 }
        let pulse = await heartbeat.value
        XCTAssertEqual(pulse, 7)
        do { _ = try await read.value; XCTFail("Normalization waits behind the held worker") }
        catch let error as DeviceReadoutError { XCTAssertEqual(error.code, .readTimeout) }
        XCTAssertLessThan(start.duration(to: .now), .milliseconds(300))
        collector.release.signal()
        let ram = try await pending.value
        XCTAssertEqual(ram.physicalBytes, 42)
        await fulfillment(of: [returned], timeout: 1)
        let fresh = try await access.get(screen)
        let modes = try XCTUnwrap(fresh.supportedModes)
        XCTAssertEqual(modes.count, 10_000)
        XCTAssertTrue(modes.allSatisfy { $0.refreshRateHz == nil && $0.pixelSize == Size(width: 1920, height: 1080) })
        XCTAssertNil(fresh.brightness)
        XCTAssertEqual(raw.supportedModes?.first?.refreshRateHz, .infinity, "Normalizing a snapshot does not mutate supplied state")
    }

    @MainActor
    func testDisplayModesNormalizeNullableMembersAndRetainEmptyCollectionsAndSnapshotValues() async throws {
        var modes = [
            DisplayMode(pixelSize: Size(width: 1920, height: 1080), refreshRateHz: .infinity),
            DisplayMode(pixelSize: nil, refreshRateHz: 0),
            DisplayMode(pixelSize: Size(width: 2560, height: 1440), refreshRateHz: 59.94)
        ]
        let raw = DisplaySnapshot(
            currentMode: DisplayMode(pixelSize: Size(width: 1920, height: 1080), refreshRateHz: .nan),
            supportedModes: modes, maximumRefreshRateHz: 120)
        modes[0] = DisplayMode(refreshRateHz: 999)
        let access = DeviceAccess(collector: FixedSnapshotCollector(snapshot: raw))
        defer { access.close() }
        let screens = try await access.displays.list()
        let screen = try XCTUnwrap(screens.first)
        let before = Date()
        let value = try await access.get(screen)
        XCTAssertEqual(value.currentMode, DisplayMode(pixelSize: Size(width: 1920, height: 1080), refreshRateHz: nil))
        XCTAssertEqual(value.supportedModes, [
            DisplayMode(pixelSize: Size(width: 1920, height: 1080), refreshRateHz: nil),
            DisplayMode(refreshRateHz: 0),
            DisplayMode(pixelSize: Size(width: 2560, height: 1440), refreshRateHz: 59.94)])
        XCTAssertEqual(value.maximumRefreshRateHz, 120)
        XCTAssertGreaterThanOrEqual(value.collectedAt, before)
        XCTAssertLessThanOrEqual(value.collectedAt, Date())
        var consumerCopy = try XCTUnwrap(value.supportedModes)
        consumerCopy[0] = DisplayMode(refreshRateHz: 777)
        let again = try await access.get(screen)
        XCTAssertEqual(again.supportedModes, value.supportedModes)
        let observed = try access.observers.target(Entities.display, id: "app")
        try access.observers.publish(observed, snapshot: DisplaySnapshot(supportedModes: []))
        var stream = access.watch(observed).makeAsyncIterator()
        let empty = try await stream.next()
        XCTAssertEqual(empty?.supportedModes, [])
        try access.observers.publish(observed, snapshot: DisplaySnapshot())
        let missing = try await stream.next()
        XCTAssertNotNil(missing)
        XCTAssertNil(missing?.supportedModes)
    }

    @MainActor
    func testOrientationSamplesProduceFiniteUnitQuaternionsWithoutChangingAxisOrSign() async throws {
        try await checkRotation(Entities.relativeOrientation, make: { RelativeOrientationSnapshot(value: $0) }, value: \.value)
        try await checkRotation(Entities.absoluteOrientation, make: { AbsoluteOrientationSnapshot(value: $0) }, value: \.value)
    }

    @MainActor
    private func checkRotation<Snapshot>(_ kind: Entity<Snapshot>, make: @escaping @Sendable (Quaternion?) -> Snapshot,
                                         value: KeyPath<Snapshot, Quaternion?>) async throws {
        let access = DeviceAccess(collector: FixedSnapshotCollector(snapshot: RamSnapshot()))
        defer { access.close() }
        let target = try access.observers.target(kind, id: "rotation")
        let samples: [Quaternion?] = [
            Quaternion(x: .nan, y: 0, z: 0, w: 1), Quaternion(x: 0, y: .infinity, z: 0, w: 1),
            Quaternion(x: 0, y: 0, z: -.infinity, w: 1), Quaternion(x: 0, y: 0, z: 0, w: .nan),
            nil, Quaternion(x: 0, y: 0, z: 0, w: 0), Quaternion(x: 0, y: 0, z: 0, w: 1),
            Quaternion(x: 0, y: 0, z: 0, w: -1), Quaternion(x: 0, y: 0, z: 3, w: 4),
            Quaternion(x: 0, y: 0, z: -3, w: -4),
            Quaternion(x: .greatestFiniteMagnitude, y: .greatestFiniteMagnitude, z: 0, w: 0),
            Quaternion(x: .leastNonzeroMagnitude, y: 0, z: 0, w: 0)
        ]
        let source = try access.observers.sensorSource(target) { session in
            for sample in samples { session.publish(make(sample)) }
            return nil
        }
        defer { source.close() }
        let single = try await access.get(target)
        XCTAssertNil(single[keyPath: value])
        var values: [Quaternion?] = []
        for try await snapshot in access.watch(target) {
            values.append(snapshot[keyPath: value])
            if values.count == samples.count { break }
        }
        XCTAssertEqual(values.count, 12)
        let expected: [Quaternion?] = [nil, nil, nil, nil, nil, nil,
            Quaternion(x: 0, y: 0, z: 0, w: 1), Quaternion(x: 0, y: 0, z: 0, w: -1),
            Quaternion(x: 0, y: 0, z: 0.6, w: 0.8), Quaternion(x: 0, y: 0, z: -0.6, w: -0.8),
            Quaternion(x: 0.7071067811865475, y: 0.7071067811865475, z: 0, w: 0),
            Quaternion(x: 1, y: 0, z: 0, w: 0)]
        for (actual, expected) in zip(values, expected) {
            if let expected = expected {
                let actual = try XCTUnwrap(actual)
                XCTAssertEqual(actual.x, expected.x, accuracy: 1e-15)
                XCTAssertEqual(actual.y, expected.y, accuracy: 1e-15)
                XCTAssertEqual(actual.z, expected.z, accuracy: 1e-15)
                XCTAssertEqual(actual.w, expected.w, accuracy: 1e-15)
            } else { XCTAssertNil(actual) }
        }
    }

    @MainActor
    func testAllVectorSensorKindsRejectPartialInvalidSamplesAndPreserveSignsAndZero() async throws {
        try await checkVector(Entities.accelerometer, make: { AccelerometerSnapshot(value: $0) }, value: \.value)
        try await checkVector(Entities.linearAcceleration, make: { LinearAccelerationSnapshot(value: $0) }, value: \.value)
        try await checkVector(Entities.gravity, make: { GravitySnapshot(value: $0) }, value: \.value)
        try await checkVector(Entities.gyroscope, make: { GyroscopeSnapshot(value: $0) }, value: \.value)
        try await checkVector(Entities.magnetometer, make: { MagnetometerSnapshot(value: $0) }, value: \.value)
    }

    @MainActor
    private func checkVector<Snapshot>(_ kind: Entity<Snapshot>, make: @escaping @Sendable (Vector3?) -> Snapshot,
                                       value: KeyPath<Snapshot, Vector3?>) async throws {
        let access = DeviceAccess(collector: FixedSnapshotCollector(snapshot: RamSnapshot()))
        defer { access.close() }
        let target = try access.observers.target(kind, id: "vector")
        let samples: [Vector3?] = [
            Vector3(x: .nan, y: 2, z: 3), Vector3(x: 1, y: .infinity, z: 3),
            Vector3(x: 1, y: 2, z: -.infinity), nil,
            Vector3(x: 0, y: 0, z: 0), Vector3(x: -1.5, y: 0.25, z: 9.81),
            Vector3(x: .greatestFiniteMagnitude, y: -.greatestFiniteMagnitude, z: 0)
        ]
        let source = try access.observers.sensorSource(target) { session in
            for sample in samples { session.publish(make(sample)) }
            return nil
        }
        defer { source.close() }
        let single = try await access.get(target)
        XCTAssertNil(single[keyPath: value], "A broken component invalidates the entire vector")
        var values: [Vector3?] = []
        for try await snapshot in access.watch(target) {
            values.append(snapshot[keyPath: value])
            if values.count == samples.count { break }
        }
        XCTAssertEqual(values, [nil, nil, nil, nil, Vector3(x: 0, y: 0, z: 0),
            Vector3(x: -1.5, y: 0.25, z: 9.81),
            Vector3(x: .greatestFiniteMagnitude, y: -.greatestFiniteMagnitude, z: 0)])
    }

    @MainActor
    func testScreenGeometryRejectsWholeInvalidStructuresAndPreservesIndependentFields() async throws {
        let raw = DisplaySnapshot(
            label: "screen", logicalBounds: Rect(x: .nan, y: 0, width: 1280, height: 720),
            workAreaBounds: Rect(x: -1280, y: -100, width: 1280, height: .infinity),
            pixelSize: Size(width: 1920, height: 1080),
            physicalSizeMillimeters: Size(width: -.infinity, height: 200)
        )
        let access = DeviceAccess(collector: FixedSnapshotCollector(snapshot: raw))
        defer { access.close() }
        let screens = try await access.displays.list()
        let screen = try XCTUnwrap(screens.first)
        let value = try await access.get(screen)
        XCTAssertNil(value.logicalBounds)
        XCTAssertNil(value.workAreaBounds)
        XCTAssertNil(value.physicalSizeMillimeters)
        XCTAssertEqual(value.pixelSize, Size(width: 1920, height: 1080))
        XCTAssertEqual(value.label, "screen")
        let appScreen = try access.observers.target(Entities.display, id: "app")
        try access.observers.publish(appScreen, snapshot: DisplaySnapshot(
            logicalBounds: Rect(x: -1280, y: -100, width: 1280, height: 720),
            workAreaBounds: Rect(x: -1280, y: -100, width: 0, height: 0),
            physicalSizeMillimeters: Size(width: 310.5, height: 174.75)))
        let valid = try await access.get(appScreen)
        XCTAssertEqual(valid.logicalBounds, Rect(x: -1280, y: -100, width: 1280, height: 720))
        XCTAssertEqual(valid.workAreaBounds, Rect(x: -1280, y: -100, width: 0, height: 0))
        XCTAssertEqual(valid.physicalSizeMillimeters, Size(width: 310.5, height: 174.75))
        let viewport = try access.observers.target(Entities.viewport, id: "view")
        try access.observers.publish(viewport, snapshot: ViewportSnapshot(
            size: Size(width: .infinity, height: 400), visualViewportSize: Size(width: 200, height: .nan),
            safeAreaInsets: Insets(top: 20, right: -.infinity, bottom: 0, left: 0)))
        var stream = access.watch(viewport).makeAsyncIterator()
        let invalid = try await stream.next()
        XCTAssertNil(invalid?.size)
        XCTAssertNil(invalid?.visualViewportSize)
        XCTAssertNil(invalid?.safeAreaInsets)
        try access.observers.publish(viewport, snapshot: ViewportSnapshot(
            size: Size(width: 0, height: 400), visualViewportSize: Size(width: 200.5, height: 300.25),
            safeAreaInsets: Insets(top: 20.5, right: 0, bottom: 8, left: 0)))
        let recovered = try await stream.next()
        XCTAssertEqual(recovered?.size, Size(width: 0, height: 400))
        XCTAssertEqual(recovered?.visualViewportSize, Size(width: 200.5, height: 300.25))
        XCTAssertEqual(recovered?.safeAreaInsets, Insets(top: 20.5, right: 0, bottom: 8, left: 0))
    }

    @MainActor
    func testRatiosRejectOutOfRangeAndNonfiniteValuesAcrossNativeObservedAndSensorReads() async throws {
        let cases: [(Double?, Double?)] = [
            (nil, nil), (.nan, nil), (.infinity, nil), (-.infinity, nil),
            (-0.001, nil), (1.001, nil), (0, 0), (1, 1), (0.25, 0.25)
        ]
        for (raw, expected) in cases {
            let access = DeviceAccess(collector: RatioCollector(value: raw))
            defer { access.close() }
            let displays = try await access.displays.list()
            let display = try XCTUnwrap(displays.first)
            let screen = try await access.get(display)
            XCTAssertEqual(screen.brightness, expected)
            let battery = try access.observers.target(Entities.battery, id: "app-battery")
            try access.observers.publish(battery, snapshot: BatterySnapshot(level: raw, charging: false))
            var stream = access.watch(battery).makeAsyncIterator()
            let power = try await stream.next()
            XCTAssertEqual(power?.level, expected)
            XCTAssertEqual(power?.charging, false)
            let humidity = try access.observers.target(Entities.relativeHumidity, id: "humidity")
            let source = try access.observers.sensorSource(humidity) { session in
                session.publish(RelativeHumiditySnapshot(value: raw))
                return nil
            }
            defer { source.close() }
            let measurement = try await access.get(humidity)
            XCTAssertEqual(measurement.value, expected)
        }
    }
}

private struct RatioCollector: DeviceCollector {
    let value: Double?
    func list(_ kind: EntityKind) throws -> [String] { ["display"] }
    func read(_ request: EntityRequest) throws -> any DeviceSnapshot {
        XCTAssertFalse(Thread.isMainThread)
        XCTAssertEqual(request.kind, .display)
        return DisplaySnapshot(brightness: value)
    }
}

private struct FixedSnapshotCollector: DeviceCollector {
    let snapshot: any DeviceSnapshot
    func list(_ kind: EntityKind) throws -> [String] { ["native"] }
    func read(_ request: EntityRequest) throws -> any DeviceSnapshot {
        XCTAssertFalse(Thread.isMainThread)
        return snapshot
    }
}

private final class HeldNormalizationCollector: DeviceCollector, @unchecked Sendable {
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
