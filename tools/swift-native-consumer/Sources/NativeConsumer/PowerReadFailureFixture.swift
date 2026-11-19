#if os(macOS)
import DeviceReadout
import Foundation

enum PowerReadFailureFixture {
    @MainActor
    static func run() async throws {
        guard let tracePath = ProcessInfo.processInfo.environment["DEVICE_READOUT_POWER_READ_TRACE"] else {
            throw Failure.missingFixture
        }
        let access = try DeviceAccess().withPollInterval(.milliseconds(20))
        defer { access.close() }
        let supported = try await access.capabilities.get(Entities.power)
        guard supported.readable == true, supported.watchable == true else { throw Failure.missingPower }

        let began = Date()
        let read: PowerSnapshot = try await access.get(Entities.power)
        try verify(read)
        guard read.collectedAt >= began, read.collectedAt <= Date() else { throw Failure.invalidTimestamp }
        var iterator = access.watch(Entities.power).makeAsyncIterator()
        guard let first = try await iterator.next(), let second = try await iterator.next() else {
            throw Failure.streamEnded
        }
        try verify(first)
        try verify(second)
        guard first.collectedAt > read.collectedAt, second.collectedAt > first.collectedAt else {
            throw Failure.invalidTimestamp
        }
        let pulse = await Task { @MainActor in 31 }.value
        guard pulse == 31 else { throw Failure.blockedCaller }
        access.close()

        let trace = try String(contentsOfFile: tracePath, encoding: .utf8)
        FileHandle.standardOutput.write(Data(("SWIFT_POWER_READ_FAILURE_TRACE\n" + trace).utf8))
        let calls = trace.split(separator: "\n").filter { $0 == "source-info-unavailable main=0" }
        guard trace.contains("fixture-loaded"), calls.count >= 3 else { throw Failure.missingFixture }
        guard !trace.contains("source-info-unavailable main=1") else { throw Failure.nativeWorkOnMainThread }
        print("SWIFT_POWER_READ_FAILURE_CONSUMER {\"passed\":true,\"sourceNull\":true,\"otherFieldsPreserved\":true,\"watchSnapshots\":2,\"freshSnapshots\":true,\"callerProgress\":true}")
    }

    private static func verify(_ value: PowerSnapshot) throws {
        guard value.powerSource == nil else { throw Failure.sourceNotNull }
        guard value.powerSaveMode != nil, case .apple(_)? = value.thermalState else {
            throw Failure.otherFieldsLost
        }
    }

    private enum Failure: Error {
        case missingFixture, missingPower, sourceNotNull, otherFieldsLost, invalidTimestamp
        case streamEnded, blockedCaller, nativeWorkOnMainThread
    }
}
#endif
