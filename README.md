# DeviceReadout

Typed device information through `DeviceAccess.get(Entity)` and `watch(Entity)`.

**Implementation in progress.** The shared schema generates all 46 entities for TypeScript, C#, Kotlin, Dart and Swift. Browser worker collectors, initial Windows and Android collectors, the Kotlin suspend/Flow runtime, Dart state/sensor contracts and Flutter screen/lifecycle observers are implemented and tested. Flutter Android connects twenty state collectors, including seven multi-target kinds, and seventeen sensor mappings through background workers. The initial React Native Android transport/TurboModule connects native queries and app-owned state/permission/lifecycle inputs; an actual RN 0.88.0/Hermes app passes representative read/watch, screen-change and sensor lifecycle checks on API 26 and API 36 emulators. The [Swift package](swift/README.md) provides worker-based typed reads, state/sensor streams, discovery, app observers, permission coordination and support queries with immutable configuration; Swift framework lifecycle adapters and Apple collectors, remaining Flutter collectors/platform plugins, the full React Native matrix and the complete acceptance matrix are still required. Entity declarations alone are not a claim of platform support.

## Build and verify

The [latest upload checkpoint](docs/verification/2026-11-18-upload-power-storage.md) includes the verified C# power changes and initial Dart Windows storage collection. Dart analysis and the standalone storage check pass on this host; aggregate, compiled, independent-reference and Flutter storage verification remain pending.

