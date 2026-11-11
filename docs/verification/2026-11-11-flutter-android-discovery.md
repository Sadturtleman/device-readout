# Flutter Android native discovery and target lifetime — 2026-11-11

Follow-up: [capability query verification](2026-11-11-flutter-android-capabilities.md) adds Dart/Flutter Android support probes and records the expanded 47 Dart, 7 protocol and 27-per-AVD suites. Counts and pending work below describe this earlier discovery checkpoint.

This checkpoint adds native list/current and selected-target get/watch for seven Android state collections. Flutter now connects all twenty existing Kotlin Android state mappings plus the seventeen sensor mappings. This is a binding count, not complete field, hardware or platform support. It follows [singleton state and native streams](2026-11-11-flutter-android-state.md); the full 46-entity, multi-platform design remains required.

## Connected behavior

The newly connected state collections are CpuCore, Battery, NetworkInterface, StorageVolume, WifiConnection, CellularSubscription and TelephonyIdentity. Applications use the existing typed list/current/get/watch interfaces through `FlutterAndroidDeviceAccess.create()`. Native current selection follows the Kotlin collector; CPU cores and logical telephony slots have no invented default. Screen and permission state remain app-owned observer inputs.

The common Dart collector can optionally implement `DeviceDiscoveryCollector`. List/current share the existing serial collection queue and caller deadline/cancellation machinery with reads. OS access, inventory validation and cleanup execute in the collection isolate; Flutter platform calls use its background messenger and Kotlin's collection lane. The bounded inventory admits 4096 unique, nonempty identities of at most 1024 characters. A malformed inventory fails before handle reconciliation and does not retire healthy targets.

Live handles remain stable across repeated discovery and immutable configuration views of the same context. Native missing-target errors, observed absence in a successful inventory and explicit observer removal retire old generations. Existing watches receive EntityRemoved without waiting for their next poll. Rediscovery creates a fresh handle, even when the adapter reuses its identity. Native adapters remain responsible for identifying removals that occur between SDK queries; entirely unobserved physical replacement is not generically detectable.

The Android bridge owns opaque, context-scoped target IDs and validates the entity kind for selected queries. A handle from another context or the wrong collection is rejected. List/current/read each have a cancellable request ID and a timeout covering native protocol work, including waiting for inventory coordination. Sessions still retain native event/poll behavior and background reply draining before Dart worker exit.

App-owned inventories take precedence and are not merged with native lists. Explicit observer selection of a discovered native target preserves the native inventory; null clears the selection. In-flight discovery rejects caller cancellation and observer failure, including failure followed immediately by recovery. Late results cannot reverse those outcomes or mutate handle generations.

Three defects were reproduced and fixed while adding this path:

- App-observed removal originally left the native identity cache pointing to the retired handle. It now retires the native generation before rediscovery.
- Selecting a native target through the observer incorrectly claimed an empty app inventory. Current selection and inventory ownership are now separate.
- String-based local handle names could collide with app observer names. Native handles now use private identity objects, and target-specific errors use those identities. App names, native source names and native generations cannot alias each other.

No SDK read/list/watch requests permission, queries Flutter screen properties, or changes system/network settings. ACCESS_NETWORK_STATE is declared by the debug fixture. NetworkInterface discovery additionally requires the app's INTERNET manifest permission for Android interface enumeration; the collector sends no probe traffic.

## Final validation

| Execution | Result |
|---|---|
| Dart strict analysis, JIT and native AOT | 43/43 in each execution mode |
| Dart web negative boundary | Native discovery also fails without invoking the host collector |
| Flutter package analysis and engine tests | 16/16 |
| Native Android bridge JVM tests | 6/6 |
| Actual Flutter Android APK on API 26 | 25/25 |
| Same APK on API 36 | 25/25 |
| Native Windows Release screen runner | 5/5; ordinary example rebuilt afterward |

The six added Dart contracts cover typed discovery/selection, scoped and stable handles, removal/reappearance, malformed inventories, terminating existing watches after removal, blocked list/current deadlines, nonjoining disposal, observer inventory/selection ownership, late result rejection after cancellation or transient failure, and app/native identity separation. Controlled collectors execute in real isolates. These establish the common runtime contract, not physical hotplug behavior.

