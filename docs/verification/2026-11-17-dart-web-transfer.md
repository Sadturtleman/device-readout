# Dart browser transfer scheduling — 2026-11-17

Scope: scheduling the Dart-side preparation and delivery of large browser snapshots through the existing public DeviceAccess API. The objective remains all 46 entities, every specified binding and the complete platform, physical-device, version and acceptance matrices. This checkpoint does not complete that objective.

The subsequent [Flutter web checkpoint](2026-11-17-flutter-web.md) exercises real compiled Flutter applications, framework observers and worker lifetimes in Chrome and Edge. The remaining physical/browser/platform matrix still applies.

## Reproduced problems

The preceding browser transport normalized values in its worker, but synchronously called toJson/jsify for observed input, dartify for incoming graphs, and collection decoders/constructors for typed output. Worker collection alone did not prevent these host traversals from occupying one event-loop turn.

A public get(Display) consumer now receives 12,000 display modes from an actual browser Worker. At the message boundary, the test schedules a host timer and instruments the final array element. Before the change, the SDK reached that element before the host timer could run, on both Chrome and Edge. The result must preserve all modes, ordering, false values and immutable output. This is an explicit scheduling check rather than a machine-speed threshold.

A second public observer/get case publishes 12,000 modes through the SDK's real normalization worker. A timer armed before get must run before the resulting request reaches postMessage. This also failed before the change. The worker normalizes a NaN refresh rate to null while retaining the final mode and leaving the application snapshot unchanged.

After introducing asynchronous preparation, an additional public test reproduced a gap in request admission: 129 simultaneous large reads could all start preparation before entering the existing RPC limit. Admission now covers the complete read lifetime. The 129th request fails with ReadFailed; cancelling the first 128 releases their slots before starting a worker, and a subsequent CPU read succeeds.

## Implementation

- A shared internal transfer budget checks operation validity during traversal and yields to an event-loop task after 512 steps or an observed 4 ms of slice time. It checks again after resuming. These are scheduling thresholds, not a guaranteed maximum pause or a new public configuration.
- Outgoing snapshots use a shallow field projection, then incremental JS array/object construction. Large graphs no longer enter synchronous toJson/jsify during SDK reads. Grouped normalization and completion stamping remain worker-owned.
- Incoming response IDs are still checked before payload traversal. Live JS graphs are copied incrementally into private Dart data; cancelled, expired and closed operations stop traversing and cannot poison subsequent reads. Invalid excessive nesting fails explicitly.
- Generated typed hydration traverses collections with the same budget. It wraps privately owned collections in unmodifiable views and uses private constructors to avoid a second synchronous collection copy. Public constructors keep their defensive-copy behavior. No partially constructed snapshot is exposed, and the worker's collectedAt is retained.
- Each watch read owns its deadline through queued materialization. Later reading headers cannot extend an earlier read's deadline. Raw and typed deliveries share the existing 2048-item admission limit and remain ordered. A normal worker end drains accepted values; cancellation/failure discards unfinished work. Pause/resume and duplicate delivery are preserved.
- The 128 active-read limit covers preparation, RPC and typed delivery. The separate existing RPC/watch bounds remain in effect. Admission errors and timeout/cancellation do not silently restart the worker.

The JS array view is used only to inspect one received element at a time, then copied into SDK-owned data. Its wrapping semantics are documented in the official [Dart JSArray conversion reference](https://api.dart.dev/dart-js_interop/JSArrayToList/toDart.html). The [unmodifiable-view reference](https://api.dart.dev/dart-collection/UnmodifiableListView-class.html) explains why the mutable backing collections must remain private; the implementation does not wrap and return application-owned lists.

## Verification

| Suite | Result | Scope |
| --- | --- | --- |
| Dart 3.13.7 compiled JavaScript / Chrome 158.0.8127.37 | 11/11 grouped scenarios | Existing six scenarios plus large incoming/outgoing values, transfer termination, ordered stream delivery and complete-read admission |
| Same consumer / Edge 157.0.4341.60 | 11/11 grouped scenarios | Independently executed with actual Workers |
| Native Dart JIT | 50/50 | Existing public contracts, including normalization and held-native behavior |
| Native Dart compiled executable | 50/50 | Same public contracts on Windows x64 |
| JS without Worker | Passed | Unsupported collection never invokes the host factory |
| Dart analysis | No issues | Includes final browser code and generated hydration |
| Flutter framework/engine | 22/22 | Existing observers, lifecycle and held-native behavior |

The transfer-termination group covers cancelling/closing during outgoing preparation and cancelling, closing or timing out during incoming traversal. It also covers watch cancellation and watch deadlines. Response-boundary counters establish that an incoming value was received and that the last element was not visited after termination. Later reads on surviving contexts succeed. The large-watch case places two equal small snapshots behind a large snapshot, then a normal end; all three values remain ordered through a pause/resume. No uncaught page errors were reported.

The two large-transfer failures and the admission failure were reproduced before their fixes. The additional termination and stream cases characterize the final implementation; they are not claimed as independently reproduced prior defects.

Local ignored evidence: `.tools/dart-web-large-red.log`, `.tools/dart-web-outbound-red.log`, `.tools/dart-web-admission-red.log`, `.tools/dart-web-transfer-final.log`, `.tools/dart-web-transfer-native.log`, `.tools/dart-web-transfer-flutter.log`, `.tools/dart-web-transfer-analyze.log`, and `.tools/evidence/dart-browser-{chrome,edge}.json`. Reproduction commands are `./tools/test-dart-browser.ps1`, `./tools/test-dart.ps1` and `./tools/test-flutter.ps1`; the final browser run compiled the Dart consumer against the unchanged worker asset and ran `node --test tools/test-dart-browser.mjs`.

## Remaining evidence and limits

These checks establish cooperative host traversal for representative large list payloads. They do not establish zero host overhead, a frame-time SLA, physical UI performance or process-crash isolation. Browser structured cloning/postMessage, object-key enumeration, individual scalar conversions, allocation/GC and application callbacks still contain synchronous work that this scheduler cannot preempt. The existing controlled slow-property test continues to verify deadline rejection after synchronous work, not responsiveness inside that work.

Response byte budgeting, sustained overload and memory limits, broader concurrency/permission/lifecycle interleavings and full schema/enum wire equivalence remain incomplete. Actual Flutter web applications, Firefox/Safari/Wasm, Apple native collectors/builds, physical devices, external package consumption and the complete minimum/latest-version matrix remain required. TypeScript, Kotlin, .NET, native Android applications and React Native suites were not rerun in this checkpoint; their previous evidence remains separate. Native Dart and Flutter checks were run after the shared model/helper changes; the final admission fix changes only the browser transport and was covered by analysis and the final browser suite.
