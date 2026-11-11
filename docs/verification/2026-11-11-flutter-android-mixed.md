# Flutter Android shared state/sensor context — 2026-11-11

Follow-up: [sensor inventory observation](2026-11-11-flutter-android-inventory.md) adds automatic dynamic-connection refresh and metadata updates, and reruns the 33 APK scenarios on both APIs with the changed runtime. Counts and pending work below describe this earlier checkpoint.

This checkpoint verifies representative native state and sensor workloads through one public `DeviceAccess`. Previously, the actual APK exercised native state and sensor normalization in separate access contexts. The new harness connects both Android adapters to the same Dart access context and normalization worker. The adapters still own their separate native channel contexts; this is not a claim that they share one Kotlin collector.

The production runtime required no change for these scenarios. The Android integration harness, lifecycle probe, runner expectations and documentation changed. The full 46-entity, multi-platform implementation goal remains active.

## Verified interactions

| Scenario | Evidence from the running APK |
|---|---|
| Concurrent native and sensor work | OS and selected CPU-core polling coexist with two native accelerometer watches. Concurrent RAM/core/sensor get, CPU discovery, native capabilities and sensor metadata return typed native values. |
| Individual subscription cancellation | Cancelling one sensor watch and the CPU-core watch leaves the other sensor watch and OS stream delivering values. Cancelled subscriptions receive no further values. |
| Scoped failure | An ordinary-app HardwareSerial PermissionDenied does not terminate either remaining watch. A selected-sensor observer failure terminates that sensor watch with the original typed error while OS polling continues. Clearing the app failure permits a fresh sensor watch. |
| Paused sensor deadline | During a real Activity pause, sensor get reaches its 150ms deadline. The same public access still obtains another OS stream snapshot and a positive native RAM value before resumption. |
| Existing lifecycle scenario strengthened | The same sensor watch resumes fresh values without inactive delivery. Other shared state/sensor watches remain usable. Independent SensorManager diagnostics show the test app's registrations removed while paused and restored after resume. |
| Provider replacement | Detaching the sensor adapter ends its watch with EntityRemoved while OS polling continues. Reattachment creates a fresh sensor handle, keeps the retired handle unavailable and preserves the selected native CPU handle. Disposing the retired adapter again does not affect its replacement. |
| Whole-context disposal | With both an OS watch and a sensor watch active, disposing the common access terminates each once with DeviceReadoutCancelled. Subsequent adapter cleanup succeeds, and the remaining independent-context test scenarios still run. |

The real lifecycle scenario moved from the earlier controlled blocked-collector context to this native shared context. Six additional scenario assertions expand the existing suite from 27 to 33: 28 application checks and five host-side corroboration checks. The deliberate blocked-collector test remains separate and continues to verify the main-isolate heartbeat and independent sensor deadline.

The app records real framework lifecycle events. The host sends Home and restores only the owned test Activity; it checks native registrations before, during and after that transition. System/launcher sensor registrations can remain while paused: the assertion concerns the test app's registrations. The native Power fixture still restores its temporary AVD battery override.

## Results and artifacts

| Execution | Result |
|---|---|
| Flutter 3.47.9 / Dart 3.13.7 example analysis and Android APK build | Passed |
| Actual API 26 x86_64 APK | 33/33 |
| Actual API 36 x86_64 APK | 33/33 |
| PowerShell runner syntax, Dart formatting and local documentation links | Passed |

Commands: `tools/build-flutter-android.ps1 -SdkRoot C:/Users/rugsn/AppData/Local/Android/Sdk`, followed by `tools/test-flutter-android.ps1` with that SDK path for each project-owned AVD. The test app is force-stopped after evidence collection and late-reply survival checking. Both AVDs were shut down after restoration checks.

Local artifacts under `.tools` are `flutter-android-mixed-build.log`, `flutter-android-mixed-api26-validation.log`, `flutter-android-mixed-api36-validation.log`, `flutter-android-mixed-api26.json`, `flutter-android-mixed-api36.json`, and `flutter-android-mixed-api{26,36}-lifecycle-{before,paused,resumed}.txt`.

The preceding [capability checkpoint](2026-11-11-flutter-android-capabilities.md) remains the evidence for 47 Dart JIT/AOT contracts, 16 Flutter engine contracts, seven native bridge contracts and five Windows screen cases. Those unchanged production components were not rerun solely for this harness extension. Both Android APK runs include their previous state/discovery/capability/sensor checks, repeated disposal, independent OS/kernel comparisons and process survival after late native replies.

## Remaining scope

This establishes representative shared-context interactions on two emulators, not the complete concurrency or hardware matrix. Requested sensor rates are not asserted as exact delivery frequencies. Short Activity-background observations do not guarantee indefinite execution under mobile OS suspension. Full transport overload, engine detach, physical hotplug/sensor coverage, automatic inventory/metadata refresh, native permission coordination, external packaging, other Flutter platforms, Swift/Apple, React Native and the complete field/version matrix remain required. No SDK query requests permission or reads UI state; explicit app-owned observers still supply screen, permission and sensor lifecycle inputs.
