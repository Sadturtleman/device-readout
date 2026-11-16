# DeviceReadout React Native binding

This is an implementation checkpoint, not a release-ready platform claim. The Android TurboModule compiles against React Native 0.88.0 and its actual generated interface. Native get/watch, discovery/current, capabilities, sensor metadata, native inventory notifications and app-owned state/permission/lifecycle/sensor-source inputs connect to the existing Kotlin runtime. The autolinked Hermes/JSI example passes twelve baseline scenarios plus actual focus loss, window change and native sensor resume on API 26 and API 36 emulators: fifteen reported passes each, with independent kernel-memory and sensor-registration checks. See [independent observer failure verification](../../docs/verification/2026-11-17-observer-failure-ownership.md), [framework-observer verification](../../docs/verification/2026-11-16-react-native-framework-observers.md) and the preceding [app-owned sensor-source verification](../../docs/verification/2026-11-15-react-native-sensor-sources.md).

The intended application entrypoint preserves the shared API:

```typescript
import { createReactNativeDeviceAccess, RamEntity, Duration } from '@device-readout/react-native';

const access = createReactNativeDeviceAccess();
try {
  const ram = await access.get(RamEntity);
  const stream = access.withPollInterval(Duration.seconds(2)).watch(RamEntity);
  // Consume stream with for-await; breaking the loop releases that subscription.
} finally {
  access.close();
}
```

Construction and stream creation do not start native collection. The first operation lazily opens one native context shared by immutable configuration views. Closing an idle transport cancels its requests; final `access.close()` releases the owning native context, including one whose creation finishes late. Always close the SDK context when its owner ends.

The TurboModule schedules request decoding, native queries, normalization, serialization and cleanup off the app entrypoint. Kotlin retains its collection worker and read deadlines. JavaScript performs bounded request encoding, response decoding and typed-value construction; this is not process isolation or a zero-cost JS-thread guarantee. JSON integer strings become exact `bigint` values, including category maps. Responses and commands have bounded queues and payloads. Full overload and engine-detachment interleavings remain unverified.

App-owned callbacks can publish through `access.observers.publish(entity, values)`, select `access.observers.current(kind, entity)`, report `permission(entity, status)`, and provide `sensorActivity(active)`. Register app targets with `target(kind, id)`; their names cannot alias native discovery handles. `remove(entity)` and `failure(entity, error)` also end affected inactive sensor streams. `failureSource(entity)` gives a provider its own typed error slot: publish an error, clear it with `publish(null)`, and release it with `close()`. Clearing that slot preserves application policy and other providers. These failures also reach inactive streams. Snapshot input omits collectedAt; the worker supplies the collection-completion timestamp. The native endpoint does not open a permission dialog or query an Activity/screen.

Register an app coordinator with `access.observers.onPermissionRequest(handler)` before using `access.permissions.request(entity)`. That explicit request notifies the coordinator, then waits for `observers.permission(entity, status)`. Returning from the handler does not complete the request, and the user-response wait has no read timeout. Merely calling get/watch does not request permission.

The application explicitly connects its framework observers. `observeReactNativeViewport` copies the initial window dimensions and subsequent event payloads into a typed target; SDK get/watch do not query Dimensions. It supplies logical `size` and `textScaleFactor`; visual viewport fields and safe-area insets remain null. The example independently compares results with `useWindowDimensions`.

```typescript
import {AppState, Dimensions} from 'react-native';
import {
  createReactNativeDeviceAccess,
  observeReactNativeSensorActivity,
  observeReactNativeViewport,
} from '@device-readout/react-native';

const access = createReactNativeDeviceAccess();
const viewport = observeReactNativeViewport(access, Dimensions);
const activity = observeReactNativeSensorActivity(access, AppState);
try {
  const snapshot = await access.get(viewport.entity);
} finally {
  activity.close();
  viewport.close();
  access.close();
}
```

Attach one sensor-activity observer per shared SDK context before starting sensor work, and close both adapters before closing the SDK. The default `ForegroundOnly` policy enables sensors only for AppState `active`; unknown and inactive states suspend them. The optional typed `ReactNativeSensorActivityPolicy.AllowInactive` also enables the inactive state when that matches the application's lifecycle requirements. Focus/blur alone do not change sensor activity. Desktop integration remains unverified. API 26/36 verification checks native registrations, fresh samples after resume and continued collection while the notification drawer removes focus. Permission coordination still uses controlled app observer state and does not validate an OS permission dialog.

