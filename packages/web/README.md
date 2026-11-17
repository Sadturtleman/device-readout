# DeviceReadout for browsers

Development package, not published. Use with `@device-readout/core` 0.1.0.

The `@device-readout/web/dart-worker` export supplies a module-worker asset for Dart's `DeviceAccess.web(workerUri: ...)`. It reuses these collectors and normalizes app-observed values in the worker; [Dart usage and verification](../../docs/verification/2026-11-17-dart-web-worker.md) describe asset serving and the current coverage. The ordinary TypeScript entrypoint continues to use `worker.js`.

```ts
import {RamEntity, Duration} from '@device-readout/core';
import {createWebDeviceAccess} from '@device-readout/web';

const access = createWebDeviceAccess();
const ram = await access.get(RamEntity);
const polling = access.withPollInterval(Duration.seconds(2));
for await (const snapshot of polling.watch(RamEntity, {signal})) {
  render(snapshot.advertisedBytes);
}
access.close();
```

Ship `dist/worker.js` beside the entry module, or pass a same-origin module-worker URL in `createWebDeviceAccess({workerUrl})`. Your CSP must allow this worker. Importing or constructing the SDK does not start a worker. Core stays a peer dependency so Entity handles retain their identity across packages. The worker contains its own collector runtime.

The implemented worker collectors are DeviceInfo, Os, Runtime, Cpu, Ram, Locale, TimeZone, NetworkPath, NetworkPerformance and OriginStorage. Their availability depends on the browser's exposed APIs. A missing whole API produces `UnsupportedEntity`; individual unavailable fields are null. Viewport, Display, motion/orientation events and eight Generic Sensor families additionally have explicit application observers. The remaining entities do not have native browser collectors yet. Custom screen and permission state can also be supplied through `access.observers`; see the root README.

The worker never accesses Window or the DOM. It reads `WorkerNavigator`, `Intl`, StorageManager and User-Agent Client Hints. It does not call `persist()`, request screen access, generate identifiers or send telemetry. Network and locale changes use worker events; other supported state entities use serial polling. The bounded consumer queue fails explicitly rather than silently dropping snapshots.

`Cpu.availableLogicalProcessorCount` comes from hardwareConcurrency; physical processor counts stay null. RAM uses `advertisedBytes`; physical RAM stays null. Origin quota is separate from physical disk space. Browser online state does not populate internet validation. Desktop-class client hints do not distinguish laptops and desktop hardware, so that hint does not fill formFactor.

## Application viewport observer

```ts
import {createWebDeviceAccess, observeWebViewport} from '@device-readout/web';

const access = createWebDeviceAccess();
// Call from the application's window lifecycle. Passing Window is explicit.
const viewport = observeWebViewport(access, window);
try {
  for await (const snapshot of access.watch(viewport.entity, {signal})) {
    render(snapshot.size, snapshot.visualViewportSize, snapshot.visualViewportScale);
  }
} finally {
  viewport.close();
  access.close();
}
```

`observeWebViewport` copies the initial state and subscribes to Window and VisualViewport `resize` events. It does not start a worker until the first SDK operation. Only these application observer callbacks read the window; `get` and `watch` consume the observed data through the worker. Each event publishes a complete snapshot input, including equal values. No timers, DOM elements, CSS probes, orientation locks or permission prompts are created.

`size` is the layout viewport in CSS pixels, including scrollbars. `visualViewportSize` and `visualViewportScale` use VisualViewport; they remain null if unavailable. A field whose native getter fails is null, and zero remains zero. `safeAreaInsets` and `textScaleFactor` are null: this adapter does not insert style probes or treat page/pinch zoom as text scaling. A viewport is not a physical display.

Each observation returns its own context-local typed entity; multiple application windows/frames can be observed. Same-origin access is required; inaccessible windows fail with `PermissionDenied` before target registration. `close()` is idempotent, removes the listeners and retires the target. `pagehide` also retires it, including entry into the back/forward cache; the app must attach a new observation on `pageshow` when restoring. Reattachment never revives an old handle. Dispose the observation with its owning application lifecycle, before closing the SDK. Ordinary tab visibility or focus changes do not retire this viewport, and this adapter does not change the sensor activity input.

