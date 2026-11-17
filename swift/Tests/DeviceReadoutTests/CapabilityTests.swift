import DeviceReadout
import Foundation
import XCTest

final class CapabilityTests: XCTestCase {
    @MainActor
    func testNewAppOwnershipSupersedesLateNativeCapabilityValuesAndErrors() async throws {
        for fails in [false, true] {
            let entered = expectation(description: "old native capability query held")
            let returned = expectation(description: "old native query returned")
            let answer: Result<EntityCapabilities, Error> = fails
                ? .failure(DeviceReadoutError(.readFailed, "Old provider failed"))
                : .success(EntityCapabilities(readable: false, watchable: false))
            let collector = HeldCapabilityCollector(entered: entered, returned: returned, answer: answer)
            let access = try DeviceAccess(collector: collector).withReadTimeout(.seconds(1))
            defer { collector.release.signal(); access.close() }
            let pending = Task { try await access.capabilities.get(Entities.ram) }
            defer { pending.cancel() }
            await fulfillment(of: [entered], timeout: 1)
            try access.observers.publish(Entities.ram, snapshot: RamSnapshot(physicalBytes: 42))
            collector.release.signal()
            let support = try await pending.value
            XCTAssertEqual(support, EntityCapabilities(readable: true, watchable: true))
            await fulfillment(of: [returned], timeout: 1)
        }
    }

    @MainActor
    func testCapabilityCollectorPreservesTypedErrorsAndCancellationAndWrapsUnexpectedFailures() async throws {
        let access = DeviceAccess(collector: FailingCapabilityCollector())
        defer { access.close() }
        do { _ = try await access.capabilities.get(Entities.ram); XCTFail("Typed provider error") }
        catch let error as DeviceReadoutError {
            XCTAssertEqual(error, DeviceReadoutError(.unsupportedEntity, "Provider has no support metadata"))
        }
        do { _ = try await access.capabilities.get(Entities.cpu); XCTFail("Unexpected provider error") }
        catch let error as DeviceReadoutError { XCTAssertEqual(error.code, .readFailed) }
        do { _ = try await access.capabilities.get(Entities.os); XCTFail("Provider canceled its query") }
        catch is CancellationError { }
    }

    @MainActor
    func testCapabilitiesRespectTargetNamespaceGenerationAndContext() async throws {
        let access = DeviceAccess(collector: NativeCapabilityCollector())
        defer { access.close() }
        let available = EntityCapabilities(readable: true, watchable: true)
        let unavailable = EntityCapabilities(readable: false, watchable: false)
        let nativeTargets = try await access.displays.list()
        let native = try XCTUnwrap(nativeTargets.first)
        let app = try access.observers.target(Entities.display, id: "native")
        let nativeSupport = try await access.capabilities.get(native)
        let appSupport = try await access.capabilities.get(app)
        XCTAssertEqual(nativeSupport, unavailable)
        XCTAssertEqual(appSupport, available)
        let other = DeviceAccess(collector: NativeCapabilityCollector())
        defer { other.close() }
        do { _ = try await other.capabilities.get(app); XCTFail("Foreign handles are invalid") }
        catch let error as DeviceReadoutError { XCTAssertEqual(error.code, .invalidConfiguration) }
        let old = try access.observers.target(Entities.pressure, id: "reused")
        let oldRegistration = try access.observers.sensorSource(old) { _ in XCTFail("Passive query"); return nil }
        defer { oldRegistration.close() }
        try access.observers.remove(old)
        let replacement = try access.observers.target(Entities.pressure, id: "reused")
        let registration = try access.observers.sensorSource(replacement) { _ in XCTFail("Passive query"); return nil }
        defer { registration.close() }
        oldRegistration.close()
        let oldSupport = try await access.capabilities.get(old)
        let newSupport = try await access.capabilities.get(replacement)
        let kindSupport = try await access.capabilities.get(Entities.pressure)
        XCTAssertEqual(oldSupport, unavailable)
        XCTAssertEqual(newSupport, available)
        XCTAssertEqual(kindSupport, available)
        registration.close()
        let empty = try await access.capabilities.get(Entities.pressure)
        XCTAssertEqual(empty, unavailable)
        access.close()
        do { _ = try await access.capabilities.get(app); XCTFail("Closed contexts reject cached capability queries") }
        catch let error as DeviceReadoutError { XCTAssertEqual(error.code, .entityRemoved) }
    }

