# DeviceReadout for Flutter

Windows network watch now uses the shared Dart native-notification bridge with polling for remaining fields. The [notification checkpoint](../../docs/verification/2026-11-18-dart-windows-network-events.md) rebuilds and verifies both checkout and installed Windows consumers at 18/18 scenarios each, with 27/27 framework checks. The bridge is part of the ordinary Windows native asset; reference/fixture DLLs are excluded. Physical network transitions and the complete platform matrix remain pending.

Windows network-interface discovery/get/watch uses the shared Dart isolate collector. The [initial network checkpoint](../../docs/verification/2026-11-18-dart-windows-network.md) compares all nine fields for 84 NDIS entries and 61 routes in both checkout and installed-Pub apps; each passes 18/18 scenarios and framework checks pass 27/27. Its polling baseline is extended by the notification follow-up above; physical transitions and the full platform matrix remain pending.

Windows `cpuCores.list()` uses the shared Dart collector for typed logical-CPU get/watch, membership and clock fields. The [CPU-core checkpoint](../../docs/verification/2026-11-18-dart-windows-cpu-cores.md) passes 17/17 scenarios in both checkout and installed-Pub Windows applications, with full native membership comparisons and timer progress; framework tests pass 27/27. Physical topology changes and the full platform matrix remain pending.

The [CPU native follow-up](../../docs/verification/2026-11-18-dart-windows-cpu-native.md) verifies the current CPU collector in both checkout and independently installed Pub consumers: 16/16 Windows app scenarios each and 27/27 framework checks pass. Native empty-list handling is corrected and the Dart gate includes seventeen CPU response/stall cases per execution mode. Other architectures, physical configurations and the full platform matrix remain pending.

Windows `Entities.cpu` uses the shared isolate-owned Dart collector for identity, topology and process-default availability. The [upload checkpoint](../../docs/verification/2026-11-18-upload-storage-cpu.md) passes 16/16 actual checkout Windows app scenarios, including independent CPU field comparisons and timer progress during polling. Installed CPU consumers and other platform/configuration combinations remain pending.

The [native storage follow-up](../../docs/verification/2026-11-18-dart-windows-storage-native.md) preserves Win32 errors in a Windows-only code asset and fixes malformed optional metadata. Flutter build hooks compile and bundle the production helper automatically. Both checkout and installed-Pub Windows applications pass 15/15; framework checks pass 27/27. An installed Android consumer builds without the Windows DLL; other platform runtimes and physical storage transitions remain pending.

Windows local storage volumes are available through typed `storageVolumes.list()` handles and the shared Dart collector. The [storage checkpoint](../../docs/verification/2026-11-18-dart-windows-storage.md) verifies independent capacity/metadata agreement, explicit app current-volume selection and polling in the actual Windows release app: 15/15 scenarios and 27/27 framework checks pass. Native fault/removal and other storage environments remain pending.

Windows `Entities.power` is available through the shared Dart collector, with isolate-owned get/watch and no additional platform plugin. The [power checkpoint](../../docs/verification/2026-11-18-dart-windows-power.md) passes 14/14 actual Windows release-app scenarios and 27/27 framework tests. Current source/saver values match native references; battery/UPS transitions, native faults and installed Windows consumer coverage remain pending.

The [locale platform follow-up](../../docs/verification/2026-11-18-flutter-locale-platforms.md) verifies the observer on actual Android API 26/36 and Chrome/Edge applications, both from checkout and separately installed Pub archives. Android passes 34/34 per device and consumer; web passes ten application scenarios per browser and consumer. These development packages remain unpublished; physical devices, Apple applications and further browsers/versions remain unverified.

`FlutterLocaleObserver.attach(access, state: valueListenable)` connects app-captured `FlutterLocaleState` to `Entities.locale`. Publish the selected Localizations scope from the app lifecycle; get/watch do not query UI state. The observer preserves supplied language-list scopes, handles failures and releases its source on dispose. See the [integration example and verified contract](../../docs/verification/2026-11-18-flutter-locale-observer.md): 27/27 framework checks and 13/13 actual Windows release-app scenarios pass. Other application platforms and external consumers remain to be verified.