The [C# native power checkpoint](docs/verification/2026-11-18-dotnet-power-native.md) adds 23 child-process scenarios through the production P/Invoke declarations, covering source flags, native failures, real system capability reads and held-call deadlines/cancellation. The final ordinary-user .NET suite passes 168/168. It also corrects a Wi-Fi test that assumed native cleanup completed synchronously. Physical power transitions and the full acceptance matrix remain pending.

The [C# Windows power-source follow-up](docs/verification/2026-11-18-dotnet-power-source.md) fixes ambiguous DC reads being reported as Battery while preserving exact native source events and independent saver state. The normal-user .NET suite passes 168/168 with zero build warnings/errors. The record also preserves five restricted-environment native failures; native-call coverage is extended by the checkpoint above, while actual battery/UPS transitions remain pending.

The [Dart and Flutter Windows power checkpoint](docs/verification/2026-11-18-dart-windows-power.md) adds native Power get/watch, saver status and conservative battery-source disambiguation. Final Dart JIT/native checks pass 69/69 each, the actual Windows release app passes 14/14 and Flutter framework checks pass 27/27. On-battery/UPS transitions, native failures and the full acceptance matrix remain pending; the C# direct-source follow-up is recorded above.

The [Flutter locale platform checkpoint](docs/verification/2026-11-18-flutter-locale-platforms.md) verifies actual app locale changes and native fallback on Android API 26/36 and Chrome/Edge, including separate consumers installed from Pub archives. Android passes 34/34 per device and consumer; web passes ten application scenarios per browser and consumer, including package worker deployment. Physical devices, Apple platforms, further browsers and the full acceptance matrix remain pending.

The [Flutter app locale checkpoint](docs/verification/2026-11-18-flutter-locale-observer.md) connects explicit application locale observations to get/watch, with owned source lifetime and native fallback after detachment. Dart JIT/native checks pass 68/68 each, Flutter framework tests pass 27/27 and the actual Windows release app passes 13/13, including real Localizations changes. Other platform/application combinations and the complete acceptance matrix remain pending.

The [Dart and Flutter Windows locale checkpoint](docs/verification/2026-11-18-dart-windows-locale.md) adds NLS/ICU collection for all eleven Locale fields with separate user/system/process language lists. Current fields match independent sources; Dart JIT/native suites pass 66/66 each, the actual Flutter Windows app passes 12/12 and framework tests pass 24/24. Additional settings/locale combinations, app-framework locale observations and the full platform matrix remain pending.

The [Dart and Flutter Windows time-zone checkpoint](docs/verification/2026-11-18-dart-windows-time-zone.md) adds native Windows/IANA IDs, current UTC offset and DST state through isolate-owned get/watch. Final Dart JIT/native suites pass 65/65 each, actual Flutter Windows checks pass 11/11 and framework tests pass 24/24. The record preserves an earlier, unreproduced JIT compiler abort in a registry test child. Other zones/DST transitions, native failures and the full platform matrix remain pending.

The [Windows registry boundary checkpoint](docs/verification/2026-11-18-dart-windows-registry.md) fixes a normal terminated 64 KiB DeviceInfo string being rejected because of an extra native sizing allowance. Six actual child-process registry scenarios cover partial fields, Unicode, malformed text, size limits and watch recovery. Dart JIT/native suites pass 64/64 each, the actual Flutter Windows app passes 10/10 and framework tests pass 24/24. Growth races, remaining collectors and the full acceptance matrix remain pending.

The [Windows upload checkpoint](docs/verification/2026-11-17-windows-upload-checkpoint.md) includes Runtime, Os and DeviceInfo collectors plus child-process registry coverage for wrong-type and missing fields. Upload-time Dart JIT/native contracts pass 59/59 each, with clean analysis and the negative web boundary passing. The preceding Flutter Windows 10/10 and framework 24/24 results remain recorded below; the full implementation and acceptance matrix remains unfinished.

The [Dart and Flutter Windows DeviceInfo checkpoint](docs/verification/2026-11-17-dart-windows-device-info.md) adds native manufacturer, model name, board and computer-name get/watch. Independent Win32 and CIM comparisons pass. Dart JIT/native contracts pass 58/58 each, the actual Flutter Windows release app passes 10/10 and framework tests pass 24/24. Other DeviceInfo mappings, native failure/encoding cases and the full platform matrix remain pending.

The [Dart and Flutter Windows OS checkpoint](docs/verification/2026-11-17-dart-windows-os.md) adds OS get/watch and capability reporting. Version/build agree with independent native and CIM sources. Dart JIT/native contracts pass 57/57 each, the actual Flutter Windows release app passes 9/9 and framework tests pass 24/24. Collection remains isolate-owned; native faults, ARM64/emulation, other versions and the complete platform matrix remain pending.

The [Dart and Flutter Windows runtime checkpoint](docs/verification/2026-11-17-dart-windows-runtime.md) adds native host architecture without inferring it from the process ABI. Dart JIT/native contracts pass 56/56 each. The actual Flutter Windows release app passes 8/8, including independent native comparisons for ProcessMemory and Runtime; framework tests pass 24/24. ARM64/emulation, native faults and the complete platform matrix remain pending.

The preceding [Dart Windows process-memory checkpoint](docs/verification/2026-11-17-dart-windows-process-memory.md) adds `ProcessMemory.allocationRemainingBytes` from the current process's Windows commit budget. Its standalone JIT/native contracts passed 55/55 each. Dedicated Flutter release-app coverage is recorded in the subsequent runtime checkpoint above.

The [Dart Windows RAM checkpoint](docs/verification/2026-11-17-dart-windows-ram.md) adds isolate-owned Win32 RAM get/watch with distinct installed, OS-accessible and available byte counts. Dart JIT/native contracts pass 54/54 each, the real Flutter Windows release app passes 6/6, framework tests pass 24/24, Dart browsers pass sixteen scenarios each, and rebuilt Android apps pass 33/33 on each API 26/36. Native faults, ARM64, remaining collectors and the full acceptance matrix still require work.

The [Flutter web package checkpoint](docs/verification/2026-11-17-flutter-web-packages.md) adds a packaged collection worker and `FlutterWebDeviceAccess.create()`. Installed Pub consumers and rebuilt checkout applications pass nine scenarios per Chrome/Edge browser, including nested routes and a separate same-origin asset base. Flutter framework checks pass 24/24; a rebuilt installed Android consumer passes 33/33 on each API 26/36, and its APK excludes the web worker. Content-hashed/cross-origin deployments and the full platform matrix remain unverified. Packages remain unpublished.

The [Flutter Android package checkpoint](docs/verification/2026-11-17-flutter-android-packages.md) fixes hosted-Pub path dependencies and missing native source packaging. Real `pub get` downloads the Dart SDK and Flutter plugin from a loopback fixture; an independent app builds from the Pub cache and passes 33/33 scenarios on each API 26/36 emulator. Flutter framework 22/22 and native bridge 12/12 checks pass. These local archives are not pub.dev releases; hosted web-worker distribution and the complete platform/device/version matrix remain required.

The [React Native Android package checkpoint](docs/verification/2026-11-17-react-native-android-packages.md) removes native monorepo path dependencies. An independent npm/Metro consumer builds from tarballs containing shared Kotlin sources and consumer-resolved Codegen. Each API 26/36 emulator passes fifteen application scenarios and three held-native deadline/cleanup scenarios. Existing RN contracts pass 12/12, and installed RN Web applications still pass seven scenarios per Chrome/Edge. Packages remain unpublished; physical devices, remaining platforms and the complete acceptance matrix are still required.

The [React Native Web checkpoint](docs/verification/2026-11-17-react-native-web.md) adds a browser package entrypoint backed by the existing module worker. RN Web 0.21.4 / React 19.3.0 passes seven application scenarios in each Chrome/Edge browser, including actual resize, app-owned lifecycle/permission inputs and worker cleanup. Local tarball consumers pass TypeScript 5.0 and inert server-import checks without installing React Native mobile; existing RN contracts pass 12/12. Physical/native visibility, other RN platforms and the complete acceptance matrix remain pending.

The [Dart watch-delivery checkpoint](docs/verification/2026-11-17-dart-watch-delivery.md) prevents polling from accumulating behind paused consumers and keeps completed reads from timing out during delivery waits. Native events and other subscriptions remain independent; overload fails only its watch. Verification passes sixteen Dart browser scenarios per Chrome/Edge browser, 51 Dart JIT/native contracts each, 37 common tests, 64 existing browser tests, 22 Flutter framework checks and rebuilt Flutter web applications. The full physical/platform/version acceptance matrix remains unfinished.

The [Flutter web application checkpoint](docs/verification/2026-11-17-flutter-web.md) connects the actual Flutter example to the served module worker and corrects web display units. Chrome and Edge each pass the rendered-example case plus six application scenarios covering reads, resizing, native focus lifecycle, explicit app permission coordination, held-worker responsiveness and disposal. Use `./tools/test-flutter-web.ps1` to rebuild and reproduce them. Physical browser sensors, further browsers and the complete platform/acceptance matrix remain pending.

The [Dart browser transfer checkpoint](docs/verification/2026-11-17-dart-web-transfer.md) divides large incoming/outgoing snapshot traversals and typed collection construction across host event-loop turns. Cancellation and deadlines stop unfinished traversal; watch delivery preserves order, duplicates and pause/resume, and read admission includes preparation through typed delivery. Eleven scenarios pass in each Chrome/Edge browser, alongside 50 Dart JIT/native contracts and 22 Flutter framework checks. Browser cloning costs, sustained overload, full wire coverage, actual Flutter web applications and the complete platform/acceptance matrix remain unverified.

The [Dart web-worker checkpoint](docs/verification/2026-11-17-dart-web-worker.md) adds `DeviceAccess.web(workerUri: ...)` with lazy module workers, typed get/watch, observer normalization and passive metadata. Six compiled Dart scenarios pass in each Chrome/Edge browser, alongside 37 common/collector tests, the existing 64 browser tests, 50 Dart JIT/native contracts and 22 Flutter framework checks. Held workers retain independent deadlines/cancellation; expired responses are discarded before Dart materialization. Large-payload marshaling, complete field/browser coverage and actual Flutter web applications remain unverified.

The preceding [Dart normalization checkpoint](docs/verification/2026-11-17-dart-normalization.md) completes common unit-quaternion normalization across the five bindings and moves Dart's worker completion timestamp after decoding. Dart passes 50/50 contracts in JIT and native executables, plus strict analysis and the negative web boundary check. Flutter passes 22/22 framework tests; the rebuilt APK passes 33/33 scenarios on each API 26/36 emulator. The subsequent web-worker checkpoint above adds the Dart browser connection. Apple collectors and the complete platform/acceptance matrix remain unfinished.

The preceding [upload checkpoint](docs/verification/2026-11-17-upload-checkpoint.md) includes Swift support queries and structured normalization, plus common unit-quaternion validation in TypeScript, Kotlin and C#. TypeScript now stamps completion after field preparation. Verification passes 36 common/collector tests, 64 Chrome/Edge tests, 44 Kotlin tests, 166 .NET/Windows tests and the preceding 81 Swift tests in both Debug and Release. The subsequent Dart checkpoints above resolve unit-quaternion normalization and completion ordering. Apple collectors and the full platform/acceptance matrix remain unfinished; this is a development checkpoint, not a completed release.

The preceding [Swift normalization checkpoint](docs/verification/2026-11-17-swift-normalization.md) validates eighteen additional fields across eleven entities: ratios, screen geometry, vector samples, unit quaternions and nested display modes. Invalid values become nil without losing independent fields, valid zeros or empty lists. Generated snapshots stamp completion after normalization. A 10,000-mode observed snapshot retains independent publication and queued-read deadlines behind held native work. All eighty-one Swift 5.9.2 Linux tests pass in Debug and Release with warnings treated as errors. The later upload and Dart checkpoints above add common quaternion parity. Apple collectors and the full acceptance matrix remain required.

The preceding [Swift capabilities checkpoint](docs/verification/2026-11-17-swift-capabilities.md) adds passive `capabilities.get(Entity)` with nullable readable/watchable support, app-source ownership and native worker queries. Permission failures remain separate from support; held native queries retain independent deadlines and cancellation. Additional sensor checks cover inactive termination and independent configured consumers. All seventy-five Swift 5.9.2 Linux tests pass in Debug and Release with warnings treated as errors. Apple collectors, framework adapters, remaining normalization and the full acceptance matrix remain required.

The preceding [Swift sensor-activity checkpoint](docs/verification/2026-11-17-swift-sensor-activity.md) adds app-supplied pause/resume with fresh sensor sessions and rejection of late old-session samples/errors. Inactive sensor gets retain their original deadline, and state reads remain available. All sixty-six Swift 5.9.2 Linux tests pass in Debug and Release with warnings treated as errors. Framework lifecycle adapters, Apple collectors and the full acceptance matrix remain required.

The preceding [Swift sensor-source checkpoint](docs/verification/2026-11-17-swift-sensor-sources.md) adds app-owned sensor get/watch, passive descriptions and immutable sampling requests. Registration and cleanup run on the collection worker; caller completion remains independent of held setup or cleanup. Event watches wait for real occurrences without an event-wait timeout, and bounded queues report overflow explicitly. All sixty-one Swift 5.9.2 Linux tests pass in Debug and Release with warnings treated as errors. Sensor lifecycle pause/resume, native/Apple collectors and adapters, remaining normalization and the full platform matrix remain required.

The preceding [Swift permissions checkpoint](docs/verification/2026-11-17-swift-permissions.md) added app-observed checks and explicit app-coordinated requests with independent cancellation. Its fifty-one tests remain in the current suite.

The preceding [Swift observer-failure checkpoint](docs/verification/2026-11-17-swift-observer-failures.md) added typed target/kind errors and independently owned failure sources, preserving application policy and invalidating work crossing a failure. Its forty-four Debug/Release tests remain in the current suite.

The preceding [Swift watch handoff checkpoint](docs/verification/2026-11-17-swift-watch-handoff.md) added ordered handoff from native polling to app state, original first-value deadlines and context-scoped singleton removal. Its thirty-eight Debug/Release tests remain in the current suite.

The preceding [Swift state-observer checkpoint](docs/verification/2026-11-17-swift-state-observers.md) fixed the first observed-value deadline and added explicit current selection, target removal and generation-safe rediscovery. Its thirty-two Debug/Release tests remain in the current suite. The [upload-time work-in-progress record](docs/verification/2026-11-17-swift-observers-wip.md) preserves the earlier failing checkpoint.

The [Swift context checkpoint](docs/verification/2026-11-17-swift-context-lifetime.md) adds shared-context `close()`, independent completion of held reads/discovery and idle watches, and worker-owned native cleanup. Native read admission is bounded to 128 waiting operations, with explicit overload errors and a separate cleanup path. All twenty-two Swift 5.9.2 Linux tests pass in Debug and Release with warnings treated as errors. Apple collectors, app observers, sensors and the full platform matrix remain required.

The [Swift discovery checkpoint](docs/verification/2026-11-17-swift-discovery.md) adds typed `list`/`current` and resource collections, context-owned target generations and immediate watch termination after accepted removal. Late or malformed inventories preserve existing handles. All seventeen Swift 5.9.2 Linux tests pass in Debug and Release with warnings treated as errors. Autonomous native hotplug, app-owned observers, sensor APIs and Apple platform verification remain required.

The [Swift state-stream checkpoint](docs/verification/2026-11-17-swift-state-streams.md) adds cold `watch(Entity)` polling and immutable `withPollInterval`, plus scalar value normalization. All ten Swift 5.9.2 Linux tests pass in Debug and Release with compiler warnings treated as errors. Independent subscription cadence, cancellation, per-read deadlines, loop-exit cleanup and explicit delivery overflow are covered. Native notifications, typed targets, sensor/observer APIs and Apple platform verification remain required.

The [Swift foundation checkpoint](docs/verification/2026-11-17-swift-foundation.md) passes three public-API tests with Swift 5.9.2 on Ubuntu 22.04 under WSL. These cover nullable snapshots, worker execution, independent deadlines and caller cancellation. Apple platform builds and native collection remain unverified.

The [Windows relative-altitude checkpoint](docs/verification/2026-11-17-windows-relative-altitude.md) adds native signed-meter snapshots, default-device identity checks and shared sampling ownership. Nine held-call cases preserve caller deadlines and nonjoining cleanup. The complete .NET/Windows suite passes 165/165 with zero build warnings or errors. Actual default-altimeter discovery is empty; physical measurements and the full platform matrix remain required.

The [Windows human-presence checkpoint](docs/verification/2026-11-17-windows-human-presence.md) adds Boolean presence snapshots, passive metadata and native streams. Unknown values remain null. It also fixes caller-token propagation, delayed native cancellation and stale synchronous initial samples. The complete .NET/Windows suite passes 161/161 with zero build warnings or errors. Physical presence measurements, native consent behavior and the full platform matrix remain required.

The [Windows hinge-angle checkpoint](docs/verification/2026-11-17-windows-hinge.md) adds HingeAngle discovery, metadata and radian snapshots. Native events can satisfy a first read while its asynchronous initial request is pending; late initial values no longer follow newer events. Deadline, cancellation and recovery checks pass, and native angular thresholds remain unchanged. The complete .NET/Windows suite passes 156/156 with zero build warnings or errors. Physical measurements and the full platform matrix remain required.

The [Windows proximity checkpoint](docs/verification/2026-11-17-windows-proximity.md) adds ProximityNear and ProximityDistance with independent Boolean/meters snapshots, passive maximum-range metadata and native event cadence. Seven held native-call cases preserve caller deadlines and nonjoining disposal. The complete .NET/Windows suite passes 152/152 with zero build warnings or errors. Actual inventories are empty; physical measurements and the full platform matrix remain required.

The [Windows orientation checkpoint](docs/verification/2026-11-17-windows-orientation.md) adds AbsoluteOrientation and RelativeOrientation discovery, metadata and get/watch. Named unit quaternions preserve device-to-reference direction and native reference kinds. Invalid fields return null; activity changes, type mismatches and held reads retain the existing lifecycle and deadline contracts. The complete .NET/Windows suite passes 148/148 with zero build warnings or errors. Physical orientation measurements and the full platform matrix remain required.

The [Windows acceleration checkpoint](docs/verification/2026-11-17-windows-acceleration.md) adds Accelerometer, LinearAcceleration and Gravity collectors with separate native selectors and validated reading kinds. G-force values are normalized to the common m/s² convention. Native activity/permission observer integration, partial fields and held reads are covered; the complete .NET/Windows suite passes 144/144 with zero build warnings or errors. Physical measurements and the full platform matrix remain required.

The [Windows vector sensor checkpoint](docs/verification/2026-11-17-windows-vector-sensors.md) adds Gyroscope and Magnetometer get/watch, descriptions and discovery. Native degree/s readings become rad/s; magnetic readings retain microteslas. Partial axis failures return a null vector without ending the stream, and canceled native reads stop collecting remaining components. The complete .NET/Windows suite passes 140/140 with zero build warnings or errors. Physical vector measurements and the remaining platform matrix are still required.

The [Windows scalar sensor checkpoint](docs/verification/2026-11-17-windows-scalar-sensors.md) adds native Illuminance and Pressure discovery, metadata, get/watch and sampling configuration. The complete .NET/Windows suite passes 136/136 with zero build warnings or errors. Controlled native ABI tests cover measurements and ownership; independent native enumeration confirms that this host has neither sensor. Physical measurements and the remaining Windows sensor families are still required.

The [.NET state lifetime checkpoint](docs/verification/2026-11-17-dotnet-state-lifetime.md) fixes cancellation/error/disposal waiting on native cleanup and a missed subscription release during registration cancellation. The complete Windows suite passes 129/129, including 128 repeated registration/cancellation cycles and actual native removal checks.

The [.NET target identity checkpoint](docs/verification/2026-11-17-dotnet-target-identity.md) separates same-name native and app targets across state/sensor queries, discovery, current selection, permission requests, errors and removal. The complete Windows run passes 125/125; broader concurrency and physical/platform coverage remain pending.

The [.NET sensor-source checkpoint](docs/verification/2026-11-17-dotnet-sensor-sources.md) adds app-owned sensor registration, passive metadata, independent get/watch sessions and explicit activity-driven pause/resume. Cancellation and late-registration cleanup regressions are fixed. All 121 .NET/Windows checks pass; native Windows sensor collectors and physical-device evidence remain pending.

The [web display ownership checkpoint](docs/verification/2026-11-17-web-display-ownership.md) preserves application errors through observer recovery/disposal, keeps newer inventories during reentrant initial reads, and retires removed handles even when host listener cleanup fails. Common/collector checks pass 34/34 and the full Chrome/Edge suite passes 64/64.

The [.NET observer/cancellation checkpoint](docs/verification/2026-11-17-dotnet-observer-cancellation.md) adds independent provider failure handles and separates native cancellation callbacks from SDK control signals. All 115 .NET/Windows checks pass, including held native callbacks, caller deadlines, context disposal and in-flight result invalidation. Remaining physical-device and platform coverage is recorded in the checkpoint.

The latest [observer ownership checkpoint](docs/verification/2026-11-17-observer-failure-ownership.md) preserves independent provider failures and delivers permission loss while sensors are inactive. Common/collector tests pass 34/34, actual Chrome/Edge tests 56/56, Kotlin contracts 43/43 and RN transport/framework contracts 12/12. The RN/Hermes/JSI app passes fifteen reported scenarios on each Android API 26/36.

The [web Generic Sensor adapter](docs/verification/2026-11-16-web-generic-sensors.md) adds eight typed sensor mappings with explicit app-owned permission observation. Six families work in the tested default browser configurations; magnetic field and light additionally pass with an experimental browser feature. Physical devices, other browser engines and the full support matrix remain required.

The preceding [React Native framework-observer checkpoint](docs/verification/2026-11-16-react-native-framework-observers.md) adds explicit Dimensions and AppState adapters. Transport/framework contracts pass 12/12. The actual RN/Hermes/JSI app passes fourteen reported scenarios on each API 26/36, including window changes, sensor suspension/resume and continued sensor collection during focus loss. Safe-area/visual viewport fields, other RN platforms and physical-device coverage remain required.

The preceding [React Native sensor-source checkpoint](docs/verification/2026-11-15-react-native-sensor-sources.md) connects app-owned sources to native get/watch demand, independent sampling settings, lifecycle suspension/resume and cleanup. Kotlin passes 41/41 contracts. Its actual RN/Hermes/JSI app passes thirteen reported scenarios on each API 26/36, with independent kernel-memory and native sensor-registration checks. Source callbacks use controlled samples; physical plugin and broader concurrency coverage remain required.

The preceding [React Native responsiveness checkpoint](docs/verification/2026-11-15-react-native-isolation.md) verifies get/watch deadlines and context close while native collection is deliberately held. Its Hermes/JSI app passes three such scenarios on each API 26/36, with JS and Android UI progress before external release and collector-worker exit afterward. Broader blocked-event/cleanup, overload and physical-device coverage remain required.

The preceding [React Native inventory checkpoint](docs/verification/2026-11-15-react-native-mixed-inventory.md) preserves native removal detection alongside app-owned inventories. A controlled regression verifies isolated target removal, and Kotlin tests total 37/37. Physical dynamic hotplug, broader concurrent failure/replacement cases and external package consumption remain unverified.

The [React Native observer checkpoint](docs/verification/2026-11-11-react-native-observers.md) adds app-owned screen/state, permission and lifecycle protocol handling to the native transport. Native/app target identities stay separate, and paused sensors still receive errors and removal. Full application/framework/platform verification remains required.

The latest [sensor inventory verification](docs/verification/2026-11-11-flutter-android-inventory.md) adds native connection observation, metadata updates without resubscription, generation-safe removal and whole-inventory deadlines. Dart 48/48 in JIT/AOT, Flutter 22/22, native bridge 12/12 and actual APK 33/33 on each API 26/36 pass.

The preceding [shared-context verification](docs/verification/2026-11-11-flutter-android-mixed.md) covers simultaneous native state/sensor work, scoped cancellation/failure and actual Activity lifecycle through one DeviceAccess: 33 APK scenarios pass on each API 26/36.

The [Dart/Flutter Android capability checkpoint](docs/verification/2026-11-11-flutter-android-capabilities.md) adds passive `capabilities.get(entity)` queries with separate permission state, explicit source registration and worker-owned native probes.

```sh
npm ci --workspaces=false --ignore-scripts
npm test
npm run test:browser
# Swift 5.9.2 portable foundation (requires Swift and a POSIX shell):
sh tools/test-swift.sh -Xswiftc -warnings-as-errors
sh tools/test-swift.sh -c release -Xswiftc -warnings-as-errors
# Windows/.NET 10:
./tools/test-dotnet.ps1
# Kotlin/JVM:
./tools/test-kotlin.ps1
# Dart 3.13.7 from Flutter 3.47.9, Windows x64 foundation:
./tools/test-dart.ps1
# Flutter 3.47.9 screen observers, Windows test engine:
./tools/test-flutter.ps1
# Actual hidden Windows Release runner, followed by ordinary example build:
./tools/test-flutter-windows.ps1
# Flutter Android bridge contracts and native test APK:
./tools/build-flutter-android.ps1 -SdkRoot 'C:/path/to/Android/Sdk' -NativeUnitOnly
./tools/build-flutter-android.ps1 -SdkRoot 'C:/path/to/Android/Sdk'
# Requires a running project-owned DeviceReadout AVD:
./tools/test-flutter-android.ps1 -SdkRoot 'C:/path/to/Android/Sdk' -Serial emulator-5584
# Android build/lint (supply the installed SDK path):
./tools/build-android.ps1 -SdkRoot 'C:/path/to/Android/Sdk'
```

The pinned TypeScript 5.0.4 compiler checks the library and consumer declarations. Node's test runner starts actual worker threads, including a deliberately blocking collector to check host responsiveness and deadline handling. `--workspaces=false` avoids workspace symlinks on restricted Windows hosts.

## Interface

```ts
const fast = access
  .withPollInterval(Duration.milliseconds(250))
  .withReadTimeout(Duration.seconds(5));

const ram = await fast.get(RamEntity);
for await (const snapshot of fast.watch(RamEntity, {signal})) {
  // physicalBytes is bigint | null; collectedAt is an immutable Instant.
  render(snapshot);
}
```

Settings are immutable. Defaults are one-second polling, a five-second read deadline, and `SensorSamplingRate.PlatformDefault`. Calling `watch` does not start collection until iteration. `return()` cancels a pending `next()` immediately.

## UI and permission observer inputs

The application owns UI-affine observers. SDK collection receives their state and does not read the DOM, display permission prompts, or change application settings. The browser package includes an explicit `observeWebViewport(access, window)` adapter for the application's window lifecycle; only its initial/event callbacks read window properties.

```ts
const display = access.observers.target(DisplayEntity, 'application-screen');

// Invoke from an application-owned screen observer, using its reported state.
access.observers.publish(display, {pixelSize: {width, height}});
access.observers.current(DisplayEntity, display);

// Feed this from the application's mobile/web lifecycle observer.
access.observers.sensorActivity(isActive);

// The application performs the platform-specific permission interaction.
const unregister = access.observers.onPermissionRequest(async ({entity, signal}) => {
  await applicationPermissionCoordinator.request(entity, signal);
  // The app's permission observer publishes the resulting status separately.
});
access.observers.permission(DisplayEntity, PermissionStatus.Granted);
```

Observers can publish before the first read without starting a collector. State updates replace the observed value, so absent fields become null instead of retaining stale values. Target handles work across configured views of the same access context and cannot be used in another context. Sensor inactivity releases active collector subscriptions and suspends the initial-sample timer; resuming acquires a fresh session. Desktop integrations must not equate ordinary window focus loss with sensor inactivity.

TypeScript observer adapters can report an entire target/collection failure with `access.observers.failure(entity, new DeviceReadoutError(ErrorCode.ReadFailed, message))`. This invalidates cached values and terminates affected streams. Publish fresh state and clear with `failure(entity, null)` when the external observer recovers; old streams do not restart. Removed handles remain invalid. The browser's explicit `observeWebDisplays` adapter uses this path for inventory failures and optional app-supplied PermissionStatus changes. Kotlin, .NET and Dart also provide typed observer failure inputs. Flutter Viewport/Display adapters use Dart's observer path; real permission-plugin integration remains pending; see the [Dart package](dart/device_readout/README.md).

TypeScript `observers.sensorSource(target, {description, subscribe(session)})` registers a lifecycle-managed app sensor source. Each get/watch invokes subscribe with a typed samplingRate, AbortSignal, publish and fail callbacks. Return native-listener cleanup; keep subscription callbacks short, nonblocking and free of permission prompts. Samples are normalized in the collector worker. Get uses PlatformDefault; a sample watch receives its own immutable frequency setting. Cancellation, inactivity, timeout, native error and context closure release observations. Registration/metadata queries are inert. Use a source registration instead of raw publish for a target whose native subscription must follow SDK demand. The browser package's `observeWebMotion(access, window)`, `observeWebOrientation(access, window)` and `observeWebSensorActivity(access, document)` use this route.

In TypeScript, Kotlin, .NET and Dart, an observed kind-level permission status also applies to targets with no explicit target status. An explicit target status, including null, takes precedence. Both permission checks and pending app-coordinated requests use this rule; permission status does not implicitly request UI or replace a blocking observer failure.

Use `AbortSignal` to cancel a pending read, permission request or stream. `access.close()` closes the shared context, including all configured views; invoke it when the owning integration is disposed.

The current delivery queue is bounded to 2048 pending snapshots. A consumer that cannot keep up receives `ReadFailed`; samples are not silently dropped or conflated. Applications can apply their own stream processing.

## Design and status

* [Authoritative design](docs/design.ko.md)
* [Host execution contract](docs/execution-isolation.md)
* [Implementation and verification ledger](docs/implementation-status.md)
* [Dart isolated collection foundation](docs/verification/2026-11-11-dart-foundation.md)
* [Dart screen and permission observer verification](docs/verification/2026-11-11-dart-observers.md)
* [Dart sensors and Flutter lifecycle verification](docs/verification/2026-11-11-dart-sensors.md)
* [Flutter Android sensor bridge verification](docs/verification/2026-11-11-flutter-android-sensors.md)
* [Flutter Android failure ownership and disposal verification](docs/verification/2026-11-11-flutter-android-lifetimes.md)
* [Flutter screen ownership and real Android lifecycle verification](docs/verification/2026-11-11-flutter-observer-lifecycle.md)
* [Flutter Android state collection and native stream verification](docs/verification/2026-11-11-flutter-android-state.md)
* [Flutter Android native discovery and target lifetime verification](docs/verification/2026-11-11-flutter-android-discovery.md)
* [Flutter viewport observer verification](docs/verification/2026-11-11-flutter-viewport.md)
* [Flutter Display and Windows application verification](docs/verification/2026-11-11-flutter-screens.md)
* [Flutter package and example](flutter/device_readout_flutter/README.md)
* [Dart package and current limitations](dart/device_readout/README.md)
* [Windows cellular account and observer verification](docs/verification/2026-11-11-windows-cellular.md)
* [Windows cellular native watcher and removal verification](docs/verification/2026-11-11-windows-cellular-watcher.md)
* [Android power, sensors and regional verification](docs/verification/2026-11-11.md)
* [Android network and worker verification](docs/verification/2026-11-11-network.md)
* [Android CPU and storage verification](docs/verification/2026-11-11-cpu-storage.md)
* [Latest Android Wi-Fi and cellular verification](docs/verification/2026-11-11-wireless.md)
* [Android restricted identifier verification](docs/verification/2026-11-11-identities.md)
* [Web viewport observer verification](docs/verification/2026-11-11-web-viewport.md)
* [Web display and permission observer verification](docs/verification/2026-11-11-web-displays.md)
* [Kotlin/.NET observer failure verification](docs/verification/2026-11-11-observer-failures.md)
* [Web motion and sensor source verification](docs/verification/2026-11-11-web-motion.md)
* [Web orientation and native permission verification](docs/verification/2026-11-11-web-orientation.md)
* [Windows battery field and lifetime verification](docs/verification/2026-11-11-windows-battery.md)
* [Windows power events and deferred-read cleanup verification](docs/verification/2026-11-11-windows-power-events.md)
* [Windows battery interface lifetime and hotplug verification](docs/verification/2026-11-11-windows-battery-hotplug.md)
* [Windows aggregate battery and WinRT lifetime verification](docs/verification/2026-11-11-windows-aggregate-battery.md)
* [Windows individual battery status and overlapped I/O verification](docs/verification/2026-11-11-windows-battery-status.md)
* [Windows CPU topology and logical-core verification](docs/verification/2026-11-11-windows-cpu.md)
* [Windows live process CPU availability verification](docs/verification/2026-11-11-windows-cpu-availability.md)
* [Windows network generations and native notification verification](docs/verification/2026-11-11-windows-network.md)
* [Windows network routes and IPv6 MTU verification](docs/verification/2026-11-11-windows-network-fields.md)
* [Windows publisher identity and worker lifetime verification](docs/verification/2026-11-11-windows-publisher-identity.md)
* [Windows preferred network path and native status observation](docs/verification/2026-11-11-windows-connectivity.md)
* [Windows network performance and native plan lifetime verification](docs/verification/2026-11-11-windows-network-performance.md)
* [Windows Wi-Fi targets, permission observers and lifetime verification](docs/verification/2026-11-11-windows-wifi.md)
* [Windows Wi-Fi RSSI, native failures and deadline verification](docs/verification/2026-11-11-windows-wifi-signal.md)
* [Shared schema](schema/device-readout.json)
* [Browser package](packages/web/README.md)
* [.NET package](dotnet/README.md)
* [Kotlin package](kotlin/README.md)
* [Implemented native mappings](docs/collector-mappings.md)

MIT licensed. Nothing is published to a package registry yet.
