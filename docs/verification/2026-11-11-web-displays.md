# Web display and permission observers — 2026-11-11

## Implemented scope

Added `observeWebDisplays(access, window, details, {permission})`, WebDisplayObservation and structural ScreenDetails types compatible with TypeScript 5.0. The app supplies already-obtained screen details and optionally a native PermissionStatus. The adapter never requests screen access or queries permission itself. Use one active display observer per DeviceAccess context, owned by the app window whose current display should be selected.

Display now joins Viewport as an explicit browser observer adapter, alongside the ten dedicated-worker entities. This is not complete browser or all-platform support.

The mapping includes screen label, primary/internal flags, logical/work-area bounds, native per-screen devicePixelRatio, color depth, and pixel size derived by multiplying logical size by that ratio and rounding. Current-screen orientation/angle use Window.screen.orientation; non-current orientation is null. Physical millimeters, power state, density DPI, display modes, refresh rate, gamut, HDR formats and brightness are not supplied by this adapter.

ScreenDetails inventory/current changes, individual screen changes and window orientation changes publish complete observer inputs. Native object identity distinguishes equal labels. Removed targets never rebind when an equivalent monitor returns. Close/pagehide detach listeners and retire all owned targets. SDK get/watch/list consume the observed data without native UI reads.

With a supplied native PermissionStatus, denied/prompt state blocks display reads and discovery with PermissionDenied. Re-grant refreshes the inventory for new calls; old streams remain failed. The adapter only publishes permission state initially or when it changes, so unrelated screen events cannot complete an in-progress application permission request. Without that input, the app must close or explicitly fail its observer when permission is revoked.

## Common TypeScript runtime changes

Added `observers.failure(entity, DeviceReadoutError | null)` for target or collection failures. A failure terminates matching streams and invalidates cached values on both sides of the worker connection. Clearing alone does not make old values current: a fresh observation is required. Fresh state received while an error is active is replayed in publication order. Removed-target tombstones survive late state publication and reconnect. An explicitly observed empty collection yields an empty list.

The corresponding Kotlin/.NET/other binding input is still pending; this checkpoint does not claim parity. Existing language-specific worker/native error paths are unchanged.

## Evidence and corrections

Five new browser scenarios run on each browser:

1. App-supplied native ScreenDetails map an additional virtual monitor, including negative origin, 2× scale, 30-bit color and work-area insets. Native rename/work-area events update its watch. Replacing Window.getScreenDetails with a throwing function confirms the SDK does not invoke it.
2. Native virtual-monitor addition/removal and current-window movement update discovery/current selection. Two screens with the same label remain distinct. Removal terminates the selected watch and re-addition never revives the old target.
3. Real browser PermissionStatus revoke/re-grant events drive typed errors and recovery. An app-coordinated permission request remains pending through unrelated screen events and completes on the native grant. Its old failed display stream never restarts.
4. A controlled external screen-inventory getter exercises empty inventory, read failure, recovery and disposal. SDK get/list/watch cause no additional inventory reads. Failure closes with typed ReadFailed; explicit disposal clears its failure state and returns an empty inventory.
5. A controlled external permission source changes during inventory collection. Partial refresh cannot clear PermissionDenied as if the collection had succeeded.

Three new common-runtime scenarios cover failure scope/cache invalidation, empty observed discovery, and fresh-state replay order. Their initial failures exposed stale pre-error values, incorrect replay ordering, and late state callbacks replacing removal tombstones. These were corrected and retested through the public APIs with actual Node worker threads.

The native probe also exposed that Chromium's non-current ScreenDetailed orientation reflects the app window's current screen. The adapter therefore leaves those fields null. CDP display rotation and the web orientation angle use different conventions: the 90-degree virtual-screen fixture reports a web angle of 270 after the window moves there, which the SDK preserves. These findings are from browser-native values, not an assumed formula.

The browser fixture originally used an async predicate with waitForFunction. Its readiness check was corrected to await the SDK result through page.evaluate and poll with a bounded deadline before asserting native transitions.

## Final verification

`npm test` passed on TypeScript 5.0.4 with ES2020 output: generation of all 46 entities, core/web consumer declaration checks, twenty common tests and five worker mapping tests. `node --test packages/web/test/browser.test.mjs` passed all twenty scenarios after the final runtime corrections.

| Environment | Browser scenarios | Host heartbeat during blocked-worker deadline |
|---|---|---|
| Chrome 158.0.8127.18 / Windows | 10 passed | 30 ticks |
| Edge 157.0.4341.42 / Windows | 10 passed | 30 ticks |

The heartbeat fixture uses a 2-second blocked dedicated worker and a 150 ms caller deadline. Tests use isolated headless profiles and an ephemeral local HTTP origin. Screen changes and permission grants affect only these disposable browser fixtures, not the host's monitors or existing browser session. All launched test browsers were closed.

Evidence: `.tools/displays-node-checks.log`, `.tools/displays-browser-checks.log`, `.tools/evidence/displays-chrome.json`, `.tools/evidence/displays-edge.json`, and the refreshed browser/viewport evidence JSON files. Native monitor and permission scenarios are separate from the controlled external getter/permission-source fixtures.

## Remaining work

Physical monitor hotplug, fractional display scaling, physical rotation, browser zoom effects, back/forward-cache restoration, Firefox/Safari and the latest-two-version browser matrix remain unverified. Multi-observer ownership conflicts in one SDK context are not arbitrated; the documented owner must replace/dispose its previous observer. Browser sensor adapters and real visibility-driven sensor lifecycle are pending. General concurrency, payload-size and overload validation still need the broader SDK audit. Android/.NET/Kotlin native tests were not rerun for these TypeScript/browser-only changes. App-owned UI callbacks necessarily perform a small state copy; this is not zero main-thread cost or process-crash isolation.

The full 46-entity, all-binding SDK objective remains active.

## Primary references

- [Window Management: screen details, identity and events](https://www.w3.org/TR/window-management/)
- [Chromium ScreenDetailed implementation](https://raw.githubusercontent.com/chromium/chromium/main/third_party/blink/renderer/modules/screen_details/screen_detailed.cc)
- [Chromium window-owned ScreenOrientation implementation](https://raw.githubusercontent.com/chromium/chromium/main/third_party/blink/renderer/modules/screen_orientation/screen_orientation.cc)
- [Official DevTools protocol: headless screens and test permission settings](https://raw.githubusercontent.com/ChromeDevTools/devtools-protocol/master/json/browser_protocol.json)