Windows `Entities.locale` is available through the shared Dart collector when no app state source is attached. Its native scope is the user's formatting preferences and user/system/process MUI languages. The preceding [native locale checkpoint](../../docs/verification/2026-11-18-dart-windows-locale.md) compares eleven current fields and records 12/12 release-app scenarios plus 24/24 framework tests. Further native locale/configuration combinations remain pending.

Windows `DeviceAccess.native()` also supports `Entities.timeZone` through the shared Dart collector. The [time-zone checkpoint](../../docs/verification/2026-11-18-dart-windows-time-zone.md) verifies all four current fields against independent native sources and preserves timer progress during polling. The rebuilt release application passes 11/11 and framework tests pass 24/24. Actual DST transitions, other zones/native failures and the full platform matrix remain pending.

The [Windows registry boundary follow-up](../../docs/verification/2026-11-18-dart-windows-registry.md) fixes 64 KiB DeviceInfo string handling in the shared Dart collector. Rebuilt Flutter Windows release-app tests pass 10/10 and framework tests pass 24/24; standalone Dart JIT/native suites pass 64/64 each, including six native registry scenarios. Other platform results below were not rerun for this Windows-only change.

On Windows, `DeviceAccess.native()` reads and watches `Entities.ram`, `Entities.processMemory`, `Entities.runtime`, `Entities.os` and `Entities.deviceInfo` through the common Dart collector, with no additional Flutter platform plugin. The latest [Windows DeviceInfo checkpoint](../../docs/verification/2026-11-17-dart-windows-device-info.md) passes ten actual release-app scenarios covering native device metadata, memory, host/process architecture, OS version/build, screen observations and worker deadlines. Independent native queries corroborate the new fields; standalone Dart tests also compare manufacturer/model/board against CIM. DeviceInfo brand/modelCode/product/formFactor remain null. Framework tests pass 24/24; Android results remain those of the preceding RAM/package checkpoints. ARM64/emulation, remaining fields/collectors and the complete platform matrix remain pending.

For browser applications, create `final access = FlutterWebDeviceAccess.create();` after Flutter initialization. The factory resolves the bundled collection-worker asset; `workerUri:` optionally selects an explicitly served worker. Attach the existing observers and dispose the access context with its application owner. Checkout web builds run `npm run build` and `node tools/prepare-flutter-web.mjs` first; `tools/build-flutter-web.ps1` performs both steps. Prepared package consumers receive the asset automatically.

The [web hosted-package checkpoint](../../docs/verification/2026-11-17-flutter-web-packages.md) passes actual Pub downloads, analysis, two release builds and nine application scenarios per Chrome/Edge browser, including nested routes and a separate same-origin asset base. Reproduce with `tools/test-flutter-web-packages.ps1`; checkout builds use `tools/test-flutter-web.ps1`. Framework tests pass 24/24, and the rebuilt installed Android app passes 33/33 scenarios on each API 26/36 with the web asset excluded from its APK. Content-hashed/cross-origin deployments and additional browsers remain unverified.

The [Android hosted-package checkpoint](../../docs/verification/2026-11-17-flutter-android-packages.md) verifies actual Pub downloads of this plugin and the Dart SDK into an independent consumer. The installed APK passes 33/33 scenarios on each API 26/36 emulator; framework 22/22 and native bridge 12/12 checks also pass. The local package fixture does not publish to pub.dev.

For checkout development, the plugin declares the common SDK by version and the checked-in `pubspec_overrides.yaml` selects its local path. The example has its own override because dependency overrides are not inherited. Android build helpers stage canonical Kotlin source under `android/shared` before compilation; `node tools/prepare-flutter-native.mjs` performs that step when invoking Flutter/Gradle directly from the repository. Staged native files are included in prepared package archives but ignored by Git.

`tools/build-flutter-packages.ps1` builds an independent Android app using actual hosted Pub resolution against a GET-only loopback fixture; `-Platform Web` builds the browser applications. The archive includes the common Kotlin runtime, Android collectors and web worker, so an installed consumer has no source path into this checkout. Add `-InstalledPackage` to `tools/test-flutter-android.ps1` to test that APK. Both pubspecs retain `publish_to: none`; registry publication remains pending.

