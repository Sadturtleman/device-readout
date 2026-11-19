#if os(macOS) || os(iOS)
import Darwin
import Foundation

enum NativeAppleCpu {
    // Called on the collection worker; only read-only system queries.
    static func read() -> CpuSnapshot {
        let process = ProcessInfo.processInfo
        let total = process.processorCount
        let available = process.activeProcessorCount
        return CpuSnapshot(logicalProcessorCount: total > 0 ? total : nil,
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
}
#endif
