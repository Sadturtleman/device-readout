# DeviceReadout for Dart

Implementation foundation, verified with Dart 3.13.7 from Flutter 3.47.9 on Windows x64. This is not yet a complete Flutter plugin or a claim of support for the complete platform matrix.

Windows `get(Entities.locale)` / `watch(Entities.locale)` now read the default formatting locale, distinct user/system/process language lists and NLS/ICU format preferences. The [locale checkpoint](../../docs/verification/2026-11-18-dart-windows-locale.md) passes 66/66 JIT/native contracts, with all eleven fields compared on this host. Process MUI languages do not automatically describe a framework's private locale override; app-local observations and further locale combinations remain required.

On Windows, `get(Entities.timeZone)` and `watch(Entities.timeZone)` collect Windows/IANA IDs, current UTC offset and DST state without modifying app defaults. The [time-zone checkpoint](../../docs/verification/2026-11-18-dart-windows-time-zone.md) records independent native/.NET agreement and final 65/65 JIT/native suites, alongside an earlier unreproduced JIT compiler abort. Other zones, native failures and the complete platform matrix remain unverified.

The [Windows registry boundary checkpoint](../../docs/verification/2026-11-18-dart-windows-registry.md) accepts complete strings at the 64 KiB bound despite extra native sizing allowance. Public get/watch tests cover Unicode, malformed and missing fields, empty strings, oversized values and field recovery. JIT/native suites pass 64/64 each. Collection remains isolate-owned; the complete collector/platform matrix is still pending.

Orientation snapshots return unit quaternions while preserving axes and signs; zero-length or nonfinite rotations are null. get/watch/describe normalize values on the collection isolate and stamp collectedAt afterward. Direct snapshot constructors and SnapshotCodec retain explicitly supplied timestamps, or the epoch default when omitted. The [normalization checkpoint](../../docs/verification/2026-11-17-dart-normalization.md) passes 50/50 JIT and native contracts, Flutter framework checks and rebuilt Android applications.

```dart
import 'package:device_readout/device_readout.dart';

final sdk = DeviceAccess.native();
final fast = sdk.withPollInterval(const Duration(milliseconds: 250));

try {
  final RuntimeSnapshot runtime = await sdk.get(Entities.runtime);
  print(runtime.processArchitecture);

  await for (final snapshot in fast.watch(Entities.runtime).take(3)) {
    print(snapshot.collectedAt);
  }
} finally {
  sdk.dispose();
}
```

The native collector implements `Runtime.processArchitecture` and `Runtime.processBitness`, using the running Dart VM's ABI and native pointer size. On Windows, `Runtime.hostArchitecture` comes independently from `IsWow64Process2`; it remains null on other native operating systems. Supported ABI lists remain null. On Windows it also supports `get(Entities.ram)` and `watch(Entities.ram)`: installed physical bytes, kernel-accessible bytes, available bytes and OS low-memory state. Advertised/free/threshold values remain null. `get(Entities.processMemory)` and `watch(Entities.processMemory)` return the current process's available commit budget as `allocationRemainingBytes`, independently of available physical RAM. `get(Entities.os)` and `watch(Entities.os)` return Windows identity, native NT major.minor.build and the build number; version-source failures leave dependent fields null. `get(Entities.deviceInfo)` and `watch(Entities.deviceInfo)` return manufacturer, model name, board and active NetBIOS computer name; brand/modelCode/product/formFactor remain null. Win32 binding, allocation, collection and cleanup run in the collection isolate; native library references are released with their context. Other native entity reads return `UnsupportedEntity`; generated models do not imply native support.

The [Windows RAM checkpoint](../../docs/verification/2026-11-17-dart-windows-ram.md) passes 54/54 contracts in JIT and compiled execution, an independent OS comparison, repeated-read resource checks and a real Flutter Windows release consumer. The full platform/field/version matrix is still incomplete.

