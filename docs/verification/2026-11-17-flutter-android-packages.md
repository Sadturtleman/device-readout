# Flutter Android hosted-package checkpoint — 2026-11-17

The Dart SDK and Flutter Android plugin now work as independently downloaded package archives in the tested consumer. Pub resolves both SDK packages from its hosted cache, and the plugin compiles its packaged Kotlin sources without paths into the checkout. This is local package-consumption evidence; nothing was published to pub.dev and the full device, field, version and platform matrix remains incomplete.

## Reproduced failures

An actual `flutter pub get` against the loopback package fixture rejected the Flutter plugin's `../../dart/device_readout` dependency: a relative path cannot describe a dependency in a hosted pubspec. The plugin now declares `device_readout: ^0.1.0`. Checkout-only `pubspec_overrides.yaml` files in the plugin and example preserve local development. Both files are needed because a dependency's overrides do not control the consuming app's resolution. They are omitted from the package archives.

After that correction, download and Dart analysis passed, but Android compilation failed because the plugin's Gradle source sets pointed at missing checkout Kotlin directories. The preparation tool now stages the 26 canonical core/Android Kotlin files under the plugin's `android/shared`, with a SHA-256 manifest. Gradle compiles those packaged directories. The staged copies are ignored by Git; development builds refresh them from the canonical Kotlin source. Consumers do not need Node, the repository, or a native build task that downloads SDK source.

## Consumer and archives

`tools/build-flutter-packages.ps1` prepares the two archives, starts a GET-only loopback repository implementing the relevant Hosted Pub v2 endpoints, and invokes the real Flutter/Pub client. The server advertises archive SHA-256 digests and records that both archives were downloaded. It binds only to loopback and closes after the command, including failure. It cannot publish or accept uploads.

The independent app uses the Flutter plugin as a hosted dependency. A root override directs the common SDK to the same fixture repository; this is a hosted URL override, not a source-path override. The fixture is necessary because the SDK is not on pub.dev. The actual package pubspecs retain `publish_to: none`. They are neither rewritten to point into the checkout nor marked as published.

The copied application has its own `.dart_tool/package_config.json`, plugin discovery and Android build output. Both SDK entries must resolve under the hosted Pub cache and must have been downloaded during the current run. The artifacts contain library code, pubspec, README and the repository MIT license; the Flutter artifact also contains its native plugin and shared Kotlin sources. The tested archives have 22 and 42 files respectively. They exclude development overrides, example/test fixtures, build output, local.properties and signing keys. Every installed shared-source checksum agrees with its manifest and the canonical source.

These are explicitly prepared local archives. The native source files are staged, and direct `pub publish` from an unprepared checkout is not a supported distribution command. Registry names/ownership, publication metadata and real publication remain separate work. The source manifests still prevent accidental publication.

## Verification

The pinned environment is Flutter 3.47.9 / Dart 3.13.7 on Windows x64, Gradle 8.14.3, AGP 8.11.1, Kotlin 2.2.20 and Android NDK 28.2.13676358. Gradle installed that NDK into the project-owned SDK; the user's global SDK/configuration was not changed. Flutter reports upcoming support-removal warnings for the Gradle/AGP/Kotlin versions and a newer dependency notice. Validation is not warning-free, and these versions are not a claim that every supported consumer patch was exercised.

| Verification | Result |
|---|---|
| Actual hosted `pub get`, cache-origin checks and Dart analysis | Both archives downloaded; analysis clean |
| Installed-package Android APK | Build passes |
| Installed APK on API 26 and API 36 x86_64 emulators | 33/33 scenarios on each |
| Checkout Flutter framework regression | Clean analysis; 22/22 checks |
| Checkout Android native bridge regression | 8 sensor + 4 state contracts, zero failures/errors |

The application scenarios cover native state reads and discovery, equal polling values, native power events, capabilities, mixed state/sensor workloads, scoped cancellation/failures, app-owned permission policy, real Activity suspension/resume, source replacement and cleanup. Independent Android/kernel reads corroborate representative RAM/CPU/storage/interface fields. SensorManager diagnostics verify native registration, suspension, resumed registration and final release, and the process survives late native replies after disposal.

The main-isolate scenario deliberately holds a Dart collection isolate for 600 ms. A 150 ms sensor-read deadline settles while a 10 ms host timer advances, before that collector returns. This is a controlled Dart-worker boundary with a real native sensor input; it is not a claim that every Kotlin OS call was physically blocked or that UI frame times are bounded. The separate native bridge contracts retain their worker/deadline checks. Permission-loss and dynamic inventory cases include controlled app/platform fixtures; emulator measurements do not prove physical sensors or privileged identifiers.

```powershell
./tools/build-flutter-packages.ps1
./tools/test-flutter-android.ps1 -SdkRoot .tools/android-sdk -Serial emulator-5584 -InstalledPackage
./tools/test-flutter-android.ps1 -SdkRoot .tools/android-sdk -Serial emulator-5586 -InstalledPackage
./tools/test-flutter.ps1
./tools/build-flutter-android.ps1 -SdkRoot .tools/android-sdk -NativeUnitOnly
```

Use the project-owned API 26/36 emulators with the existing startup helper. Runtime reports record `installedConsumer=true` and the exact APK SHA-256. Package records include the archive URLs/digests, installed cache paths and request paths. Local records are `.tools/evidence/flutter-installed-packages.json` and `.tools/flutter-installed-android-DeviceReadout_API*-sensors.json`. Red/build/regression logs are `.tools/flutter-installed-red.log`, `.tools/flutter-installed-native-red.log`, `.tools/flutter-installed-build.log`, `.tools/flutter-package-framework.log` and `.tools/flutter-package-native-regression.log`; none are committed.

## Remaining scope

Real registry publication, Flutter web package/worker-asset distribution, other native Flutter platforms, physical devices, native permission dialogs, all field and version combinations, Apple collectors and the complete acceptance matrix remain unfinished. The earlier Flutter web application results use the checkout worker build and are not reclassified as hosted-package evidence here.

Primary references: [Dart custom package repositories](https://dart.dev/tools/pub/custom-package-repositories), [Hosted Pub Repository Specification v2](https://github.com/dart-lang/pub/blob/master/doc/repository-spec-v2.md) and [Pub dependency overrides](https://dart.dev/tools/pub/dependencies#pubspec_overridesyaml).
