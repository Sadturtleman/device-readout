# Swift native Apple power collection

Work in progress toward the full SDK design. `DeviceAccess()` now reads Power on macOS and iOS. Native source notifications and the final Apple matrix are still being verified; this record does not declare the SDK complete.

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

The macOS source reference runs `/usr/bin/pmset -g batt` only in the test process, before and after the SDK read. Stable reference values must equal the SDK result. CI hosts observed External; this does not verify battery or UPS hardware. Foundation notifications are explicitly posted by tests: they prove adapter wiring, not a system thermal or saver-mode transition.

The source-notification test runs only on the isolated GitHub Actions host. Apple's notify namespace reserves com.apple.system.* posting for root, so the test launches `sudo -n /usr/bin/notifyutil -p com.apple.system.powersources.source` on a detached task. It changes no power setting. Other hosts skip this specific system-wide notification test; GitHub CI must execute it. No command execution or privilege escalation is included in the SDK.

Intermediate iOS jobs superseded by later TDD commits are not counted as passed. The final unchanged-source Apple matrix, a Power-aware independent consumer, native error/cleanup boundaries, physical battery/UPS and thermal/saver transitions, minimum-OS execution and framework adapters remain required. Other native Apple entities and the complete five-binding/platform acceptance matrix are still in scope.

Local logs and source captures remain under ignored `.tools/apple-power` and `.tools/apple-ci` paths. Linux logs for d1bf557 are `source-linux-debug.log` and `source-linux-release.log`; Apple logs are retained by job ID.

## Primary references

- [Low-power mode](https://developer.apple.com/documentation/foundation/processinfo/islowpowermodeenabled) and [thermal notification registration](https://developer.apple.com/documentation/foundation/processinfo/thermalstatedidchangenotification).
- [Power source snapshot](https://developer.apple.com/documentation/iokit/1523839-iopscopypowersourcesinfo) and [providing source type](https://developer.apple.com/documentation/iokit/iopowersources_h/1810316-iopsgetprovidingpowersourcetype).
- Apple's public [IOPowerSources header](https://github.com/apple-oss-distributions/IOKitUser/blob/main/ps.subproj/IOPowerSources.h), [source constants](https://github.com/apple-oss-distributions/IOKitUser/blob/main/ps.subproj/IOPSKeys.h), and [implementation](https://github.com/apple-oss-distributions/IOKitUser/blob/main/ps.subproj/IOPowerSources.c).
- Apple's [notify module map](https://github.com/apple-oss-distributions/Libnotify/blob/main/notify.modulemap) and [namespace permissions](https://github.com/apple-oss-distributions/Libnotify/blob/main/notify.3).
