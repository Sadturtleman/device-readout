#if os(macOS)
import DeviceReadout
import Foundation
import XCTest

final class AppleOsTests: XCTestCase {
    @MainActor
    func testNativeMacOsMatchesIndependentSystemReportAndPollsFreshSnapshots() async throws {
        // Commands are an independent test reference; product collection must not launch them.
        let reference = try await Task.detached { try MacOsReference.read() }.value
        let access = try DeviceAccess().withPollInterval(.milliseconds(20))
        defer { access.close() }
        let before = Date()
        let value: OsSnapshot = try await access.get(Entities.os)
        XCTAssertEqual(value.family, .macOS)
        XCTAssertEqual(value.name, reference.name)
        XCTAssertEqual(value.version, reference.version)
        XCTAssertEqual(value.build, reference.build)
        XCTAssertEqual(value.kernelName, reference.kernelName)
        XCTAssertEqual(value.kernelVersion, reference.kernelVersion)
        XCTAssertGreaterThanOrEqual(value.collectedAt, before)
        XCTAssertLessThanOrEqual(value.collectedAt, Date())
        let support = try await access.capabilities.get(Entities.os)
        XCTAssertEqual(support.readable, true)
        XCTAssertEqual(support.watchable, true)
        var iterator = access.watch(Entities.os).makeAsyncIterator()
        let firstValue = try await iterator.next()
        let secondValue = try await iterator.next()
        let first = try XCTUnwrap(firstValue)
        let second = try XCTUnwrap(secondValue)
        XCTAssertEqual(first.version, value.version)
        XCTAssertEqual(second.version, value.version)
        XCTAssertEqual(second.build, value.build)
        XCTAssertEqual(second.kernelVersion, value.kernelVersion)
        XCTAssertGreaterThan(first.collectedAt, value.collectedAt)
        XCTAssertGreaterThan(second.collectedAt, first.collectedAt)
        let pulse = await Task { @MainActor in 41 }.value
        XCTAssertEqual(pulse, 41)
        print("APPLE_OS_REFERENCE \(reference.name) \(reference.version) \(reference.build) \(reference.kernelName) \(reference.kernelVersion)")
    }
}

private struct MacOsReference: Sendable {
    let name: String
    let version: String
    let build: String
    let kernelName: String
    let kernelVersion: String

    static func read() throws -> Self {
        let rawVersion = try command("/usr/bin/sw_vers", "-productVersion")
        var components = rawVersion.split(separator: ".").compactMap { Int($0) }
        guard (2...3).contains(components.count), components.count == rawVersion.split(separator: ".").count else {
            throw ReferenceFailure.unrecognizedVersion
        }
        if components.count == 2 { components.append(0) }
        return Self(name: try command("/usr/bin/sw_vers", "-productName"),
                    version: components.map(String.init).joined(separator: "."),
                    build: try command("/usr/bin/sw_vers", "-buildVersion"),
                    kernelName: try command("/usr/bin/uname", "-s"),
                    kernelVersion: try command("/usr/bin/uname", "-r"))
    }

    private static func command(_ executable: String, _ argument: String) throws -> String {
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = [argument]
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { throw ReferenceFailure.failedCommand }
        return text
    }

    private enum ReferenceFailure: Error { case unrecognizedVersion, failedCommand }
}
#endif
