import DeviceReadout
import Foundation

@main
struct Consumer {
    static func main() async throws {
        #if os(macOS)
        if CommandLine.arguments.dropFirst().elementsEqual(["--os-consumer"]) {
            try await OsConsumer.run()
            return
        }
        if CommandLine.arguments.dropFirst().elementsEqual(["--power-read-failure-fixture"]) {
            try await PowerReadFailureFixture.run()
            return
        }
        if CommandLine.arguments.dropFirst().elementsEqual(["--power-cleanup-fixture"]) {
            try await PowerCleanupFixture.run()
            return
        }
        #endif
        let access = DeviceAccess()
        defer { access.close() }
        let runtime: RuntimeSnapshot = try await access.get(Entities.runtime)
        let zone: TimeZoneSnapshot = try await access.get(Entities.timeZone)
        let supported = try await access.capabilities.get(Entities.timeZone)
        guard runtime.processArchitecture != nil, runtime.processBitness != nil,
              zone.ianaId != nil, zone.utcOffsetSeconds != nil, zone.daylightSavingTime != nil,
              supported.readable == true, supported.watchable == true else {
            throw ConsumerFailure.missingFields
        }
        let polling = try access.withPollInterval(.milliseconds(20)).withReadTimeout(.seconds(1))
        var iterator = polling.watch(Entities.timeZone).makeAsyncIterator()
        guard let first = try await iterator.next(), let second = try await iterator.next(),
              second.ianaId == first.ianaId, second.collectedAt > first.collectedAt,
              access.pollInterval == .seconds(1), access.readTimeout == .seconds(5) else {
            throw ConsumerFailure.watchContract
        }
        access.close()
        do { _ = try await polling.get(Entities.runtime); throw ConsumerFailure.closedContext }
        catch let error as DeviceReadoutError where error.code == .entityRemoved { }
        let report: [String: Any] = [
            "passed": true, "processArchitecture": runtime.processArchitecture!.rawValue,
            "processBitness": runtime.processBitness!, "ianaId": zone.ianaId!,
            "utcOffsetSeconds": zone.utcOffsetSeconds!, "daylightSavingTime": zone.daylightSavingTime!,
            "pollSnapshots": 2, "freshEqualSnapshots": true, "immutableSettings": true, "sharedClose": true,
        ]
        let bytes = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
        print("SWIFT_NATIVE_CONSUMER " + String(decoding: bytes, as: UTF8.self))
    }
}

private enum ConsumerFailure: Error { case missingFields, watchContract, closedContext }
