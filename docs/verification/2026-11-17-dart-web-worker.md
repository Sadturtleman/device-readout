# Dart browser worker connection — 2026-11-17

Scope: an actual browser transport for the common Dart API, preserving existing native behavior and app ownership of UI, permission, lifecycle and sensor inputs. The objective still includes every specified field, binding and complete platform/acceptance matrix.

## API and architecture

`DeviceAccess.web(workerUri: Uri)` accepts the served URL of the SDK's module worker. Construction and watch creation are inert; first demand starts one worker per shared context. Immutable configuration views retain the same context without changing existing streams. Disposal terminates that owned worker exactly once.

The asset is built as `packages/web/dist/dart-worker.js` and exported by the web package as `@device-readout/web/dart-worker`. Applications must serve it and pass its URL; registry publication and automatic Flutter asset packaging remain pending. The adapter reuses BrowserCollector and the common worker endpoint. It forwards native get/watch/support/discovery operations where implemented. App-owned discovery stays in the Dart context; observed state, sensor samples and descriptions are sent to worker normalization. Event sensors require a true occurrence. The worker performs range/group normalization and converts exact integer values to decimal strings before delivery. Dart materializes generated typed models without repeating quaternion/range normalization or replacing the worker timestamp.

The closure-based `DeviceAccess.isolated` constructor remains unsupported in a browser. A missing Worker API does not run collection or sensor sources on the host. Capability inference is now channel-specific so a working web channel and an unsupported isolate channel can coexist. Existing app permission checks/requests and lifecycle ownership remain in the common Dart runtime.

The transport bounds pending requests and native watches to 128 each and pending watch delivery to 2048 snapshots. Overflow fails explicitly. Equal state polls are retained; worker notifications use per-read deadlines without an overall idle-stream deadline. Caller cancellation and context disposal finish without waiting for a held worker. Worker loading/protocol failures are typed and remain terminal for the affected context rather than silently restarting it.

## Reproduced defects

The first public consumer failed to compile before web access existed. Subsequent public get/watch and observer cases reproduced unsupported stream and normalization paths before implementation.

A held-worker fixture then exposed eager materialization of responses whose requests had already timed out or been cancelled. A response-boundary getter proves those payloads were traversed; they now are discarded by request ID before Dart conversion, and later reads recover. The fixture uses actual browser Worker messaging with controlled host-side response instrumentation.

A separate response getter delays live materialization by 200 ms after a warmed worker responds. The original get path reported success despite its 100 ms deadline. Get and watch now check monotonic elapsed time around materialization; the two cases return ReadTimeout. This test deliberately delays the host at the external boundary. It verifies the resulting error contract, not responsiveness during arbitrary synchronous host work.

Common TypeScript normalization also accepted fractional values in Size<Integer>. A public Display observer test reproduced a fractional pixelSize escaping. Integer component validation now nulls that grouped field, while independent fractional logical geometry and mode refresh rates remain available. This prevents invalid wire pixel dimensions from reaching Dart's integer representation.

## Verification

| Suite | Result | Evidence scope |
| --- | --- | --- |
| Dart 3.13.7 compiled JavaScript / Chrome 158.0.8127.37 | 6/6 grouped scenarios | Actual module workers, browser CPU/language reads and controlled transport/observer fixtures |
| Same consumer / Edge 157.0.4341.60 | 6/6 grouped scenarios | Same scenarios, independently executed |
| Common/collector TypeScript tests | 37/37 | Includes new grouped integer-pixel regression; TS 5.0.4 and consumer checks |
| Existing TypeScript Chrome/Edge suite | 64/64 | Existing browser/native virtual-sensor, observer and worker contracts |
| Dart native JIT and compiled executable | 50/50 each | Existing native contracts preserved; strict analysis reports no issues |
| Compiled JS without Worker | Passed | Explicit web access and closure-based access fail without host collection |
| Flutter framework/engine | 22/22 | Existing display, viewport, lifecycle, inventory and blocked-native cases |

The six browser scenarios cover lazy typed reads and owned cleanup; cold native polling with duplicates and immutable configuration; observed screens, sensors, descriptions and typed target retirement; held-worker deadlines/cancellation/context closure; worker load/protocol failures; and live materialization deadlines. The held case exercises get timeout, caller cancellation, context closure and watch update timeout. Host timers advance during the 500 ms worker stall, queued reads keep independent deadlines and subsequent reads recover. Exact UInt64 maximum, zero and false are retained through the wire. The actual UI navigator CPU getter is replaced with a throwing fixture, confirming reads use the worker's navigator instead. No uncaught browser page errors remain.

Commands: `npm test`; `./tools/test-dart.ps1`; `./tools/test-dart-browser.ps1`; `node --test packages/web/test/browser.test.mjs`; `./tools/test-flutter.ps1`. Browser runs require access to the ephemeral localhost server. The Flutter framework suite runs in the normal-user environment due the previously documented sandbox compiler-file limitation.

Logs are local ignored artifacts: `.tools/dart-web-core-final.log`, `.tools/dart-web-native-verified.log`, `.tools/dart-web-delivery-green.log`, `.tools/dart-web-ts-browser-final.log`, `.tools/dart-web-flutter-final.log` and `.tools/dart-web-analyzer-final.log`. Red evidence includes `dart-web-read-red.log`, `dart-web-watch-red.log`, `dart-web-observers-red.log`, `dart-web-retired-red.log`, `dart-web-delivery-red.log` and `dart-web-pixel-red.log`. Browser reports are `.tools/evidence/dart-browser-{chrome,edge}.json`.

## Remaining scope and execution limits

Follow-up: the [transfer scheduling checkpoint](2026-11-17-dart-web-transfer.md) implements cooperative host marshaling/materialization, full-read admission and additional ordered-stream/lifetime checks. It records eleven browser scenarios per Chrome/Edge. The paragraphs below retain this initial connection checkpoint's original scope; the follow-up defines the current transfer evidence and remaining limits.

Live app snapshots must still be marshaled and received values materialized on the Dart host. Large-payload scheduling, response-size budgeting, full schema/enum wire equivalence, overload and pause/resume interleavings need further verification. A deadline check cannot preempt synchronous host work already executing. The implementation therefore does not establish zero main-thread cost or process-crash isolation.

All ten existing BrowserCollector kinds are connected structurally, but this checkpoint's actual native Dart browser reads cover CPU and language, with other values supplied by controlled fixtures. Full field/API coverage, native event and permission/lifecycle transitions through Dart, Firefox/Safari, Dart Wasm and real Flutter web applications remain pending. Android APKs, native bridge units, React Native apps, Apple collectors/builds and native Windows Flutter screen scenarios were not rebuilt here; their earlier evidence remains separate. External package consumption and the complete minimum/latest-version matrix remain unfinished.

JS interop declarations follow the official [Dart interop usage guide](https://dart.dev/interop/js-interop/usage) and [global-object property API](https://api.dart.dev/dart-js_interop_unsafe/JSObjectUnsafeUtilExtension/has.html). Browser behavior claims above come from this repository's test runs rather than those API references.
