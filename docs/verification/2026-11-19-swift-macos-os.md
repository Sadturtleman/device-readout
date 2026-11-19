# Swift native macOS OS checkpoint — 2026-11-19

`DeviceAccess().get(Entities.os)` now reads the executing macOS system. `watch(Entities.os)` uses the existing serial polling contract, including immediate collection, unchanged-value delivery and a fresh snapshot completion timestamp. This checkpoint does not add native iOS OS collection or complete the SDK release matrix.

## Field mapping

| Field | Source and meaning |
|---|---|
| `family` | `OsFamily.macOS` in the native macOS collector |
| `name` | `macOS`, the product name for the supported macOS 13+ range |
| `version` | `ProcessInfo.operatingSystemVersion`, formatted as numeric `major.minor.patch` |
| `build` | Public `sysctlbyname("kern.osversion")` |
| `kernelName` | Public `uname().sysname` |
| `kernelVersion` | Public `uname().release` |

Darwin errors leave only the corresponding fields nil. Kernel strings require a terminator and valid UTF-8. The build-string allocation is bounded to 4 KiB; failed size queries, oversized or empty results, out-of-bounds returned lengths and invalid text return nil. The product SDK does not execute `sw_vers` or `uname` commands: those commands are independent test references only.

Native work stays on the existing collection worker. Capability inspection is passive; construction does not collect OS state. The collector does not query UIKit/AppKit, change process settings or request permission. UI, permission and lifecycle state remain app-owned observer inputs.

References: [ProcessInfo](https://developer.apple.com/documentation/foundation/processinfo), [sysctlbyname manual](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/sysctlbyname.3.html), [uname manual](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/uname.3.html). The archived manual pages describe Darwin/macOS behavior despite their URL directory name.

## Observed red and green

The test-first source [87a70e7](https://github.com/Sadturtleman/device-readout/commit/87a70e7dc0d53c16f8758d6145ea51c6b2d7b2d5) compiled and failed the new public macOS OS test with `UnsupportedEntity` in [Intel Debug job 135442645273](https://github.com/Sadturtleman/device-readout/actions/runs/44489920850/job/135442645273). The result was a behavioral failure, not a compiler failure.

Implementation source [9b115ab](https://github.com/Sadturtleman/device-readout/commit/9b115ab8f7907b6d55cfa084ad8b140b5ab3bfe8) passes the complete [Apple run 44490748735](https://github.com/Sadturtleman/device-readout/actions/runs/44490748735):

| Environment | Result |
|---|---|
| macOS ARM64 Debug | 93 tests pass; six OS fields match the independent system report |
| macOS ARM64 Release | 93 tests pass; six OS fields match the independent system report |
| macOS Intel Debug | 93 tests pass; six OS fields match the independent system report |
| macOS Intel Release | 93 tests pass; six OS fields match the independent system report |
| iOS device/simulator SDK builds | Four builds pass with iOS 16 deployment target |
| iOS simulator Debug and Release | 90 tests pass in each configuration; no native iOS OS support is claimed |
| Swift 5.9.2, Ubuntu 22.04, Debug and Release | 88 tests pass in each configuration; macOS-specific code is excluded |

The macOS test also verifies readable/watchable capabilities, one get plus two equal watch snapshots with increasing `collectedAt`, and caller progress. Independent reports recorded macOS 15.8.2 / build 24H232 on ARM and macOS 15.7.9 / build 24G830 on Intel; both reported Darwin 24.6.0. These are runner environments, not evidence of minimum macOS 13 execution.

## Separate consumer and native boundaries

Source [579e435](https://github.com/Sadturtleman/device-readout/commit/579e4357acd283f4507da3d787032c0d9bd60e31) adds three separate SwiftPM consumer scenarios:

1. Healthy reads compare all six fields with independent system-command output, then verify two fresh equal watch snapshots.
2. Test-only interposition makes public `sysctlbyname` and `uname` fail. `build`, `kernelName` and `kernelVersion` become nil, while family/name/version and watch delivery remain usable.
3. A public Darwin call waits on an explicit test gate. A 500 ms configured read returns `ReadTimeout`, `close()` returns and subsequent reads reject the closed context before the gate opens. A second context and MainActor task also progress while the native call is held. Late native completion is not returned to the already timed-out caller.

Fault libraries load only into the standalone consumer. Native-call traces verify off-main execution. The gate has a fixture failsafe, and the consumer removes fault injection from its independent reference subprocesses. There are no private SDK test hooks or fault behavior in the product collector.

At source 579e435, [run 44492038416](https://github.com/Sadturtleman/device-readout/actions/runs/44492038416) passed all three scenarios in ARM Debug and both Intel configurations. All four iOS builds and 90 tests in each simulator configuration also passed. ARM Release was canceled at the configured 25-minute job limit. Its final test log reports `testClosingContextReleasesUnusedCoordinatorWhileRegistrationHandleRemainsAlive` as passed, followed by no further test progress; it does not identify the suspended operation. The native consumer step never ran in that job. This is a partial verification result, not a full pass. Swift SDK/test sources at 579e435 are unchanged from the separately verified 9b115ab Linux runs.

## Remaining verification

- Reproduce the intermittent permission-test stall with bounded stack capture and identify its cause; the OS collector is not a claimed fix.
- Finish the current full consumer matrix and audit its exact source/log evidence.
- Add native iOS OS collection with app-owned UI identity state; do not confuse a simulator host kernel/build with its simulated iOS runtime.
- Verify actual Swift 5.9 Apple compilation, minimum OS versions and physical devices.
- Exercise further Darwin boundary cases, including malformed native strings and independent field failures.
- Complete remaining entities, framework bindings and the full SDK acceptance matrix.

A held native call can continue occupying its collection worker until the OS returns. Timeout and context closure provide independent caller completion; they do not forcibly interrupt synchronous native work or provide process crash containment.
