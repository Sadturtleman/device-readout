#if os(macOS)
import DeviceReadout
import Foundation

enum CpuTopologyConsumer {
    @MainActor
    static func run() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let scenario = environment["DEVICE_READOUT_CPU_CASE"] else { throw Failure.fixture }
        let access = try DeviceAccess().withPollInterval(.milliseconds(20)).withReadTimeout(.milliseconds(500))
        defer { access.close() }
        if scenario == "held-get" || scenario == "held-watch" {
            try await heldRead(access, scenario: scenario, environment: environment)
            return
        }
        let expected: (Int?, Int?)
        switch scenario {
        case "known": expected = (2, 1)
        case "physical-failure": expected = (nil, 1)
        case "package-failure": expected = (2, nil)
        case "zero", "negative", "short-response", "oversized-response": expected = (nil, nil)
        default: throw Failure.fixture
        }
        let reference = await Task.detached {
            (ProcessInfo.processInfo.processorCount, ProcessInfo.processInfo.activeProcessorCount)
        }.value
        let began = Date()
        let read = try await access.get(Entities.cpu)
        var iterator = access.watch(Entities.cpu).makeAsyncIterator()
        guard let first = try await iterator.next(), let second = try await iterator.next() else { throw Failure.ended }
        for snapshot in [read, first, second] {
            guard snapshot.physicalCoreCount == expected.0, snapshot.processorPackageCount == expected.1 else {
                throw Failure.topology
            }
            guard snapshot.logicalProcessorCount == reference.0,
                  snapshot.availableLogicalProcessorCount == reference.1 else { throw Failure.logicalCountsLost }
        }
        guard read.collectedAt >= began, first.collectedAt > read.collectedAt,
              second.collectedAt > first.collectedAt, second.collectedAt <= Date() else { throw Failure.timestamp }
        let trace = try trace(environment)
        for event in ["physical-read", "package-read"] {
            guard trace.components(separatedBy: event + " main=0").count >= 4 else { throw Failure.fixture }
        }
        guard !trace.contains("main=1") else { throw Failure.mainThread }
        try report(["passed": true, "case": scenario, "valuesCorrect": true, "logicalCountsPreserved": true,
                    "freshSnapshots": true, "watchSnapshots": 2, "nativeOffMain": true])
    }

    @MainActor
    private static func heldRead(_ access: DeviceAccess, scenario: String, environment: [String: String]) async throws {
        guard let gate = environment["DEVICE_READOUT_CPU_GATE"] else { throw Failure.fixture }
        let read = Task<CpuSnapshot?, Error> {
            if scenario == "held-watch" {
                var iterator = access.watch(Entities.cpu).makeAsyncIterator()
                return try await iterator.next()
            }
            return try await access.get(Entities.cpu)
        }
        defer {
            read.cancel()
            _ = FileManager.default.createFile(atPath: gate, contents: Data())
        }
        try await waitFor("cpu-held main=0", environment: environment)
        let pulse = await Task { @MainActor in 47 }.value
        guard pulse == 47 else { throw Failure.mainThread }
        do { _ = try await read.value; throw Failure.missingTimeout }
        catch let error as DeviceReadoutError where error.code == .readTimeout { }
        guard !(try trace(environment)).contains("cpu-released") else { throw Failure.joinedNativeRead }
        let other = try DeviceAccess().withReadTimeout(.seconds(1))
        defer { other.close() }
        guard try await other.get(Entities.runtime).processArchitecture != nil else { throw Failure.otherContext }
        let began = ContinuousClock.now
        access.close()
        guard began.duration(to: .now) < .seconds(1),
              !(try trace(environment)).contains("cpu-released") else { throw Failure.joinedNativeRead }
        do { _ = try await access.get(Entities.cpu); throw Failure.closedContext }
        catch let error as DeviceReadoutError where error.code == .entityRemoved { }
        guard FileManager.default.createFile(atPath: gate, contents: Data()) else { throw Failure.fixture }
        try await waitFor("cpu-released main=0", environment: environment)
        guard !(try trace(environment)).contains("main=1") else { throw Failure.mainThread }
        try report(["passed": true, "case": scenario, "readTimeoutBeforeRelease": true,
                    "closeBeforeRelease": true, "otherContextProgress": true, "callerProgress": true,
                    "nativeOffMain": true])
    }

    private static func trace(_ environment: [String: String]) throws -> String {
        guard let path = environment["DEVICE_READOUT_CPU_TRACE"] else { throw Failure.fixture }
        return try String(contentsOfFile: path, encoding: .utf8)
    }

    private static func waitFor(_ event: String, environment: [String: String]) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !(try trace(environment)).contains(event) {
            guard ContinuousClock.now < deadline else { throw Failure.fixture }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private static func report(_ value: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        print("SWIFT_CPU_TOPOLOGY_CONSUMER " + String(decoding: data, as: UTF8.self))
    }

    private enum Failure: Error {
        case fixture, ended, topology, logicalCountsLost, timestamp, mainThread, missingTimeout
        case joinedNativeRead, otherContext, closedContext
    }
}
#endif
