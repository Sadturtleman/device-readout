# Web motion and app sensor source verification — 2026-11-11

This checkpoint adds TypeScript lifecycle-managed application sensor sources, a web DeviceMotion adapter for four sensor kinds, and an explicit web visibility observer. The SDK still receives screen/permission/lifecycle state from the application and performs no implicit UI or permission interaction.

## Implemented behavior

`access.observers.sensorSource(target, {description, subscribe(session)})` registers an app-owned source without opening it. Worker get/watch demand creates a separate observation with typed samplingRate, AbortSignal, publish and fail callbacks. Get uses PlatformDefault; continuous watch uses its immutable frequency setting. A source returns native-listener cleanup. Metadata/discovery do not start collection, and kind-level capabilities now include registered observer targets.

Host callbacks copy samples; the worker normalizes fields and stamps collectedAt. Sensor values are not replayed as an initial sample. Inactivity releases the observation; resuming creates a fresh session and discards late callbacks from the old one. Watch's first-sample wait is suspended while inactive; get retains its read deadline. Paused source get/watch also receive explicit observer failures without starting the native source. Error, timeout, cancellation and context closure release app-owned subscriptions. Removing a source retires the handle permanently, including after worker reconnect.

`observeWebMotion(access, window)` registers Accelerometer, LinearAcceleration, Gravity and Gyroscope event-source targets. It attaches a native listener only for an active SDK observation and never invokes DeviceMotionEvent.requestPermission or navigator.permissions.query. The app publishes permission state and collection failures from its own observer.

| Entity | Value mapping |
|---|---|
| Accelerometer | accelerationIncludingGravity, device-axis vector in m/s² |
| LinearAcceleration | acceleration, device-axis vector in m/s² |
| Gravity | accelerationIncludingGravity minus acceleration from the same event |
| Gyroscope | rotationRate alpha→X, beta→Y, gamma→Z; degrees/s × π/180 |

The rotationRate axes were corrected after a native virtual-gyroscope test failed. The current normative getters and Chromium's implementation use this mapping; device-orientation Euler angles use a different order. [W3C rotation-rate interface](https://www.w3.org/TR/orientation-event/#devicemotioneventrotationrate), [Chromium motion event pump](https://raw.githubusercontent.com/chromium/chromium/main/third_party/blink/renderer/modules/device_orientation/device_motion_event_pump.cc).

All vector components must be finite; otherwise value is null. Zero and equal events are retained. DeviceMotion exposes no frequency setter, so this adapter forwards its native event cadence without resampling. Physical sensor metadata stays null. The adapter does not query or follow screen rotation.

`observeWebSensorActivity(access, document)` copies visibility initially and on visibilitychange/pageshow. Pagehide deactivates sensors. One app-owned activity observer should own each context. Closing it leaves sensors inactive. The motion adapter closes permanently on non-persisted pagehide; a persisted transition leaves its registration available for resumption. Actual back/forward-cache restoration is not yet verified.

## Evidence

Final TypeScript command: `npm test`. Library, core consumer and web consumer compilation use TypeScript 5.0.4. **Twenty-four core worker tests plus five browser worker mapping tests pass (29 total).** New cases cover lazy source registration/metadata, settings, fresh get, cleanup, permanent removal, inactive get/resumption, failure while paused, native source errors, deadlines and context close. Collectors run in actual Node worker threads.

Final browser command: `node --test packages/web/test/browser.test.mjs`. **Thirty cases pass** across Chrome 158.0.8127.18 and Edge 157.0.4341.42, including twenty previous screen/worker cases and these five new cases per browser:

| Case | Evidence level |
|---|---|
| Native accelerometer/linear-acceleration/gyroscope → browser motion events → worker snapshots | Native DevTools virtual-sensor backend; no JavaScript synthetic event is used in this case |
| Permission denial/re-grant reported by the app's native PermissionStatus observer | Actual browser permission state changes; denied stream ends, new read after re-grant returns changed native sensor values |
| Motion units, same-event gravity and fresh one-shot read | Controlled external EventTarget with native DeviceMotionEvent objects |
| Visibility pause/resume, no inactive watch timeout and stale event rejection | Controlled external visibility/page-transition event source in actual browsers |
| Equal samples, zero, whole-vector null, no frequency-based dropping and target retirement | Controlled external event source in actual browsers |

The native input values produce Accelerometer (2,3,10), LinearAcceleration (1,1,0.2), Gravity (1,2,9.8) and Gyroscope (π/2,−π/4,π). After disposal, the three native virtual sensors report requestedSamplingFrequency=0. An installed permission-request trap records zero SDK calls. Native sensor emulation is the browser protocol's platform-sensor override, not a replacement SDK collector. [DevTools protocol definitions](https://raw.githubusercontent.com/ChromeDevTools/devtools-protocol/master/json/browser_protocol.json).

The previous blocked-worker heartbeat case also passes in both browsers, retaining 30 host ticks during the 150 ms read deadline. This does not promise zero CPU cost or process-crash isolation. Motion callbacks perform only fixed-size copying/unit conversion; arbitrary snapshot normalization remains on the worker.

Logs: `.tools/web-motion-node.log`, `.tools/web-motion-browser.log`. Native evidence: `.tools/evidence/motion-chrome.json`, `.tools/evidence/motion-edge.json`. The exploratory `.tools/probe-web-sensors.mjs` checks environment exposure and lifecycle behavior; it is not production code. This host's Chrome exposed the tested sensor classes on Window, not in a dedicated Worker.

## Remaining evidence and implementation

The available headless browser actions (another tab, lifecycle freezing and virtual-window minimization) left document.visibilityState visible. They do not prove actual hidden/visible transitions. Controlled visibility fixtures establish SDK behavior, while actual tab/background/foreground and back/forward-cache transitions remain pending.

Generic Sensor and device-orientation adapters, magnetometer/other sensor kinds, physical mobile hardware, Firefox/Safari and the latest-two-version matrix remain pending. Generic Sensor start can invoke permission access, so a future adapter must preserve the app-owned authorization contract rather than implicitly opening a prompt. [Generic Sensor permission algorithm](https://www.w3.org/TR/generic-sensor/#request-sensor-access).

Kotlin/.NET/Android native builds and device instrumentation were not rerun for these TypeScript/web-only changes. The all-46-entity, all-binding release objective remains incomplete and active.
