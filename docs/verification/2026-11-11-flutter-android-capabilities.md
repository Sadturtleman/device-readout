# Dart and Flutter Android capability queries — 2026-11-11

Follow-up: [shared state/sensor context verification](2026-11-11-flutter-android-mixed.md) expands the actual APK suite to 33 cases on each API 26/36. Counts and pending work below describe the capability checkpoint.

This checkpoint adds `access.capabilities.get(entity)` to Dart and connects the existing Android state support probes through Flutter's background bridge. The 46-entity, multi-platform implementation goal remains active. It follows [native discovery and target lifetime](2026-11-11-flutter-android-discovery.md).

## Public behavior

`EntityCapabilities` has immutable nullable booleans `readable` and `watchable`. True means the operation has a connected implementation; false means unavailable; null means the adapter cannot determine support. Support is independent of permission, temporary read failures, and individual field coverage. A supported entity can still return partial snapshots or PermissionDenied. Polling counts as watch support.

The query accepts singleton entities, collection kinds and selected typed handles. A collection-level answer concerns availability of that kind; get/watch still require a selected handle for a multi-target entity. Foreign-context handles fail with InvalidConfiguration. Retired handles return false/false without probing a replacement. Immutable configuration views retain their own readTimeout and share target ownership.

App-observed state support comes from target/state registration; it does not wait for a first value. Sensor support requires a registered `SensorObserverSource`. An explicit empty app inventory, a sensor without its source, or a removed source reports false/false. Paused activity and denied permission do not erase implementation support. Probing does not subscribe, invoke the permission coordinator, initialize UI bindings, or read screens. App registry checks are small host-side bookkeeping; native probes run in the collection isolate.

Custom adapters may implement `DeviceCapabilityCollector.capabilities(address, ReadContext)`. Existing collectors without this optional interface return null/null without performing a read. The standalone Dart collector reports only Runtime support. Because this Dart runtime still consumes sensors through explicit sources, native sensor metadata alone cannot advertise a usable sensor path. The absent Dart web worker bridge reports false/false even for registered inputs; get/watch continue to reject unsupported collection without host execution.

## Native bridge and lifetime

Native probes share the bounded serial request queue, remaining dispatch budget, caller cancellation and lifetime cancellation used by reads/discovery. The configured deadline includes queue waiting. A blocked probe does not block host timers or force the caller/disposal to join native work. Cleanup stays worker-owned and waits for outstanding native work and platform replies. Removal during a pending query cancels it and returns false/false; a late positive answer cannot revive the target.

The Android state protocol accepts capability requests for all known entity names, routes the twenty connected state mappings to Kotlin's existing support probe, and reports false/false for other mappings. Selected IDs retain context and kind validation. Collection queries do not invoke the generic list operation or bind public handles. A native presence probe can still inspect hardware inventory; TelephonyIdentity checks logical modem slots on its collection worker. Nullable booleans survive the platform codec; malformed replies fail with ReadFailed instead of becoming default support. Sensor availability is supplied by the separately attached app-owned sensor adapter.

A missing-source defect was reproduced while extending the tests: querying an unattached sensor kind could initialize the native factory and accept an unusable native support answer. The common Dart query now resolves that case from explicit source registration. The original red test and the missing-API/protocol red tests remain in local artifacts.

## Verification

| Execution | Result |
|---|---|
| Dart 3.13.7 strict analysis, JIT and native AOT | 47/47 in each execution; analysis clean |
| Dart web boundary | Compiled and passed; no host factory/source startup |
| Flutter 3.47.9 engine contracts | 16/16 |
| Android JVM protocol contracts | 7/7 |
| Actual Flutter Android APK, API 26 x86_64 | 27/27 |
| Actual Flutter Android APK, API 36 x86_64 | 27/27 |
| Actual Windows Release screen runner | 5/5; ordinary example rebuilt |

Four added Dart cases cover passive/worker-owned queries, permission separation, nullable support, collection/selected/scoped handles, registration/removal, unsupported web/runtime boundaries and blocked probes. The blocked probe fixture checks timeout, explicit cancellation, context disposal and target removal while host heartbeat continues. Native work remains pending when callers finish; disposal occurs afterward on its owning worker.

The Android protocol tests verify no reads or observation setup during probes, unknown support, unconnected entities, selected IDs, foreign/wrong-kind rejection and removal. The existing blocked-native test now covers read/list/current/capabilities for both timeout and explicit cancellation.

Both APK runs add native support/permission separation and selected target retirement/rebinding. Existing sensor cases also check support after explicit attachment and after disposal. Earlier native state fields, CPU/interface corroboration, Power events, actual Activity pause/resume, independent SensorManager registration checks, repeated disposal and late-reply process survival still pass. Simulated removal is an explicit observer removal, not physical hotplug evidence. Native fields remain partial and platform-dependent.

Artifacts are local under `.tools`: `dart-capabilities-validation.log`, `dart-capabilities-red.log`, `dart-capabilities-sensor-red.log`, `flutter-capabilities-engine-validation.log`, `flutter-android-capabilities-native-validation.log`, `flutter-android-capabilities-native-red.log`, `flutter-android-capabilities-build.log`, `flutter-android-capabilities-api26-validation.log`, `flutter-android-capabilities-api36-validation.log`, `flutter-android-capabilities-api26.json`, `flutter-android-capabilities-api36.json`, `flutter-capabilities-windows-validation.log` and `flutter-windows-viewport-b0011e326e69474fa24c5003dcb772e2.json`.

Only project-owned AVDs/test processes were controlled. Both battery overrides were restored and the AVDs shut down after validation. No permission prompt, production setting change or package publication was added. Isolates provide execution separation, not native crash isolation or zero overhead.

Native permission coordination, automatic sensor inventory/metadata refresh, simultaneous mixed native state/sensor workloads, further engine-detach/overload cases, actual target hotplug, complete field/physical coverage, external packaging, Swift/Apple, React Native, other Flutter platforms and the full version matrix remain pending. Other runtime native/app identity ownership still needs its separate audit.