The subsequent [Windows process-memory checkpoint](../../docs/verification/2026-11-17-dart-windows-process-memory.md) passes 55/55 JIT and compiled contracts, including an independent same-process Win32 comparison. `tools/test-dart.ps1` now requires Visual Studio 2022 C++ tools and its CMake component to build this test-only reference DLL; the SDK has no corresponding production dependency.

The [Windows runtime checkpoint](../../docs/verification/2026-11-17-dart-windows-runtime.md) passes 56/56 JIT and compiled contracts with native host architecture. The actual Flutter Windows app passes eight scenarios, including process-memory and runtime comparisons; Flutter framework tests pass 24/24.

The [Windows OS checkpoint](../../docs/verification/2026-11-17-dart-windows-os.md) adds native OS reads and polling, with independent C and CIM version/build comparisons. JIT and compiled contracts pass 57/57 each, the actual Flutter Windows app passes nine scenarios and framework tests pass 24/24.

The latest [Windows DeviceInfo checkpoint](../../docs/verification/2026-11-17-dart-windows-device-info.md) adds four device-information fields with independent Win32/CIM comparisons. JIT and native contracts pass 58/58 each, the actual Flutter Windows app passes ten scenarios and framework tests pass 24/24. Remaining fields, ARM64/emulation, native fault/encoding cases and the full matrix remain pending.

All 46 entity types and `SensorDescription` are generated from the shared schema. Fields are directly nullable, snapshots have one UTC completion timestamp, and collection properties are detached and unmodifiable. Byte counts and signed 64-bit counters use `BigInt`; JSON uses decimal strings. Unknown enums and enum collections containing unknown elements normalize to null. Platform thermal-state enums retain their original meaning.

`get(Entity)` returns a typed `Future`; `watch(Entity)` returns a cold single-subscription `Stream`. Defaults are one-second polling, a five-second read timeout and platform-default sensor sampling. Each successful poll is delivered, including equal values. A stream captures its configuration view. `withPollInterval`, `withReadTimeout` and `withSensorSamplingRate` return new views sharing one owning context. A requested sampling rate applies only to continuous sensor watches; one-shot reads and event sensors use platform defaults.

State polls are serial and schedule the next read after completion. App-observed and native event streams preserve intermediate and duplicate values. Pausing a Dart stream pauses future common polling; observed/native updates wait in bounded queues of up to 2048 entries, with explicit ReadFailed on overflow. Cancellation stops that subscription, and whole-read errors terminate it without automatic retry. App-observed state can replace a native source without surfacing its cancellation.

Pass a `CancellationToken` to `get` for caller cancellation. `dispose()` closes the shared context, including configured views, without waiting for a blocked native call. The caller's deadline and cancellation complete independently; the isolate keeps ownership of resources and disposes them after in-flight native work returns. A permanently stuck native call can prevent that eventual cleanup. Isolates do not provide native-process crash isolation or zero CPU/memory overhead.

Custom native adapters use `DeviceAccess.isolated(topLevelFactory, initialData: sendableData)` and `DeviceCollector`. Construction, reads, normalization and disposal execute in the collection isolate. Use a top-level/static factory; closures can capture unsendable host state. The native request queue admits at most 128 pending read/discovery/capability requests and fails overflow with `ReadFailed`. Expired or cancelled queued work is removed before dispatch. `SnapshotCodec` is the lower-level native-adapter decoder; application queries use typed `Entities`.

