# Flutter Android state collection and native streams — 2026-11-11

This checkpoint connects thirteen existing Android singleton collectors to Flutter's typed `DeviceAccess.get(Entity)` and `watch(Entity)`. It follows [screen ownership and Android lifecycle verification](2026-11-11-flutter-observer-lifecycle.md). The full 46-entity, multi-platform scope remains unchanged.

## Connected interface

`FlutterAndroidDeviceAccess.create()` returns a common Dart DeviceAccess with a lazy background collector. Create it from the application's existing root isolate/binding. Construction does not query Android. Configured views retain the existing immutable poll, read-timeout and sensor-rate settings.

| Singleton entities | Connection |
|---|---|
| DeviceInfo, Os, Runtime, Cpu, Ram | Existing Kotlin Android readers |
| Locale, TimeZone | Existing regional readers and their event/poll behavior |
| AndroidBuild, AndroidIdentity, HardwareSerial | Existing identity readers and typed permission failures |
| Power, NetworkPath, NetworkPerformance | Existing native event/poll state flows |

This is a mapping count, not a claim that all fields are available. The ordinary test application receives PermissionDenied for HardwareSerial. ProcessMemory remains UnsupportedEntity. No identifier value is printed in the test report. Native multi-target state discovery is not connected in this checkpoint; the seven remaining Android state mappings require that work. The existing seventeen sensor mappings still use explicit `FlutterAndroidSensors.attach(access)` and their app-owned lifecycle inputs.

Screen state and permission status remain observer inputs. No read/watch/list performs screen access, requests permission, initializes Flutter's binding or changes application settings. Network collection requires the application's ACCESS_NETWORK_STATE manifest declaration; the debug verification application declares it explicitly. The library does not prompt or add runtime consent.

## Execution and stream contract

The common Dart collector seam now optionally implements `DeviceStateCollector.watch(address, context)`. It returns a stream of deferred `SnapshotRead` functions including the initial state, or null to select common serial polling. This is an adapter interface; application queries remain typed get/watch. Collection setup, deferred reads, normalization and disposal execute in the collection isolate. `ReadContext.readTimeout` carries the remaining budget at dispatch to native bindings; the independent host deadline remains authoritative.

The native state stream captures poll/read settings, retains equal updates, preserves paused delivery order and reports bounded-source overflow as ReadFailed. Waiting for a later native event has no idle read timeout. Each deferred read/normalization has an independent caller-side deadline, including when the collection isolate is synchronously blocked. The initial state deadline also covers startup. Source teardown and shared-context disposal do not join blocked work. A get performs a fresh read instead of replaying a watch value.

The Flutter adapter uses a background BinaryMessenger and a background Android MethodChannel task queue. Kotlin's existing collection lane owns OS reads, state event registration and cleanup. Native streams wait on events or the existing Kotlin polling fallback; a pending `next` response is not a polling query. Platform JSON decoding stays in the Dart worker. A shared factory future prevents concurrent read/watch startup from creating duplicate collectors.

Cancellation closes native sessions and cancels pending reads. The Dart collector drains all issued platform responses before its isolate exits, retaining the earlier late-reply crash fix. The application does not wait for that drain. A native reply that never finishes can retain worker resources; isolates do not isolate native process crashes or provide zero CPU/memory cost.

Two defects were reproduced and fixed during this connection:

- Switching a watch to app-observed state exposed the retired native source's cancellation. The observer input now replaces the native source without leaking its cancellation into the application stream.
- A synchronous exception in an adapter's cancellation callback stopped subsequent cancellation listeners and source teardown. Cancellation callbacks now contain synchronous errors and continue notifying owners. The same access context remains usable, and worker disposal completes. Callbacks must still be short and nonblocking; this does not claim containment of arbitrary unawaited asynchronous work.

## Validation

