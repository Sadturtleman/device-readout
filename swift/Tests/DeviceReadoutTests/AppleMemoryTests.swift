#if os(macOS) || os(iOS)
import Darwin
import DeviceReadout
import Foundation
import XCTest

final class AppleMemoryTests: XCTestCase {
    @MainActor
    func testNativePhysicalMemoryMatchesSystemHardwareReportAndPollsFreshSnapshots() async throws {
        // An independent Darwin hardware query checks the Foundation-backed product value.
        let reference = try await Task.detached { try physicalMemoryReference() }.value
        let access = try DeviceAccess().withPollInterval(.milliseconds(20))
        defer { access.close() }
        let began = Date()
        let value: RamSnapshot = try await access.get(Entities.ram)
        XCTAssertGreaterThan(reference, 0)
        XCTAssertEqual(value.physicalBytes, reference)
        XCTAssertGreaterThanOrEqual(value.collectedAt, began)
        XCTAssertLessThanOrEqual(value.collectedAt, Date())
        let supported = try await access.capabilities.get(Entities.ram)
        XCTAssertEqual(supported.readable, true)
        XCTAssertEqual(supported.watchable, true)
        var iterator = access.watch(Entities.ram).makeAsyncIterator()
        let firstValue = try await iterator.next()
        let secondValue = try await iterator.next()
        let first = try XCTUnwrap(firstValue), second = try XCTUnwrap(secondValue)
        XCTAssertEqual(first.physicalBytes, reference)
        XCTAssertEqual(second.physicalBytes, reference)
        XCTAssertGreaterThan(first.collectedAt, value.collectedAt)
        XCTAssertGreaterThan(second.collectedAt, first.collectedAt)
        print("APPLE_PHYSICAL_MEMORY_REFERENCE \(reference)")
    }
}

private func physicalMemoryReference() throws -> UInt64 {
    var memory: UInt64 = 0
    var size = MemoryLayout<UInt64>.size
    let status = withUnsafeMutablePointer(to: &memory) { buffer in
        sysctlbyname("hw.memsize", buffer, &size, nil, 0)
    }
    guard status == 0, size == MemoryLayout<UInt64>.size else { throw MemoryReferenceFailure.unavailable }
    return memory
}

private enum MemoryReferenceFailure: Error { case unavailable }
#endif
