# Flutter Android sensor connection — 2026-11-11

This connects the [Dart sensor foundation](2026-11-11-dart-sensors.md) to the existing Kotlin/Android SensorManager collectors. The full SDK goal remains active. Physical hardware, full sensor-kind coverage through Flutter, platform lifecycle/permission transitions and independently distributable plugin packaging remain incomplete.

Follow-up: [provider lifetimes](2026-11-11-flutter-android-lifetimes.md) records owned failure slots, invalid refresh validation and a disposal crash found and fixed on API 26. It supersedes this initial checkpoint with 31 Dart contracts and 13 Android scenarios per API 26/36. The initial counts below are historical evidence.

## Implemented path

`FlutterAndroidSensors.attach(access)` explicitly creates an Android sensor source owner for an existing DeviceAccess context. The app attaches its Flutter lifecycle observer first. Native discovery supplies typed targets and SensorDescription inputs; applications use the existing `access.list(Entities.accelerometer)`, `get(target)`, `watch(target)` and `describe(target)` interfaces. `refresh(kind)` re-enumerates a sensor collection, preserving live handles and retiring observed missing targets. Discovery currently refreshes explicitly, not on every generic list call.

All 19 schema sensor kinds are considered during attachment. The bridge reuses the existing Android adapter's 17 mappings; RelativeAltitude and HumanPresence remain UnsupportedEntity. Missing devices produce a known empty inventory. Unsupported/denied kinds are exposed through typed collection failures; they do not prevent attachment of independent available sensor kinds. Metadata is captured during discovery and normalized again at describe time, without starting sensors. It is not a new native metadata query on every describe.

Each get/watch opens its own native Kotlin Flow subscription with its captured sampling rate and read timeout. `SensorObserverSession.readTimeout` now exposes the operation's immutable deadline setting to native adapters. Get/event sources use platform-default sampling; continuous watches use their configured request. No adapter requests permission or bypasses Android's restrictions. Actual source failures retain common typed errors.

The execution path is:

| Work | Owner |
|---|---|
| Initial app lifecycle/permission observations | Explicit app callbacks |
| Channel requests, JSON decoding, native metadata/snapshot conversion | Dedicated Flutter background isolate |
| Platform message handling and response encoding | Background task queue / coroutine dispatcher |
| Native discovery, registration, normalization and resource release | Existing Kotlin collection worker and Android sensor callback lane |
| Final Dart snapshot normalization and UTC completion stamp | Existing Dart collection isolate |
| Small source forwarding callback and final stream delivery | Application isolate |

Flutter background isolates cannot install unsolicited platform message handlers. The bridge therefore issues a `next` request whose response waits for an actual queued native event. This is event-driven waiting, not timer polling. Android's MethodChannel.Result permits responses from a background thread. See [Flutter channel threading](https://docs.flutter.dev/platform-integration/platform-channels#channels-and-platform-threading), [background messenger restrictions](https://api.flutter.dev/flutter/services/BackgroundIsolateBinaryMessenger/setMessageHandler.html) and [MethodChannel.Result](https://api.flutter.dev/javadoc/io/flutter/plugin/common/MethodChannel.Result.html).

One pending next request is permitted per native session. Native delivery queues are bounded to 2048 entries and fail explicitly on overflow. A per-session acknowledgement allows only one unconsumed sample message to the application isolate; the Dart SDK also retains its existing bounded source queue. Comprehensive transport saturation and failure interleavings still need dedicated validation.

Closing a source cancels its pending native receive and subscription without joining a blocked registration. A late successful registration retains worker-owned cleanup. Plugin detachment fails outstanding replies, including a coroutine cancelled before its body starts. Disposing the Flutter adapter retires registered targets, closes active watches and schedules native-context disposal. App callbacks and worker scheduling have overhead; neither the bridge nor isolates provide native-process crash isolation.

## Verified results

Pinned environment: Flutter 3.47.9, Dart 3.13.7, Gradle 8.14.3, Android Gradle Plugin 8.11.1, Kotlin plugin 2.2.20, coroutines 1.10.2, compile/target SDK 36, minimum SDK 26. The x86_64 debug APK runs on project-owned API 26 and API 36 Google APIs AVDs. Gradle's cached archive matches the official SHA-256, which is pinned in the wrapper. Flutter accepts these build versions but emits warnings that its future toolchain floors will increase; no dependency-validation bypass is used.

`tools/test-dart.ps1` passes **28/28** in JIT and compiled native execution, plus strict analysis and the web negative boundary. Its settings case now verifies that a configured seven-second read timeout reaches the sensor source session. `tools/test-flutter.ps1` passes **13/13** existing engine contracts after importing the Android adapter.

