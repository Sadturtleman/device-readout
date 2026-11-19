import DeviceReadout
import Foundation
import XCTest
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

final class NativeCollectorTests: XCTestCase {
    @MainActor
    func testNativeTimeZoneReceivesFoundationNotificationsBeforeItsPoll() async throws {
        let access = try DeviceAccess().withPollInterval(.seconds(3600))
        defer { access.close() }
        let initial = expectation(description: "initial time-zone read")
        let consumer = Task { () throws -> [TimeZoneSnapshot] in
            var values: [TimeZoneSnapshot] = []
            for try await value in access.watch(Entities.timeZone) {
                values.append(value)
                if values.count == 1 { initial.fulfill() }
                if values.count == 2 { break }
            }
            return values
        }
        defer { consumer.cancel() }
        await fulfillment(of: [initial], timeout: 1)
        let failSafe = Task.detached {
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled { consumer.cancel() }
        }
        defer { failSafe.cancel() }
        NotificationCenter.default.post(name: .NSSystemTimeZoneDidChange, object: nil)
        let values = try await consumer.value
        XCTAssertEqual(values.count, 2, "Foundation notifications wake the native watch without waiting for its poll.")
        XCTAssertEqual(values[1].ianaId, values[0].ianaId)
        XCTAssertGreaterThan(values[1].collectedAt, values[0].collectedAt)
    }

    func testNativeTimeZoneMatchesCLibraryAndPollsEqualSnapshots() async throws {
        let access = DeviceAccess()
        defer { access.close() }
        let value = try await access.get(Entities.timeZone)
        tzset()
        var clock = time(nil), reference = tm()
        XCTAssertNotNil(localtime_r(&clock, &reference))
        XCTAssertEqual(value.utcOffsetSeconds, Int(reference.tm_gmtoff))
        XCTAssertEqual(value.daylightSavingTime, reference.tm_isdst > 0)
        XCTAssertNotNil(value.ianaId)
        XCTAssertNil(value.windowsId)
        if let zone = ProcessInfo.processInfo.environment["TZ"], ["Etc/UTC", "Asia/Kathmandu"].contains(zone) {
            XCTAssertEqual(value.ianaId, zone)
        }
        let supported = try await access.capabilities.get(Entities.timeZone)
        XCTAssertEqual(supported.readable, true)
        XCTAssertEqual(supported.watchable, true)
        let unsupported = try await access.capabilities.get(Entities.battery)
        XCTAssertEqual(unsupported.readable, false)
        XCTAssertEqual(unsupported.watchable, false)
        let polling = try access.withPollInterval(.milliseconds(20))
        var iterator = polling.watch(Entities.timeZone).makeAsyncIterator()
        let first = try await iterator.next(), second = try await iterator.next()
        XCTAssertEqual(first?.ianaId, value.ianaId)
        XCTAssertEqual(second?.utcOffsetSeconds, value.utcOffsetSeconds)
        XCTAssertGreaterThan(try XCTUnwrap(second?.collectedAt), try XCTUnwrap(first?.collectedAt))
    }

    func testDefaultNativeRuntimeDescribesTheRunningExecutable() async throws {
        let access = DeviceAccess()
        defer { access.close() }
        let before = Date()
        let value = try await access.get(Entities.runtime)
        #if os(Linux)
        let executable = try Data(contentsOf: URL(fileURLWithPath: "/proc/self/exe"))
        XCTAssertEqual(Array(executable.prefix(4)), [0x7f, 0x45, 0x4c, 0x46])
        XCTAssertEqual(executable[5], 1, "This reference decodes little-endian ELF headers.")
        let machine = Int(executable[18]) | (Int(executable[19]) << 8)
        let reference: [Int: Architecture] = [3: .x86, 62: .x64, 40: .arm32, 183: .arm64]
        XCTAssertEqual(value.processArchitecture, reference[machine])
        XCTAssertEqual(value.processBitness, executable[4] == 2 ? 64 : 32)
        #else
        XCTAssertEqual(value.processBitness, MemoryLayout<UnsafeRawPointer>.size * 8)
        #endif
        XCTAssertNil(value.hostArchitecture, "Process architecture is not evidence of host architecture.")
        XCTAssertNil(value.supportedAbis)
        XCTAssertGreaterThanOrEqual(value.collectedAt, before)
        XCTAssertLessThanOrEqual(value.collectedAt, Date())
    }
}
