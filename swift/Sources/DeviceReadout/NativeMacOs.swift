#if os(macOS)
import Darwin
import Foundation

enum NativeMacOs {
    // Invoked by the collection worker; no UI access or process-wide mutation.
    static func read() -> OsSnapshot {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let productVersion = version.majorVersion > 0 && version.minorVersion >= 0 && version.patchVersion >= 0
            ? "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)" : nil
        var kernel = utsname()
        let hasKernel = uname(&kernel) == 0
        let kernelName = hasKernel ? withUnsafeBytes(of: kernel.sysname) { string($0) } : nil
        let kernelVersion = hasKernel ? withUnsafeBytes(of: kernel.release) { string($0) } : nil
        return OsSnapshot(family: .macOS, name: "macOS", version: productVersion,
                          build: systemString("kern.osversion"),
                          kernelName: kernelName, kernelVersion: kernelVersion)
    }

    private static func systemString(_ name: String) -> String? {
        var count = 0
        guard sysctlbyname(name, nil, &count, nil, 0) == 0, count > 1, count <= 4096 else { return nil }
        var bytes = [UInt8](repeating: 0, count: count)
        let status = bytes.withUnsafeMutableBytes { buffer in
            sysctlbyname(name, buffer.baseAddress, &count, nil, 0)
        }
        guard status == 0, count > 1, count <= bytes.count else { return nil }
        return string(bytes.prefix(count))
    }

    private static func string<Bytes: Collection>(_ bytes: Bytes) -> String? where Bytes.Element == UInt8 {
        guard let terminator = bytes.firstIndex(of: 0), terminator != bytes.startIndex else { return nil }
        return String(bytes: bytes[..<terminator], encoding: .utf8)
    }
}
#endif
