# Web application viewport checkpoint — 2026-11-11

## Implemented contract

Added `observeWebViewport(access, window)` and its immutable `WebViewportObservation` return type. The application passes its Window explicitly. The observation owns a typed Viewport entity and an idempotent close method. Multiple application windows or same-origin frames can be connected independently. SDK import/construction and observer attachment do not start a worker; collection starts at an SDK operation.

The adapter copies the initial state and subsequent native Window/VisualViewport resize events into `access.observers`. Each input includes all Viewport fields. Worker normalization/timestamping and the existing typed get/watch interface are reused. The adapter creates no polling timers or DOM/CSS probes, requests no permission and does not change sensor activity or window settings. Equal native events remain deliverable.

| Field | Mapping |
|---|---|
| size | Window.innerWidth / innerHeight; layout viewport CSS pixels, including scrollbars |
| visualViewportSize | VisualViewport.width / height; CSS pixels |
| visualViewportScale | VisualViewport.scale |
| safeAreaInsets | null; no style probe is inserted |
| textScaleFactor | null; page/pinch zoom is not substituted |

A missing VisualViewport produces null visual fields. An individual getter failure makes that field null; zero dimensions are preserved. Cross-origin access fails with PermissionDenied before registration. Closing the observation or receiving pagehide detaches listeners and permanently retires the target; old get/watch operations fail with EntityRemoved. A new connection creates a new target, including after page-cache restoration. The app owns reattachment on pageshow and explicit disposal before SDK close. Ordinary tab visibility/focus changes do not retire this target.

## Red-to-green evidence

The public seam is observeWebViewport → typed get/watch/list, with real browser Window events. Native getter overrides are confined to one external-browser-API availability fixture; SDK internals are not mocked.

Four test slices per browser exposed and fixed these behaviors:

1. Missing viewport observation support. Real resizing from 800×600 to 640×480 now updates immutable snapshots. Chromium's visual zoom at 2 preserves layout 640×480 while reporting visual 320×240 and scale 2.
2. Navigation left a stale successful target. Real same-origin iframe navigation now terminates its old watch with EntityRemoved; a new observation succeeds and the old handle stays invalid. Legitimate resize events before pagehide are consumed before checking removal.
3. Cross-origin attachment threw an untyped native error and left a phantom target. A real opaque-origin iframe now produces PermissionDenied and leaves the previously valid target inventory unchanged.
4. One unavailable dimension getter failed the whole attachment. Controlled native property getters now yield null for the unavailable size, retain zero when it becomes available, and deliver repeated equal resize events. Getter probes confirm that get/watch, including a configured 1 ms poll interval, perform no extra UI property reads. Explicit detach prevents further reads; a callback after SDK closure detaches safely without an uncaught page error.

## Final checks

`npm test` passed with TypeScript 5.0.4, ES2020 output, all 46 generated models, core and web consumer type checks, seventeen core tests and five browser worker mapping tests.

`node --test packages/web/test/browser.test.mjs` passed all ten actual browser scenarios: four new viewport scenarios and one existing worker/permission/deadline scenario on each browser.

| Browser / host | Result | Host heartbeat during blocked-worker deadline |
|---|---|---|
| Chrome 158.0.8127.18 / Windows | 5 scenarios passed | 30 ticks |
| Edge 157.0.4341.42 / Windows | 5 scenarios passed | 30 ticks |

The existing responsiveness fixture blocks its dedicated worker for 2 seconds while the caller uses a 150 ms read deadline. The final browser run had no uncaught page errors. Browser fixtures use an ephemeral local server and isolated temporary headless profiles. Edge startup fails inside the tool sandbox, so the final browser tests ran in a normal user process; no existing browser profile was attached or modified.

Evidence: `.tools/viewport-node-checks.log`, `.tools/viewport-browser-checks.log`, `.tools/evidence/viewport-chrome.json`, `.tools/evidence/viewport-edge.json`, and the existing browser evidence JSON files refreshed by the final run.

## Limits and next work

This adds one browser entity adapter, alongside the ten worker collectors. It does not establish physical Display support, Generic Sensor/DeviceMotion adapters, actual hidden/visible sensor lifecycle, Firefox/Safari or the latest-two browser version matrix. Browser-emulated visual zoom is not a physical mobile pinch/keyboard test. Actual back/forward-cache restoration, window-process termination without lifecycle events, safe-area and text scaling remain unverified or unimplemented. Do not infer zero main-thread cost: the application observer necessarily performs a small Window-property copy on its callback path. Android, Windows, Kotlin and .NET tests were not rerun for this browser-only change.

The all-platform SDK goal remains active.

## Primary references

- [CSSOM View Window dimensions](https://drafts.csswg.org/cssom-view/#extensions-to-the-window-interface)
- [CSSOM View VisualViewport dimensions, scale and resize events](https://drafts.csswg.org/cssom-view/#the-visualviewport-interface)
- [HTML cross-origin WindowProxy access checks](https://html.spec.whatwg.org/multipage/nav-history-apis.html#security-infrastructure-for-window-windowproxy-and-location-objects)
