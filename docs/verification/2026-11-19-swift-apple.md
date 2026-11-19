# Swift verification with Apple SDKs

The existing Swift SDK passes the complete Apple workflow at source `ac0ffef3d8413c3bc7d0839c41ee9f7655815544`: [run 8](https://github.com/Sadturtleman/device-readout/actions/runs/44468209865), [PR #1](https://github.com/Sadturtleman/device-readout/pull/1). The source/log audit passes for 582 non-Markdown inputs, six runtime configurations, four iOS SDK builds, the separate consumers and 688 local documentation links.

Native SDK sources are unchanged from `038feca7c876b61c08df53e39621f4a8cdd00e78`. Runtime and TimeZone remain the only bundled native collector kinds. The full 46-entity, binding, minimum-version and physical-device acceptance scope remains unfinished.

## Verified configurations

Apple jobs use Xcode 16.4, Apple Swift 6.1.2 in Swift 5 language mode, macOS 15 and iOS SDK 18.5. Compiler warnings are errors. The iOS build deployment target is 16.0; minimum-OS execution is a separate outstanding requirement.

| Check | Result |
| --- | --- |
| macOS ARM64 Debug / Release | 88/88 tests and separate SwiftPM consumer in each configuration. |
| macOS Intel Debug / Release | 88/88 tests and separate SwiftPM consumer in each configuration. |
| iOS 18.5 ARM64 simulator Debug / Release | 88/88 tests in each configuration, in the original Debug → Release order. |
| iOS device SDK Debug / Release | Both builds pass. This does not imply device execution. |
| iOS simulator SDK Debug / Release | Both builds pass. |
| Swift 5.9.2, Ubuntu 22.04 under WSL | 88/88 tests in each Debug/Release configuration after the contract-test changes. |

The macOS consumers import the public product through a distinct SwiftPM package. They verify native reads, equal snapshots with fresh timestamps, immutable settings and shared context closure. Process architectures match independently recorded ARM64/x86-64 runner architectures. UTC Debug and Kathmandu Release runs preserve their IANA identifiers and offsets of 0 and 20700 seconds.

Most contract tests use controlled collectors and app-owned observers. Native TimeZone tests compare offset/DST with C-library localtime and exercise Foundation notification-center wiring. They do not change OS settings or prove a real settings-change notification occurred. These results do not implement the remaining declared entities.

## First-run simulator failure

Without an explicit complete-boot wait, the first simulator test configuration repeatedly failed across different test classes. It was initially Debug. In the controlled [order comparison](https://github.com/Sadturtleman/device-readout/actions/runs/44467177930), only the configuration order changed: Release first failed five assertions, while Debug second passed 88/88. This contradicted a Debug-specific code-generation explanation.

Isolated [diagnosis 2](https://github.com/Sadturtleman/device-readout/actions/runs/44465882518) and [diagnosis 3](https://github.com/Sadturtleman/device-readout/actions/runs/44467178034) retained failures rather than retrying them into success. Diagnosis 3 failed its first handoff group, then passed the original full Debug suite without instrumentation. Instrumented copies also passed, so instrumentation was not required for success. Pulse measurements in passing copies did not measure the earlier failure and were not treated as proof of its cause.

The simulator script now waits for the selected device's `simctl bootstatus <UDID> -b` completion before starting timed tests. Run 8 records data migration and system-app readiness before terminal `Finished`, taking 64 seconds, then passes both complete configurations in the original order. This closes the reproduced first-run CI failure through explicit environment readiness; it does not claim a change to SDK scheduling or hard real-time guarantees. No test assertion or timeout was changed in the order/readiness experiments, no failed configuration was ignored, and no fixed sleep was added.

Temporary diagnostic workflows, copied-package runners and tagged scheduling probes are removed after this result. Their source and logs remain available in the linked historical commits/runs. The normal workflow still fails if either simulator configuration fails.

## Earlier failures and regression improvements

- [Run 1](https://github.com/Sadturtleman/device-readout/actions/runs/44459325890), `7a8e6d0`: one sensor test assumed repeated lifecycle transitions and result observation would fit 220 ms. Its replacement keeps restarting unmeasured sessions while the original get deadline must expire. Removing the original timer in an isolated copy makes the replacement fail.
- [Run 2](https://github.com/Sadturtleman/device-readout/actions/runs/44460294270), `d943069`: a handoff test exceeded a 300 ms elapsed ceiling. Its replacement makes a value available after the original deadline but before a restarted deadline and requires ReadTimeout; a deliberate deadline-restart mutation fails. Separately, lowercasing a simulator UUID prevented Xcode from finding the destination. The script preserves the returned identifier and specifies architecture.
- [Run 3](https://github.com/Sadturtleman/device-readout/actions/runs/44461376615), `7448fe6`: iOS Debug executed 88 tests with 16 failures (5 unexpected); Release passed. Queue recovery had assumed canceled slots were already drained, and overflow assumed thousands of timer-driven reads would fit five seconds. Recovery now tolerates temporary typed saturation before requiring the next native value. Overflow uses source invalidations and still requires 2,049 ordered accepted snapshots, ReadFailed and exactly 2,050 source calls. A silent-drop mutation fails.
- [Run 4](https://github.com/Sadturtleman/device-readout/actions/runs/44462954036), `bf041ac`, and [run 5](https://github.com/Sadturtleman/device-readout/actions/runs/44464128925), `480a586`: Debug still failed with 11 and 10 failures respectively; Release passed. Test-margin corrections alone did not resolve the CI problem.
- [Run 6](https://github.com/Sadturtleman/device-readout/actions/runs/44465882533), `ffdaaa0`: Debug failed with 37 failures (7 unexpected), now concentrated in sensor/target cases; Release passed. This prompted the order comparison rather than further timeout widening.

The first diagnostic script also failed before its full-suite stage because Bash 3.2 treats an empty array as unbound under nounset. That invocation was corrected; it was never counted as an executed or passed SDK suite. A local Swift 5.9.2 diagnostic-copy build encountered a compiler signal 11. The established scratch/cache/module-cache configuration subsequently compiled and passed four handoff tests; the compiler failure remains recorded without a claimed cause.

## Reproduction and retained evidence

The [workflow](../../.github/workflows/swift-apple.yml) uses read-only repository permissions, pinned official actions and no publishing step. Each job records the exact source, OS, architecture and toolchain. Text logs remain in 14-day workflow artifacts and ignored local `.tools/apple-ci` copies. The local `verified-ac0ffef.json` audit records source/log hashes, consumer outputs and remaining scope. Earlier failed and mutation logs are preserved.

On macOS with Xcode selected:

```sh
TZ=Etc/UTC sh tools/test-swift.sh -Xswiftc -warnings-as-errors
TZ=Asia/Kathmandu sh tools/test-swift.sh -c release -Xswiftc -warnings-as-errors
TZ=Etc/UTC sh tools/test-swift-native-consumer.sh
TZ=Asia/Kathmandu sh tools/test-swift-native-consumer.sh -c release
bash tools/test-swift-apple-build.sh
bash tools/test-swift-apple-simulator.sh
```

The simulator command selects an available iPhone matching the selected SDK, preserves its exact ID, waits for boot completion and runs both configurations. Failures survive log capture. Apple documents test destinations in [Building from the Command Line with Xcode](https://developer.apple.com/library/archive/technotes/tn2339/_index.html); runner architectures follow the [GitHub-hosted runner documentation](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).

## Remaining scope

macOS 13 and iOS 16 runtime tests, an Apple Swift 5.9 toolchain, physical devices, actual settings-change notifications, additional native fields/entities and Apple Flutter/React Native/UI/lifecycle integration remain required. The standalone consumer uses a local package dependency, not a tagged remote release. Worker-owned reads/registration/cleanup and MainActor progress are exercised; native-crash containment and zero shared-process overhead are not established.
