#if os(iOS) && !targetEnvironment(macCatalyst)
import Darwin
import DeviceReadout
import Foundation
import UIKit
import XCTest

final class AppleIosOsTests: XCTestCase {
    @MainActor
    func testNativeIosVersionAndKernelMatchAppAndDarwinReferences() async throws {
        // UIKit is an app-owned reference only; the SDK must not query UI state.
        let version = try normalizedVersion(UIDevice.current.systemVersion)
        let kernel = try await Task.detached { try kernelReference() }.value
        let access = try DeviceAccess().withPollInterval(.milliseconds(20))
        defer { access.close() }
        let began = Date()
        let read = try await access.get(Entities.os)
        let capabilities = try await access.capabilities.get(Entities.os)
        XCTAssertEqual(capabilities.readable, true)
        XCTAssertEqual(capabilities.watchable, true)
        var iterator = access.watch(Entities.os).makeAsyncIterator()
        let firstValue = try await iterator.next(), secondValue = try await iterator.next()
        let first = try XCTUnwrap(firstValue), second = try XCTUnwrap(secondValue)
        for value in [read, first, second] {
            XCTAssertEqual(value.version, version)
            XCTAssertEqual(value.kernelName, kernel.0)
            XCTAssertEqual(value.kernelVersion, kernel.1)
            #if targetEnvironment(simulator)
            // The host's kern.osversion is not the simulated iOS product build.
            XCTAssertNil(value.build)
            #endif
        }
        XCTAssertGreaterThanOrEqual(read.collectedAt, began)
        XCTAssertGreaterThan(first.collectedAt, read.collectedAt)
        XCTAssertGreaterThan(second.collectedAt, first.collectedAt)
        let pulse = await Task { @MainActor in 41 }.value
        XCTAssertEqual(pulse, 41)
        print("APPLE_IOS_OS_REFERENCE version=\(version) kernel=\(kernel.0) release=\(kernel.1)")
    }

    @MainActor
    func testAppObservedOsIdentityPreservesNativeVersionAndKernel() async throws {
        let name = UIDevice.current.systemName
        let family: OsFamily?
        switch name {
        case "iOS", "iPhone OS": family = .iOS
        case "iPadOS": family = .iPadOS
        default: family = nil
        }
        let access = try DeviceAccess().withPollInterval(.milliseconds(20))
        defer { access.close() }
        let native = try await access.get(Entities.os)
        XCTAssertNotNil(native.version)
        try access.observers.publish(Entities.os, snapshot: OsSnapshot(
            family: family, name: name, version: native.version, build: native.build,
            kernelName: native.kernelName, kernelVersion: native.kernelVersion))
        let read = try await access.get(Entities.os)
        var iterator = access.watch(Entities.os).makeAsyncIterator()
        let firstValue = try await iterator.next(), secondValue = try await iterator.next()
        let first = try XCTUnwrap(firstValue), second = try XCTUnwrap(secondValue)
        for value in [read, first, second] {
            XCTAssertEqual(value.family, family)
            XCTAssertEqual(value.name, name)
            XCTAssertEqual(value.version, native.version)
            XCTAssertEqual(value.build, native.build)
            XCTAssertEqual(value.kernelName, native.kernelName)
            XCTAssertEqual(value.kernelVersion, native.kernelVersion)
        }
        XCTAssertGreaterThan(first.collectedAt, read.collectedAt)
        XCTAssertGreaterThan(second.collectedAt, first.collectedAt)
        print("APPLE_IOS_OS_OBSERVER name=\(name) version=\(native.version ?? "null")")
    }
}

private func normalizedVersion(_ text: String) throws -> String {
    let parts = text.split(separator: ".", omittingEmptySubsequences: false)
    var values = parts.compactMap { Int($0) }
    guard (2...3).contains(parts.count), values.count == parts.count,
          values.allSatisfy({ $0 >= 0 }) else { throw IosOsReferenceFailure.version }
    if values.count == 2 { values.append(0) }
    return values.map(String.init).joined(separator: ".")
}

private func kernelReference() throws -> (String, String) {
    var kernel = utsname()
    guard uname(&kernel) == 0 else { throw IosOsReferenceFailure.kernel }
    let name = withUnsafeBytes(of: kernel.sysname) { bytes in String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self) }
    let version = withUnsafeBytes(of: kernel.release) { bytes in String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self) }
    guard !name.isEmpty, !version.isEmpty else { throw IosOsReferenceFailure.kernel }
    return (name, version)
}

private enum IosOsReferenceFailure: Error { case version, kernel }
#endif