The first native discovery registers one context-owned inventory observer on the collector worker. Callbacks refresh only previously discovered kinds, with serialized, bounded reads. A successful native list reporting a target absent ends requests and streams for that token with `EntityRemoved`; a replacement gets a new handle. This also works without another app list call when the native collector sends a change notification. Native refresh continues when an app-owned inventory takes over the public list, while preserving the app targets and values. Android currently supplies dynamic-sensor notifications. Controlled tests cover inactive and mixed-inventory removal, malformed refresh, blocked registration, synchronous failure and terminal observation failure. Physical hotplug and broader concurrent failure/replacement cases remain unverified.

`access.observers.sensorSource(target, {description, subscribe})` now connects app-owned sensor sources on Android. Registration and metadata reads are inert. Every get/watch receives its own observation; gets and event sources use the platform-default rate, while continuous watches receive their configured rate. Return listener cleanup from `subscribe`, copy event values with `session.publish`, and report a request-scoped error with `session.fail`. Cancellation, timeout, inactivity, removal and close abort the session and release its listener; resume creates a fresh session. Keep the app's JS subscription and cleanup callbacks nonblocking. Samples are decoded and normalized by native background work, and late samples cannot enter a different session.

**Still required:** Display, safe-area and visual viewport framework integrations, physical app-source plugin integration, broader source replacement/concurrency, all-kind native inventory notifications, broader mixed-inventory/target-retirement and malformed-input handling, blocked-event/cleanup and overload coverage, external package consumption and distribution, iOS/Windows/macOS/web adapters and the complete version/field/device matrix. The earlier [observer verification](../../docs/verification/2026-11-11-react-native-observers.md) retains its controlled-test scope.

The preceding example-only `Isolation` checkpoint passes deliberately blocked get/watch/close checks through the real TurboModule and Hermes on API 26 and API 36. Both JS and Android UI loops advance while collection is held, deadlines and close settle before external release, and the worker exits after release. That checkpoint retains its original build and eleven ordinary-app scenarios. See the [runtime evidence and limits](../../docs/verification/2026-11-15-react-native-isolation.md); the earlier [fixture checkpoint](../../docs/verification/2026-11-15-react-native-isolation-fixture.md) records compilation separately.

Verification from the monorepo root:

```powershell
./tools/prepare-react-native.ps1
npm run test:react-native
./tools/test-kotlin.ps1
./tools/build-react-native-android.ps1
# Actual APK; use a short Gradle cache path on Windows to avoid Ninja path limits:
./tools/build-react-native-app.ps1 -SdkRoot 'C:/path/to/Android/Sdk' -GradleHome 'C:/short/gradle-cache'
# Requires a running project-owned DeviceReadout AVD and SDK platform-tools:
./tools/test-react-native-android.ps1 -SdkRoot 'C:/path/to/Android/Sdk'
# Separate blocked-collector example and external-release verification:
./tools/build-react-native-app.ps1 -SdkRoot 'C:/path/to/Android/Sdk' -GradleHome 'C:/short/gradle-cache' -Variant Isolation
./tools/test-react-native-isolation.ps1 -SdkRoot 'C:/path/to/Android/Sdk'
```

Preparation installs the locked runtime only under `.tools/react-native-0.88`. The independent core still compiles with TypeScript 5.0.4. RN-specific declarations use TypeScript 5.9.3, React/types 19.3.0 and RN's own 0.88.0 TypeScript configuration, including its `skipLibCheck: true`. A separate strict dependency-declaration run reports upstream RN declaration errors; it is not a passing compatibility gate.

The standalone `build-react-native-android.ps1` script compiles Kotlin and generated Java with Gradle 8.14.3 / AGP 8.11.1 / Kotlin 2.2.20 / compile SDK 36 / min SDK 26. This remains a source/API compilation check. The actual example instead uses the RN 0.88.0 template toolchain: Gradle 9.4.1, AGP 9.2.1, Kotlin 2.2.0, compile SDK 37, build tools 37.0.0, NDK 27.1.12297006 and CMake 3.22.1; target SDK is 36 and min SDK is 26. It bundles JavaScript into the x86_64 debug APK without requiring a Metro server. The library directly compiles shared monorepo Kotlin sources; standalone publication remains a separate gate. See the [foundation record](../../docs/verification/2026-11-11-react-native-foundation.md) and [application evidence](../../docs/verification/2026-11-11-react-native-app.md).
