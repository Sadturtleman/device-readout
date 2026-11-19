// Temporary diagnostic fixture. Copied only into an isolated CI test package.
import Foundation
import XCTest

final class SchedulingProbe: NSObject, XCTestObservation, @unchecked Sendable {
    private static let shared = SchedulingProbe()
    private let lock = NSLock()
    private var started = false
    private var maximum: [String: Duration] = [:]
    private var counts: [String: Int] = [:]
    private var timers: [DispatchSourceTimer] = []
    private var task: Task<Void, Never>?

    static func install() { shared.start() }

    private func start() {
        guard !started else { return }
        started = true
        XCTestObservationCenter.shared.addTestObserver(self)
        for (name, queue) in [
            ("dispatch-utility", DispatchQueue(label: "diagnostic utility", qos: .utility)),
            ("dispatch-default", DispatchQueue(label: "diagnostic default", qos: .default)),
            ("dispatch-main", DispatchQueue.main)
        ] {
            let timer = DispatchSource.makeTimerSource(queue: queue)
            let sample = PulseSample()
            timer.schedule(deadline: .now() + .milliseconds(100), repeating: .milliseconds(100))
            timer.setEventHandler { [self] in record(name, gap: sample.advance()) }
            timers.append(timer)
            timer.resume()
        }
        task = Task.detached(priority: .utility) { [self] in
            let sample = PulseSample()
            do {
                while true {
                    try await Task.sleep(for: .milliseconds(100))
                    record("task-utility", gap: sample.advance())
                }
            } catch { }
        }
    }

    private func record(_ name: String, gap: Duration) {
        lock.lock()
        counts[name, default: 0] += 1
        maximum[name] = max(maximum[name, default: .zero], gap)
        lock.unlock()
    }

    func testCaseWillStart(_ testCase: XCTestCase) {
        lock.lock(); maximum.removeAll(); counts.removeAll(); lock.unlock()
    }

    func testCaseDidFinish(_ testCase: XCTestCase) {
        lock.lock()
        let output = maximum.keys.sorted().map { "\($0):count=\(counts[$0, default: 0]),maxGap=\(maximum[$0]!)" }
        lock.unlock()
        print("[DEBUG-ios-scheduling] \(testCase.name) \(output.joined(separator: " "))")
    }

    func testBundleDidFinish(_ testBundle: Bundle) {
        task?.cancel()
        timers.forEach { $0.cancel() }
    }
}

private final class PulseSample: @unchecked Sendable {
    private var previous = ContinuousClock.now
    func advance() -> Duration {
        let now = ContinuousClock.now
        let gap = previous.duration(to: now)
        previous = now
        return gap
    }
}
