#if os(macOS) || os(iOS)
import Darwin
import DeviceReadout
import Foundation
import XCTest

final class AppleCpuTests: XCTestCase {
    @MainActor
    func testNativeProcessorCountsMatchIndependentDarwinReportAndPollFreshSnapshots() async throws {
        // Foundation's documented reference values are hw.ncpu and hw.logicalcpu.
        // These direct Darwin reads are independent of the product's Foundation getters.
        let reference = try await Task.detached {
            (try processorReference("hw.ncpu"), try processorReference("hw.logicalcpu"))
        }.value
        let access = try DeviceAccess().withPollInterval(.milliseconds(20))
        defer { access.close() }
        let began = Date()
        let value: CpuSnapshot = try await access.get(Entities.cpu)
        XCTAssertEqual(value.logicalProcessorCount, reference.0)
        XCTAssertEqual(value.availableLogicalProcessorCount, reference.1)
        XCTAssertGreaterThanOrEqual(value.collectedAt, began)
        XCTAssertLessThanOrEqual(value.collectedAt, Date())
        let support = try await access.capabilities.get(Entities.cpu)
        XCTAssertEqual(support.readable, true)
        XCTAssertEqual(support.watchable, true)
        var iterator = access.watch(Entities.cpu).makeAsyncIterator()
        let firstValue = try await iterator.next(), secondValue = try await iterator.next()
        let first = try XCTUnwrap(firstValue), second = try XCTUnwrap(secondValue)
        for snapshot in [first, second] {
            XCTAssertEqual(snapshot.logicalProcessorCount, reference.0)
            XCTAssertGreaterThan(try XCTUnwrap(snapshot.availableLogicalProcessorCount), 0)
            XCTAssertLessThanOrEqual(try XCTUnwrap(snapshot.availableLogicalProcessorCount), reference.0)
        }
        XCTAssertGreaterThan(first.collectedAt, value.collectedAt)
        XCTAssertGreaterThan(second.collectedAt, first.collectedAt)
        print("APPLE_CPU_REFERENCE logical=\(reference.0) available=\(reference.1)")
    }
}

private func processorReference(_ name: String) throws -> Int {
    var value: Int32 = 0
    var size = MemoryLayout<Int32>.size
    let status = withUnsafeMutablePointer(to: &value) { pointer in
        sysctlbyname(name, pointer, &size, nil, 0)
    }
    guard status == 0, size == MemoryLayout<Int32>.size, value > 0 else {
        throw ProcessorReferenceFailure.unavailable
    }
    return Int(value)
}

private enum ProcessorReferenceFailure: Error { case unavailable }
#endif
