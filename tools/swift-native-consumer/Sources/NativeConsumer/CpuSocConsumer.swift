#if os(macOS)
import DeviceReadout
import Foundation

enum CpuSocConsumer {
    @MainActor
    static func run() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let scenario = environment["DEVICE_READOUT_SOC_CASE"] else { throw Failure.fixture }
        let access = try DeviceAccess().withPollInterval(.milliseconds(20)).withReadTimeout(.milliseconds(500))
        defer { access.close() }
        if scenario.hasPrefix("held-") {
            try await heldRead(access, scenario: scenario, environment: environment)
            return
        }
        let expected: String?
        switch scenario {
        case "known": expected = "Fixture SoC"
        case "unicode": expected = "SoC-Δ-가"
        case "limit": expected = String(repeating: "S", count: 4095)
        case "missing-entry", "missing-property", "wrong-type", "empty-data", "empty-string",
             "missing-nul", "invalid-utf8", "oversized": expected = nil
        default: throw Failure.fixture
        }
        let read = try await access.get(Entities.cpu)
        var iterator = access.watch(Entities.cpu).makeAsyncIterator()
        guard let first = try await iterator.next(), let second = try await iterator.next() else { throw Failure.ended }
        for value in [read, first, second] {
            guard value.socModel == expected, value.socManufacturer == nil else { throw Failure.value }
            guard value.model != nil, value.logicalProcessorCount == ProcessInfo.processInfo.processorCount,
                  (value.physicalCoreCount ?? 0) > 0, (value.processorPackageCount ?? 0) > 0 else { throw Failure.otherFields }
        }
        guard first.collectedAt > read.collectedAt, second.collectedAt > first.collectedAt else { throw Failure.timestamp }
        access.close()
        try await waitForBalancedEntries(environment)
        let trace = try trace(environment)
        guard count("entry-lookup", in: trace) >= 3, !trace.contains("main=1") else { throw Failure.fixture }
        if scenario == "missing-entry" {
            guard count("entry-acquired", in: trace) == 0, count("property-read", in: trace) == 0 else { throw Failure.cleanup }
        } else {
            guard count("entry-acquired", in: trace) >= 3, count("property-read", in: trace) >= 3 else { throw Failure.fixture }
        }
        try report(["passed": true, "case": scenario, "valueCorrect": true, "otherFieldsPreserved": true,
                    "freshSnapshots": true, "watchSnapshots": 2, "entriesReleased": true, "nativeOffMain": true])
    }

    @MainActor
    private static func heldRead(_ access: DeviceAccess, scenario: String, environment: [String: String]) async throws {
        guard let gate = environment["DEVICE_READOUT_SOC_GATE"] else { throw Failure.fixture }
        let read = Task<CpuSnapshot?, Error> {
            if scenario.hasSuffix("-watch") {
                var iterator = access.watch(Entities.cpu).makeAsyncIterator()
                return try await iterator.next()
            }
            return try await access.get(Entities.cpu)
        }
        defer {
            read.cancel()
            _ = FileManager.default.createFile(atPath: gate, contents: Data())
        }
        try await waitFor("soc-held main=0", environment: environment)
        let pulse = await Task { @MainActor in 47 }.value
        guard pulse == 47 else { throw Failure.mainThread }
        do { _ = try await read.value; throw Failure.missingTimeout }
        catch let error as DeviceReadoutError where error.code == .readTimeout { }
        guard !(try trace(environment)).contains("soc-resumed") else { throw Failure.joinedNativeRead }
        let other = try DeviceAccess().withReadTimeout(.seconds(1))
        defer { other.close() }
        guard try await other.get(Entities.runtime).processArchitecture != nil else { throw Failure.otherContext }
        let began = ContinuousClock.now
        access.close()
        guard began.duration(to: .now) < .seconds(1),
              !(try trace(environment)).contains("soc-resumed") else { throw Failure.joinedNativeRead }
        do { _ = try await access.get(Entities.cpu); throw Failure.closedContext }
        catch let error as DeviceReadoutError where error.code == .entityRemoved { }
        guard FileManager.default.createFile(atPath: gate, contents: Data()) else { throw Failure.fixture }
        try await waitFor("entry-released main=0", environment: environment)
        try await waitForBalancedEntries(environment)
        guard !(try trace(environment)).contains("main=1") else { throw Failure.mainThread }
        try report(["passed": true, "case": scenario, "readTimeoutBeforeRelease": true, "closeBeforeRelease": true,
                    "otherContextProgress": true, "callerProgress": true, "entriesReleased": true, "nativeOffMain": true])
    }

    private static func count(_ event: String, in trace: String) -> Int {
        trace.components(separatedBy: event + " main=0").count - 1
    }
    private static func trace(_ environment: [String: String]) throws -> String {
        guard let path = environment["DEVICE_READOUT_SOC_TRACE"] else { throw Failure.fixture }
        return try String(contentsOfFile: path, encoding: .utf8)
    }
    private static func waitFor(_ event: String, environment: [String: String]) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !(try trace(environment)).contains(event) {
            guard ContinuousClock.now < deadline else { throw Failure.fixture }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
    private static func waitForBalancedEntries(_ environment: [String: String]) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while true {
            let value = try trace(environment)
            if count("entry-acquired", in: value) == count("entry-released", in: value) { return }
            guard ContinuousClock.now < deadline else { throw Failure.cleanup }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
    private static func report(_ value: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        print("SWIFT_CPU_SOC_CONSUMER " + String(decoding: data, as: UTF8.self))
    }
    private enum Failure: Error {
        case fixture, ended, value, otherFields, timestamp, cleanup, mainThread, missingTimeout
        case joinedNativeRead, otherContext, closedContext
    }
}
#endif
