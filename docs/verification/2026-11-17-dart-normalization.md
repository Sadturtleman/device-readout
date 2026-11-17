# Dart rotation normalization and completion timestamps — 2026-11-17

Scope: both orientation entities, generated worker completion for all 46 snapshots and SensorDescription, and integration with existing Flutter observers and the Android adapter. All entity fields, bindings and the complete physical/version/platform acceptance matrix remain the objective.

## Changes and evidence

The public rotation test reproduced a zero quaternion escaping from RelativeOrientation watch. The shared decoder now rejects zero/nonfinite rotations and scales finite components before converting to unit length. This avoids overflowing the norm and preserves a smallest-positive-component rotation. Axes and component signs are retained; normalization does not convert a native reference frame.

The final [rotation test](../../dart/device_readout/test/rotations.dart) exercises twelve inputs for both RelativeOrientation and AbsoluteOrientation through both get and watch: NaN/infinity in each component, null, zero, signed identities, signed 3–4 rotations, maximum finite values and the smallest positive value. Expectations are fixed worked examples with component tolerance 1e-15. Collection uses the actual isolate transport and public app-source API.

Source inspection found prepareSnapshot and prepareDescription captured the clock before decoding. They now finish decoding before calling a generated private completion method. Its private constructor copies the already normalized immutable field references, then invokes the base completion constructor to read the UTC clock. No collection traversal or second normalization occurs after that clock read. Each generated model retains its concrete type. Public constructors and SnapshotCodec remain compatible: explicit timestamps are retained and omitted timestamps still default to the epoch.

The [completion characterization](../../dart/device_readout/test/completion.dart) checks get/watch/describe timestamps, independent normalized screen fields, nested mode nulls, valid false/zero, empty and immutable collections, typed metadata, passive descriptions, and unchanged source snapshots. It also checks explicit and default decoder timestamps. This validates the observable preservation contract; it does not instrument the exact instant of private normalization or claim a separately reproduced timestamp-order failure.

## Verification

| Environment | Result | Coverage |
| --- | --- | --- |
| Dart 3.13.7 / Windows x64 JIT | 50/50 | Full public contracts; strict analysis reports no issues |
| Dart compiled native executable | 50/50 | Same contracts, including held-native deadlines, cancellation and host heartbeat |
| Dart compiled JavaScript | Passed | The existing negative web test rejects collection without a Web Worker connection and starts no host source |
| Flutter 3.47.9 framework/engine | 22/22 | Existing viewport/display, source ownership, lifecycle, inventory and blocked-native tests |
| Rebuilt Flutter Android APK, API 26 x86_64 | 33/33 | State/sensor/metadata/discovery contracts, independent OS comparisons and native lifecycle evidence |
| Same APK, API 36 x86_64 | 33/33 | Same application and native checks |

Commands: `./tools/test-dart.ps1`, `./tools/test-flutter.ps1`, `./tools/build-flutter-android.ps1` and `./tools/test-flutter-android.ps1` with the project-owned API 26 and 36 targets. Both emulator runs observe real Activity pause/resume, native SensorManager registration/removal and a surviving test process after late replies. Emulators were started headlessly for this check and stopped afterward. Battery fixture overrides are restored by the test runner.

The first Flutter framework attempt failed while copying compiler output inside the sandbox's temporary directory. That run was stopped and is not counted as passing evidence; the ordinary-user run completes all 22 tests. The Android build passes with existing Flutter dependency-version and SDK XML-version warnings; this checkpoint does not claim a warning-free Android build.

Local ignored logs: `.tools/rotation-dart-red.log`, `.tools/rotation-dart-green.log`, `.tools/completion-dart-green.log`, `.tools/dart-normalization-final.log`, `.tools/flutter-normalization-verified.log`, `.tools/flutter-normalization-android-build.log`, `.tools/flutter-normalization-api26.log` and `.tools/flutter-normalization-api36.log`. Per-AVD JSON reports and native lifecycle evidence remain in `.tools/`.

## Remaining work

Follow-up: the [Dart web-worker checkpoint](2026-11-17-dart-web-worker.md) connects explicit web access and adds actual Chrome/Edge evidence. The remaining-work paragraphs below preserve this earlier checkpoint's scope.

The shared quaternion rule and completion-order implementation now exist in all five bindings. This is not proof of complete cross-language semantic equivalence for every field or platform. The TypeScript/Kotlin/C#/Swift results in the [preceding checkpoint](2026-11-17-upload-checkpoint.md) remain separate evidence; they were not rerun for this Dart-only implementation change.

Dart's actual Web Worker connection remains unimplemented; its negative test is not browser collection support. Apple collectors/builds, other Flutter/RN platforms, physical sensor units/reference frames, remaining fields and native permission adapters, external package consumption and the full minimum/latest-version matrix remain pending. Native bridge unit tests, React Native applications and Windows Flutter native-screen scenarios were not rerun here. Worker execution does not mean zero main-thread cost, forced interruption of stuck native code or isolation from native process crashes.
