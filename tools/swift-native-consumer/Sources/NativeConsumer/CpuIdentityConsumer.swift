#if os(macOS)
import Darwin
import DeviceReadout
import Foundation

enum CpuIdentityConsumer {
    @MainActor
    static func run() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let scenario = environment["DEVICE_READOUT_IDENTITY_CASE"] else { throw Failure.fixture }
        let access = try DeviceAccess().withPollInterval(.milliseconds(20)).withReadTimeout(.milliseconds(500))
        defer { access.close() }
        if scenario == "held-get" || scenario == "held-watch" {
            try await heldRead(access, scenario: scenario, environment: environment)
            return
        }
        let expected: (String?, String?)
        switch scenario {
        case "known": expected = ("Fixture CPU", "Fixture Vendor")
        case "unicode": expected = ("CPU-Δ-가", "Vendor-회사")
        case "shrink": expected = ("CPU", "Vendor")
        case "limit": expected = (String(repeating: "M", count: 4095), String(repeating: "V", count: 4095))
        case "model-failure": expected = (nil, "Fixture Vendor")
        case "vendor-failure": expected = ("Fixture CPU", nil)
        case "read-failure", "size-zero", "size-one", "size-too-large", "size-overflow", "empty",
             "missing-nul", "short-write", "invalid-utf8", "reported-growth": expected = (nil, nil)
        default: throw Failure.fixture
        }
        let counts = try await Task.detached { try Counts.read() }.value
        let began = Date()
        let read = try await access.get(Entities.cpu)
        var iterator = access.watch(Entities.cpu).makeAsyncIterator()
        guard let first = try await iterator.next(), let second = try await iterator.next() else { throw Failure.ended }
        for snapshot in [read, first, second] {
            guard snapshot.model == expected.0, snapshot.manufacturer == expected.1 else { throw Failure.identity }
            guard snapshot.logicalProcessorCount == counts.logical,
                  snapshot.availableLogicalProcessorCount == counts.available,
                  snapshot.physicalCoreCount == counts.physical,
                  snapshot.processorPackageCount == counts.packages else { throw Failure.countsLost }
        }
        guard read.collectedAt >= began, first.collectedAt > read.collectedAt,
              second.collectedAt > first.collectedAt, second.collectedAt <= Date() else { throw Failure.timestamp }
        let trace = try trace(environment)
        for field in ["model", "vendor"] {
            guard trace.components(separatedBy: field + "-size main=0").count >= 4 else { throw Failure.fixture }
            let noRead = ["size-zero", "size-one", "size-too-large", "size-overflow"].contains(scenario)
                || scenario == field + "-failure"
            if noRead {
                guard !trace.contains(field + "-read") else { throw Failure.unboundedRead }
            } else {
                guard trace.components(separatedBy: field + "-read main=0").count >= 4 else { throw Failure.fixture }
            }
        }
        guard !trace.contains("main=1") else { throw Failure.mainThread }
        try report(["passed": true, "case": scenario, "valuesCorrect": true, "countsPreserved": true,
                    "freshSnapshots": true, "watchSnapshots": 2, "boundedRead": true, "nativeOffMain": true])
    }

    @MainActor
    private static func heldRead(_ access: DeviceAccess, scenario: String, environment: [String: String]) async throws {
        guard let gate = environment["DEVICE_READOUT_IDENTITY_GATE"] else { throw Failure.fixture }
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
        try await waitFor("identity-held main=0", environment: environment)
        let pulse = await Task { @MainActor in 47 }.value
        guard pulse == 47 else { throw Failure.mainThread }
        do { _ = try await read.value; throw Failure.missingTimeout }
        catch let error as DeviceReadoutError where error.code == .readTimeout { }
        guard !(try trace(environment)).contains("identity-released") else { throw Failure.joinedNativeRead }
        let other = try DeviceAccess().withReadTimeout(.seconds(1))
        defer { other.close() }
        guard try await other.get(Entities.runtime).processArchitecture != nil else { throw Failure.otherContext }
        let began = ContinuousClock.now
        access.close()
        guard began.duration(to: .now) < .seconds(1),
              !(try trace(environment)).contains("identity-released") else { throw Failure.joinedNativeRead }
        do { _ = try await access.get(Entities.cpu); throw Failure.closedContext }
        catch let error as DeviceReadoutError where error.code == .entityRemoved { }
        guard FileManager.default.createFile(atPath: gate, contents: Data()) else { throw Failure.fixture }
        try await waitFor("identity-released main=0", environment: environment)
        guard !(try trace(environment)).contains("main=1") else { throw Failure.mainThread }
        try report(["passed": true, "case": scenario, "readTimeoutBeforeRelease": true,
                    "closeBeforeRelease": true, "otherContextProgress": true, "callerProgress": true,
                    "nativeOffMain": true])
    }

    private static func trace(_ environment: [String: String]) throws -> String {
        guard let path = environment["DEVICE_READOUT_IDENTITY_TRACE"] else { throw Failure.fixture }
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
        print("SWIFT_CPU_IDENTITY_CONSUMER " + String(decoding: data, as: UTF8.self))
    }
    private struct Counts: Sendable {
        let logical: Int, available: Int, physical: Int, packages: Int
        static func read() throws -> Self {
            Self(logical: ProcessInfo.processInfo.processorCount,
                 available: ProcessInfo.processInfo.activeProcessorCount,
                 physical: try number("hw.physicalcpu_max"), packages: try number("hw.packages"))
        }
        private static func number(_ name: String) throws -> Int {
            var value: Int32 = 0
            var count = MemoryLayout<Int32>.size
            let status = withUnsafeMutablePointer(to: &value) { sysctlbyname(name, $0, &count, nil, 0) }
            guard status == 0, count == MemoryLayout<Int32>.size, value > 0 else { throw Failure.reference }
            return Int(value)
        }
    }
    private enum Failure: Error {
        case fixture, ended, identity, countsLost, timestamp, unboundedRead, mainThread, missingTimeout
        case joinedNativeRead, otherContext, closedContext, reference
    }
}
#endif
