# DeviceReadout

Typed device information through `DeviceAccess.get(Entity)` and `watch(Entity)`.

**Implementation in progress.** The shared schema generates all 46 entities for TypeScript, C#, Kotlin and Dart. Browser worker collectors, initial Windows and Android collectors, the Kotlin suspend/Flow runtime, Dart state/sensor contracts and Flutter screen/lifecycle observers are implemented and tested. Flutter Android connects twenty state collectors, including seven multi-target kinds, and seventeen sensor mappings through background workers. The initial React Native Android transport/TurboModule connects native queries and app-owned state/permission/lifecycle inputs; an actual RN 0.88.0/Hermes app passes representative read/watch, screen-change and sensor lifecycle checks on an API 36 emulator. Swift, remaining Flutter collectors/platform plugins, the full React Native matrix and the complete acceptance matrix are still required. Entity declarations alone are not a claim of platform support.

## Build and verify

The latest [React Native application checkpoint](docs/verification/2026-11-11-react-native-app.md) verifies the autolinked Hermes/JSI application on API 36: eight baseline scenarios, independent kernel-memory agreement, an actual window change and native sensor release/resume. RN API 26 execution, physical-device coverage and external package consumption remain unverified.

The [React Native observer checkpoint](docs/verification/2026-11-11-react-native-observers.md) adds app-owned screen/state, permission and lifecycle protocol handling to the native transport. Native/app target identities stay separate, and paused sensors still receive errors and removal. Full application/framework/platform verification remains required.

The latest [sensor inventory verification](docs/verification/2026-11-11-flutter-android-inventory.md) adds native connection observation, metadata updates without resubscription, generation-safe removal and whole-inventory deadlines. Dart 48/48 in JIT/AOT, Flutter 22/22, native bridge 12/12 and actual APK 33/33 on each API 26/36 pass.

The preceding [shared-context verification](docs/verification/2026-11-11-flutter-android-mixed.md) covers simultaneous native state/sensor work, scoped cancellation/failure and actual Activity lifecycle through one DeviceAccess: 33 APK scenarios pass on each API 26/36.

The [Dart/Flutter Android capability checkpoint](docs/verification/2026-11-11-flutter-android-capabilities.md) adds passive `capabilities.get(entity)` queries with separate permission state, explicit source registration and worker-owned native probes.

```sh
npm ci --workspaces=false --ignore-scripts
npm test
npm run test:browser
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