| Execution | Final result |
|---|---|
| Dart strict analysis, JIT and native AOT | 37/37 contracts in each execution mode |
| Dart web negative boundary | Unsupported collection never starts a host factory |
| Flutter package analysis and engine contracts | 16/16 |
| Android bridge JVM contracts | 5/5: three sensor and two state tests |
| Actual Flutter Android APK, API 26 | 20/20 |
| Same APK, API 36 | 20/20 |
| Actual Windows Release screen runner | 5/5; ordinary example rebuilt afterward |

The six added Dart contracts exercise cold native streams and captured settings; app-observer replacement; a blocked deferred update with an independent deadline and host heartbeat; native read-budget propagation; pause/order/duplicate delivery and source overload; and cancellation-callback failure containment. These use deliberately controlled collectors through the public collector/get/watch seams.

Native state protocol tests verify an initial snapshot, an equal native update after the read-timeout duration but before polling, typed PermissionDenied, subscription release, explicit read cancellation, and an independent timeout while an uninterruptible fixture read remains pending. Context disposal finishes before that native fixture returns. These are controlled protocol tests, not physical-device evidence.

The Android application exercises twelve successful singleton reads and expected HardwareSerial denial. Three OS polls preserve equal values and fresh timestamps. A Power watch uses a one-minute poll interval and 500ms read timeout; the runner waits more than 500ms and changes only the owned AVD's simulated power source. The native event arrives without waiting for polling and without an idle timeout. The runner refuses a preexisting battery override and restores its own change on success or failure. Post-run checks confirmed automatic battery updates were restored on both AVDs.

The host independently compares Android API level, model name and kernel RAM with `getprop` and `/proc/meminfo`. API 26 reports 2,096,115,712 kernel-accessible bytes; API 36 reports 2,067,742,720. These are emulator values, not physical RAM claims. Existing native sensor discovery, app-policy ownership, real Activity pause/resume, listener release/restoration, blocked-worker heartbeat and late-reply process-survival scenarios remain in the twenty checks. Actual sensor measurements still center on accelerometer.

The longer result report exposed Android log truncation. The test harness now sends bounded, numbered base64 fragments and validates complete reconstruction before accepting the report. This change affects test reporting, not the SDK transport. Only project-owned test AVDs/app processes were controlled; both AVDs were shut down after verification.

Final evidence:

- `.tools/dart-native-state-stream-validation.log`.
- `.tools/flutter-native-state-engine-validation.log`.
- `.tools/flutter-android-state-native-validation.log`.
- `.tools/flutter-android-state-build.log`.
- `.tools/flutter-android-state-api26-validation.log` and `.tools/flutter-android-state-api36-validation.log`.
- `.tools/flutter-android-DeviceReadout_API{26,36}-sensors.json` plus per-AVD power/lifecycle/SensorManager diagnostic files.
- `.tools/flutter-native-state-windows-validation.log` and `.tools/flutter-windows-viewport-5ca2870880f746c39a6a432ca08f032c.json`.

Expected failing cases remain in `.tools/dart-native-state-handoff-red.log` and `.tools/dart-native-state-cancellation-red.log`. Reproduce with the Dart/Flutter/Android scripts in the [package guide](../../flutter/device_readout_flutter/README.md). The validated Android toolchain remains Gradle 8.14.3, AGP 8.11.1, Kotlin 2.2.20 and compile/target SDK 36; future-floor warnings are not bypassed.

## Remaining implementation

Follow-up: [native discovery and target lifetime](2026-11-11-flutter-android-discovery.md) connects the seven multi-target state mappings and records the expanded validation. The thirteen-mapping and test counts above remain evidence for this earlier checkpoint.

Connect native multi-target state discovery/read/current and preserve handle generations through removal/reappearance. Complete capabilities, automatic sensor inventory/metadata observation, native permission coordination, further lifecycle/engine-detach races, full transport saturation/malformed-input coverage and independent package consumption. The Flutter plugin still references shared Kotlin source sets in the monorepo. Standalone Dart still supplies only two native Runtime fields. Swift/Apple, React Native, other Flutter platform collectors, the web worker bridge and the complete physical/version/architecture matrix remain required. This checkpoint is not a release-completion claim.
