#if os(macOS) || os(iOS)
import Darwin
import DeviceReadout
import Foundation
import XCTest

final class AppleCpuTopologyTests: XCTestCase {
    @MainActor
    func testNativePhysicalCoreCountMatchesIndependentMachReport() async throws {
        let reference = try await Task.detached { try machPhysicalCoreReference() }.value
        let access = DeviceAccess()
        defer { access.close() }
        let value = try await access.get(Entities.cpu)
        XCTAssertEqual(value.physicalCoreCount, reference)
        print("APPLE_CPU_MACH_REFERENCE physical=\(reference)")
    }

    #if os(macOS)
    @MainActor
    func testNativePhysicalTopologyMatchesIndependentSystemReport() async throws {
        let reference = try await Task.detached { try TopologyReference.read() }.value
        let access = try DeviceAccess().withPollInterval(.milliseconds(20))
        defer { access.close() }
        let began = Date()
        let read = try await access.get(Entities.cpu)
        var iterator = access.watch(Entities.cpu).makeAsyncIterator()
        let firstValue = try await iterator.next(), secondValue = try await iterator.next()
        let first = try XCTUnwrap(firstValue), second = try XCTUnwrap(secondValue)
        for snapshot in [read, first, second] {
            XCTAssertEqual(snapshot.physicalCoreCount, reference.physical)
            XCTAssertEqual(snapshot.processorPackageCount, reference.packages)
            XCTAssertGreaterThan(try XCTUnwrap(snapshot.logicalProcessorCount), 0)
            XCTAssertGreaterThan(try XCTUnwrap(snapshot.availableLogicalProcessorCount), 0)
        }
        XCTAssertGreaterThanOrEqual(read.collectedAt, began)
        XCTAssertGreaterThan(first.collectedAt, read.collectedAt)
        XCTAssertGreaterThan(second.collectedAt, first.collectedAt)
        print("APPLE_CPU_TOPOLOGY_REFERENCE physical=\(reference.physical) packages=\(reference.packages)")
    }
    #endif
}

#if os(macOS)
private struct TopologyReference: Sendable {
    let physical: Int, packages: Int

    static func read() throws -> Self {
        Self(physical: try number("hw.physicalcpu_max"), packages: try number("hw.packages"))
    }

    private static func number(_ name: String) throws -> Int {
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/sysctl")
        process.arguments = ["-n", name]
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let text = String(data: data, encoding: .utf8),
              let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)), value > 0 else {
            throw TopologyReferenceFailure.unavailable
        }
        return value
    }
}
#endif

private func machPhysicalCoreReference() throws -> Int {
    let host = mach_host_self()
    guard host != MACH_PORT_NULL else { throw TopologyReferenceFailure.unavailable }
    defer { _ = mach_port_deallocate(mach_task_self_, host) }
    var value = host_basic_info_data_t()
    let capacity = MemoryLayout<host_basic_info_data_t>.size / MemoryLayout<integer_t>.size
    var count = mach_msg_type_number_t(capacity)
    let status = withUnsafeMutablePointer(to: &value) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: capacity) { buffer in
            host_info(host, HOST_BASIC_INFO, buffer, &count)
        }
    }
    guard status == KERN_SUCCESS, count == mach_msg_type_number_t(capacity), value.physical_cpu_max > 0 else {
        throw TopologyReferenceFailure.unavailable
    }
    return Int(value.physical_cpu_max)
}

private enum TopologyReferenceFailure: Error { case unavailable }
#endif