## Application display observer

```ts
import {createWebDeviceAccess, observeWebDisplays, type WebScreenDetails} from '@device-readout/web';

const access = createWebDeviceAccess();

// Called by the app after its screen-access flow obtains native ScreenDetails.
function connectScreens(details: WebScreenDetails, permission: PermissionStatus) {
  return observeWebDisplays(access, window, details, {permission});
}

// After connecting, use the same typed discovery/get/watch interface.
const current = await access.displays.current();
if (current) {
  const snapshot = await access.get(current);
  render(snapshot.logicalBounds, snapshot.scaleFactor);
}
```

The app obtains `ScreenDetails` with its own `getScreenDetails()` permission interaction and may supply the native `PermissionStatus` returned by its Permissions API query. The SDK never invokes either API. `WebScreenDetails`/`WebScreenDetailed` are structural types for TypeScript DOM libraries that do not yet declare this browser API. The `PermissionStatus` in this example is the browser's native type, not DeviceReadout's permission enum.

Use one active display observer per DeviceAccess context, associated with the app window whose current display should be selected. `screenschange`, `currentscreenchange`, per-screen `change` and current-window orientation events feed the observed state. Native object identity distinguishes screens with the same label. Removal permanently retires a handle; reconnecting creates a new one. Current selection follows the browser, without choosing a default monitor arbitrarily. The app owns `close()`; pagehide also disposes the observation. Close it before replacing it or closing the SDK.

The adapter reports label, primary/internal flags, logical/work-area bounds, native screen devicePixelRatio as scaleFactor and color depth. Pixel size is the logical screen size multiplied by that screen's ratio and rounded to integers. It does not use Window.devicePixelRatio, which can reflect page zoom. Current-display orientation/angle come from the app window's ScreenOrientation. Other displays' orientation fields remain null because Chromium's ScreenDetailed orientation can describe the window's current screen. Physical millimeters, power state, DPI, modes, refresh rate, gamut, HDR formats and brightness remain null.

When a native PermissionStatus is supplied, its observed state updates `access.permissions.check(DisplayEntity)`. Denied/prompt states block display get/watch/discovery with PermissionDenied. Re-granting refreshes the inventory for new calls; terminated streams stay terminated. Unrelated screen events do not complete a pending app permission interaction. If no PermissionStatus is supplied, the app must close or fail its observation when screen access is revoked; this adapter does not infer authorization from cached ScreenDetails.

An inventory callback failure is reported through the adapter's independently owned `access.observers.failureSource(DisplayEntity)` handle. Cached values are invalidated, including the cache used after worker reconnect. Later successful input clears only that adapter's failure after publishing fresh state; application policy and other providers remain intact during recovery and disposal. This is an explicit observer-state update; a failed stream is never restarted automatically. An empty observed inventory is an empty list, not an unsupported collector placeholder.

Newer inventory callbacks take precedence over stale initial getter results or exceptions. Listener cleanup failures cannot prevent target retirement or release of the adapter's error slot; old callbacks are gated after removal and after reattachment of the same native screen object. See the [ownership, ordering and cleanup verification](../../docs/verification/2026-11-17-web-display-ownership.md).

Verified on Windows with Chrome 158.0.8127.37 and Edge 157.0.4341.60: actual resize/navigation, browser-emulated visual zoom, native headless monitor addition/removal/rename, current-screen movement, permission revoke/re-grant and controlled native-getter failures. This is not the full latest-two-version browser matrix. Physical monitor/hotplug and fractional scaling, actual hidden/visible sensor lifecycle, Firefox and Safari still require verification. Actual back/forward-cache restoration, physical mobile keyboards and pinch gestures remain unverified.

## Application motion and activity observers

```ts
import {AccelerometerEntity} from '@device-readout/core';
import {createWebDeviceAccess, observeWebMotion, observeWebSensorActivity} from '@device-readout/web';

const access = createWebDeviceAccess();
const activity = observeWebSensorActivity(access, document);
const motion = observeWebMotion(access, window);
try {
  const [accelerometer] = await access.sensors.list(AccelerometerEntity);
  if (accelerometer) {
    for await (const snapshot of access.watch(accelerometer, {signal})) {
      render(snapshot.value);
    }
  }
} finally {
  motion.close();
  activity.close();
  access.close();
}
```

