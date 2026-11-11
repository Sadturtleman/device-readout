# Web orientation observer verification — 2026-11-11

`observeWebOrientation(access, source)` now connects application-owned DeviceOrientation events to RelativeOrientation and AbsoluteOrientation targets. Registration and discovery are inert. Each get/watch obtains its own native listener through the existing sensorSource bridge; cancellation, inactivity, failure and context closure release that listener. SDK calls never request permission or inspect screen rotation.

The adapter converts native intrinsic Z–X′–Y″ angles to named x/y/z/w unit quaternions with device-to-reference direction. Relative samples retain the native collection session reference. Absolute samples use east/magnetic-north/up. An event with a mismatched absolute flag, missing angle or nonfinite angle yields a whole null value. No screen correction, first-sample rebasing or fabricated orientation is applied. These conventions follow the [Device Orientation model](https://www.w3.org/TR/orientation-event/#model) and its linked [Earth reference frame](https://www.w3.org/TR/orientation-sensor/#absoluteorientationsensor-model).

Absolute targets prefer deviceorientationabsolute when the supplied source exposes it. Otherwise they consume only absolute=true samples from deviceorientation; relative-only samples yield null. Relative targets are registered only when deviceorientation exists. This is an event-source inventory, not a claim that physical sensors or permission are available.

## Results

`npm test` passes TypeScript 5.0.4 library/consumer builds, 25 core tests and five browser mapping tests. `node --test packages/web/test/browser.test.mjs` passes 38 browser cases: 19 each on Chrome 158.0.8127.18 and Edge 157.0.4341.42.

| Scenario | Evidence |
|---|---|
| Quaternion axes, multiplication order and device-to-reference direction | Controlled native DeviceOrientationEvent fixtures; expected transformed basis vectors, including a composite rotation |
| Equal samples, nonzero first relative pose, zero, incomplete/nonfinite sample and mismatched frame | Controlled application event source; every native event preserved, whole invalid value null |
| Generic-event absolute fallback, absolute-only source and unsupported source | Controlled application event-source capabilities |
| Pause/restart, persisted page transition and stale callbacks | Controlled app visibility/page-transition observations; listeners released while inactive; fresh listener on resume |
| Native getter exception, removal and reattachment | Typed ReadFailed/EntityRemoved; no uncaught page error; retired handles stay invalid |
| Native relative/absolute orientation readings | Actual trusted browser events from CDP platform virtual sensors, through the public adapter and collection worker |
| Native source cleanup | Both virtual orientation sensors report requestedSamplingFrequency=0 after disposal |
| Permission request isolation | Installed native requestPermission trap records zero SDK calls |
| Permission denial and re-grant | Actual native PermissionStatus changes, app observer publishes state/failure; both affected streams fail; new reads receive changed native poses after re-grant |

CDP supplies RelativeOrientation (0,0,√½,√½) and AbsoluteOrientation (½,½,½,½). A later relative sample rotates 45° around Y. SDK results match the supplied quaternions within native precision, allowing q and −q to represent the same rotation. Native virtual input replaces the browser's platform sensor, not the SDK collector. [CDP sensor commands](https://raw.githubusercontent.com/ChromeDevTools/devtools-protocol/master/json/browser_protocol.json).

The permission experiment found that denying the magnetometer descriptor in these Chromium versions also changes accelerometer and gyroscope to denied. The fixture observes all native statuses and reports failures for their dependent entities; it does not assume per-descriptor independence. This also exposed a core defect: a kind-level permission observation was not visible when checking a target. TypeScript, Kotlin and .NET now inherit the kind observation unless the app explicitly supplies a target status, including null. Pending permission requests follow the same rule; an unrelated kind update cannot override an explicit target status. Public regressions in all three runtimes reproduce the previous null response and cover both check and request behavior.

The native parity changes pass 21 Kotlin core tests, 13 Android service contract tests and 19 .NET checks. Android AAR/test APK assembly and lint pass; the .NET build has zero warnings/errors. An existing Kotlin screen observer fixture failed under build load because its fixed 40 ms delay did not guarantee receipt of the first snapshot. It now waits for the first public Flow value before publishing the next input, and the full build passes. This fixture correction does not change runtime semantics. Logs: `.tools/permission-inheritance-android.log`, `.tools/permission-inheritance-dotnet.log`; the red regression logs are retained separately.

The existing blocked-worker deadline scenario still passes with 30 host heartbeat ticks during 150 ms in both browsers. Orientation event callbacks perform only bounded angle-to-quaternion conversion and sample posting; schema normalization and timestamping remain worker-owned. This establishes scheduling responsiveness, not zero CPU cost or process-crash isolation.

Logs: `.tools/web-orientation-node.log`, `.tools/web-orientation-browser.log`. Native evidence: `.tools/evidence/orientation-{chrome,edge}.json` and `.tools/evidence/orientation-permission-{chrome,edge}.json`.

## Remaining work

Actual hidden/visible and back/forward-cache transitions, physical hardware/compass calibration, Safari/Firefox and the latest-two-version matrix remain unverified. Event APIs expose no frequency control; the SDK preserves delivered events and does not synthesize an interval or undo native thresholding. Browser-native fusion accuracy is outside these virtual-input checks.

Generic Sensor, remaining sensor kinds and broader browser fields remain pending. Android on-device instrumentation was not repeated for the shared permission-observer change; JVM/service tests and Android build/lint provide this checkpoint's native evidence. Apple, Flutter, React Native and the full release acceptance matrix remain incomplete; the overall implementation goal stays active.
