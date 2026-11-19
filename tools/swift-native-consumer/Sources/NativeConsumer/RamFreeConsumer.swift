#if os(macOS)
import DeviceReadout
import Foundation

enum RamFreeConsumer {
    @MainActor
    static func run() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let scenario = environment["DEVICE_READOUT_RAM_CASE"],
              let tracePath = environment["DEVICE_READOUT_RAM_TRACE"] else { throw Failure.missingFixture }
        let expected: UInt64?
        switch scenario {
        case "known": expected = 2_097_152 // 512 free pages, each 4 KiB; speculative pages are already counted.
        case "large-page": expected = 8_388_608 // 512 pages at 16 KiB; do not hard-code the page size.
        case "zero": expected = 0
        case "page-failure", "statistics-failure", "short-response", "invalid-page", "overflow": expected = nil
        default: throw Failure.missingFixture
        }
        let access = try DeviceAccess().withPollInterval(.milliseconds(20))
        defer { access.close() }
        let began = Date()
        let read = try await access.get(Entities.ram)
        var iterator = access.watch(Entities.ram).makeAsyncIterator()
        guard let first = try await iterator.next(), let second = try await iterator.next() else { throw Failure.ended }
        for snapshot in [read, first, second] {
            guard snapshot.freeBytes == expected else {
                print("RAM_FREE_MISMATCH case=\(scenario) expected=\(String(describing: expected)) actual=\(String(describing: snapshot.freeBytes))")
                throw Failure.freeValue
            }
            guard let physical = snapshot.physicalBytes, physical > 0 else { throw Failure.physicalValueLost }
            guard snapshot.availableBytes == nil, snapshot.lowMemoryThresholdBytes == nil else {
                throw Failure.unrelatedFieldsFabricated
            }
        }
        guard read.collectedAt >= began, first.collectedAt > read.collectedAt,
              second.collectedAt > first.collectedAt, second.collectedAt <= Date() else { throw Failure.timestamp }
        access.close()
        let trace = try String(contentsOfFile: tracePath, encoding: .utf8)
        guard trace.components(separatedBy: "page-size main=0").count >= 4 else { throw Failure.missingFixture }
        if scenario != "page-failure" && scenario != "invalid-page" {
            guard trace.components(separatedBy: "vm-statistics main=0").count >= 4 else { throw Failure.missingFixture }
        }
        guard !trace.contains("main=1") else { throw Failure.mainThread }
        let report: [String: Any] = ["passed": true, "case": scenario, "freeValueCorrect": true,
                                    "physicalPreserved": true, "freshSnapshots": true, "watchSnapshots": 2,
                                    "nativeOffMain": true]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
        print("SWIFT_RAM_FREE_CONSUMER " + String(decoding: data, as: UTF8.self))
    }

    private enum Failure: Error {
        case missingFixture, ended, freeValue, physicalValueLost, unrelatedFieldsFabricated, timestamp, mainThread
    }
}
#endif