`tools/build-flutter-android.ps1 -NativeUnitOnly` passes **3/3** bridge contracts through its protocol operations:

1. A deliberately uninterruptible native registration runs off the caller. Close completes within a separate 200ms bound; a pending next ends, and a late resource is released on its registration worker.
2. An event sensor waits beyond a 200ms read timeout without fabricated events, uses platform-default sampling, rejects a second simultaneous next request, preserves duplicate occurrences and propagates PermissionDenied.
3. Native inventory refresh preserves live opaque IDs, rejects foreign-context IDs, retires missing targets and allocates a new ID after reappearance. Closed contexts reject discovery.

The final APK passes **7/7 scenarios on API 26 and 7/7 on API 36**:

| Scenario | Direct evidence |
|---|---|
| Discovery and metadata | Actual SensorManager accelerometer target; typed kind and native name |
| Fresh get | Non-null native vector and UTC completion timestamp |
| Continuous watch/cancel | Three actual samples requested at 60Hz; consumer cancellation |
| Stable discovery | Explicit unchanged inventory refresh preserves the original Dart handle |
| Host responsiveness | A separate fixture blocks the Dart collection isolate for 600ms; Flutter main-isolate heartbeat progresses and a sensor get times out at 150ms before the fixture returns |
| Active adapter disposal | A live watch ends with EntityRemoved and the retired target cannot be read |
| Native registration/release | Independent `dumpsys sensorservice` shows the SDK listener while the app is collecting and no SDK listener after disposal, before force-stopping the test app |

Accelerometer values here are Android emulator sensor values, not physical-device measurements. The delayed RAM collector is an explicit isolation fixture, not an Android RAM implementation. Native event/permission/removal edge cases above use controlled collector inputs; these do not prove physical Android permission dialogs or hardware hotplug.

## Reproduce and evidence

```powershell
./tools/test-dart.ps1
./tools/test-flutter.ps1
./tools/build-flutter-android.ps1 -SdkRoot 'C:/path/to/Android/Sdk' -NativeUnitOnly
./tools/build-flutter-android.ps1 -SdkRoot 'C:/path/to/Android/Sdk'
# Start a project-owned DeviceReadout_API26 or DeviceReadout_API36 AVD first.
./tools/test-flutter-android.ps1 -SdkRoot 'C:/path/to/Android/Sdk' -Serial emulator-5584
```

The runner validates the AVD identity, installs only the example package, reads logs for its exact process, checks native sensor state and stops only that package. It does not alter sensor values or permissions. The two AVDs started for this checkpoint were shut down after validation.

Evidence lives in `.tools/dart-sensor-native-timeout-validation.log`, `.tools/flutter-android-source-validation.log`, `.tools/flutter-android-bridge-validation.log`, `.tools/flutter-android-build.log`, `.tools/flutter-android-native-validation.log` and `.tools/flutter-android-api26-validation.log`. Per-AVD JSON reports and active/released SensorManager dumps are `.tools/flutter-android-DeviceReadout_API{26,36}-sensors.json` and the corresponding `-active-sensors.txt` / `-released-sensors.txt` files.

Initial red analysis is recorded in `.tools/flutter-android-sensor-red.log` and `.tools/dart-sensor-timeout-source-red.log`. Two fixture issues were corrected: PowerShell interpreted adb's `-W`/`-d`/`-v` as function parameters, so arguments now use explicit arrays; the delayed-native fixture now deliberately ignores Java interruption before checking late cleanup. These were fixture defects, not failed native sensor field mappings.

Disk pressure initially prevented AVD launch. The already-extracted Flutter download archive and inactive project-AVD boot snapshots were removed after verifying paths and absence of running emulators. SDK binaries, AVD user data, source and verification records were retained. No user AVD or external project was cleaned.

## Remaining work

- Verify all mapped kinds through Flutter, actual requested/observed frequency behavior, physical units/frames and real mobile background/foreground and permission transitions.
- Complete automatic/native discovery observation, metadata refresh semantics and capabilities. The follow-up implements failure ownership and refresh input validation; simultaneous inventory ownership by several adapters remains unverified.
- Exercise worker exit, engine detach/reattach, simultaneous cancellation/failure and every queue's saturation. The native protocol tests do not directly simulate Flutter engine detachment.
- Package the shared Kotlin dependency for external consumers. The current Gradle source sets reference the monorepo's existing Kotlin sources; this is not a standalone published pub package. No package was published.
- Add Flutter state collectors and remaining platform plugins, the web worker bridge, Swift/Apple, React Native and the full version/architecture/package-consumption matrix.

The ordinary Windows example and its five screen scenarios remain prior evidence; they were not rerun for this Android-only integration. TypeScript, standalone .NET and standalone Android suites were also unchanged.