    @MainActor
    func testHeldNativeCapabilitiesKeepCallerDeadlinesAndAppMetadataResponsive() async throws {
        for ending in CapabilityEnding.allCases {
            let entered = expectation(description: "native capability query held")
            let returned = expectation(description: "held query returned")
            let collector = HeldCapabilityCollector(entered: entered, returned: returned)
            let access = try DeviceAccess(collector: collector).withReadTimeout(.milliseconds(120))
            defer { collector.release.signal(); access.close() }
            let targets = try await access.displays.list()
            let target = try XCTUnwrap(targets.first)
            let pending = Task { try await access.capabilities.get(target) }
            defer { pending.cancel() }
            await fulfillment(of: [entered], timeout: 1)
            let failSafe = Task.detached {
                try? await Task.sleep(for: .seconds(1))
                if !Task.isCancelled { collector.release.signal(); pending.cancel() }
            }
            defer { failSafe.cancel() }
            try access.observers.publish(Entities.ram, snapshot: RamSnapshot(physicalBytes: 42))
            let start = ContinuousClock.now
            let observed = try await access.capabilities.get(Entities.ram)
            XCTAssertEqual(observed, EntityCapabilities(readable: true, watchable: true))
            XCTAssertLessThan(start.duration(to: .now), .milliseconds(80), "Known app metadata must not join held native work")
            switch ending {
            case .timeout: break
            case .cancel: pending.cancel()
            case .remove: try access.observers.remove(target)
            case .close: access.close()
            }
            do {
                let value = try await pending.value
                XCTAssertEqual(ending, .remove)
                XCTAssertEqual(value, EntityCapabilities(readable: false, watchable: false))
            } catch is CancellationError { XCTAssertEqual(ending, .cancel) }
            catch let error as DeviceReadoutError {
                XCTAssertTrue(ending == .timeout || ending == .close)
                XCTAssertEqual(error.code, ending == .timeout ? .readTimeout : .entityRemoved)
            }
            XCTAssertLessThan(start.duration(to: .now), .milliseconds(300))
            collector.release.signal()
            await fulfillment(of: [returned], timeout: 1)
            if ending == .remove {
                let removed = try await access.capabilities.get(target)
                XCTAssertEqual(removed, EntityCapabilities(readable: false, watchable: false))
            }
        }
    }

    @MainActor
    func testAppStateAndSensorCapabilitiesUseRegistrationsWithoutActivatingSources() async throws {
        let access = DeviceAccess(collector: NoCapabilityCollector())
        defer { access.close() }
        let available = EntityCapabilities(readable: true, watchable: true)
        let unavailable = EntityCapabilities(readable: false, watchable: false)
        try access.observers.current(Entities.display, target: nil)
        let empty = try await access.capabilities.get(Entities.display)
        XCTAssertEqual(empty, unavailable)
        let screen = try access.observers.target(Entities.display, id: "app")
        let screenSupport = try await access.capabilities.get(screen)
        XCTAssertEqual(screenSupport, available, "Registered state input can receive future app values")
        let screens = try await access.capabilities.get(Entities.display)
        XCTAssertEqual(screens, available)
        try access.observers.publish(Entities.ram, snapshot: RamSnapshot(physicalBytes: 42))
        try access.observers.failure(Entities.ram, error: DeviceReadoutError(.permissionDenied, "Cache invalidated"))
        let ram = try await access.capabilities.get(Entities.ram)
        XCTAssertEqual(ram, available, "Invalidating cached values does not remove app support")
        let sensor = try access.observers.target(Entities.pressure, id: "pressure")
        let noSource = try await access.capabilities.get(sensor)
        XCTAssertEqual(noSource, unavailable)
        let source = try access.observers.sensorSource(sensor) { _ in
            XCTFail("Capabilities must not activate a sensor source")
            return nil
        }
        defer { source.close() }
        try access.observers.sensorActivity(false)
        try access.observers.permission(sensor, status: .denied)
        let pressure = try await access.capabilities.get(sensor)
        XCTAssertEqual(pressure, available)
        let sensorKind = try await access.capabilities.get(Entities.pressure)
        XCTAssertEqual(sensorKind, available)
        source.close()
        let removed = try await access.capabilities.get(sensor)
        XCTAssertEqual(removed, unavailable)
        let emptySensors = try await access.capabilities.get(Entities.pressure)
        XCTAssertEqual(emptySensors, unavailable)
        try access.observers.remove(screen)
        let removedScreen = try await access.capabilities.get(screen)
        XCTAssertEqual(removedScreen, unavailable)
        let removedScreens = try await access.capabilities.get(Entities.display)
        XCTAssertEqual(removedScreens, unavailable)
    }

    @MainActor
    func testPermissionAndObservationFailuresDoNotChangeSupportOrRequestAuthorization() async throws {
        let access = DeviceAccess(collector: NativeCapabilityCollector())
        defer { access.close() }
        let coordinator = try access.observers.onPermissionRequest { _ in
            XCTFail("Capability checks must not request authorization")
        }
        defer { coordinator.close() }
        try access.observers.permission(Entities.ram, status: .denied)
        let failure = try access.observers.failureSource(Entities.ram)
        defer { failure.close() }
        try failure.publish(DeviceReadoutError(.permissionDenied, "Reading is currently denied"))
        let support = try await access.capabilities.get(Entities.ram)
        XCTAssertEqual(support, EntityCapabilities(readable: true, watchable: true))
        let permission = try await access.permissions.check(Entities.ram)
        XCTAssertEqual(permission, .denied)
        do { _ = try await access.get(Entities.ram); XCTFail("Support does not grant permission") }
        catch let error as DeviceReadoutError { XCTAssertEqual(error.code, .permissionDenied) }
    }

