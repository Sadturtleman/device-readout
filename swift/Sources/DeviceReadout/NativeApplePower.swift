#if os(macOS) || os(iOS)
import Foundation

enum NativeApplePower {
    // Invoked only from the collector worker; no UI or global state mutation.
    static func read() -> PowerSnapshot {
        let system = ProcessInfo.processInfo
        let thermal: ThermalState?
        switch system.thermalState {
        case .nominal: thermal = .apple(.nominal)
        case .fair: thermal = .apple(.fair)
        case .serious: thermal = .apple(.serious)
        case .critical: thermal = .apple(.critical)
        @unknown default: thermal = nil
        }
        return PowerSnapshot(powerSaveMode: system.isLowPowerModeEnabled, thermalState: thermal)
    }
}
#endif
