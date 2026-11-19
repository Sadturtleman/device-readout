# Swift verification with Apple SDKs

This checkpoint adds repeatable Apple verification for the existing Swift package. Native SDK implementation files are unchanged from `038feca7c876b61c08df53e39621f4a8cdd00e78`; changes consist of CI, reproduction scripts and public-contract tests. Runtime and TimeZone remain the only bundled native collector kinds. The full 46-entity, binding, platform, minimum-version and physical-device acceptance scope remains unfinished.

The latest completed full run in this checkpoint verifies `ffdaaa0991e17df19765ce00fc5e84f308912aac` in [PR #1](https://github.com/Sadturtleman/device-readout/pull/1). The [sixth Apple workflow run](https://github.com/Sadturtleman/device-readout/actions/runs/44465882533) checks that exact commit rather than an unrecorded local source tree.

## Environment and results

Apple jobs use Xcode 16.4 and Apple Swift 6.1.2 in Swift 5 language mode. The iOS builds use SDK 18.5 with deployment target 16.0. The hosted macOS systems are macOS 15; declaring macOS 13/iOS 16 deployment targets does not establish execution on those minimum OS releases.

| Check | Result |
| --- | --- |
| macOS ARM64 Debug | 88/88 tests; separate SwiftPM consumer passes. |
| macOS ARM64 Release | 88/88 tests; separate SwiftPM consumer passes. |
| macOS Intel Debug | 88/88 tests; separate SwiftPM consumer passes. |
| macOS Intel Release | 88/88 tests; separate SwiftPM consumer passes. |
| iOS 18.5 simulator Debug | 88 tests execute; 37 assertion/unexpected-error failures (7 unexpected). Gate fails. |
| iOS 18.5 simulator Release | 88/88 pass. |
| iOS device SDK builds | Debug and Release pass, targeting iOS 16. No device execution is implied. |
| iOS simulator SDK builds | Debug and Release pass. |
| Swift 5.9.2 on Linux | 88/88 tests in each Debug/Release configuration after the test changes. |

Compiler warnings are treated as errors in these commands. The macOS consumers import the public product from a distinct SwiftPM package and verify native reads, equal snapshots with fresh timestamps, immutable settings and shared context closure. Their process architectures agree with the runner's independently reported ARM64/x86-64 architecture. UTC Debug and Kathmandu Release values retain their IANA identifiers and expected offsets of 0 and 20700 seconds.

Most contract tests use controlled collectors and app-owned observer inputs. Their success is not evidence of native implementations for the remaining declared entities. Native TimeZone tests compare offset/DST with C-library localtime and exercise Foundation notification-center wiring; they do not change the OS time-zone setting or prove a hardware/system notification was delivered.

## Failures preserved and test corrections

1. [Run 1](https://github.com/Sadturtleman/device-readout/actions/runs/44459325890), source `7a8e6d0`: ARM64 Debug/Release, Intel Release and the four iOS builds pass. Intel Debug fails a sensor restart test that assumed lifecycle transitions and result observation would fit a 220 ms window. The replacement keeps restarting unmeasured sessions while the original get deadline must still expire. Removing that original timer in an isolated copy makes the replacement fail; the original SDK passes.
2. [Run 2](https://github.com/Sadturtleman/device-readout/actions/runs/44460294270), source `d943069`: ARM64 Debug fails a 300 ms elapsed-time ceiling during source handoff. The replacement makes a snapshot available after the original deadline but before a restarted deadline and requires ReadTimeout. A deliberate deadline-restart mutation fails. The simulator command separately fails before running tests because it lowercases an available uppercase device ID; the script now preserves the platform-provided ID and specifies the architecture.
3. [Run 3](https://github.com/Sadturtleman/device-readout/actions/runs/44461376615), source `7448fe6`: all macOS configurations/consumers and the four iOS builds pass. Actual iOS simulator Release passes 88/88; Debug executes 88 tests with 16 assertions/unexpected-error failures across seven cases. These include assuming canceled queue slots have already drained, requiring thousands of timer-driven reads within five seconds, and tight setup/observation windows.

The queue-recovery test now accepts temporary ReadFailed while canceled entries drain, then still requires the next native value to be exactly the second read. The overflow test uses native invalidations, waits for observation cleanup before draining, and still requires 2,049 ordered accepted snapshots, ReadFailed and exactly 2,050 source reads. An isolated mutation that ignores dropped snapshots fails both the error and source-count assertions. Other affected tests retain deadline, idle lifetime, cancellation, immutable cadence and stale-value/error rejection checks, with bounded source gates and wider setup margins. Idle waits still exceed their configured read deadline. No tests are skipped or automatically retried to produce a passing result.

These changes strengthen the test harness; they do not establish a native scheduler/performance fix or explain every preceding timing delay. All earlier failed runs and local mutation logs remain part of the evidence.

## Reproduction and evidence

The [workflow](../../.github/workflows/swift-apple.yml) runs on [standard GitHub macOS runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners), with read-only repository permissions, pinned official actions and no publishing step. Each job records its source SHA, OS, architecture and toolchain. Text logs are retained as workflow artifacts for 14 days; local copies and hashes are kept under ignored `.tools/apple-ci` paths.

On macOS with Xcode selected, run:

```sh
TZ=Etc/UTC sh tools/test-swift.sh -Xswiftc -warnings-as-errors
TZ=Asia/Kathmandu sh tools/test-swift.sh -c release -Xswiftc -warnings-as-errors
TZ=Etc/UTC sh tools/test-swift-native-consumer.sh
TZ=Asia/Kathmandu sh tools/test-swift-native-consumer.sh -c release
bash tools/test-swift-apple-build.sh
bash tools/test-swift-apple-simulator.sh
```

The simulator script selects an available iPhone matching the selected Xcode SDK, logs the selected runtime/device, and runs both configurations. Apple documents the test destination mechanism in [Building from the Command Line with Xcode](https://developer.apple.com/library/archive/technotes/tn2339/_index.html). The test scripts use ignored scratch/cache/result directories and preserve command failure exit codes through log capture.

The source capture for `ffdaaa0` contains 582 non-Markdown inputs. The all-green audit has not passed: the iOS Debug job fails. No complete Apple verification report is claimed.

## Remaining scope

macOS 13 and iOS 16 runtime tests, an Apple Swift 5.9 toolchain, physical devices, actual settings-change notifications, additional native fields/entities and Apple Flutter/React Native/UI/lifecycle integration remain required. The standalone consumer uses a local package dependency, not a tagged remote release. Worker-owned reads/registration/cleanup and MainActor progress are exercised by the contract tests; native crash containment and zero shared-process overhead are not established.

## Additional failures and active diagnosis

Run 4 (`bf041ac`) still fails iOS Debug with 11 failures (2 unexpected); Release passes 88/88. Run 5 (`480a586`) fails Debug with 10 failures (1 unexpected), now in earlier read/native-observation cases; Release again passes. The varying failed cases do not establish a stable SDK failure cause.

The first diagnosis (`44464129000`) runs one late-handoff test successfully and all five Watch tests successfully, but the four-test handoff class fails. Its full-suite invocation fails before test execution because macOS Bash 3.2 treats an empty array as unbound under nounset. That execution must not be reported as an SDK test failure or a passed full suite.

The second diagnosis (`ffdaaa0`, run `44465882518`) corrects that shell expansion and compares the original tests with an isolated package containing queue/task scheduling pulse measurements. The public SDK source is copied unchanged; no instrumentation is added to the published package. It covers utility/default/main dispatch queues and utility Swift tasks. The independent full gate (`44465882533`) still runs all 88 tests in both simulator configurations.

The probe initially encounters a Swift 5.9.2 compiler signal 11 in a fresh default build location. Re-running with the established scratch/cache/module-cache settings compiles it and passes all four handoff tests. That compiler failure is retained in `probe-compile-linux.log`, and the successful configured run in `probe-compile-configured-linux.log`; no compiler cause is claimed.

The sixth full run fails Debug with 37 failures (7 unexpected), concentrated this time in sensor and target cases; Release passes 88/88. All macOS configurations and separate consumers pass, and all four iOS builds pass. No SDK source or test assertion changed between this run and the preceding full run.

The second diagnostic run executes the original four handoff tests successfully, then its original full Debug suite fails with 17 failures (7 unexpected). The later instrumented copy passes both four handoff tests and all 88 tests. Its 100 ms pulse measurements include maximum observed gaps of 0.133 s on default dispatch, 0.525 s on main dispatch, 0.533 s on utility dispatch and 0.587 s on utility Swift tasks. Measurements were taken in the passing copy; they do not prove the cause of the earlier failure, and instrumentation and run order remain confounded.

Commit `95e12bf` changes only the full simulator script order to Release then Debug, preserving both configurations and every assertion. The [seventh full run](https://github.com/Sadturtleman/device-readout/actions/runs/44467177930) fails the first configuration, now Release, with five failures; the second configuration, now Debug, passes all 88 tests. This is an explicit order experiment, not a retry-until-success policy; either failed configuration still fails the job.

The failure following the first configuration rather than Debug changes the next experiment: the simulator script now waits for `simctl bootstatus <selected-device> -b` before executing timed tests, and restores Debug then Release. It waits for an explicit platform boot state, not a fixed sleep, and does not change SDK code, test limits or assertions. The result of that readiness experiment is still pending; a startup cause is not yet claimed proved.