The [Dart watch-delivery checkpoint](../../docs/verification/2026-11-17-dart-watch-delivery.md) adds per-subscription browser polling handoff and preserves completed reads across consumer pauses. It reruns all 22 framework checks and rebuilds the actual Flutter web applications, which pass the rendered-example case and six integration scenarios in each Chrome/Edge browser. Earlier Android/native-screen evidence below remains unchanged.

The Flutter adapters explicitly observe application viewports, engine-exposed displays and app lifecycle state for sensor activity. An Android plugin connects twenty Kotlin state collectors, including seven multi-target kinds, and seventeen sensor mappings. Native support queries and app-source registration are available through `capabilities.get(entity)`. Flutter 3.47.9 / Dart 3.13.7 passes twenty-two engine checks, twelve native bridge contracts and thirty-three Android state/sensor scenarios on each API 26/36. Five Windows screen scenarios remain prior-checkpoint evidence. Native connection callbacks now refresh sensor inventories and metadata; see [inventory verification](../../docs/verification/2026-11-11-flutter-android-inventory.md). Real Activity background/resume has framework and native sensor-registration evidence. Physical measurements, native permission integration, other lifecycle transitions and the complete platform matrix remain pending.

The [Dart normalization checkpoint](../../docs/verification/2026-11-17-dart-normalization.md) reruns all 22 framework checks and rebuilds the Android APK, which passes 33/33 scenarios on each API 26/36. The native bridge unit suite and Windows screen scenarios retain their earlier evidence.

Import `package:device_readout_flutter/device_readout_flutter.dart`; it also exports the common Dart SDK. Attach from the widget/view lifecycle after the binding exists:

```dart
final observer = FlutterViewportObserver.attach(
  access,
  view: View.of(context),
);

final viewport = await access.get(observer.entity);
final snapshots = access.watch(observer.entity);

// If this is the current view for the application:
access.observers.current(Entities.viewport, observer.entity);

// Dispose the observation before disposing its owning access context.
observer.dispose();
```

The adapter creates a typed viewport handle, copies initial state and registers a `WidgetsBindingObserver`. Only attachment, metrics notifications and system text-scale notifications query the view. SDK get/watch/list operate on observed state; normalization and snapshot timestamping remain in the collection isolate. No polling timer, permission request, layout mutation, renderer invocation or global callback replacement is used by the adapter.

| Field | Mapping |
|---|---|
| `size` | `FlutterView.physicalSize / devicePixelRatio`, in logical pixels |
| `safeAreaInsets` | `FlutterView.viewPadding / devicePixelRatio`, independent of keyboard viewInsets |
| `textScaleFactor` | `PlatformDispatcher.textScaleFactor`, the system-reported scalar preference |
| `visualViewportSize` | null; not derived from keyboard occlusion |
| `visualViewportScale` | null; device pixel ratio is not a visual-viewport zoom factor |

Nonpositive/nonfinite device pixel ratio leaves dependent fields null. A zero viewport size remains zero. The scalar text-scale field does not describe an app-specific or nonlinear `TextScaler` at every font size.

Each attachment has a fresh context-local identity. `current()` stays null unless the app selects a target. The supplied view must be the exact currently registered view object. Attachment rejects stale objects even when their ID has been reused. The adapter also checks registered view identity on notifications: removal or replacement retires the old SDK handle before reading its fields. Disposing removes the framework observer and retires the handle. Attach a new observer for a new view lifetime.

Source exceptions are published as typed ReadFailed observer failures, invalidating cached state and ending streams. A later successful Flutter notification publishes fresh state and clears only the adapter's failure slot; failed streams require an explicit new subscription. App-supplied target or collection failures remain independent and are never cleared by adapter recovery/disposal. An already-removed target causes a late recovery callback to detach safely rather than throw into Flutter. App permission coordination remains the explicit Dart `permissions` / `observers.permission` path; this adapter opens no permission UI.

## Displays

Create one Display collection owner per DeviceAccess context. Configuration copies share that context. The app explicitly chooses which registered view determines the current display:

