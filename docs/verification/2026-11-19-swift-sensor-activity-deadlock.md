# Swift sensor activity cancellation checkpoint — 2026-11-19

An application can publish foreground/visibility policy through `access.observers.sensorActivity(...)` while a sensor get reaches its deadline. On macOS, that combination could deadlock the MainActor and the read's cancellation path. The fix releases the activity control's state lock before delivering its internal stream value.

UI, permission and activity inputs remain application-owned. No implicit UI getter, prompt, global setting or forced permission-response deadline is introduced.

## Evidence and diagnosis

The first useful full-suite capture is [4795e44, run 44498374901](https://github.com/Sadturtleman/device-readout/actions/runs/44498374901). The 180-second external watchdog expired on the first fresh Release suite. Both SwiftPM and its XCTest descendant were sampled before termination. XCTest starts a separate process group; an earlier process-group-only sampler had missed it.

The captured task stacks show the cycle:

```text
MainActor: sensorActivity -> SensorActivityControl.change
  holds control NSLock
  AsyncThrowingStream.yield -> waits for Swift task status lock

read deadline: ReadOperation.resolve -> task.cancel
  holds Swift task status lock
  stream termination -> producer cancellation -> observation.cancel
  SensorActivityControl.close -> waits for control NSLock
```

The final printed permission-test name was buffered output from an earlier test. The live stack was in `SensorActivityTests.testGetDeadlineSurvivesRepeatedUnmeasuredSessionRestarts`, not a permission request.

The reduced public consumer at [fe84fda, run 44500304650](https://github.com/Sadturtleman/device-readout/actions/runs/44500304650) removes XCTest, permission operations, native collectors and unrelated entities. It uses an app-owned pressure source without samples, a 20 ms read deadline and MainActor activity changes every millisecond. It repeats the same API interaction up to 1,000 times. It froze before the first 100 completed iterations and hit the 90-second external watchdog; the standalone consumer stack shows the identical lock cycle.

Artifacts were downloaded and checked against GitHub's SHA-256 digests:

| Evidence | Artifact ID | ZIP SHA-256 |
|---|---|---|
| Full-suite stack | 14516980374 | `6a8cd14719421887689c64de0230f6a064cd68579f5ce8b7c1c544b8589e6fc5` |
| Reduced consumer stack | 14516488920 | `558cf5c9d952322a341e11b92cdc272877ef2607d83d86d2b9ab144bac6d04d2` |

The pre-fix consumer passed on Swift 5.9.2/Linux, so Linux success alone would have missed the actual macOS failure.

## Fix and validation

Implementation [f4135ef](https://github.com/Sadturtleman/device-readout/commit/f4135ef20e324a9aea7bbc06b9364502f9b37e65) validates the activity generation while holding the control lock, releases it, then calls `yield`. A concurrent newer generation may overtake delivery; existing sensor-watch and session-install checks reject that stale generation. Overflow still terminates the activity stream with ReadFailed, and its closed flag is updated under the control lock.

The unchanged reduced consumer passes all 1,000 cycles in the macOS [verification probe](https://github.com/Sadturtleman/device-readout/actions/runs/44500976524). Swift 5.9.2/Linux passes the same consumer plus 88 tests in each Debug/Release configuration. All ten fresh full-suite macOS Release repetitions completed successfully, with 92 tests per repetition and no permission phase tracing. Artifact 14516779885 was downloaded, its ZIP SHA-256 `acedbb627de39744abf747d3674653a97e625daa2dc378d35d9ae1748c730980` was checked, and every original suite log plus the consumer pass record was inspected. The final cleanup commit's regular Apple matrix is still required.

## Permanent regression and cleanup

The separate SwiftPM consumer retains `--sensor-activity-consumer`. After building that consumer, `python3 tools/test-swift-sensor-activity.py` runs 1,000 real deadline/activity races with an external 90-second watchdog. A successful run must return the exact pass record. The watchdog can detect a blocked MainActor because it runs in a separate process.

Regular Apple CI runs this consumer for ARM64/Intel in Debug/Release. Temporary permission phase prints, standalone permission replays, fresh-suite probes and the diagnostic-only workflow are removed. The cleaned consumer builds and passes on Swift 5.9.2/Linux. These regression results do not complete native sensor integration, framework lifecycle adapters, minimum-OS/physical-device validation or the full SDK matrix.
