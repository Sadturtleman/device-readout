# Swift native Apple power collection

Work in progress toward the full SDK design. `DeviceAccess()` now reads Power on macOS and iOS. The unchanged-source Apple matrix at 385e2f2 passes, including native source notifications. An earlier intermittent permission-test stall remains unresolved; this record does not declare the SDK complete.

## Fields and execution

| Field | macOS | iOS |
| --- | --- | --- |
| powerSaveMode | ProcessInfo.isLowPowerModeEnabled | ProcessInfo.isLowPowerModeEnabled |
| thermalState | Apple nominal/fair/serious/critical stages | Apple nominal/fair/serious/critical stages |
| powerSource | Public IOKit AC/Battery/UPS result maps to External/Battery/Ups | nil from the bundled collector; UIKit battery monitoring is app-owned |

Unknown thermal/source values remain nil. A missing IOKit result affects only powerSource; the other fields remain readable. Copy ownership is released by ARC and the Get result is borrowed. The SDK uses exported IOKit constants and no shell command or private API.

The public IOKit function can itself fall back to AC power inside the OS. DeviceReadout preserves the value returned by the public API; it cannot identify every hidden OS failure as nil. No battery source is inferred from low-power mode or thermal state.

Native reads, normalization, registration and cleanup use the existing serial collection worker. Construction and passive capability queries do not read Power or enable monitoring. Foundation power/thermal callbacks supply invalidations only; the worker rereads a complete snapshot and stamps collectedAt. The thermal state is read before notification registration, as Foundation requires. Polling continues to supplement native invalidations.

App-owned state keeps its existing whole-entity precedence. Context close, cancellation, read deadlines and late native setup retain the worker lifetime contract; the generic held-boundary tests cover this runtime behavior. They do not establish native power-daemon fault handling or physical transitions. No UIKit getters, permission prompts or global power setting changes are introduced.

## Observed verification