```dart
final displays = FlutterDisplayObserver.attach(access);
final targets = await access.displays.list();
displays.selectView(View.of(context));
final current = await access.displays.current();
if (current != null) {
  final screen = await access.get(current);
  final updates = access.watch(current);
}
displays.selectView(null);
displays.dispose();
```

`selectView` and initial/framework callbacks read Flutter's reported inventory. Ordinary get/watch/list/current calls do not query Flutter. Display object replacement during a metrics update preserves the handle for the same live Flutter display ID. Observed absence retires the handle permanently; reappearance creates a fresh handle. Missing or replaced selected views clear current selection. A stale view object cannot be selected again under a reused ID. Disposing retires this adapter's targets and unregisters its framework observer.

| Display field | Mapping |
|---|---|
| `pixelSize` | Native: positive finite whole-pixel `Display.size`; unavailable/invalid dimensions leave the whole field null. Web: null because the pinned engine reports CSS screen dimensions, not physical mode pixels |
| `scaleFactor` | Positive finite `Display.devicePixelRatio` |
| `currentMode` | Windows only: current pixel size and positive `Display.refreshRate` above the Windows 0/1 unspecified sentinel; null when mode rate is unavailable |
| All other fields | null; no invented monitor origin, primary status, physical DPI, maximum rate or supported mode list |

The pinned Windows engine obtains its refresh rate from `EnumDisplaySettings(ENUM_CURRENT_SETTINGS)`. Other engines can expose rendering cadence instead of physical mode rate; their `currentMode` remains null pending adapter-specific mapping. Each optional property failure is independent. A failed or malformed inventory produces ReadFailed in the adapter's own collection failure slot, invalidates previous state and ends affected streams. Fresh successful observation or disposal clears only that slot, preserving app policy and independent providers' failures. The collection's state and current selection still require one inventory owner per context.

The list contains only displays the Flutter engine exposes, which can be a subset of the OS inventory. `current()` follows Flutter's association for the app-selected view. On this Windows host, the initially hidden runner briefly reported a pre-parenting monitor association; a real metrics update after native parenting corrected it. The SDK does not poll or move windows to correct source timing. Apps that require a settled initial association should select their registered view from the appropriate view lifecycle/metrics observation. Other-platform display availability and physical monitor transitions still need validation.

## Sensor activity

Attach one lifecycle owner per shared DeviceAccess context before opening sensors:

```dart
final lifecycle = FlutterSensorActivityObserver.attach(access);
// Register app-owned sensor sources and use access.get/watch/describe.
// Dispose this observer before disposing the owning access context.
lifecycle.dispose();
```

The adapter copies the initial binding state once, then consumes `WidgetsBindingObserver.didChangeAppLifecycleState`. SDK queries never re-read lifecycle state. It does not initialize a binding, request permission or install sensor plugins. The adapter uses these activity rules:

| Flutter lifecycle | Mobile / web | Native desktop |
|---|---|---|
| resumed | Collect | Collect |
| inactive | Suspend | Keep collecting |
| hidden / paused / detached / unknown initial state | Suspend | Suspend |

