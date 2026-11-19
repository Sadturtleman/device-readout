#if os(macOS)
import DeviceReadout
import Foundation

enum OsConsumer {
    @MainActor
    static func run() async throws {
        let environment = ProcessInfo.processInfo.environment
        let mode = environment["DEVICE_READOUT_OS_MODE"] ?? "normal"
        let access = try DeviceAccess().withPollInterval(.milliseconds(20)).withReadTimeout(.milliseconds(500))
        defer { access.close() }
        let supported = try await access.capabilities.get(Entities.os)
        guard supported.readable == true, supported.watchable == true else { throw Failure.unsupported }
        if mode == "held" {
            try await heldRead(access, environment: environment)
            return
        }
        let reference = try await Task.detached { try Reference.read() }.value
        let start = Date()
        let value = try await access.get(Entities.os)
        var iterator = access.watch(Entities.os).makeAsyncIterator()
        guard let first = try await iterator.next(), let second = try await iterator.next() else { throw Failure.ended }
        for snapshot in [value, first, second] {
            guard snapshot.family == .macOS, snapshot.name == reference.name,
                  snapshot.version == reference.version else { throw Failure.incorrectIdentity }
            if mode == "unavailable" {
                guard snapshot.build == nil, snapshot.kernelName == nil, snapshot.kernelVersion == nil else {
                    throw Failure.failedFieldsNotNull
                }
            } else {
                guard snapshot.build == reference.build, snapshot.kernelName == reference.kernelName,
                      snapshot.kernelVersion == reference.kernelVersion else { throw Failure.incorrectNativeFields }
            }
        }
        guard value.collectedAt >= start, first.collectedAt > value.collectedAt,
              second.collectedAt > first.collectedAt, second.collectedAt <= Date() else { throw Failure.timestamp }
        if mode == "unavailable" {
            let trace = try trace(environment)
            guard trace.components(separatedBy: "sysctl-unavailable main=0").count >= 4,
                  trace.components(separatedBy: "uname-unavailable main=0").count >= 4 else { throw Failure.fixture }
            guard !trace.contains("unavailable main=1") else { throw Failure.mainThread }
            print("SWIFT_OS_UNAVAILABLE_CONSUMER {\"passed\":true,\"failedFieldsNull\":true,\"identityPreserved\":true,\"freshSnapshots\":true,\"watchSnapshots\":2}")
        } else {
            print("SWIFT_OS_NATIVE_CONSUMER {\"passed\":true,\"independentReference\":true,\"fields\":6,\"freshSnapshots\":true,\"watchSnapshots\":2}")
        }
    }

    @MainActor
    private static func heldRead(_ access: DeviceAccess, environment: [String: String]) async throws {
        guard let gate = environment["DEVICE_READOUT_OS_GATE"] else { throw Failure.fixture }
        let read = Task { try await access.get(Entities.os) }
        defer {
            read.cancel()
            _ = FileManager.default.createFile(atPath: gate, contents: Data())
        }
        try await waitFor("sysctl-held main=0", environment: environment)
        let pulse = await Task { @MainActor in 47 }.value
        guard pulse == 47 else { throw Failure.mainThread }
        do { _ = try await read.value; throw Failure.missingTimeout }
        catch let error as DeviceReadoutError where error.code == .readTimeout { }
        guard !(try trace(environment)).contains("sysctl-released") else { throw Failure.joinedNativeRead }
        let other = try DeviceAccess().withReadTimeout(.seconds(1))
        defer { other.close() }
        let runtime = try await other.get(Entities.runtime)
        guard runtime.processArchitecture != nil else { throw Failure.otherContext }
        let began = ContinuousClock.now
        access.close()
        guard began.duration(to: .now) < .seconds(1),
              !(try trace(environment)).contains("sysctl-released") else { throw Failure.joinedNativeRead }
        do { _ = try await access.get(Entities.os); throw Failure.closedContext }
        catch let error as DeviceReadoutError where error.code == .entityRemoved { }
        guard FileManager.default.createFile(atPath: gate, contents: Data()) else { throw Failure.fixture }
        try await waitFor("sysctl-released main=0", environment: environment)
        guard !(try trace(environment)).contains("sysctl-held main=1") else { throw Failure.mainThread }
        print("SWIFT_OS_HELD_CONSUMER {\"passed\":true,\"readTimeoutBeforeRelease\":true,\"closeBeforeRelease\":true,\"otherContextProgress\":true,\"callerProgress\":true}")
    }

    private static func trace(_ environment: [String: String]) throws -> String {
        guard let path = environment["DEVICE_READOUT_OS_TRACE"] else { throw Failure.fixture }
        return try String(contentsOfFile: path, encoding: .utf8)
    }

    private static func waitFor(_ event: String, environment: [String: String]) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !(try trace(environment)).contains(event) {
            guard ContinuousClock.now < deadline else { throw Failure.fixture }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private struct Reference: Sendable {
        let name: String, version: String, build: String, kernelName: String, kernelVersion: String
        static func read() throws -> Self {
            var version = try command("/usr/bin/sw_vers", "-productVersion")
            if version.split(separator: ".").count == 2 { version += ".0" }
            return Self(name: try command("/usr/bin/sw_vers", "-productName"), version: version,
                        build: try command("/usr/bin/sw_vers", "-buildVersion"),
                        kernelName: try command("/usr/bin/uname", "-s"),
                        kernelVersion: try command("/usr/bin/uname", "-r"))
        }
        private static func command(_ executable: String, _ argument: String) throws -> String {
            let process = Process(), output = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = [argument]
            process.standardOutput = output
            // Reference subprocesses must not inherit the consumer-only fault injection.
            process.environment = ProcessInfo.processInfo.environment.filter { $0.key != "DYLD_INSERT_LIBRARIES" }
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { throw Failure.reference }
            return text
        }
    }

    private enum Failure: Error {
        case unsupported, ended, incorrectIdentity, failedFieldsNotNull, incorrectNativeFields, timestamp
        case fixture, mainThread, missingTimeout, joinedNativeRead, otherContext, closedContext, reference
    }
}
#endif
