#if os(macOS)
import DeviceReadout
import Foundation
import XCTest

final class AppleCpuIdentityTests: XCTestCase {
    @MainActor
    func testNativeIdentityMatchesIndependentSystemReportAndPreservesCounts() async throws {
        let reference = try await Task.detached { try CpuIdentityReference.read() }.value
        XCTAssertFalse(reference.model.isEmpty)
        let access = try DeviceAccess().withPollInterval(.milliseconds(20))
        defer { access.close() }
        let read = try await access.get(Entities.cpu)
        var iterator = access.watch(Entities.cpu).makeAsyncIterator()
        guard let first = try await iterator.next(), let second = try await iterator.next() else {
            XCTFail("CPU watch ended before two snapshots"); return
        }
        for snapshot in [read, first, second] {
            XCTAssertEqual(snapshot.model, reference.model)
            XCTAssertEqual(snapshot.manufacturer, reference.vendor)
            XCTAssertGreaterThan(try XCTUnwrap(snapshot.logicalProcessorCount), 0)
            XCTAssertGreaterThan(try XCTUnwrap(snapshot.physicalCoreCount), 0)
        }
        XCTAssertGreaterThan(first.collectedAt, read.collectedAt)
        XCTAssertGreaterThan(second.collectedAt, first.collectedAt)
        print("APPLE_CPU_IDENTITY_REFERENCE model=\(reference.model) vendor=\(reference.vendor ?? "null")")
    }
}

private struct CpuIdentityReference: Sendable {
    let model: String, vendor: String?
    static func read() throws -> Self {
        guard let model = try string("machdep.cpu.brand_string") else { throw CpuIdentityReferenceFailure.unavailable }
        return Self(model: model, vendor: try string("machdep.cpu.vendor"))
    }
    private static func string(_ name: String) throws -> String? {
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/sysctl")
        process.arguments = ["-n", "-i", name]
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, var text = String(data: data, encoding: .utf8) else {
            throw CpuIdentityReferenceFailure.unavailable
        }
        if text.hasSuffix("\n") { text.removeLast() }
        return text.isEmpty ? nil : text
    }
}

private enum CpuIdentityReferenceFailure: Error { case unavailable }
#endif
