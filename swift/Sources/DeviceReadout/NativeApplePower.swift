#if os(macOS) || os(iOS)
import Foundation
#if os(macOS)
import IOKit.ps
import notify
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
    #if os(macOS)
    private let sourceRetirement: NativePowerSourceRetirement
    #endif

    init(notify: @escaping @Sendable () -> Void) throws {
        // Foundation requires this read before thermal notification registration.
        _ = ProcessInfo.processInfo.thermalState
        #if os(macOS)
        var token: Int32 = 0
        let status = notify_register_dispatch(kIOPSNotifyPowerSource, &token, .global(qos: .utility)) { _ in notify() }
        guard status == UInt32(NOTIFY_STATUS_OK) else {
            throw DeviceReadoutError(.readFailed, "Power-source notification registration failed (\(status)).")
        }
        sourceRetirement = NativePowerSourceRetirement(token: token)
        #endif
        let center = NotificationCenter.default
        self.center = center
        tokens = [NSNotification.Name.NSProcessInfoPowerStateDidChange,
                  ProcessInfo.thermalStateDidChangeNotification].map { name in
            center.addObserver(forName: name, object: nil, queue: nil) { _ in notify() }
        }
    }

    func close() {
        tokens.forEach { center.removeObserver($0) }
        #if os(macOS)
        sourceRetirement.close()
        #endif
    }
}

#if os(macOS)
// A failed native cancellation still owns a live token. Keep it until the OS
// accepts retirement, without holding up ordinary collection or the caller.
private final class NativePowerSourceRetirement: @unchecked Sendable {
    private let token: Int32
    private let lock = NSLock()
    private var started = false

    init(token: Int32) { self.token = token }

    func close() {
        lock.lock()
        guard !started else { lock.unlock(); return }
        started = true
        lock.unlock()
        attempt(retryDelay: 0.1)
    }

    private func attempt(retryDelay: TimeInterval) {
        let status = notify_cancel(token)
        if status == UInt32(NOTIFY_STATUS_OK) || status == UInt32(NOTIFY_STATUS_INVALID_TOKEN) { return }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + retryDelay) { [self] in
            attempt(retryDelay: min(retryDelay * 2, 30))
        }
    }
}
#endif
#endif