Desktop inactive means visible windows without focus; hidden means all views are hidden. These meanings follow [Flutter AppLifecycleState](https://api.flutter.dev/flutter/dart-ui/AppLifecycleState.html). The desktop branch includes Windows, macOS and Linux, but this is not a claim of complete Linux or Apple SDK support. Web policy is declared; the Dart Web Worker bridge is still absent, so sensor queries remain UnsupportedEntity.

Inactivity closes each app source session and invalidates pending samples without ending the public watch. Resumption opens fresh sessions with their captured sampling settings. `get` still obeys its overall deadline. Disposing the observer detaches it and suspends sensor sources; existing watches stay pending until cancelled or their SDK context closes. If the SDK closes first, a subsequent callback detaches safely. Use one owner, including across configuration copies, and do not independently overwrite the same activity input.

App source setup/cleanup remains a small nonblocking app-side callback; native sensor work belongs in a worker. The common Dart SDK performs normalization in its isolate. See [Dart sensor source contracts](../../dart/device_readout/README.md#app-owned-sensor-sources). Framework notifications may skip states or disappear when a process is killed; this adapter consumes observed states and does not synthesize lifecycle polling.

On the project API 26/36 AVDs, real Activity pause/resume notifications release and recreate the native SensorManager listener. The same watch resumes without delivering samples while inactive; a get while paused still reaches its own deadline. This is verified for those transitions, not arbitrary background execution or process recreation. See [screen and lifecycle verification](../../docs/verification/2026-11-11-flutter-observer-lifecycle.md).

## Android state

Create the Android access context from the application's existing root isolate after its binding is ready:

```dart
final access = FlutterAndroidDeviceAccess.create();
final RamSnapshot ram = await access.get(Entities.ram);
final Stream<PowerSnapshot> powerUpdates = access
    .withPollInterval(const Duration(seconds: 2))
    .withReadTimeout(const Duration(seconds: 5))
    .watch(Entities.power);
// Listen to powerUpdates for updates; cancel subscriptions during app teardown.
// access.dispose() closes this shared context and all configured views.
```

Creation is inert. Reads and subscribed watches connect the background collector lazily. The connected singleton entities are DeviceInfo, Os, Runtime, Cpu, Ram, Locale, TimeZone, AndroidBuild, AndroidIdentity, HardwareSerial, Power, NetworkPath and NetworkPerformance. They reuse the Kotlin Android mappings and field/permission rules. HardwareSerial usually requires privileges unavailable to an ordinary application. Unconnected entities return UnsupportedEntity; unavailable individual fields remain null. No universal permanent identifier is fabricated.

Native state watches use the Kotlin event source where available and its polling fallback otherwise. Equal results are retained, each successful snapshot has its own completion time, and waiting for the next event has no idle timeout. The Dart collection isolate owns platform requests, decoding and normalization; the Android background task queue and Kotlin collection worker own OS access. get always requests fresh state. Cancellation and disposal return without joining native work, while background cleanup drains pending platform responses before worker exit.

Network state consumers must declare `android.permission.ACCESS_NETWORK_STATE` in their application manifest. Native NetworkInterface discovery additionally requires `android.permission.INTERNET`; it enumerates OS interfaces without sending probe traffic. The verification application's debug manifest declares both. Reads never request permission. Screen, permission and sensor-activity state still comes from the app's explicit observers, which can attach to this same access context. Capabilities and automatic permission observation remain pending. See [state and stream verification](../../docs/verification/2026-11-11-flutter-android-state.md).

The Android access context also connects these seven multi-target state entities:

| Entity | Discovery | Native current selection |
|---|---|---|
| CpuCore | `access.cpuCores.list()` | null; no implicit default core |
| Battery | `access.batteries.list()` | The platform's current battery when defined |
| NetworkInterface | `access.networkInterfaces.list()` | Interface associated with the active network, when resolvable |
| StorageVolume | `access.storageVolumes.list()` | The app-data volume |
| WifiConnection | `access.list(Entities.wifiConnection)` | `access.current(Entities.wifiConnection)` |
| CellularSubscription | `access.cellularSubscriptions.list()` | Current data subscription when available |
| TelephonyIdentity | `access.telephonyIdentities.list()` | null; no implicit default logical slot |

```dart
final cores = await access.cpuCores.list();
if (cores.isNotEmpty) {
  final CpuCoreSnapshot core = await access.get(cores.first);
  final Stream<CpuCoreSnapshot> updates = access.watch(cores.first);
}
final volume = await access.storageVolumes.current();
if (volume != null) {
  final StorageVolumeSnapshot storage = await access.get(volume);
}
```

Native list/current requests perform fresh discovery on the worker and honor the configured deadline and cancellation. Live targets preserve handle identity across configured views. Observed absence, native EntityRemoved and explicit observer removal retire old generations; reappearance creates a new handle. Unobserved physical replacement cannot be detected by the generic layer alone. Handles from another access context are rejected. App-owned inventory/current observations take precedence, and explicit selection of a discovered native target preserves its inventory. Selected get/watch queries reuse the existing Kotlin readers/flows. Field availability and permission errors remain platform-specific; a returned partial snapshot does not establish access to all Wi-Fi or identity fields. See [discovery verification](../../docs/verification/2026-11-11-flutter-android-discovery.md).

## Operation support

```dart
final support = await access.capabilities.get(Entities.hardwareSerial);
// readable/watchable can be true even when ordinary-app reads are denied.
final cores = await access.cpuCores.list();
if (cores.isNotEmpty) {
  final selectedSupport = await access.capabilities.get(cores.first);
}
```

The nullable booleans describe connected operations, separately from permission and individual field coverage. Native queries run through the background bridge with the configured timeout and cancellation; they do not read snapshots or subscribe. Native presence probes may inspect hardware inventories on their worker, but the query does not discover public handles. Unconnected Android state mappings report false/false. Screen and sensor support comes from app-owned registration; an unattached sensor is unavailable even if Android has that sensor. Retired handles report false/false. The permission coordinator is invoked only by an explicit permission request. See [capability verification](../../docs/verification/2026-11-11-flutter-android-capabilities.md).

## Android sensors

Use one Android sensor owner for the SDK context. Attach from the app's existing root isolate and lifecycle; no binding is initialized implicitly:

```dart
final access = FlutterAndroidDeviceAccess.create();
final activity = FlutterSensorActivityObserver.attach(access);
final sensors = await FlutterAndroidSensors.attach(access);
try {
  final targets = await access.list(Entities.accelerometer);
  if (targets.isNotEmpty) {
    final sensor = targets.first;
    final metadata = await access.describe(sensor);
    final sample = await access.get(sensor);
    await for (final value in access
        .withSensorSamplingRate(SensorSamplingRate.atHertz(60))
        .watch(sensor)
        .take(3)) {
      print(value.value);
    }
  }
  await sensors.refresh(Entities.accelerometer);
} finally {
  sensors.dispose();
  activity.dispose();
  access.dispose();
}
```

Attachment registers native dynamic connection observation before discovering sensors and capturing metadata. A connection change refreshes affected collections automatically; an event during a refresh triggers another fresh read. Generic `list` reads this observed inventory. Explicit `refresh(kind)` remains available, including for metadata changes without connection notifications. Its readTimeout covers native coordination, discovery and all metadata queries. Refresh requires a typed sensor collection; a bound target is rejected before native work or state mutation. Unchanged native targets preserve handles; observed absence and disposal retire them. Description reads use the latest captured metadata without opening or restarting the sensor. Metadata updates retain live handles and existing subscriptions. A terminal inventory-observation failure requires explicit adapter replacement; a late successful read cannot clear it. The bridge reuses all seventeen Android sensor mappings; unsupported RelativeAltitude/HumanPresence and per-kind permission failures remain typed errors. Empty supported inventories remain empty.

The adapter owns separate failure slots. Refresh and disposal cannot clear the application's blocking policy or another provider's errors. Detaching an adapter permits replacement sources; reattachment prepares fresh handles even while app policy blocks reads. Use one native sensor adapter at a time per context: simultaneous inventory ownership remains unverified. See [provider lifetime verification](../../docs/verification/2026-11-11-flutter-android-lifetimes.md).

The background Flutter isolate performs platform requests and decoding. Android task queues and Kotlin workers perform native registration, reads and cleanup. Each pending next request waits for an actual source event. Acknowledgements bound sample messages to the app isolate, and bounded native/common SDK queues report overload explicitly. Cancellation never joins a blocked registration. The small root-isolate source callback only forwards typed inputs; source normalization still runs in the SDK's isolate. Permission requests remain app-owned and explicit.

Disposal stops app-side collection immediately. The worker receives all outstanding platform replies before exiting, so late native replies cannot target a prematurely closed Dart port. This drain does not block the app. A native reply that never finishes retains its background receiver; arbitrary native crashes and engine-detachment races are not covered by this guarantee.

This Android build currently consumes shared Kotlin source sets from the monorepo. External plugin distribution and further field/platform coverage remain pending. Validated tools are Gradle 8.14.3, AGP 8.11.1 and Kotlin 2.2.20, with compile/target SDK 36 and min SDK 26. Flutter warns about future toolchain floor increases; current validation uses no bypass.

```powershell
./tools/build-flutter-android.ps1 -SdkRoot 'C:/path/to/Android/Sdk' -NativeUnitOnly
./tools/build-flutter-android.ps1 -SdkRoot 'C:/path/to/Android/Sdk'
# A project-owned DeviceReadout test AVD must already be running:
./tools/test-flutter-android.ps1 -SdkRoot 'C:/path/to/Android/Sdk' -Serial emulator-5584
```

The Android build command creates the test entrypoint's debug APK. The runner checks its exact app process, compares state/target fields with independent Android OS reads, and verifies registration/release with SensorManager diagnostics before stopping the app. It accepts only project-owned AVDs. Its Power event check temporarily changes the owned emulator's battery simulation, refuses preexisting overrides and restores automatic battery updates on success or failure. Thirty-three scenarios pass on each API 26/36 with the inventory observer attached; controlled service/transport fixtures separately cover connection changes. See [discovery verification](../../docs/verification/2026-11-11-flutter-android-discovery.md), [Android state verification](../../docs/verification/2026-11-11-flutter-android-state.md) and the [earlier sensor bridge](../../docs/verification/2026-11-11-flutter-android-sensors.md) for native versus fixture evidence and remaining cases.

## Example and verification

For web, construct the access context with an explicitly served module worker:

```dart
final access = DeviceAccess.web(
  workerUri: Uri.base.resolve('device-readout-dart-worker.js'),
);
```

The example selects this factory with `kIsWeb`. Run `./tools/build-flutter-web.ps1` to build the example and copy the SDK worker into the output, or `./tools/test-flutter-web.ps1` to build both consumers and verify installed Chrome/Edge. Serve the resulting directory over HTTP. Flutter viewport, display and sensor-activity observers remain explicitly attached by the app; permissions and sensor sources remain app-owned. Each browser passes the rendered-example case and six integration scenarios. See [Flutter web verification](../../docs/verification/2026-11-17-flutter-web.md) for real browser versus controlled fixture evidence and remaining coverage.

Native state and sensor adapters can share one DeviceAccess. The actual API 26/36 suite verifies concurrent polling/sensors/queries, scoped failure and cancellation, sensor-provider replacement, and whole-context closure. During the real Activity pause fixture, sensor collection stops while native OS/RAM work remains usable. See [shared-context verification](../../docs/verification/2026-11-11-flutter-android-mixed.md) for the tested scope and background-execution limits.

The [example widget](example/lib/main.dart) attaches in `didChangeDependencies`, watches snapshots, explicitly selects its current viewport and disposes the observer before the SDK context. It now includes a Windows runner and builds as a Release executable. It is an unpackaged example, not an installer or signed release.

Run `./tools/test-flutter.ps1` for twenty-two engine checks and `./tools/test-flutter-windows.ps1` for five native Windows screen scenarios. The latter builds a test-only hidden window, verifies actual client resizing, native monitor values, re-enumeration, teardown and helper-isolate responsiveness, then rebuilds the regular example without the test channel. It controls only its own HWND and uses a unique report path. It does not change monitor configuration or system preferences.

The scripts use the bundled Dart analyzer and offline package resolution. Initial dependencies must first be available in the repository's `.tools/dart-pub-cache`; lockfiles record the validated versions. The Windows build also requires Visual Studio's C++ desktop tools. On this host the Flutter test compiler and native app verification run in a normal-user process. Scripts restore their environment and do not change global telemetry preferences.

This package implements Viewport, partial Display, sensor activity observation, twenty native Android state mappings with discovery/current/capabilities, seventeen Android sensor mappings and the explicit Dart web-worker connection. Other platform collectors, full physical sensor evidence, mobile/desktop permission adapters and the full browser matrix remain required. The common Dart permission coordinator remains app-owned; no observer opens UI. See the [capability queries](../../docs/verification/2026-11-11-flutter-android-capabilities.md), [Android discovery](../../docs/verification/2026-11-11-flutter-android-discovery.md), [state bridge](../../docs/verification/2026-11-11-flutter-android-state.md), [sensor bridge](../../docs/verification/2026-11-11-flutter-android-sensors.md), [sensor/lifecycle record](../../docs/verification/2026-11-11-dart-sensors.md), [screen verification](../../docs/verification/2026-11-11-flutter-screens.md) and [earlier viewport checkpoint](../../docs/verification/2026-11-11-flutter-viewport.md).
