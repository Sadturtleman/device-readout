# Web Generic Sensor verification — 2026-11-16

`observeWebGenericSensors(access, source, permissions)` connects eight Generic Sensor families through the existing application-owned sensor-source interface. TypeScript 5.0.4 builds and consumer declarations pass. `npm test` passes **33/33** common/collector contracts; the actual browser suite passes **52/52**, including fourteen new cases across Chrome **158.0.8127.37** and Edge **157.0.4341.60**.

## Interface and collection

The application explicitly supplies its Window/sensor constructors and native PermissionStatus observers. Registration, list, describe and capability queries do not construct or start a native sensor. Each active get/watch owns a separate native sensor object. One-shot gets and PlatformDefault omit frequency; configured continuous watches pass their requested hertz. The adapter forwards every delivered reading without resampling. Cancellation, deadline, source error, inactivity and disposal stop the affected native object and remove its listeners. Resume creates a fresh object.

Each exposed constructor creates one logical browser-default target, not a physical hardware inventory. Missing constructors are omitted; no exposed supported constructor yields UnsupportedEntity. Constructor presence does not prove hardware availability. Native failures are typed: SecurityError/NotAllowedError become PermissionDenied, NotSupportedError becomes UnsupportedEntity, and other failures become ReadFailed. Sensor descriptions retain kind; unavailable native metadata remains null.

| Native constructor | Entity | Value convention | Required observed permission |
| --- | --- | --- | --- |
| Accelerometer | Accelerometer | Vector3, m/s², including gravity | accelerometer |
| LinearAccelerationSensor | LinearAcceleration | Vector3, m/s², excluding gravity | accelerometer |
| GravitySensor | Gravity | Vector3, m/s² | accelerometer |
| Gyroscope | Gyroscope | Vector3, rad/s | gyroscope |
| Magnetometer | Magnetometer | Vector3, μT | magnetometer |
| RelativeOrientationSensor | RelativeOrientation | Named x/y/z/w quaternion, native relative reference | accelerometer + gyroscope |
| AbsoluteOrientationSensor | AbsoluteOrientation | Named x/y/z/w quaternion, east/magnetic-north/up reference | accelerometer + gyroscope + magnetometer |
| AmbientLightSensor | Illuminance | Number, lux | ambientLight (native ambient-light-sensor) |

Spatial sensors explicitly request the device reference frame. Native scalar/vector/quaternion values are copied without screen correction, unit substitutions or first-pose rebasing. Nonfinite/missing vector components invalidate the whole value in the worker. Native timestamps are not exposed as Unix time: the worker supplies the single collection-completion collectedAt. These mappings follow the [accelerometer](https://www.w3.org/TR/accelerometer/), [gyroscope](https://www.w3.org/TR/gyroscope/), [magnetometer](https://www.w3.org/TR/magnetometer/), [orientation](https://www.w3.org/TR/orientation-sensor/) and [ambient-light](https://www.w3.org/TR/ambient-light/) definitions.

Permission observers are read only during explicit attachment/change callbacks. All dependencies must have an observed granted state before construction and again before start. Missing, unreadable, prompt or denied state cannot authorize collection. Active observations fail when a dependency loses authorization; reauthorization permits a new get/watch. The adapter does not query permissions, invoke permission request methods, or clear application-owned failure state. The [Generic Sensor start algorithm](https://www.w3.org/TR/generic-sensor/#sensor-start) performs its own platform permission processing; observed authorization is required before invoking it. Browser-owned permission changes remain subject to native event delivery.

Framework/native callbacks perform a fixed-size copy on the browser main thread. Normalization, stamping and collection orchestration use the SDK worker. This retains the observer requirement without claiming zero UI-thread overhead or process isolation. Use `observeWebSensorActivity` for app-owned visibility/page lifecycle state, and close observations before closing DeviceAccess.

## Verification and corrections

The first accelerator contract failed because the adapter was absent. The subsequent family contract reproduced missing target discovery until the remaining mappings were connected. A separate reentrant-permission contract showed a sensor could start after its constructor synchronously reported lost permission. Rechecking observed authorization after construction fixes that regression; both browser tests now verify zero starts for the denied object and exactly one stop.

Four controlled cases per browser cover lazy metadata and denied access, independent get/watch settings, duplicate samples, all eight value shapes/units, grouped nulls, worker timestamps, constructor-time permission loss, application failure preservation, request-scoped deadlines/errors, failed native getters, throwing cleanup and ignored stale callbacks. Native browser cases separately exercise virtual hardware through the actual Generic Sensor implementation and worker, plus real PermissionStatus denial/regrant.

| Runtime evidence | Chrome | Edge |
| --- | --- | --- |
| Default browser configuration | Six families: acceleration, linear acceleration, gravity, gyro, relative/absolute orientation | Same six |
| Experimental GenericSensorExtraClasses configuration | All eight, adding magnetic field and illuminance | All eight |
| Requested 17 Hz | Six motion/orientation families report 17 Hz; magnetic/light report native 10 Hz caps | Same |
| No active demand / app-reported inactivity / final disposal | Native requested frequencies return to zero | Same |
| Resume | Fresh native objects deliver samples | Same |
| Native permission revoke/regrant | Streams fail PermissionDenied; later get receives updated values; final frequency zero | Same |
| Existing blocked-worker responsiveness check | Host timer advances 30 ticks during the bounded wait | 30 ticks |

The experimental test configuration uses Chromium's [own extra-sensor test flag](https://chromium.googlesource.com/chromium/src/+/main/third_party/blink/web_tests/VirtualTestSuites), `--enable-features=GenericSensorExtraClasses`. This is not evidence of ordinary default-browser availability for magnetic field or light. A renderer-only flag initially exposed constructors while the service refused collection; the fixture was corrected to the official feature flag. Initial exact input comparisons also revealed native precision reduction, so fixed virtual inputs use representable values and small native-unit tolerances. The SDK does not reverse browser precision or frequency limits.

Commands: `npm test`, then `node --test packages/web/test/browser.test.mjs`. Local logs are `.tools/web-generic-core-full.log` and `.tools/web-generic-browser-full.log`. Per-browser JSON evidence under `.tools/evidence/generic-sensors-*-default.json`, `generic-sensors-*-experimental.json` and `generic-sensor-permission-*.json` records versions, native values, requested frequencies and permission outcomes. Logs and browser profiles remain ignored local artifacts.

## Remaining scope

The [2026-11-17 follow-up](2026-11-17-observer-failure-ownership.md) adds independent failure owners, verifies native permission loss while inactive, and records 56 browser / 34 common tests. It also clarifies that descriptions are blocked while authorization is absent. Counts above preserve this original checkpoint.

Physical hardware, Firefox/Safari and the exact latest-two-version matrix remain unverified. Real visibility/background and BFCache transitions, additional attachment/detachment races and broader multiple-observer ownership need further evidence. Remaining sensor families require meaningful browser sources where available; they are not synthesized from unrelated APIs. These results do not complete the whole SDK or change its release requirements.
