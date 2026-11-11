# Flutter screen ownership and native lifecycle — 2026-11-11

This follows [Android provider lifetimes](2026-11-11-flutter-android-lifetimes.md). It completes failure-slot adoption in the Flutter screen adapters and adds real Android Activity background/resume evidence. The full SDK implementation remains in progress.

## Screen observer changes

Flutter Display and Viewport adapters now use their own `ObserverFailureSource` slots. A failed framework observation reports ReadFailed without overwriting the application's direct failure input. Fresh framework state clears only the adapter's slot; disposal releases that slot. App policy remains until its owner explicitly clears it. As before, failed streams stay ended and recovery requires a new subscription.

Both original adapters overwrote an app-supplied PermissionDenied with their observation error. New public-API tests reproduced this for the Display collection and an individual Viewport target before the fix. They also verify recovery and Display disposal preserve the app's gate. Target-before-collection error precedence remains the common Dart contract; this change does not merge permission status with blocking policy.

A further test reproduced a late Viewport recovery callback after the app had removed a failed target. Clearing the provider's slot raised EntityRemoved into Flutter's framework callback. The adapter now detaches on this terminal condition, releases its slot and ignores later notifications. The old handle remains removed. SDK get/watch/list still never query the view or display APIs, and observer-only reads do not create a native collector.

## Real Android lifecycle verification

The test APK opens a continuous accelerometer watch through `FlutterAndroidSensors` and the existing `FlutterSensorActivityObserver`. Its diagnostic observer records framework notifications but does not inject sensor activity. The host runner uses only the project-owned AVD and its test Activity: it sends Home, observes suspension, then brings that Activity back with NEW_TASK and REORDER_TO_FRONT.

Both API 26 and API 36 recorded:

```text
inactive → hidden → paused → hidden → inactive → resumed
```

While the Activity is paused, a separate get reaches its 150ms deadline without receiving a fabricated sample. The existing watch remains subscribed beyond its configured 300ms read timeout while inactive; the runner holds the background state for another 500ms after the paused get completes. No snapshot is delivered while the diagnostic observer marks the app inactive. On resume, the same watch delivers a non-null sample whose collection-completion time follows the observed resume notification.

The runner independently reads SensorManager diagnostics at three points: an SDK listener exists before backgrounding, none remains while paused, and a listener exists after resume. This verifies native resource release and recreation, not just a Flutter state variable. The test keeps the resumed watch active long enough for the diagnostic check, then cancels it. Existing native disposal, app-policy, six-cycle replacement and delayed-reply process-survival cases still pass.

The tests use Android emulator accelerometer values. They do not establish physical-device measurements, actual sampling frequency, iOS lifecycle behavior, permission-dialog integration, process recreation, long-term background execution or every engine-detachment race. Android app permission gates in earlier scenarios remain explicitly supplied fixture inputs. No production lifecycle change was needed: the existing framework observer/source pipeline passed these real transitions.

## Results and artifacts

| Boundary | Result |
|---|---|
| Flutter package analysis and engine contracts | 16/16, including three new screen failure/removal cases |
| Actual Windows Release screen runner | 5/5; ordinary example rebuilt without the test channel |
| Actual Flutter Android APK on API 26 | 15/15 |
| Same Android lifecycle fixture on API 36 | 15/15 |

The Android suite adds one application lifecycle scenario and one independent native registration scenario to the preceding thirteen. Its final JSON reports include the observed lifecycle sequence. The common Dart runtime, Kotlin collectors and native bridge code were unchanged; their preceding 31/31 Dart and 3/3 bridge evidence was not rerun. Browser, standalone .NET and other-platform tests were also unchanged.

Final logs and reports:

- `.tools/flutter-screen-owner-validation.log`.
- `.tools/flutter-screen-owner-windows-validation.log` and `.tools/flutter-windows-viewport-2685bd5c20e242ce9675ea1c2e591850.json`.
- `.tools/flutter-android-lifecycle-build.log`.
- `.tools/flutter-android-lifecycle-api26-validation.log` and `.tools/flutter-android-lifecycle-api36-validation.log`.
- `.tools/flutter-android-DeviceReadout_API{26,36}-sensors.json`.
- Per-AVD `.tools/flutter-android-DeviceReadout_API{26,36}-lifecycle-{before,paused,resumed}.txt` SensorManager evidence.

Expected failing screen cases are retained in `.tools/flutter-display-owner-red.log`, `.tools/flutter-viewport-owner-red.log` and `.tools/flutter-viewport-retired-owner-red.log`.

Reproduce with `tools/test-flutter.ps1`, `tools/test-flutter-windows.ps1`, `tools/build-flutter-android.ps1` and `tools/test-flutter-android.ps1` as described in the package guide. The Android runner refuses non-project AVDs, validates app/process identity, records failures and stops its test package. Both AVDs used for this checkpoint were shut down after verification.

## Remaining implementation

Follow-up: [Flutter Android state collection](2026-11-11-flutter-android-state.md) now connects thirteen singleton readers and their native state streams. The counts above remain the evidence for this earlier checkpoint; the follow-up records the expanded validation.

Next, connect the existing Android state collectors to Flutter with the same worker-owned get/watch and cleanup contracts. The current Flutter native bridge covers sensors, while standalone Dart still has only its limited Runtime collector. Automatic inventory/metadata observation, capabilities, explicit native permission coordination, other-platform integrations, external package consumption and the complete physical/version/architecture matrix remain required. Swift/Apple and React Native are still pending; these lifecycle results do not narrow that scope.
