#if os(macOS) || os(iOS)
import Foundation
#if os(macOS)
import IOKit.ps
#endif

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
        return PowerSnapshot(powerSource: source(), powerSaveMode: system.isLowPowerModeEnabled, thermalState: thermal)
    }

    private static func source() -> PowerSource? {
        #if os(macOS)
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let value = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return nil }
        switch value as String {
        case kIOPMACPowerKey: return .external
        case kIOPMBatteryPowerKey: return .battery
        case kIOPMUPSPowerKey: return .ups
        default: return nil
        }
        #else
        // UIKit battery monitoring is app-owned; do not enable it during a read.
        return nil
        #endif
    }
}

// Construction and removal are worker-owned. Foundation callbacks only invalidate
// the source; native fields are reread and normalized by the serial collector.
final class NativeApplePowerObservation: @unchecked Sendable {
    private let center: NotificationCenter
    private let tokens: [NSObjectProtocol]

    init(notify: @escaping @Sendable () -> Void) {
        // Foundation requires this read before thermal notification registration.
        _ = ProcessInfo.processInfo.thermalState
        let center = NotificationCenter.default
        self.center = center
        tokens = [NSNotification.Name.NSProcessInfoPowerStateDidChange,
                  ProcessInfo.thermalStateDidChangeNotification].map { name in
            center.addObserver(forName: name, object: nil, queue: nil) { _ in notify() }
        }
    }

    func close() { tokens.forEach { center.removeObserver($0) } }
}
#endif
