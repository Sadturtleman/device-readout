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
        let retryGate = ProcessInfo.processInfo.environment["DEVICE_READOUT_POWER_RETRY_GATE"]
        defer {
            if let retryGate { try? Data().write(to: URL(fileURLWithPath: retryGate)) }
        }
        if let retryGate {
            // App handoff retires the native observation while its context stays usable.
            try access.observers.publish(Entities.power, snapshot: PowerSnapshot(powerSaveMode: value.powerSaveMode))
            guard let handed = try await iterator.next(), handed.powerSaveMode == value.powerSaveMode else {
                throw Failure.handoffFailed
            }
            _ = try await waitFor("retry-entered main=0", tracePath: tracePath)
            let readStarted = ContinuousClock.now
            let runtime = try await access.withReadTimeout(.seconds(1)).get(Entities.runtime)
            guard runtime.processBitness == MemoryLayout<UnsafeRawPointer>.size * 8,
                  readStarted.duration(to: .now) < .seconds(1) else { throw Failure.blockedCollection }
            let pulse = await Task { @MainActor in 23 }.value
            guard pulse == 23 else { throw Failure.blockedCaller }
            let held = try String(contentsOfFile: tracePath, encoding: .utf8)
            guard !held.contains("retry-released"), !held.contains("retry-wait-expired"),
                  !held.contains("cancelled main=") else { throw Failure.retryNotHeld }
            try Data().write(to: URL(fileURLWithPath: retryGate))
            print("SWIFT_POWER_RETRY_ISOLATION {\"passed\":true,\"sameContextNativeRead\":true,\"callerProgress\":true}")
        }
        let start = ContinuousClock.now
        access.close()
        let pulse = await Task { @MainActor in 17 }.value
        guard pulse == 17, start.duration(to: .now) < .seconds(1) else { throw Failure.blockedCaller }
        do { _ = try await access.get(Entities.power); throw Failure.contextStillOpen }
        catch let error as DeviceReadoutError where error.code == .entityRemoved { }
        let trace = try await waitFor("cancelled main=0", tracePath: tracePath)
        FileHandle.standardOutput.write(Data(("SWIFT_POWER_CLEANUP_TRACE\n" + trace).utf8))
        guard trace.contains("fixture-loaded"), trace.contains("registered main=0"),
              trace.contains("cancel-refused main=0") else { throw Failure.missingFixture }
        guard !trace.contains("registered main=1"), !trace.contains("cancel-refused main=1"),
              !trace.contains("cancelled main=1"), !trace.contains("retry-entered main=1") else {
            throw Failure.nativeWorkOnMainThread
        }
        print("SWIFT_POWER_CLEANUP_CONSUMER {\"passed\":true,\"callerProgress\":true,\"retriedCancellation\":true}")
    }

    private static func waitFor(_ event: String, tracePath: String) async throws -> String {
        var trace = ""
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        repeat {
            trace = try String(contentsOfFile: tracePath, encoding: .utf8)
            if trace.contains(event) { return trace }
            try await Task.sleep(for: .milliseconds(10))
        } while ContinuousClock.now < deadline
        FileHandle.standardOutput.write(Data(("SWIFT_POWER_CLEANUP_TRACE\n" + trace).utf8))
        throw Failure.cleanupNotRetried
    }

    private enum Failure: Error {
        case missingFixture, missingPower, blockedCaller, contextStillOpen, cleanupNotRetried, nativeWorkOnMainThread
        case handoffFailed, blockedCollection, retryNotHeld
    }
}
#endif