| Source / run | Evidence |
| --- | --- |
| f43120c / [run 10](https://github.com/Sadturtleman/device-readout/actions/runs/44470910224) | The first public native Power test fails with UnsupportedEntity. |
| 001cdc6 / [run 12](https://github.com/Sadturtleman/device-readout/actions/runs/44472383447) | The notification test fails because Foundation power/thermal notifications do not produce new snapshots before the one-hour poll. |
| 24e732d / [run 13](https://github.com/Sadturtleman/device-readout/actions/runs/44472784817) | All four macOS ARM64/Intel Debug/Release configurations pass 90/90 tests and the existing separate Runtime/TimeZone consumer. Four iOS SDK builds pass. This is not a completed iOS runtime gate. |
| 6b71dff / [run 14](https://github.com/Sadturtleman/device-readout/actions/runs/44473702788) | The independent pmset reference reports External while SDK powerSource is nil. Examined ARM64 Release and Intel Debug logs each report 91 tests with two expected assertions failing in the new source test. |
| d1bf557 / [run 15](https://github.com/Sadturtleman/device-readout/actions/runs/44474170244) | All four macOS configurations pass 91/91, including agreement with pmset. Swift 5.9.2 Linux Debug/Release each pass 88/88 with warnings treated as errors. |
| 54bbad6 / [run 16](https://github.com/Sadturtleman/device-readout/actions/runs/44474633447) | Source-notification test does not compile: Darwin alone does not expose notify_post. This compiler failure is not accepted as the intended behavioral red result. An intermediate DarwinNotify import was superseded after checking Apple's public notify.modulemap and namespace permission rules. |
| 87e8fef / [run 17](https://github.com/Sadturtleman/device-readout/actions/runs/44475262889) | Xcode 16.4 also rejects the DarwinNotify import with no such module. The current test instead uses the independent notifyutil helper. Neither compiler failure counts as a behavior regression. |
| 0304307 / [run 18](https://github.com/Sadturtleman/device-readout/actions/runs/44475794775) | Corrected source-notification test compiles and executes. ARM64 Debug reports 92 tests with two failures: no notification snapshot within two seconds, followed by bounded fail-safe cancellation. The helper succeeds and the test is not skipped. |
| 4ebebfd / [run 19](https://github.com/Sadturtleman/device-readout/actions/runs/44476412063) | Source observation passes in macOS ARM64 Debug and Intel Debug/Release (92/92 each), iOS simulator Debug/Release (90/90 each), and all four iOS SDK builds. ARM64 Release stops progressing in testCoordinatorErrorsReplacementAndSynchronousPublicationHaveExplicitRequestSemantics and is cancelled at the 25-minute job limit. The full matrix gate fails; the other five successful jobs do not establish a completed gate. |
| 385e2f2 / [run 24](https://github.com/Sadturtleman/device-readout/actions/runs/44481364261) | All four macOS ARM64/Intel Debug/Release jobs pass 92/92 tests and their separate Runtime/TimeZone consumer. All four iOS SDK builds and simulator Debug/Release tests (90/90 each) pass. Source hashes and each job's source SHA, exact counts, native Power cases and consumer records are audited. This passing run does not explain the intermittent permission stall in run 19. |

The macOS source reference runs `/usr/bin/pmset -g batt` only in the test process, before and after the SDK read. Stable reference values must equal the SDK result. CI hosts observed External; this does not verify battery or UPS hardware. Foundation notifications are explicitly posted by tests: they prove adapter wiring, not a system thermal or saver-mode transition.

The source-notification test runs only on the isolated GitHub Actions host. Apple's notify namespace reserves com.apple.system.* posting for root, so the test launches `sudo -n /usr/bin/notifyutil -p com.apple.system.powersources.source` on a detached task. It changes no power setting. Other hosts skip this specific system-wide notification test; GitHub CI must execute it. No command execution or privilege escalation is included in the SDK.

Intermediate iOS jobs superseded by later TDD commits are not counted as passed. Run 24 establishes the recorded Apple matrix for 385e2f2, not the absence of intermittent failures. Permission-stall diagnosis, a Power-aware independent consumer, native error/cleanup boundaries, physical battery/UPS and thermal/saver transitions, minimum-OS execution and framework adapters remain required. Other native Apple entities and the complete five-binding/platform acceptance matrix are still in scope.

The stalled permission case passes 100 consecutive focused repetitions on the unchanged Swift 5.9.2 Linux Release binary and 100 on macOS ARM64 Release in [probe run 1](https://github.com/Sadturtleman/device-readout/actions/runs/44481364411). These focused results do not resolve the Apple failure. The temporary probe now widens only the selection to the seven existing PermissionTests, preserving the same 100 repetitions and ten-second per-process watchdog. No timeout is added to the SDK's permission response contract. Native cancellation refusal is separately reproduced and being fixed in [PR #3](https://github.com/Sadturtleman/device-readout/pull/3).

Local logs and source captures remain under ignored `.tools/apple-power` and `.tools/apple-ci` paths. Linux logs for d1bf557 are `source-linux-debug.log` and `source-linux-release.log`; Apple logs are retained by job ID.

## Primary references

- [Low-power mode](https://developer.apple.com/documentation/foundation/processinfo/islowpowermodeenabled) and [thermal notification registration](https://developer.apple.com/documentation/foundation/processinfo/thermalstatedidchangenotification).
- [Power source snapshot](https://developer.apple.com/documentation/iokit/1523839-iopscopypowersourcesinfo) and [providing source type](https://developer.apple.com/documentation/iokit/iopowersources_h/1810316-iopsgetprovidingpowersourcetype).
- Apple's public [IOPowerSources header](https://github.com/apple-oss-distributions/IOKitUser/blob/main/ps.subproj/IOPowerSources.h), [source constants](https://github.com/apple-oss-distributions/IOKitUser/blob/main/ps.subproj/IOPSKeys.h), and [implementation](https://github.com/apple-oss-distributions/IOKitUser/blob/main/ps.subproj/IOPowerSources.c).
- Apple's [notify module map](https://github.com/apple-oss-distributions/Libnotify/blob/main/notify.modulemap) and [namespace permissions](https://github.com/apple-oss-distributions/Libnotify/blob/main/notify.3).
