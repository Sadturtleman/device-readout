# React Native held-collector responsiveness — 2026-11-15

The actual RN 0.88.0/Hermes/JSI application now passes three deliberately blocked-native scenarios on each API 26 and API 36 x86_64 emulator. The ordinary application also passes its eleven reported scenarios on each API, with independent kernel-memory and native sensor-registration checks. This advances the earlier [build-only fixture checkpoint](2026-11-15-react-native-isolation-fixture.md) to runtime evidence for the cases below.

## Path and assertions

The example's isolation package supplies a controlled `DeviceCollector` to the production TurboModule and Kotlin endpoint. Module/context/worker startup is completed with a Runtime read before timing a RAM operation. The RAM collector blocks on a latch and ignores interruption. It cannot return until the external harness sends a release broadcast; a fifteen-second safety limit fails the test rather than satisfying it.

The harness starts each scenario in a fresh app process and requires a successful log clear. It verifies:

- the access factory and held collection both execute off Android's main thread;
- `get` and the first `watch` value fail with `ReadTimeout` using an 800 ms read setting;
- a pending read fails with `EntityRemoved` when the app closes the context after 300 ms;
- JS timers advance during the operation and for another 250 ms after close;
- callbacks on Android's main Looper advance while collection is held, including after the JS close marker;
- no native return or release occurs before the app's terminal result;
- after external release, the collector returns and its worker thread exits.

These checks run through the real Hermes engine and native module. Only the blocked native collector is controlled. The ordinary application's collector remains the default Android adapter.

## Measured results

Elapsed times below are measured from the JS operation start until its terminal result, before the extra post-close observation window. The close scenario includes its intentional 300 ms delay. Timer counts are observed progress, not frame-rate benchmarks.

| API | Scenario | Result | Elapsed ms | JS ticks during operation / after close | Android UI ticks while held / after close | Native held ms |
| --- | --- | --- | ---: | --- | --- | ---: |
| 26 | get | ReadTimeout | 809 | 25 / 9 | 19 / 5 | 1510 |
| 26 | watch first value | ReadTimeout | 817 | 28 / 8 | 19 / 5 | 1316 |
| 26 | close pending get | EntityRemoved | 316 | 7 / 7 | 10 / 5 | 846 |
| 36 | get | ReadTimeout | 856 | 23 / 9 | 17 / 5 | 1388 |
| 36 | watch first value | ReadTimeout | 819 | 23 / 8 | 18 / 5 | 1207 |
| 36 | close pending get | EntityRemoved | 318 | 10 / 7 | 10 / 5 | 739 |

Every close call measured 0 ms at the JS clock's millisecond resolution; the assertion is less than 250 ms, not zero execution cost. All six collector workers exited after release. Factory and collector main-thread checks were false in every scenario.

## Ordinary-app regression and harness correction

Both APIs pass nine baseline scenarios plus actual window change and fresh sensor resume, for eleven app-reported passes each. The harness also confirms kernel RAM agreement and native sensor registration, removal during Activity backgrounding and restoration after resume. This uses the updated normal APK with the example's launch routing and the production factory default.

The first API 26 regression attempt failed at the external foreground-registration check even though the native listener was active. Android's package-manager filter returned both the ordinary application and the newly installed `.isolation` application. The old harness selected the first UID, which belonged to isolation. The captured sensor dump matched ordinary UID 10079 and did not match isolation UID 10080. Exact package-name matching fixes the harness; the subsequent API 26 and API 36 complete runs pass. Reports now include the selected package UID. No SDK sensor change was needed for this failure.

The compiled manifests also confirm the release receiver exists only in the example's isolation variant. It is absent from the ordinary debug manifest; the shipping SDK does not declare it.

## Reproduction and evidence

```powershell
./tools/build-react-native-app.ps1 -GradleHome 'C:/short/gradle-cache' -Variant Isolation
./tools/build-react-native-app.ps1 -GradleHome 'C:/short/gradle-cache' -Variant Debug
# Run against each booted, project-owned API 26 / API 36 emulator:
./tools/test-react-native-isolation.ps1 -SdkRoot 'C:/path/to/Android/Sdk'
./tools/test-react-native-android.ps1 -SdkRoot 'C:/path/to/Android/Sdk'
```

The same pair of APKs was used on both APIs. SHA-256:

- Isolation: `c60117e82497f82781b9f62583257358444be8703e15f9d0afd3b7dfeb515888`.
- Ordinary debug: `7c3c927a91dadbd7e953e13b2b3af35d54c73e6b163d057633c070a945b75819`.

Ignored local evidence includes `.tools/rn-isolation-DeviceReadout_API26.json`, the matching API 36 report and each report's get/watch/close logs. Ordinary reports use `.tools/rn-android-DeviceReadout_API26.json` and API 36 equivalents, with app, kernel and foreground/background/resumed sensor dumps. The reproduced UID mismatch is retained in `.tools/rn-api26-isolation-baseline-uid-red-app.log` and `rn-api26-isolation-baseline-uid-red-sensors.txt`. Build evidence remains in the preceding fixture record.

The Kotlin total remains 37 passing cases from the previous checkpoint. This runtime check added no Kotlin unit tests and did not rerun them. Both project-owned emulators were shut down after verification.

## Remaining requirements

This demonstrates responsiveness during a held first collection and context close in the tested app/toolchain/emulators. It does not prove zero overhead, arbitrary native crash isolation, later-event blocking, blocked cleanup, sustained overload, every detachment race or physical-device behavior. Representative ordinary sensor lifecycle checks do not replace physical sensor/permission/hotplug tests.

Reusable RN observer adapters, app-owned sensor-source sessions, broader protocol and concurrency coverage, all-kind inventory notifications, external package consumption, other RN platform bindings and the complete SDK field/version/acceptance matrix remain required. The full implementation goal is still active.
