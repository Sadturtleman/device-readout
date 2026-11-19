# Swift native Power partial-read failure

This checkpoint verifies the existing nullable-field contract when the public macOS power snapshot function fails. It follows the [native cancellation checkpoint](2026-11-19-swift-power-cleanup.md).

## Native boundary and public behavior

Apple's [public IOPowerSources header](https://github.com/apple-oss-distributions/IOKitUser/blob/main/ps.subproj/IOPowerSources.h) documents that IOPSCopyPowerSourcesInfo returns NULL on error. A test-only dylib injects that return value at the native function boundary. The separate SwiftPM consumer imports DeviceReadout and uses ordinary get/watch calls; it supplies no app-owned Power snapshot and uses no internal SDK test hook.

The consumer verifies:

- Power capabilities still report readable and watchable.
- get returns powerSource=nil while powerSaveMode and Apple thermalState remain available.
- watch delivers its initial snapshot and a subsequent snapshot with powerSource=nil, preserving the other fields and advancing collectedAt.
- At least three native snapshot calls reach the fixture off the main thread, and MainActor continues.

The fixture's constructor marker and native-call trace prevent a missing injection from counting as a successful test. The actual IOKit cancellation path and both earlier cleanup scenarios continue to execute in separate consumer processes. Product sources are unchanged by this verification addition.

## Results

Source **500a739** passes [Apple run 27](https://github.com/Sadturtleman/device-readout/actions/runs/44486763043).

| Boundary | Verified result |
| --- | --- |
| macOS ARM64 Debug and Release | 92/92 tests per configuration, ordinary SwiftPM consumer, both native cancellation scenarios and partial-read failure consumer |
| macOS Intel Debug and Release | The same complete set passes in both configurations |
| iOS device/simulator SDK builds | Four successful builds |
| iOS simulator Debug and Release | 90/90 tests per configuration |
| Source and evidence audit | All 588 non-Markdown inputs match the capture; job source SHAs, test counts, native traces and consumer reports match |
| Minimum Swift compiler evidence | The unchanged Swift SDK/test sources match 6327056, whose Swift 5.9.2 Linux Debug/Release suites each pass 88/88; this does not test the macOS-only fixture on that compiler |

Each macOS partial-read report records sourceNull, otherFieldsPreserved, freshSnapshots and callerProgress as true, with two watch snapshots. The trace records the failed native snapshot calls with main=0. The full audit retains the earlier genuine cancellation-refusal regression and source-notification regressions as separate evidence.

Raw logs and the source/evidence audit remain in the main worktree's ignored `.tools/apple-power` directory. The fixture branch retains `.tools/apple-ci/source-500a739.json`.

## Remaining scope

This injection covers an explicit NULL return. It does not establish detection of hidden AC fallbacks inside other IOKit functions, unknown source strings, malformed native data, held native registration, multiple cancellation refusals, physical power/thermal transitions or minimum Apple OS execution. The intermittent permission stall remains unresolved despite passing isolated, full-suite, fresh-build and separate-consumer repetitions. The remaining native entities, framework adapters and the complete five-binding/platform acceptance matrix are still required.
