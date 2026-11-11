# Flutter Android provider lifetimes — 2026-11-11

This follows the [initial Android sensor bridge](2026-11-11-flutter-android-sensors.md). It fixes invalid refresh input, failure ownership and a native process abort during adapter disposal. The full 46-entity and all-binding implementation goal remains active.

Follow-up: [screen ownership and native lifecycle](2026-11-11-flutter-observer-lifecycle.md) adopts owned failures in both Flutter screen adapters, contains a late removed-target callback, and verifies real Activity background/resume on API 26/36. It raises the Flutter engine suite to sixteen and the Android suite to fifteen per API; counts below describe this earlier checkpoint.

## Failures belong to their observer source

`access.observers.failureSource(entity)` creates an `ObserverFailureSource`. Its `publish(error)` supplies a blocking failure for that target or collection; `publish(null)` clears only its own slot. `dispose()` removes that slot and is idempotent, including after context closure. Publishing after disposal fails with DeviceReadoutCancelled.

An application's direct `observers.failure(entity, error)` input is independent. Within the same target/collection address it takes precedence over provider-owned failures. Existing target-before-collection lookup remains unchanged. One provider cannot clear another provider's failure, and late cleanup cannot erase a replacement owner's slot. Permission status and blocking failure remain separate inputs: a permission observation alone does not automatically disable every operation.

Failures invalidate cached state, end existing streams and reject in-flight reads. Immediate recovery or source disposal cannot revive an already-invalidated result. New state reads need fresh observed data after failure; ended streams do not restart automatically.

Sensor source registration is now allowed while a blocking failure is present. Registration remains inert: neither get nor watch starts that source until the application's policy permits collection. This lets an adapter prepare fresh observer inputs without clearing a caller's gate. Removed handles and closed contexts remain rejected.

The Android adapter owns one failure slot per sensor kind. Successful refresh and disposal affect only those slots. Refresh accepts canonical typed sensor collections, rejecting a bound target or other entity before native work and state mutation. Live inventory keeps its handles; reattachment creates fresh identities and cannot revive retired handles. Use one native sensor adapter at a time per context; simultaneous inventory ownership by several adapters remains outside this verified path.

## Disposal keeps pending response ports alive

The first API 26 run aborted after active sensor disposal with `platform_message_response_dart_port.cc(53): Check failed: did_send` and SIGABRT. This was a product failure, not a successful test or an emulator installation problem. The [pinned Flutter 3.47.9 engine source](../../.tools/flutter-3.47.9/flutter/engine/src/flutter/lib/ui/window/platform_message_response_dart_port.cc) checks that it can post a platform reply to the background isolate's Dart port.

The adapter previously exited its background isolate after the native context-dispose reply. That reply does not order other pending next/close/inventory replies. A later reply could therefore target a port that had already closed. The background worker now tracks every issued platform call, requests native context disposal, then waits for those replies to settle before exiting. New collection has already stopped, and no native reply is sent through application UI code.

Application `dispose()` remains synchronous and does not join this background drain. If a native reply never arrives, the response receiver must remain alive; caller cancellation and deadlines still complete independently. This fixes the observed premature-exit path, not arbitrary native-process crash isolation. Engine detachment, engine recreation and all transport overload interleavings still need separate validation.

## Verification

All final runs use the same toolchain and Android x86_64 debug runner as the preceding record: Flutter 3.47.9, Dart 3.13.7, min SDK 26 and compile/target SDK 36.

| Boundary | Result |
|---|---|
| Dart strict analysis, JIT and compiled native contracts | 31/31 in each execution mode |
| Dart web negative boundary | Passed; no host collector invoked |
| Existing Flutter engine contracts and analysis | 13/13 |
| Actual Flutter Android APK, API 26 | 13/13 scenarios |
| Same APK, API 36 | 13/13 scenarios |

Three new Dart contracts cover independent failure owners and cache invalidation; inert sensor registration under app policy; and immediate source recovery/disposal while a native read is blocked. The last case rejects the old read without waiting for the native call to return.

The Android suite retains the original seven discovery, measurement, cancellation, stable-handle, responsiveness, disposal and native-listener scenarios. Six additions verify:

1. A rejected bound-target refresh leaves the previously usable sensor readable.
2. Native refresh preserves the original app-owned PermissionDenied; only the app can clear it.
3. Detachment removes the adapter's UnsupportedEntity while preserving an independent provider's failure. An app-owned RelativeAltitude source can subsequently supply a fresh measurement.
4. Reattachment under an existing app gate prepares sources without clearing policy; new handles work after explicit recovery and old handles stay removed.
5. Six attach/watch/refresh/dispose cycles finish active watches and pending inventory reads while platform replies may still be in flight.
6. After the result and native listener cleanup, the runner waits two seconds and verifies that the same test process is alive with no fatal native failure.

The runner independently inspects SensorManager registrations and verifies their release before stopping its own app. Any failed run now writes a failed JSON report, including crashes/timeouts, instead of leaving an earlier passing report in place. Both project-owned AVDs were stopped after final validation.

Native measurements are emulator accelerometer samples. The replacement altitude value and permission failures are explicit application inputs; they are not physical altitude measurements or Android permission-dialog evidence. Six disposal cycles and the two-second survival check are finite regression evidence, not an exhaustive concurrency proof. Kotlin bridge sources were unchanged, so their preceding 3/3 protocol result remains prior evidence; Windows/browser/.NET suites were not rerun for this change.

## Evidence and remaining scope

Run the existing `tools/test-dart.ps1`, `tools/test-flutter.ps1`, `tools/build-flutter-android.ps1` and `tools/test-flutter-android.ps1` commands from the preceding record. The final artifacts are:

- `.tools/dart-failure-source-validation.log` and `.tools/flutter-failure-source-validation.log`.
- `.tools/flutter-android-ownership-build.log`.
- `.tools/flutter-android-ownership-api26-validation.log` and `.tools/flutter-android-ownership-api36-validation.log`.
- `.tools/flutter-android-DeviceReadout_API{26,36}-sensors.json` and the corresponding active/released SensorManager dumps.

Expected failing evidence is retained in `.tools/dart-failure-source-red.log`, `.tools/dart-blocked-source-red.log`, `.tools/flutter-android-refresh-red.json`, `.tools/flutter-android-policy-red.json` and `.tools/flutter-android-disposal-crash-red.log`.

Next work includes adoption of owned failures in other adapters, actual mobile lifecycle/permission transitions, engine detachment and transport saturation, automatic inventory/metadata observation, complete field/kind/physical-device coverage and independent plugin packaging. Swift/Apple, React Native, remaining Flutter platforms and the full support matrix remain required. This checkpoint does not narrow the design or mark the SDK complete.
