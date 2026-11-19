// Public-API regression consumer for activity publication racing a sensor read deadline.
import DeviceReadout
import Foundation

enum SensorActivityReplay {
    @MainActor
    static func run() async throws {
        for iteration in 1...1000 {
            try await cycle()
            if iteration % 100 == 0 {
                FileHandle.standardError.write(Data("[DEBUG-sensor-activity] completed \(iteration)/1000\n".utf8))
            }
        }
        print("SWIFT_SENSOR_ACTIVITY_REPLAY {\"passed\":true,\"iterations\":1000}")
    }

    @MainActor
    private static func cycle() async throws {
        let access = try DeviceAccess(collector: UnusedCollector()).withReadTimeout(.milliseconds(20))
        defer { access.close() }
        let sensor = try access.observers.target(Entities.pressure, id: "pressure")
        let source = try access.observers.sensorSource(sensor) { _ in nil }
        defer { source.close() }
        let activity = Task {
            while !Task.isCancelled {
                try access.observers.sensorActivity(false)
                try await Task.sleep(for: .milliseconds(1))
                try access.observers.sensorActivity(true)
                try await Task.sleep(for: .milliseconds(1))
            }
        }
        defer { activity.cancel() }
        do {
            _ = try await access.get(sensor)
            throw Failure.unexpectedMeasurement
        } catch let error as DeviceReadoutError {
            guard error.code == .readTimeout else { throw error }
        }
        activity.cancel()
        _ = try? await activity.value
    }

    private struct UnusedCollector: DeviceCollector {
        func read(_ request: EntityRequest) throws -> any DeviceSnapshot {
            throw Failure.unexpectedNativeRead
        }
    }
    private enum Failure: Error { case unexpectedMeasurement, unexpectedNativeRead }
}