    @MainActor
    func testNativeCapabilitiesArePassiveWorkerQueriesForSingletonKindsAndBoundTargets() async throws {
        let access = DeviceAccess(collector: NativeCapabilityCollector())
        defer { access.close() }
        let ram = try await access.capabilities.get(Entities.ram)
        XCTAssertEqual(ram, EntityCapabilities(readable: true, watchable: true))
        let missing = try await access.capabilities.get(Entities.cpu)
        XCTAssertEqual(missing, EntityCapabilities(readable: false, watchable: false))
        let unknown = try await access.capabilities.get(Entities.os)
        XCTAssertNil(unknown.readable)
        XCTAssertNil(unknown.watchable)
        let kind = try await access.capabilities.get(Entities.display)
        XCTAssertEqual(kind, EntityCapabilities(readable: true, watchable: true))
        let targets = try await access.displays.list()
        let target = try XCTUnwrap(targets.first)
        let bound = try await access.withReadTimeout(.seconds(1)).capabilities.get(target)
        XCTAssertEqual(bound, EntityCapabilities(readable: false, watchable: false))
        let fallback = DeviceAccess(collector: NoCapabilityCollector())
        defer { fallback.close() }
        let unspecified = try await fallback.capabilities.get(Entities.ram)
        XCTAssertNil(unspecified.readable)
        XCTAssertNil(unspecified.watchable)
    }
}

private struct NativeCapabilityCollector: DeviceCollector {
    func capabilities(_ request: EntityRequest) throws -> EntityCapabilities {
        XCTAssertFalse(Thread.isMainThread)
        switch request.kind {
        case .ram: return EntityCapabilities(readable: true, watchable: true)
        case .display:
            if request.targetId == nil { return EntityCapabilities(readable: true, watchable: true) }
            XCTAssertEqual(request.targetId, "native")
            return EntityCapabilities(readable: false, watchable: false)
        case .cpu: return EntityCapabilities(readable: false, watchable: false)
        default: return EntityCapabilities(readable: nil, watchable: nil)
        }
    }
    func list(_ kind: EntityKind) throws -> [String] {
        XCTAssertFalse(Thread.isMainThread)
        XCTAssertEqual(kind, .display)
        return ["native"]
    }
    func read(_ request: EntityRequest) throws -> any DeviceSnapshot {
        XCTFail("Capability queries must not read device state")
        throw DeviceReadoutError(.readFailed, "Unexpected read")
    }
}

private struct NoCapabilityCollector: DeviceCollector {
    func read(_ request: EntityRequest) throws -> any DeviceSnapshot {
        XCTFail("Default capabilities must not probe by reading state")
        throw DeviceReadoutError(.readFailed, "Unexpected read")
    }
}

private enum CapabilityEnding: CaseIterable { case timeout, cancel, remove, close }

private struct CapabilityTestError: Error { }

private struct FailingCapabilityCollector: DeviceCollector {
    func capabilities(_ request: EntityRequest) throws -> EntityCapabilities {
        XCTAssertFalse(Thread.isMainThread)
        switch request.kind {
        case .os: throw CancellationError()
        case .cpu: throw CapabilityTestError()
        default: throw DeviceReadoutError(.unsupportedEntity, "Provider has no support metadata")
        }
    }
    func read(_ request: EntityRequest) throws -> any DeviceSnapshot {
        XCTFail("Capability queries cannot probe state")
        throw CapabilityTestError()
    }
}

private final class HeldCapabilityCollector: DeviceCollector, @unchecked Sendable {
    let release = DispatchSemaphore(value: 0)
    private let entered: XCTestExpectation
    private let returned: XCTestExpectation
    private let answer: Result<EntityCapabilities, Error>
    init(entered: XCTestExpectation, returned: XCTestExpectation,
         answer: Result<EntityCapabilities, Error> = .success(EntityCapabilities(readable: true, watchable: true))) {
        self.entered = entered; self.returned = returned; self.answer = answer
    }
    func capabilities(_ request: EntityRequest) throws -> EntityCapabilities {
        XCTAssertFalse(Thread.isMainThread)
        entered.fulfill(); release.wait(); returned.fulfill()
        return try answer.get()
    }
    func list(_ kind: EntityKind) throws -> [String] { ["native"] }
    func read(_ request: EntityRequest) throws -> any DeviceSnapshot {
        XCTFail("Capability queries cannot probe state")
        throw DeviceReadoutError(.readFailed, "Unexpected read")
    }
}
