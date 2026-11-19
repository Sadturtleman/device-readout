#if os(macOS) || os(iOS)
import Darwin
import Foundation

enum NativeAppleMemory {
    // Runs on the collection worker; process allocation allowance is a different entity.
    static func readRam() -> RamSnapshot {
        let physical = ProcessInfo.processInfo.physicalMemory
        return RamSnapshot(physicalBytes: physical, freeBytes: freeMemory())
    }

    private static func freeMemory() -> UInt64? {
        let host = mach_host_self()
        guard host != 0 else { return nil }
        // mach_host_self returns a send right; every read releases its own reference.
        defer { _ = mach_port_deallocate(mach_task_self_, host) }
        var pageSize: vm_size_t = 0
        guard host_page_size(host, &pageSize) == KERN_SUCCESS, pageSize > 0 else { return nil }
        var statistics = vm_statistics64_data_t()
        let capacity = MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        var count = mach_msg_type_number_t(capacity)
        let status = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: capacity) { buffer in
                host_statistics64(host, HOST_VM_INFO64, buffer, &count)
            }
        }
        // Only the first natural_t (free_count) is needed; accept older valid structure revisions.
        guard status == KERN_SUCCESS, count > 0, count <= mach_msg_type_number_t(capacity) else { return nil }
        // Darwin's free_count already includes speculative pages.
        let (bytes, overflow) = UInt64(statistics.free_count).multipliedReportingOverflow(by: UInt64(pageSize))
        return overflow ? nil : bytes
    }
}
#endif
