#if os(macOS) || os(iOS)
import DeviceReadout
import Foundation
import XCTest

final class ApplePowerTests: XCTestCase {
    #if os(macOS)
    func testNativePowerSourceMatchesIndependentSystemReport() async throws {
        let referenceBefore = try systemPowerSource()
        let access = DeviceAccess()
        defer { access.close() }
        let value: PowerSnapshot = try await access.get(Entities.power)
        let referenceAfter = try systemPowerSource()
        XCTAssertNotNil(value.powerSource)
        if referenceBefore == referenceAfter {
            XCTAssertEqual(value.powerSource, referenceBefore)
        }
        print("APPLE_POWER_REFERENCE \(referenceBefore.rawValue) -> \(referenceAfter.rawValue)")
    }

    // Independent consumer reference only; the SDK never launches this command.
    private func systemPowerSource() throws -> PowerSource {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "batt"]
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw PowerReferenceError.failedCommand }
        let firstLine = String(decoding: data, as: UTF8.self).split(separator: "\n").first
        switch firstLine {
        case "Now drawing from 'AC Power'": return .external
        case "Now drawing from 'Battery Power'": return .battery
        case "Now drawing from 'UPS Power'": return .ups
        default: throw PowerReferenceError.unrecognizedSource
        }
    }
    #endif

    @MainActor
    func testNativePowerDeliversBothFoundationNotificationsBeforePolling() async throws {
        let access = try DeviceAccess().withPollInterval(.seconds(3600))
        defer { access.close() }
        let first = expectation(description: "initial power snapshot")
        let saver = expectation(description: "power-state notification snapshot")
        let thermal = expectation(description: "thermal-state notification snapshot")
        let consumer = Task { () throws -> [PowerSnapshot] in
            var values: [PowerSnapshot] = []
            for try await value in access.watch(Entities.power) {
                values.append(value)
                if values.count == 1 { first.fulfill() }
                if values.count == 2 { saver.fulfill() }
                if values.count == 3 { thermal.fulfill(); break }
            }
            return values
        }
        defer { consumer.cancel() }
        await fulfillment(of: [first], timeout: 2)
        let failSafe = Task.detached {
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { consumer.cancel() }
        }
        defer { failSafe.cancel() }
        NotificationCenter.default.post(name: .NSProcessInfoPowerStateDidChange, object: ProcessInfo.processInfo)
        await fulfillment(of: [saver], timeout: 2)
        NotificationCenter.default.post(name: ProcessInfo.thermalStateDidChangeNotification, object: ProcessInfo.processInfo)
        await fulfillment(of: [thermal], timeout: 2)
        let values = try await consumer.value
        XCTAssertEqual(values.count, 3)
        XCTAssertGreaterThan(values[1].collectedAt, values[0].collectedAt)
        XCTAssertGreaterThan(values[2].collectedAt, values[1].collectedAt)
    }

    func testNativePowerPreservesAppleThermalStateAndLowPowerMode() async throws {
        let access = DeviceAccess()
        defer { access.close() }
        let system = ProcessInfo.processInfo
        let saverBefore = system.isLowPowerModeEnabled
        let thermalBefore = system.thermalState.rawValue
        let before = Date()
        let value: PowerSnapshot = try await access.get(Entities.power)
        let saverAfter = system.isLowPowerModeEnabled
        let thermalAfter = system.thermalState.rawValue
        XCTAssertNotNil(value.powerSaveMode)
        if saverBefore == saverAfter { XCTAssertEqual(value.powerSaveMode, saverBefore) }
        // Public Apple values 0...3 retain their platform meanings, not Android levels.
        let states: [ThermalState] = [.apple(.nominal), .apple(.fair), .apple(.serious), .apple(.critical)]
        if thermalBefore == thermalAfter {
            let expected = states.indices.contains(thermalBefore) ? states[thermalBefore] : nil
            XCTAssertEqual(value.thermalState, expected)
        }
        XCTAssertGreaterThanOrEqual(value.collectedAt, before)
        XCTAssertLessThanOrEqual(value.collectedAt, Date())
        let support = try await access.capabilities.get(Entities.power)
        XCTAssertEqual(support.readable, true)
        XCTAssertEqual(support.watchable, true)
        #if os(iOS)
        XCTAssertNil(value.powerSource, "Battery/UI state must come from app-owned observers.")
        #endif
    }
}

#if os(macOS)
private enum PowerReferenceError: Error { case failedCommand, unrecognizedSource }
#endif
#endif