The native protocol tests add selected CPU targets, current selection, equal-value selected polling, wrong-kind/cross-context rejection and removal/reappearance. The existing blocked-native test now checks all three operations (read/list/current) for both explicit cancellation and timeout. Native work remains pending when caller completion and context disposal finish; the fixture then releases that work. The preceding sensor/state protocol cases remain included.

The actual APK exercises:

- CPU discovery with stable handles, per-core reads, null default selection and selected-target polling. Both AVDs report logical indices 0 and 1, matching the independent kernel `cpu/present` inventory.
- Storage discovery/current identity and a positive app-data volume capacity. Capacity is a native-query result, not an independently corroborated filesystem-capacity claim.
- Selected battery reads and network-interface reads. Reported interface names are independently checked for membership in `/proc/net/dev`; this is not a proof that every kernel interface must be exposed to an application.
- Wi-Fi, cellular and logical-slot discovery and ordinary-app selected reads, preserving permission outcomes. No Wi-Fi or identifier field value is copied into the report.
- The preceding singleton reads, Power event timing, sensor discovery/measurements, real Activity pause/resume, app-policy ownership, replacement, host heartbeat, native registration cleanup and late-reply process survival.

| Ordinary-app outcome | API 26 | API 36 |
|---|---|---|
| Wi-Fi inventory | One target | One target |
| Selected Wi-Fi get | PermissionDenied | Typed snapshot returned; individual field availability is not established by this check |
| Cellular subscription inventory | PermissionDenied | PermissionDenied |
| Logical modem slot inventory | One target | One target |
| Selected restricted identity get | PermissionDenied | PermissionDenied |

The first API 26 host comparison failed because adb shell could not stat the `/sys/class/net` links. The application scenarios had completed, but the runner correctly recorded failure. The final runner uses the independently readable `/proc/net/dev` table on both OS versions, without elevating the Android shell. Both final runs pass all twenty-five scenarios.

Only owned test AVDs/app processes were controlled. The existing Power fixture restored automatic battery updates on success and failure; post-run checks confirmed restoration. Both AVDs were shut down after validation. No production native collector writes settings or configures interfaces.

## Evidence and reproduction

- `.tools/dart-discovery-validation.log`.
- `.tools/flutter-discovery-engine-validation.log`.
- `.tools/flutter-android-discovery-native-validation.log`.
- `.tools/flutter-android-discovery-build.log`.
- `.tools/flutter-android-discovery-api26-validation.log` and `.tools/flutter-android-discovery-api36-validation.log`.
- `.tools/flutter-android-DeviceReadout_API{26,36}-sensors.json` and the existing lifecycle/SensorManager diagnostic files.
- `.tools/flutter-discovery-windows-validation.log` and `.tools/flutter-windows-viewport-7bbc5174c9454a28a28a22f651b367a4.json`.

Expected failures are recorded in `.tools/dart-discovery-red.log`, `.tools/dart-discovery-observer-red.log`, `.tools/dart-discovery-current-owner-red.log`, `.tools/dart-discovery-identity-red.log` and `.tools/flutter-android-discovery-native-red.log`. Reproduce using `tools/test-dart.ps1`, `tools/test-flutter.ps1`, `tools/test-flutter-windows.ps1`, `tools/build-flutter-android.ps1` and `tools/test-flutter-android.ps1`, as documented in the [Flutter guide](../../flutter/device_readout_flutter/README.md).

## Remaining work

Native capabilities, automatic sensor inventory/metadata observation, native permission coordination, simultaneous mixed state/sensor workloads, further lifecycle/engine-detach races, actual target hotplug and full transport/field coverage remain pending. Review native/app identity ownership in the other language runtimes as their integrations expand. The Flutter plugin still references monorepo Kotlin source sets; external package consumption is unverified. Standalone Dart still provides only two native Runtime fields without a platform adapter. Swift/Apple, React Native, other Flutter platform collectors, the web worker bridge and the complete physical/version/architecture matrix remain required. The overall goal is still active.
