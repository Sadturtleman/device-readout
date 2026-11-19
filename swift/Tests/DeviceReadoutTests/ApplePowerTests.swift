#if os(macOS) || os(iOS)
import DeviceReadout
import Foundation
import XCTest

final class ApplePowerTests: XCTestCase {
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
#endif
