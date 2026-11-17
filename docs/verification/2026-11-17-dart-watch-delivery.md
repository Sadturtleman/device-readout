# Dart watch delivery and polling — 2026-11-17

This checkpoint preserves the design's nonoverlapping polling, per-read timeout and independent subscription contracts. It does not complete the objective of all 46 entities, bindings, physical devices and platform/version acceptance matrices.

## Reproduced failures

1. A public Dart browser CPU watch with a 5 ms interval continued collecting snapshots while its consumer was paused. The real packaged browser worker was instrumented only at its outbound message boundary. During a 100 ms pause, it produced more than the one initial snapshot. Both Chrome and Edge failed the expectation that polling must not accumulate a delivery backlog.
2. With a warmed worker and a 150 ms read timeout, a first CPU snapshot completed while delivery was paused. Resuming after 300 ms reported ReadTimeout instead of the already-collected value. The common state watcher cancelled its initial deadline only on delivery, so consumer waiting was mistaken for collection time. Both browsers reproduced this independently after the polling correction.

The first fixture attempt dynamically imported the worker and lost the initial request before installing its listener. Static module loading corrected that harness issue; it is not counted as an SDK defect. The failure logs for the actual two regressions are `.tools/dart-web-polling-red-real.log` and `.tools/dart-web-paused-deadline-red.log`.

## Implementation

- The collector port retains its existing synchronous `send()` contract. An optional `deliver(response, signal)` hook allows a binding to await snapshot handoff before starting the next polling interval. Native event callbacks remain independent and do not wait for that handoff.
- The Dart worker assigns a delivery identity to each snapshot. Acknowledgements match both the watch and the snapshot. Dart acknowledges after incremental conversion, typed construction and stream handoff. A paused consumer therefore retains its pending polling result without creating later polling reads.
- Delivery waits are scoped to the watch's abort signal. Cancellation, a terminal failure or context closure cannot leave a waiter holding up another subscription. Event delivery remains bounded to 2,048 outstanding values per watch and fails explicitly with ReadFailed on overload; it does not silently remove duplicates.
- Native and web channels notify the common state watcher when a real snapshot has finished collection. This cancels the initial read deadline even when delivery is paused. A null native fallback signal is not collection completion. Subsequent reads retain their existing individual deadlines.

The first port implementation made `send()` return a promise. Existing Node transport tests and a TypeScript consumer returning an incidental `Array.push()` result exposed runtime/type incompatibility. The final optional hook preserves the old void callback contract; its compiler case is retained in the public consumer test. The Dart SDK and served Dart worker asset must come from the same build; mixed-version protocol compatibility is not claimed.

## Verification

| Command | Result |
|---|---|
| `./tools/test-dart-browser.ps1` | 16 grouped scenarios in each Chrome and Edge browser; final driver rerun after the shared collector change also passes |
| `./tools/test-dart.ps1` | 51/51 JIT and 51/51 compiled native contracts, clean analysis and missing-Worker negative check |
| `npm run check` | TypeScript consumer checks, 37/37 common/collector tests and 64/64 existing browser tests |
| `./tools/test-flutter.ps1` | Clean analysis and 22/22 framework checks |
| `./tools/test-flutter-web.ps1` | Both release builds; rendered example plus six application scenarios per Chrome/Edge browser, 4/4 Node parent tests |

Validated versions are Flutter 3.47.9 / Dart 3.13.7 on Windows x64, Chrome 158.0.8127.37 and Edge 157.0.4341.60. Flutter web builds retain the existing CupertinoIcons font warning and newer dependency-version notice; they are not warning-free builds.

The five added browser groups cover paused polling, completed-read deadlines, independent event/polling streams, cancellation/closure with pending delivery, and bounded native-event overload. The production worker's CPU reads are real browser collection. Language-change bursts are explicitly dispatched platform-event fixtures, including 3,000 attempted events for overload. A paused CPU watch stays paused while another watch delivers the initial locale and both equal events, and while a second CPU watch polls. Ending a paused watch does not release another poll; its shared worker remains reusable.

The added native Dart characterization pauses completed readings beyond readTimeout and receives `7, 7, 9` in order after resuming. It uses the public native collector seam and runs in both JIT and compiled executables; the independently reproduced browser failure established the common deadline correction first.

Local final logs are `.tools/delivery-common-browser-final.log`, `.tools/delivery-dart-browser-final.log`, `.tools/dart-delivery-native.log`, `.tools/delivery-flutter-framework.log` and `.tools/delivery-flutter-web-final.log`. Build output, profiles and raw local evidence remain excluded from version control.

## Remaining scope

One paused polling result can still be large. The existing 12,000-mode transfer scenarios verify cooperative traversal separately; this checkpoint does not establish a response byte budget, bounded browser structured-clone cost, arbitrary sustained-overload performance or a maximum UI frame time. The app owns its callbacks and sensor sources. Worker use does not provide process isolation or preempt arbitrary synchronous native work.

Physical sensors, native permission dialogs, Firefox/Safari/Wasm, Apple collectors/framework adapters, external package consumption and the complete field/version/platform acceptance matrix remain unfinished. Android/RN native applications and Windows screen applications retain their earlier evidence; they were not rebuilt in this checkpoint. Public `get(Entity)`, `watch(Entity)` and immutable settings remain unchanged.