`observeWebMotion` registers Accelerometer, LinearAcceleration, Gravity and Gyroscope targets. It starts no motion listener during attachment, discovery or description. Each get/watch opens its own observation when requested by the collection worker. Get awaits the next event; watch preserves every delivered event, including equal values. Closing a stream, its adapter or the SDK removes its native listener. Removing an observation retires its handles. A later attachment creates fresh handles. The browser exposes an aggregate event source, not a physical sensor inventory; its hardware name/vendor/range/rate metadata remains null.

Acceleration vectors use the event's native device axes and m/s². Gravity is accelerationIncludingGravity minus acceleration from the same event. The current DeviceMotion rotationRate mapping is alpha→X, beta→Y, gamma→Z; values are converted from degrees/s to rad/s. Any unavailable/nonfinite component makes the whole vector null. Screen orientation is not queried or applied. DeviceMotion has no frequency option: withSensorSamplingRate is accepted by the common interface, but this adapter preserves the browser's events without creating, dropping or resampling them.

The motion callback performs only a fixed-size scalar copy/unit conversion and posts the sample. Snapshot normalization and collectedAt stamping run in the worker. The adapter calls neither DeviceMotionEvent.requestPermission nor navigator.permissions.query. The app owns permission interactions, publishes status through `observers.permission`, and reports a blocking error with `observers.failure` when permission is revoked. Clear that failure after observed re-authorization; failed streams remain ended and a new get/watch can collect again. Without an app failure input, a browser that silently withholds events may lead to the first-sample read timeout.

Use one `observeWebSensorActivity` per SDK context. Its initial callback and visibilitychange/pageshow callbacks copy the supplied Document's visibility; pagehide deactivates sensors. SDK calls do not query Document. Inactivity releases source subscriptions, and resuming starts fresh sessions. Watch's first-sample timer is suspended while inactive; get retains its overall read deadline. The activity adapter's close leaves sensors inactive. The motion adapter retires targets on a non-persisted pagehide; persisted pagehide keeps its registration available for a new session on restore. Actual back/forward-cache restoration is still unverified.

Native DevTools virtual accelerometer/linear-acceleration/gyroscope input and native PermissionStatus changes pass through real Chrome/Edge events and the worker. Native requested sampling frequencies return to zero after disposal. Controlled visibility/page transition fixtures verify release/resume and stale-event rejection; the available headless window/tab actions did not produce a real hidden transition. Generic Sensor now has a separate adapter below; other sensor kinds, real visibility transitions and physical mobile devices remain pending.

## Application orientation observer

```ts
import {RelativeOrientationEntity} from '@device-readout/core';
import {createWebDeviceAccess, observeWebOrientation, observeWebSensorActivity} from '@device-readout/web';

const access = createWebDeviceAccess();
const activity = observeWebSensorActivity(access, document);
const orientation = observeWebOrientation(access, window);
try {
  const [sensor] = await access.sensors.list(RelativeOrientationEntity);
  if (sensor) {
    for await (const snapshot of access.watch(sensor, {signal})) {
      render(snapshot.value); // Quaternion | null, with named x/y/z/w components.
    }
  }
} finally {
  orientation.close();
  activity.close();
  access.close();
}
```

The explicit source registers RelativeOrientation when `ondeviceorientation` exists. AbsoluteOrientation uses `deviceorientationabsolute` when exposed, otherwise the general event with `absolute === true`. A relative sample on an absolute target, or an absolute sample on a relative target, produces `value: null`. A source exposing neither event fails with UnsupportedEntity before registration. Event support does not guarantee hardware availability or permission; metadata fields other than kind remain null.

