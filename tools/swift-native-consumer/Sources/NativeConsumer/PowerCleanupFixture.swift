#if os(macOS)
import DeviceReadout
import Foundation

enum PowerCleanupFixture {
    @MainActor
    static func run() async throws {
        guard let tracePath = ProcessInfo.processInfo.environment["DEVICE_READOUT_POWER_TRACE"] else {
            throw Failure.missingFixture
        }
        let access = try DeviceAccess().withPollInterval(.seconds(3600))
        defer { access.close() }
        let support = try await access.capabilities.get(Entities.power)
        guard support.readable == true, support.watchable == true else { throw Failure.missingPower }
        var iterator = access.watch(Entities.power).makeAsyncIterator()
        guard let value = try await iterator.next(), value.powerSource != nil,
              value.powerSaveMode != nil, case .apple(_)? = value.thermalState else { throw Failure.missingPower }
        let start = ContinuousClock.now
        access.close()
        let pulse = await Task { @MainActor in 17 }.value
        guard pulse == 17, start.duration(to: .now) < .seconds(1) else { throw Failure.blockedCaller }
        do { _ = try await access.get(Entities.power); throw Failure.contextStillOpen }
        catch let error as DeviceReadoutError where error.code == .entityRemoved { }
        var trace = ""
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        repeat {
            trace = try String(contentsOfFile: tracePath, encoding: .utf8)
            if trace.contains("cancelled main=0") { break }
            try await Task.sleep(for: .milliseconds(10))
        } while ContinuousClock.now < deadline
        FileHandle.standardOutput.write(Data(("SWIFT_POWER_CLEANUP_TRACE\n" + trace).utf8))
        guard trace.contains("fixture-loaded"), trace.contains("registered main=0"),
              trace.contains("cancel-refused main=0") else { throw Failure.missingFixture }
        guard trace.contains("cancelled main=0") else { throw Failure.cleanupNotRetried }
        guard !trace.contains("registered main=1"), !trace.contains("cancel-refused main=1"),
              !trace.contains("cancelled main=1") else { throw Failure.nativeWorkOnMainThread }
        print("SWIFT_POWER_CLEANUP_CONSUMER {\"passed\":true,\"callerProgress\":true,\"retriedCancellation\":true}")
    }

    private enum Failure: Error {
        case missingFixture, missingPower, blockedCaller, contextStillOpen, cleanupNotRetried, nativeWorkOnMainThread
    }
}
#endif
