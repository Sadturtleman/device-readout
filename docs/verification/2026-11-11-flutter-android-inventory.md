# Flutter Android sensor inventory observation — 2026-11-11

The explicitly attached Android sensor adapter now observes dynamic sensor connection changes and refreshes the affected typed collection. App-owned screen, permission and lifecycle observers remain the source of UI-dependent state. SDK get/watch/list operations do not request permission or query UI properties. This checkpoint extends the [shared-context verification](2026-11-11-flutter-android-mixed.md); the complete multi-platform implementation goal remains active.

## Behavior

Attachment registers the native inventory observer before initial discovery. Android registers its DynamicSensorCallback with a dedicated Handler, and native registration, enumeration and cleanup remain on background execution paths. Android documents this callback/Handler facility in [SensorManager](https://developer.android.com/reference/android/hardware/SensorManager#registerDynamicSensorCallback(android.hardware.SensorManager.DynamicSensorCallback,android.os.Handler)). It reports connection changes; it is not a general metadata-property notification API.

Native invalidations coalesce by entity kind in a bounded queue. The Flutter worker forwards one invalidation at a time and waits for acknowledgement after refresh. An invalidation arriving during a manual refresh forces a subsequent fresh inventory read. This coalescing concerns inventory invalidations only: measurement samples retain their existing duplicate-preserving streams and explicit overload behavior. Idle waiting for inventory notifications has no read deadline.

`FlutterAndroidSensors.refresh(kind)` remains available. Each inventory request's configured readTimeout covers native inventory coordination, enumeration and all metadata reads. Timeout and disposal return without joining an uncooperative native operation. Complete native inventory validation and metadata preparation precede binding/retirement; malformed identities, duplicates and oversized inventories fail as a whole. Final publication and context disposal are coordinated so a closed context cannot acquire late bindings.

Live targets retain their typed handles and measurement subscriptions across metadata updates. `access.observers.sensorDescription(target, description)` supplies new metadata without restarting a source; null clears metadata. `describe` still normalizes and stamps on the SDK worker, and previously returned snapshots remain immutable. Observed disappearance permanently retires a handle. Reappearance or explicit app retirement creates a fresh public generation; callbacks belonging to an earlier registration cannot retire its replacement.

Refresh failures use the provider's own failure slots. A later successful refresh can recover a transient inventory read failure without clearing application policy. A terminal inventory-observation failure remains terminal for that adapter, including when an earlier read subsequently succeeds; explicitly detach and attach a new owner to recover. A collector without optional inventory observation retains explicit discovery. This optional Kotlin seam is currently internal to the shared-source Flutter build, not a published third-party plugin ABI.

## Reproduced defects and regressions

| Failure | Correction and evidence |
|---|---|
| An old native sensor object sharing a numeric sensor ID ended a current measurement subscription | Disconnect matching now uses the selected native object and ignores closed subscriptions. The controlled Android SensorManager service reproduces the old failure and passes after the correction. Continuous and trigger disconnect paths use the same rule; the same-ID regression directly exercises the continuous path. |
| An explicitly retired app handle poisoned the next otherwise valid inventory refresh | Fresh per-registration generations replace retired handles; a captured old removal callback cannot retire the replacement. Flutter engine regression reproduced the failure before the fix. |
| A successful inventory arriving after terminal observation failure erased that failure | Recheck terminal state after the asynchronous read before applying results. The engine regression fails before this check and passes afterward. |
| Native list ignored the caller's timeout and could wait behind a blocked metadata query | One deadline encloses coordination and all native work. Both queued and active callers finish with ReadTimeout while the native fixture remains blocked; disposal also returns before its release. |
| Native duplicate/empty/oversized identities reached metadata work and binding | Validate the complete inventory first. Invalid results fail with ReadFailed, perform no metadata queries and preserve prior handles. |

Additional controlled cases cover 20,000 repeated invalidations, duplicate receive rejection, typed callback failure, late notifications after cleanup, off-main registration/callback/cleanup, observed disconnect/reconnect between list calls, metadata changes without resubscription, app policy preservation, disposal during refresh, and late native registration cleanup on its original worker after timeout. The metadata observer contract also covers null clearing, invalid/foreign/unregistered/removed targets and worker normalization.

## Results

| Verification | Result |
|---|---|
| Dart public contracts, JIT and compiled native | 48/48 in each mode; analyzer and web unsupported-boundary check pass |
| Flutter engine contracts | 22/22; analyzer passes |
| Kotlin core contracts | 21/21 |
| Android service contracts | 15/15 |
| Flutter Android native bridge contracts | 12/12 |
| Android AAR, instrumentation APK and lint | Passed |
| Flutter Android example analysis and APK build | Passed |
| Actual API 26 x86_64 APK | 33/33 |
| Actual API 36 x86_64 APK | 33/33 |
| Changed Dart files and local documentation links | Formatting unchanged; 103 links across eight documents pass |

The actual APK runs exercise native inventory observer registration and teardown alongside the existing state/sensor queries, shared-context workloads, actual Activity pause/resume, repeated disposal and late-reply process survival. Both use the new runtime. Independent SensorManager diagnostics corroborate application sensor listener release/restoration. They do not emulate physical dynamic sensor attachment: changed inventories and metadata use the controlled service/transport fixtures above. Five Windows screen scenarios remain prior-checkpoint evidence and were not rerun for these sensor changes.

Commands are `tools/test-dart.ps1`, `tools/test-flutter.ps1`, `tools/build-android.ps1`, `tools/build-flutter-android.ps1 -NativeUnitOnly`, `tools/build-flutter-android.ps1` and `tools/test-flutter-android.ps1` on each owned AVD, with the explicit installed SDK path. Flutter is 3.47.9 / Dart 3.13.7; the Android Flutter toolchain remains the one recorded in its package README. Future-floor build warnings were not bypassed.

Artifacts under `.tools`:

- `dart-sensor-metadata-validation.log`, `flutter-inventory-engine-final.log`, `android-inventory-full-validation.log`, `flutter-android-inventory-native-final.log`, `flutter-android-inventory-build.log`.
- `flutter-android-inventory-api{26,36}-validation.log`, `flutter-android-inventory-api{26,36}.json`, and `flutter-android-inventory-api{26,36}-lifecycle-{before,paused,resumed}.txt`.
- Failing regressions: `android-inventory-service-red.log`, `flutter-sensor-inventory-owner-red.log`, `flutter-inventory-failure-red.log`, `flutter-inventory-deadline-red.log`, `flutter-inventory-validation-red.log`.

An initial emulator launch failed its disk-space check. Only the unused boot-memory cache files under the project's stopped API 26/36 AVDs were removed; app data and device configuration were retained. This recovered the space needed for sequential execution. The two validation runs restored their temporary battery simulation, force-stopped their owned app and shut down the owned AVD. Other running emulators were left alone.

## Remaining scope

Physical sensor hotplug and metadata changes, full sensor-kind coverage, engine-detach and transport saturation interleavings, native permission coordinators, other Flutter platforms, minimum-version/package consumption, Swift/Apple, React Native and the complete field/version matrix remain required. Dynamic connection callbacks do not promise notification of arbitrary property changes on an already-connected device; manual refresh remains available. Worker separation prevents the demonstrated UI blocking and preserves deadlines; it does not provide process isolation from arbitrary native crashes or guarantee indefinite background execution.