All three finite native angles are converted from intrinsic Z–X′–Y″ degrees into a device-to-reference unit Quaternion. Absolute reference is east/magnetic-north/up; relative reference is the native session's reference and is not rebased to the first SDK sample. The adapter does not use compass-heading extensions, true-north substitutions or screen rotation. A missing/nonfinite angle makes the whole value null. Equal events are retained. These event APIs have no frequency option, so a requested sampling rate does not cause SDK resampling.

The same lazy-source and activity rules as motion apply: get waits for a fresh event, native listeners follow active get/watch sessions, and close or a non-persisted pagehide retires targets. A persisted pagehide preserves registration for resume; use the activity adapter to release active sessions. Actual browser back/forward-cache restoration is not yet verified. Callbacks perform fixed-size quaternion conversion and post a sample; the worker normalizes and timestamps it.

Permission UI and native PermissionStatus observation belong to the app. Relative orientation depends on accelerometer/gyroscope; absolute orientation additionally depends on magnetometer. Publish typed SDK status with `observers.permission` and a blocking failure with `observers.failure` when a dependency is denied. Clear the failure after the app observes authorization, then start a new read/stream. Chromium may group sensor permission descriptors; observe all required statuses rather than assuming one descriptor changes independently. Kind-level SDK permission observations apply to targets unless an explicit target status, including null, overrides them. The adapter itself never calls requestPermission or navigator.permissions.query.

Actual Chrome/Edge virtual orientation input, resource release and native permission revoke/re-grant pass through the worker. See [orientation verification](../../docs/verification/2026-11-11-web-orientation.md) for evidence and remaining physical-device/browser coverage.

## Application Generic Sensor observer

```ts
import {AccelerometerEntity} from '@device-readout/core';
import {
  createWebDeviceAccess, observeWebGenericSensors, observeWebSensorActivity,
  type WebGenericSensorPermissions,
} from '@device-readout/web';

async function consumeSensors(permissions: WebGenericSensorPermissions, signal: AbortSignal) {
  const access = createWebDeviceAccess();
  const activity = observeWebSensorActivity(access, document);
  const sensors = observeWebGenericSensors(access, window, permissions);
  try {
    const [target] = await access.sensors.list(AccelerometerEntity);
    if (target) for await (const snapshot of access.watch(target, {signal})) render(snapshot.value);
  } finally {
    sensors.close();
    activity.close();
    access.close();
  }
}
```

The app supplies native PermissionStatus objects under the typed `accelerometer`, `gyroscope`, `magnetometer` and `ambientLight` properties. It obtains those objects and performs any permission interaction outside SDK reads. Omitted/unknown/prompt/denied dependencies prevent native collection. Relative orientation needs accelerometer and gyroscope; absolute orientation also needs magnetometer. Permission loss ends affected observations even while native sessions are inactive. A fresh get/watch can run after authorization; the adapter clears only its own failure. App-owned failures remain intact.

Available constructors register Accelerometer, LinearAcceleration, Gravity, Gyroscope, Magnetometer, RelativeOrientation, AbsoluteOrientation and Illuminance targets. A target represents the browser's default source; constructor presence does not prove physical hardware. Descriptions require observed authorization, expose kind and leave unavailable metadata null. Discovery and permission inspection remain passive. Sensors are instantiated only for active demand, with device coordinates and optional requested frequency. Gets use platform defaults. Callbacks copy fixed-size samples; the worker normalizes values and stamps collectedAt. Dispose stops native objects; app-reported inactivity releases them and resume creates new ones.

The current Chrome/Edge default configurations expose six motion/orientation families. Magnetometer and Illuminance pass native virtual-sensor verification only with Chromium's experimental feature enabled; this is not default-browser support. The SDK itself changes no browser flags. With the subsequent display fixes, tests now pass 64 browser cases and 34 common/collector cases. See [independent ownership and inactive permission verification](../../docs/verification/2026-11-17-observer-failure-ownership.md). See [Generic Sensor evidence and remaining coverage](../../docs/verification/2026-11-16-web-generic-sensors.md).

Run `npm run test:browser` at the repository root. `DEVICEREADOUT_CHROME` and `DEVICEREADOUT_EDGE` can override executable paths. Tests use an ephemeral local HTTP server and isolated headless browser profiles; they do not attach to your existing browser session.
