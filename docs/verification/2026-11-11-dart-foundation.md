# Dart isolated collection foundation — 2026-11-11

This checkpoint adds a Dart package, not a complete Flutter binding. The release objective remains all 46 entities, every specified binding, and the complete support/acceptance matrix.

Follow-up: [Dart screen and permission observers](2026-11-11-dart-observers.md) adds app-owned state, discovery and permission coordination and brings the current suite to 18 checks. The foundation evidence below remains the historical nine-check checkpoint.

## Environment

- Flutter 3.47.9 stable, framework revision `c197ca5199e9ee5661e865596c9c07294dfab51c`.
- Bundled Dart 3.13.7 stable, Windows x64; installed separately under `.tools/flutter-3.47.9`.
- Official archive `stable/windows/flutter_windows_3.47.9-stable.zip`, 1,939,451,626 bytes.
- SHA-256 `d8e2b5977e09082c6440f89dc1aa887b94c8fbcc3b39222797046295a3f68a9e`, verified against the [official Windows release index](https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json). The chosen release record is retained in `.tools/flutter-3.47-release.json`.
- No third-party Dart package dependencies; offline pub resolution. No device settings or permission UI changed.

The official SDK replaced the previously unavailable required Flutter toolchain in the local environment. Flutter application/plugin builds have not yet been validated; these checks use its bundled Dart executable.

## Implemented

`tools/generate-dart.mjs` generates the same 46 entities, 191 fields and 11 sensor-description fields as the shared schema. Generated typed enums, `Entity<Snapshot>` values, immutable snapshot collections and a lower-level adapter decoder use the existing common contracts. BigInt counters preserve unsigned/signed 64-bit range and decimal-string JSON. Unknown enums invalidate the affected field, including entire enum sets/maps. No field-result wrapper, estimate flag or change envelope is introduced.

`DeviceAccess.get`, state `watch`, immutable configuration and cancellation use a lazy long-lived collection isolate. The host owns scheduling, deadlines and at most 128 pending reads; only one native read is dispatched at a time. Collection, normalization, timestamping and disposal run on the worker. Queued work that expires or is cancelled is never dispatched. Closing a context signals cancellation immediately and lets already-running native work return before disposal. No forced isolate kill is used.

State streams are cold and poll after the preceding read finishes, retaining duplicates. Pause stops future polls, with at most the in-flight read allowed to become buffered. Whole failures are terminal and preserve typed error categories. Worker startup failure is retained without an implicit restart. A reproduced defect passed the configured sensor-watch frequency into one-shot reads; the corrected path always supplies PlatformDefault to `get`.

The first actual native Dart collector is `Runtime`: `processArchitecture` comes from `dart:ffi`'s typed ABI token, and `processBitness` from native pointer size. Host architecture and supported ABI sets remain null. Windows x64 is the only native Dart environment verified here. Other entities remain unsupported in the default native collector.

## Verification

Command: `./tools/test-dart.ps1`.

| Check | Evidence |
|---|---|
| Generation and strict analyzer | 46 entities plus SensorDescription; no analyzer issues |
| Typed read and lazy ownership | Factory is inert until first read; read and disposal execute in a different isolate; exact uint64 maximum, zero, false and UTC completion retained |
| Cold state streams | No collector before listen; equal snapshots retained; immutable configured views; cancellation stops polling |
| Blocked native read | Controlled OS-boundary fixture sleeps for 400ms; host heartbeat continues, 90ms active and 25ms queued deadlines finish first |
| Cancellation/context closure | Active and queued cancellation remain cancellation; context closure does not join native work; late cleanup occurs on the worker; queued OS reads never execute |
| Normalization | Invalid counters/nonfinite values/negative durations/unknown classifications become null; unknown set/map entries invalidate the collection; detached collections cannot be mutated |
| Native Runtime | Actual Windows x64 VM reports X64/64 in JIT and compiled executable; no fabricated host architecture or ABI list; missing collectors report UnsupportedEntity |
| Sampling settings | Explicit 60Hz configuration does not affect get or the original view |
| Terminal stream failures | One typed PermissionDenied error follows the first snapshot; no retry or additional native reads |
| Configuration/startup errors | Invalid settings fail synchronously; undiscovered target kinds fail; failed worker startup rejects reads and stays failed |
| Native compilation | All **9/9** contract checks pass both in JIT and a compiled Windows executable |
| Web branch | JavaScript compilation succeeds; Node executes the negative boundary test and confirms the unsupported web path never invokes the supplied collector on the host |

The web check is not browser integration evidence or a working Flutter web binding. OS-boundary fixtures deliberately model blocked/failing native work; they do not establish physical-device latency or observer behavior. Runtime ABI collection is the actual native evidence in this checkpoint.

Local logs: `.tools/dart-foundation-validation.log`, with red cases in `.tools/dart-isolate-red.log`, `.tools/dart-watch-red.log`, `.tools/dart-native-runtime-red.log` and `.tools/dart-sampling-red.log`. The test script fails on nonzero generator, analyzer, JIT, native compilation/execution or web-check exit status.

## Remaining work

Dart still needs application-owned screen/permission/lifecycle observer inputs, typed discovered target handles, list/current/describe/capabilities/permissions APIs, native state notifications, sensor streams and platform collector integration. Flutter plugins must connect the existing native collectors and the web worker implementation. Actual Flutter applications, mobile/Apple/desktop targets, permission/lifecycle behavior and the complete minimum-version matrix remain unverified. Swift and React Native work remain in the overall scope.

The [Dart isolate documentation](https://api.dart.dev/dart-isolate/Isolate/spawn.html) informs factory sendability and startup error/exit registration. The [stream-controller contract](https://api.dart.dev/dart-async/StreamController/StreamController.html) informs cold, asynchronous stream delivery. [Flutter's isolate guidance](https://docs.flutter.dev/perf/isolates) distinguishes native isolate work from Flutter web and documents platform-plugin messaging limits; the implementation does not silently replace absent web isolates with host execution.