An adapter can additionally implement `DeviceStateCollector.watch(address, StateWatchContext)`. Return a `Stream<SnapshotRead>` containing the initial read and subsequent deferred reads, or null to select common polling. Setup, deferred functions and cleanup run in the collection isolate. The context captures cancellation, pollInterval and readTimeout. Each deferred read/normalization has an independent deadline; idle event waiting does not. There can be at most 128 active native state watches per context. `ReadContext.readTimeout` supplies the remaining read budget at dispatch; the host still enforces its own deadline. Cancellation callbacks must be nonblocking; synchronous callback errors are contained so other owners still receive cancellation. The [Flutter Android state adapter](../../flutter/device_readout_flutter/README.md#android-state) uses this interface.

The app owns screen and permission observations. For example, an application observer can supply its already-obtained screen state:

```dart
final screen = sdk.observers.target(Entities.display, 'screen-session-1');
sdk.observers.publish(screen, DisplaySnapshot(pixelSize: Size(width, height)));
sdk.observers.current(Entities.display, screen);

final screens = await sdk.displays.list();
final snapshot = await sdk.get(screen);
sdk.observers.permission(Entities.display, PermissionStatus.granted);

// From the app's source teardown, before disposing the owning SDK context:
sdk.observers.remove(screen);
```

This snippet consumes app-provided dimensions; it does not attach a Flutter observer itself. Publications replace the whole snapshot. Native factory initialization is deferred, so observer-only reads do not instantiate it. Normalization and completion timestamps still run in the isolate. A registered target without its first state waits within readTimeout. Removed handles remain invalid; a reappearing app source needs a fresh identity. Generic `list(kind)` / `current(kind)` and collection helpers use the app-owned inventory when one is registered, otherwise they query the native discovery adapter. An absent native adapter returns UnsupportedEntity rather than a fabricated empty inventory.

## Support information

```dart
final support = await sdk.capabilities.get(Entities.runtime);
// support.readable / support.watchable: bool?
```

True means a connected operation, false means unavailable, and null means the adapter cannot determine support. This is separate from `permissions.check(entity)` and does not guarantee every field or a successful read. Collection kinds and selected handles are accepted; multi-target get/watch still need a selected handle. Removed handles return false/false and foreign handles fail. Queries use the configured readTimeout and accept CancellationToken.

App-owned state/sensor support comes from registration without reading UI, subscribing or requesting permission. Sensors require an explicit source. Native adapters can optionally implement `DeviceCapabilityCollector`; the probe runs in the worker through the shared bounded request queue. Older collectors return null/null without a fallback read. Standalone native Dart reports only Runtime support. Explicit web access queries the connected browser collector; a missing Worker API or unsupported closure-based browser channel reports false/false. See [capability verification](../../docs/verification/2026-11-11-flutter-android-capabilities.md).

## Native discovery

An optional `DeviceDiscoveryCollector` implements `list(EntityKind, ReadContext)` and `current(EntityKind, ReadContext)` in the collection isolate. Return adapter-local string identities; application callers receive typed `Entity<S>` handles and never need to compare those strings. Identities must remain stable while a resource lives; adapters should change them when they can observe removal/replacement. Inventory validation, native calls and cleanup stay on the worker. Each inventory admits at most 4096 unique, nonempty identities of at most 1024 characters. Invalid lists fail atomically without retiring existing handles.

```dart
final volumes = await access.storageVolumes.list();
final current = await access.storageVolumes.current();
if (current != null) {
  final StorageVolumeSnapshot snapshot = await access.get(current);
  final Stream<StorageVolumeSnapshot> updates = access.watch(current);
}
```

Lists are immutable. Live handles are shared across configured views of the same context; another context rejects them. A successful list retires missing native targets. Native EntityRemoved errors and explicit observer removal also retire their generation and end existing watches. Rediscovery creates a fresh handle even if the adapter reuses the same identity. Changes never observed by the adapter or SDK cannot be detected generically. A null native current target remains null; the SDK does not select the first item.

App-owned inventories are not merged with native lists. An app can use `observers.current(kind, discoveredTarget)` to override current selection without erasing the native inventory; null clears that selection. App observer names and native handles occupy separate identity spaces, including their failure/permission state. List/current honor readTimeout, cancellation, context closure and observer failures; a late result cannot undo a cancellation or transient failure. The native context is disposed after outstanding work returns, without joining it on the host. See [native discovery verification](../../docs/verification/2026-11-11-flutter-android-discovery.md).

Report a blocking target/kind failure with `sdk.observers.failure(entity, DeviceReadoutException(ErrorCode.permissionDenied, message))`. This clears cached state, rejects in-flight results and ends streams. Publish fresh state and clear the failure with `failure(entity, null)` to recover for new reads; failed streams never restart themselves.

Adapters should own a separate failure slot: `final source = sdk.observers.failureSource(entity)`. Use `source.publish(error)` or `source.publish(null)`, and call `source.dispose()` on detachment. Clearing or disposing it cannot clear an app's direct failure input or another provider's error. At the same target/collection address, the app's direct input takes precedence; target-specific failures retain precedence over collection failures. Source disposal is idempotent, and a disposed source cannot publish again. See [failure ownership verification](../../docs/verification/2026-11-11-flutter-android-lifetimes.md).

`permissions.check(entity)` reads observed permission state. A target inherits kind-level state unless explicitly overridden, including by null. To request permission, explicitly register the application's nonblocking coordinator with `observers.onPermissionRequest((request) async { ... })` and call `permissions.request(entity)`. The callback receives typed kind/target information and cancellation. Only a separate `observers.permission` update completes the request; callback completion or unrelated screen changes do not. Permission response waits are outside readTimeout. Ordinary read/discovery/watch/check calls never invoke the coordinator. A permission status does not automatically block the whole entity; use the failure input when the operation is actually unavailable.

## App-owned sensor sources

Register a typed target and `SensorObserverSource<PressureSnapshot>` (or another sensor snapshot type) through `observers.sensorSource(target, source)`. Registration and watch construction are inert. Each subscribed watch or get opens a fresh `SensorObserverSession<S>` containing its captured `samplingRate`, `readTimeout`, `cancellation`, `publish(S)` and `fail(DeviceReadoutException)` operations. The common Dart package connects app-owned sources; native plugin connections are supplied separately, including the initial [Flutter Android sensor adapter](../../flutter/device_readout_flutter/README.md#android-sensors).

An observer source can be registered while the entity has a blocking failure. This only prepares its input: get/watch remain blocked and do not subscribe until the policy owner clears its failure. Registration still rejects removed targets and closed contexts.

The source's `subscribe` callback returns an optional cleanup function, synchronously or asynchronously. Both callbacks run on the application's owning isolate and must be nonblocking. They must delegate heavy native work to a worker and never request permission. Publish actual measurements in the shared schema's units and coordinate conventions; the collection isolate normalizes and stamps them. Cancellation closes the session immediately; late asynchronous registration still runs its returned cleanup once. Late callbacks and cleanup errors do not escape the closed operation. Unregistering a source permanently retires its target.

`get(sensor)` waits for a fresh sample within readTimeout; it never replays the last watch sample. Continuous watch waits for its first active sample within readTimeout and then receives actual source samples, including duplicates, without SDK resampling. Event watch waits without an idle timeout or fabricated initial value. A StepDetected/SignificantMotion occurrence must have `value: true`; false or null source events fail with ReadFailed. Each actual normalization/read remains subject to readTimeout. Paused consumers retain up to 2048 pending samples plus in-flight delivery; overflow fails explicitly rather than silently dropping or merging values.

Feed lifecycle policy with `observers.sensorActivity(false/true)`. Inactivity releases sensor sessions and discards pending/late samples; active subscribers resume with fresh sessions and unchanged settings. A get's overall deadline continues while inactive, while watch spends no initial-sample deadline during inactivity. The context initially permits activity, so install the lifecycle owner before opening sensors. For Flutter, use the explicit adapter below; do not map desktop focus loss alone to false. Reentrant lifecycle inputs retain the latest state.

`describe(sensor)` reads the source's optional `SensorDescription` without subscribing, including while inactive. Its kind comes from the typed target, unknown metadata stays null, and normalization plus UTC completion stamping run in the isolate. It observes readTimeout, cancellation, target removal and blocking observer failures. `observers.sensorDescription(sensor, description)` updates registered metadata without restarting measurement sessions; null clears it. Existing snapshots stay immutable. Removed, foreign and unregistered targets are rejected. Native metadata is supplied by an explicit adapter, including Flutter Android.

Remaining platform collectors are pending. The [Flutter adapters](../../flutter/device_readout_flutter/README.md) supply screen/lifecycle observations, twenty Android state readers including native multi-target discovery/current, capabilities and events/polling, and an Android sensor source bridge with automatic connection-driven inventory refresh, metadata updates and explicit refresh. See [inventory verification](../../docs/verification/2026-11-11-flutter-android-inventory.md). Generic native sensor discovery/metadata still uses that explicit sensor adapter. Other native sensor/permission plugin connections remain pending. No Dart read performs screen access or permission UI. Explicit web access connects browser collection and observed normalization through the module worker described below. The closure-based browser isolate path and a runtime without Worker remain unsupported and start no host source.

## Browser use

Native browser state polling waits for typed snapshot handoff before scheduling its next interval. Pausing a subscription retains its pending polling result; other subscriptions and native events remain independent. A completed read does not consume its timeout while delivery is paused. Event overload fails the affected watch explicitly. Deploy this Dart SDK together with the worker asset from the same build. See [delivery verification](../../docs/verification/2026-11-17-dart-watch-delivery.md) for sixteen scenarios per Chrome/Edge and 51/51 native/JIT contracts.

Large input/output graphs and typed collections are prepared across event-loop turns, with cancellation/deadline checks between traversal slices. The 128 active-read limit includes preparation through typed delivery; excess demand fails explicitly. Streams preserve order and duplicates with a bounded delivery queue. Browser cloning, allocation and application callbacks can still perform synchronous work. See the [transfer scheduling evidence](../../docs/verification/2026-11-17-dart-web-transfer.md) for the 12,000-mode checks and remaining limits.

Serve the built `packages/web/dist/dart-worker.js` module with your application. The web package also exposes this asset as `@device-readout/web/dart-worker`; package publication and automated Flutter asset packaging remain pending. Then pass its served URL explicitly:

```dart
final sdk = DeviceAccess.web(
  workerUri: Uri.base.resolve('/device-readout-dart-worker.js'),
);
final cpu = await sdk.get(Entities.cpu);
final stream = sdk.withPollInterval(const Duration(seconds: 2)).watch(Entities.cpu);
// Dispose the shared context when the owning application scope ends.
sdk.dispose();
```

Construction and creating a stream are inert. A context starts one module worker on its first collection operation. Reads use the existing browser collectors; screen, permission, lifecycle and sensor inputs remain explicit app observers. Their values are normalized in the worker before typed Dart snapshots are returned. Whole unsupported APIs fail explicitly, while individual unavailable fields remain null. Native discovery is only available where the underlying collector implements it; app-owned collections use the same typed handles as native Dart.

`DeviceAccess.isolated` cannot transfer a Dart closure into a browser worker and remains unsupported there. If the browser has no Worker API, web access reports unavailable support and collection fails without host-side fallback. Worker loading/protocol failures are typed and do not silently restart the context. See the [web checkpoint](../../docs/verification/2026-11-17-dart-web-worker.md) for verification and the remaining browser/Flutter-web matrix.

Run from the repository root:

```powershell
./tools/test-dart.ps1
./tools/test-dart-browser.ps1
# Or supply a Dart executable from the required Flutter release:
./tools/test-dart.ps1 -DartPath 'C:/path/to/flutter/bin/cache/dart-sdk/bin/dart.exe'
```

The script generates models, resolves the dependency-free package offline, analyzes it, runs fifty contract checks in JIT and compiled executables, and compiles/runs the web branch's negative host-collection check. The native runtime assertion is currently specific to the Windows x64 validation environment. See the [native discovery](../../docs/verification/2026-11-11-flutter-android-discovery.md), [native state streams](../../docs/verification/2026-11-11-flutter-android-state.md), [foundation](../../docs/verification/2026-11-11-dart-foundation.md), [state/permission observers](../../docs/verification/2026-11-11-dart-observers.md), [sensor/lifecycle](../../docs/verification/2026-11-11-dart-sensors.md) and [failure ownership](../../docs/verification/2026-11-11-flutter-android-lifetimes.md) records.
