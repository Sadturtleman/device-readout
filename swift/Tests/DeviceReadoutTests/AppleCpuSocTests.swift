#if os(macOS)
import DeviceReadout
import Foundation
import XCTest

final class AppleCpuSocTests: XCTestCase {
    @MainActor
    func testNativeSocModelMatchesIndependentDeviceTreeReport() async throws {
        let reference = try await Task.detached { try SocReference.read() }.value
        let access = try DeviceAccess().withPollInterval(.milliseconds(20))
        defer { access.close() }
        let read = try await access.get(Entities.cpu)
        var iterator = access.watch(Entities.cpu).makeAsyncIterator()
        let firstValue = try await iterator.next(), secondValue = try await iterator.next()
        let first = try XCTUnwrap(firstValue), second = try XCTUnwrap(secondValue)
        for snapshot in [read, first, second] {
            XCTAssertEqual(snapshot.socModel, reference)
            XCTAssertNil(snapshot.socManufacturer)
            XCTAssertGreaterThan(try XCTUnwrap(snapshot.logicalProcessorCount), 0)
        }
        XCTAssertGreaterThan(first.collectedAt, read.collectedAt)
        XCTAssertGreaterThan(second.collectedAt, first.collectedAt)
        print("APPLE_CPU_SOC_REFERENCE model=\(reference ?? "null")")
    }
}

private enum SocReference {
    static func read() throws -> String? {
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
        process.arguments = ["-a", "-p", "IODeviceTree", "-r", "-n", "product", "-d", "1"]
        process.standardOutput = output
        try process.run()
        let bytes = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure.command }
        let plist = try PropertyListSerialization.propertyList(from: bytes, options: [], format: nil)
        guard let entries = plist as? [[String: Any]] else { throw Failure.format }
        guard let product = entries.first(where: { ($0["IORegistryEntryName"] as? String) == "product" }),
              let value = product["product-soc-name"] else { return nil }
        guard let data = value as? Data, let end = data.firstIndex(of: 0), end > data.startIndex,
              let result = String(data: data[..<end], encoding: .utf8) else { throw Failure.format }
        return result
    }
    private enum Failure: Error { case command, format }
}
#endif
