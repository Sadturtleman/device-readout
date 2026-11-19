# Swift native power cancellation retry

This checkpoint covers one macOS native-resource failure boundary. It does not establish the complete Apple or SDK acceptance matrix.

## Contract and change

Closing a native Power observation can receive a failure from `notify_cancel`. That failure does not transfer ownership or prove that the OS subscription is gone. The prior cleanup closure threw and then lost the token. The corrected collector retains the token and retries on a utility queue after 100 ms, doubling the delay up to 30 seconds. One retirement chain owns each token; duplicate close does not schedule another chain. Success or an invalid-token response ends retirement.

The initial cleanup remains on the collection worker. Subsequent retries run independently of ordinary collection. The caller does not wait for cleanup. A permanently refusing OS may retain the token until recovery or process exit; this change cannot force the OS to release it. Native calls are not isolated from process crashes.

## Public native-boundary evidence

The separate SwiftPM consumer imports DeviceReadout, reads and watches native Power, closes the context from MainActor, verifies a subsequent read returns EntityRemoved, and confirms MainActor can continue. A test-only dylib interposes the public Darwin notification registration/cancellation functions. Registration is real; the fixture refuses the first cancellation without releasing the token and forwards the next attempt to the OS. Its trace records whether each native call ran on the main thread. No fixture code or test hook ships in the SDK.

A second scenario hands Power to an app observer while retaining the context. The fixture blocks the retry inside the native cancellation function until the consumer explicitly releases it. Before release, a native Runtime read in that same context must complete within one second and MainActor must continue. The consumer then releases the gate and verifies successful native cancellation. This checks actual held native work, not just a delayed retry timer.

| Source / run | Result |
| --- | --- |
| 6ef8dac / [run 20](https://github.com/Sadturtleman/device-readout/actions/runs/44478456840) | The new consumer fixture crashed before registration. This was a harness failure, not the required SDK regression signal. |
| a0a39e3 / [native-only probe 1](https://github.com/Sadturtleman/device-readout/actions/runs/44479118025) | A C-only probe reproduces the injected-call crash on ARM64 and Intel; its uninjected control succeeds. |
| b933d8d / [native-only probe 2](https://github.com/Sadturtleman/device-readout/actions/runs/44479361273) | Replacing dlsym-based call-through with the interposing image's direct original bindings fixes both C-only configurations. Registration, deliberate refusal and real cancellation execute. This does not prove the exact crashing stack of the old lookup. |
| b933d8d / [run 22](https://github.com/Sadturtleman/device-readout/actions/runs/44479361267) | ARM64 Debug passes 92 SDK tests, then the original Swift consumer fails with cleanupNotRetried. Its trace contains registration and cancel-refused on a worker, with no successful cancellation. This is the intended SDK red result. |
| 6327056 / [run 23](https://github.com/Sadturtleman/device-readout/actions/runs/44480132595) | ARM64 Debug and Intel Debug/Release each pass 92 SDK tests, the ordinary separate consumer and the cancellation-refusal consumer. Each native trace contains registered, cancel-refused and cancelled with main=0; callerProgress and retriedCancellation are true. All four iOS SDK builds and iOS simulator Debug/Release (90 tests each) pass. ARM64 Release instead stalls in the existing permission coordinator test and is cancelled at the 25-minute job limit, before either consumer. The complete run is not green. |
| 3bd1948 / [run 26](https://github.com/Sadturtleman/device-readout/actions/runs/44484623817) | All four macOS ARM64/Intel Debug/Release configurations pass 92/92, the ordinary consumer and both cancellation scenarios. Each held-retry report verifies same-context native collection and caller progress before gate release. Four iOS builds and simulator Debug/Release (90/90 each) pass. Source hashes, job SHAs, counts, native traces and all consumer records are audited. This full passing run does not explain the earlier intermittent permission stalls. |

Swift 5.9.2 on Linux passes 88/88 tests in Debug and Release after the fix. The separate Linux Debug consumer passes with build concurrency limited to two. An earlier fresh consumer build failed to build the CoreFoundation module; the bounded-concurrency result does not establish the cause of that compiler failure. Linux does not exercise the macOS cancellation path.

The temporary native-only probe workflow, script and C program were removed in 6327056. The retained fixture now tests the public native boundary through the Swift consumer.

## Remaining verification

The ARM64 Release permission stall is also present on the parent Power branch in [run 19](https://github.com/Sadturtleman/device-readout/actions/runs/44476412063). Both logs stop after `testCoordinatorErrorsReplacementAndSynchronousPublicationHaveExplicitRequestSemantics` starts. Isolated macOS runs of that method and the seven-test PermissionTests class each pass 100 times. [PR #4](https://github.com/Sadturtleman/device-readout/pull/4) also records 30 successful full-suite repetitions after a separate build and ten successful fresh-build full-suite invocations. Linux's prebuilt 88-test suite passes 30 repetitions. These non-reproductions do not establish a fix. No SDK timeout is added to permission-response waiting.

Held native registration calls, multiple consecutive refusals, additional native error cases, physical battery/UPS and thermal/saver transitions, minimum Apple OS runtime, the Swift 5.9 Apple compiler and the remaining collectors/framework adapters still require verification or implementation. [PR #5](https://github.com/Sadturtleman/device-readout/pull/5) adds a public IOKit read-failure boundary. The full five-binding/platform acceptance matrix remains in scope.

Raw CI logs and the audit report are preserved by job ID under the ignored `.tools/apple-power` directory in the main worktree. The cleanup worktree retains source captures for 6327056 and 3bd1948 in `.tools/apple-ci`, and Linux Debug/Release logs under `.tools/cleanup-linux-*.log`. The audit checks all 586 non-Markdown inputs at 3bd1948 and verifies that its Swift SDK and test sources match the verified Linux source commit.
