#if os(macOS) || os(iOS)
import Darwin
import Foundation

enum NativeAppleCpu {
    // Called on the collection worker; only read-only system queries.
    static func read() -> CpuSnapshot {
        let process = ProcessInfo.processInfo
        let total = process.processorCount
        let available = process.activeProcessorCount
        return CpuSnapshot(model: systemString("machdep.cpu.brand_string"),
                           manufacturer: systemString("machdep.cpu.vendor"),
                           logicalProcessorCount: total > 0 ? total : nil,
                           availableLogicalProcessorCount: available > 0 ? available : nil,
                           physicalCoreCount: positiveInteger("hw.physicalcpu_max"),
                           processorPackageCount: positiveInteger("hw.packages"))
    }

    private static func positiveInteger(_ name: String) -> Int? {
        // These public sysctls return signed 32-bit counts, even on 64-bit hosts.
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            sysctlbyname(name, pointer, &size, nil, 0)
        }
        guard status == 0, size == MemoryLayout<Int32>.size, value > 0 else { return nil }
        return Int(value)
    }

    private static func systemString(_ name: String) -> String? {
        var count = 0
        guard sysctlbyname(name, nil, &count, nil, 0) == 0, count > 1, count <= 4096 else { return nil }
        // Unwritten bytes must not fabricate a terminator in a malformed reply.
        var bytes = [UInt8](repeating: 0xff, count: count)
        let status = bytes.withUnsafeMutableBytes { buffer in
            sysctlbyname(name, buffer.baseAddress, &count, nil, 0)
        }
        guard status == 0, count > 1, count <= bytes.count,
              let terminator = bytes.prefix(count).firstIndex(of: 0), terminator > 0 else { return nil }
        return String(bytes: bytes[..<terminator], encoding: .utf8)
    }
}
#endif
