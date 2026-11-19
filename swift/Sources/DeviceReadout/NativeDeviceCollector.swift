import Foundation

struct NativeDeviceCollector: DeviceCollector {
    func observeChanges(_ request: EntityRequest, notify: @escaping @Sendable () -> Void) throws -> NativeStateCleanup? {
        guard request.kind == .timeZone else { return nil }
        let observation = FoundationTimeZoneObservation(notify: notify)
        return { observation.close() }
    }

    func capabilities(_ request: EntityRequest) throws -> EntityCapabilities {
        var supported = request.kind == .runtime || request.kind == .timeZone
        #if os(macOS) || os(iOS)
        supported = supported || request.kind == .power
        #endif
        return EntityCapabilities(readable: supported, watchable: supported)
    }

    func read(_ request: EntityRequest) throws -> any DeviceSnapshot {
        #if os(macOS) || os(iOS)
        if request.kind == .power { return NativeApplePower.read() }
        #endif
        if request.kind == .timeZone {
            // Freeze one rule set before querying its offset/DST at one instant.
            // Never reset Foundation's process-wide cache or change the app default.
            let identifier = TimeZone.autoupdatingCurrent.identifier
            guard let zone = TimeZone(identifier: identifier) else {
                throw DeviceReadoutError(.readFailed, "The system time zone cannot be resolved.")
            }
            let instant = Date()
            let known = Self.fixedIanaIdentifiers.contains(identifier) || TimeZone.knownTimeZoneIdentifiers.contains(identifier)
            return TimeZoneSnapshot(ianaId: known ? identifier : nil,
                                    utcOffsetSeconds: zone.secondsFromGMT(for: instant),
                                    daylightSavingTime: zone.isDaylightSavingTime(for: instant))
        }
        if request.kind == .runtime {
            let architecture: Architecture?
            #if arch(x86_64)
            architecture = .x64
            #elseif arch(i386)
            architecture = .x86
            #elseif arch(arm64)
            architecture = .arm64
            #elseif arch(arm)
            architecture = .arm32
            #else
            architecture = nil
            #endif
            return RuntimeSnapshot(processArchitecture: architecture,
                                   processBitness: MemoryLayout<UnsafeRawPointer>.size * 8)
        }
        throw DeviceReadoutError(.unsupportedEntity, "The native collector does not implement this entity.")
    }

    // Foundation's region listing can omit fixed IANA zones. Preserve these
    // tzdb etcetera/backward names; a synthetic GMT+HHmm identifier is not IANA.
    private static let fixedIanaIdentifiers: Set<String> = Set([
        "Etc/UTC", "Etc/GMT", "GMT", "UTC", "UCT", "Universal", "Zulu", "Greenwich",
        "GMT0", "GMT+0", "GMT-0", "Etc/GMT0", "Etc/GMT+0", "Etc/GMT-0", "Etc/Greenwich",
        "Etc/UCT", "Etc/Universal", "Etc/Zulu",
    ] + (1...12).map { "Etc/GMT+\($0)" } + (1...14).map { "Etc/GMT-\($0)" })
}

// The token is immutable and accessed only for worker-owned removal. Foundation
// controls callback delivery; that callback only signals an SDK invalidation.
private final class FoundationTimeZoneObservation: @unchecked Sendable {
    private let center: NotificationCenter
    private let token: NSObjectProtocol
    init(notify: @escaping @Sendable () -> Void) {
        let center = NotificationCenter.default
        self.center = center
        token = center.addObserver(forName: .NSSystemTimeZoneDidChange, object: nil, queue: nil) { _ in notify() }
    }
    func close() { center.removeObserver(token) }
}
