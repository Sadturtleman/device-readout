# Flutter web hosted-package checkpoint — 2026-11-17

Prepared Pub archives now include the Flutter browser collection worker. The public `FlutterWebDeviceAccess.create()` factory resolves its packaged asset through Flutter's asset manager and the document base URI. An explicit `workerUri` remains available. Creation only resolves configuration; collection still starts on the first SDK operation, and apps still own screen, lifecycle and permission observations.

An independent consumer first reproduced a missing-worker failure: the example rendered a read error and the contract app failed to return snapshots. After packaging the worker and using the factory, actual hosted downloads, Dart analysis, both release builds and all four browser test groups passed. No package was published to pub.dev.

## Package preparation

`tools/prepare-flutter-web.mjs` stages the canonical built Dart worker without its development sourcemap reference. The Flutter pubspec declares it as a web-only package asset. `tools/prepare-flutter-packages.mjs` includes that asset alongside the Dart library and native plugin sources. Generated assets and staged native copies remain ignored by Git; preparation builds them from committed sources.

`tools/build-flutter-packages.ps1 -Platform Web` builds the worker, prepares archives, serves a temporary GET-only Hosted Pub fixture and builds an independent Flutter consumer. Both SDK packages must be downloaded and resolve under the hosted Pub cache. The consumer uses neither SDK source-path dependencies nor a manually copied root worker. The server closes after the build. `publish_to: none` remains in both manifests.

## Recorded verification

The environment was Flutter 3.47.9 / Dart 3.13.7 on Windows, Chrome 158.0.8127.37 and Edge 157.0.4341.60. The run completed before this upload; the upload checks compared the current library and consumer source bytes to that installed consumer rather than rerunning the full platform matrix.

| Check | Result |
|---|---|
| Real Pub archive downloads and hosted cache origins | Both SDK packages verified |
| Consumer Dart analysis | No issues |
| Release example and contract application builds | Both pass |
| Rendered example plus six contract scenarios per browser | Pass in Chrome and Edge; four Node test groups total |
| Current library and consumer fixture source comparison | 39 files match the installed consumer |
| Packaged worker and both built application worker assets | Identical SHA-256; no manually copied root worker |

The application checks cover typed reads, observed screen resize, watch cancellation and retired handles, native browser focus notifications with controlled sensor activity, explicit permission coordination, a held worker and widget disposal. During a controlled 800 ms worker hold, a 160 ms read deadline settles while host timers and frame callbacks advance. This is representative integration evidence, not a hard frame-time or process-isolation guarantee.

The worker SHA-256 is `a5a2e0a5a8f79253d9c64602c1c43efbbd1a8341a4a9dd5e97f9cea957a9aae5`. The recorded Dart archive SHA-256 is `a59663d94146f25f06d5d5969be4c183496cc6816a6a23e044927d7d4846d7b5`; the Flutter archive SHA-256 is `d6b7188faab209a9b211d8ba7c87f745a509d531e9423626c15a7c2fcb02eee6`. These identify the tested local artifacts, not future registry releases. Later README edits can change archive bytes without changing library code.

The run reported a lockfile content-hash update for the reused local fixture consumer and a Cupertino font warning. Both current archive files match their recorded digests, and actual download/cache-origin assertions passed. The build is not described as warning-free.

Reproduce with `./tools/test-flutter-web-packages.ps1`. Local evidence is retained in `.tools/flutter-web-package-red.log`, `.tools/flutter-web-package-green.log`, `.tools/evidence/flutter-web-installed-packages.json` and `.tools/evidence/flutter-installed-browser-*.json`; generated artifacts and logs are not committed.

## Deployment and native follow-up

The unchanged public factory now has direct deployment evidence for `/contracts/nested/settings` with an HTML base of `/contracts/`, and `/asset-layout/nested/settings` with Flutter's `assetBase` set to `/external/`. The latter server deliberately returns 404 for the default asset location, so fallback cannot mask a wrong URL. These use the actual compiled Flutter application and native browser workers; neither the SDK nor Flutter's asset manager is mocked.

Both layouts verify lazy worker creation, CPU/locale values against browser APIs, viewport get/watch across resize, and final worker termination. The server records the worker URL and SHA-256 of the bytes it actually delivers. The delivered worker agrees with the package asset. Each Chrome/Edge run now covers the example, six existing integration scenarios and two deployment layouts: nine scenarios per browser, eight Node test groups total. These pass both against the installed Pub consumer and against rebuilt checkout release applications.

The framework suite passes 24/24, including two new native calls to `FlutterWebDeviceAccess.create()`: with a default worker and with an explicit URI. Both reject synchronously with `UnsupportedEntity`; importing the library on the native test engine also validates its conditional web imports. An independently downloaded Android consumer was rebuilt from the current package. API 26 and API 36 each pass all 33 state/sensor scenarios, including real Activity suspension/resumption and worker responsiveness. The APK SHA-256 is `23f85eb69d179b5c9641abfa1f3eb9600059e10a6877d34acb24aeaf4af3e9e7`; inspection finds the Flutter asset manifest and no web-worker entry. These results supersede the new factory's native-compatibility gap in the initial record above. The older twelve native bridge unit checks were not rerun in this follow-up.

The first checkout build stopped at an internal Dart analyzer null-check exception. Without changing SDK or example source, individual and full analysis passed, followed by both release builds and all eight browser test groups. The transient analysis failure remains recorded; its underlying cause is not established. Deployment and native checks were green characterization of the existing implementation, not a newly reproduced SDK defect.

Follow-up commands are `./tools/test-flutter-web-packages.ps1 -SkipBuild`, `./tools/test-flutter.ps1`, `./tools/build-flutter-packages.ps1 -Platform Android`, the installed-package Android runner on API 26/36, and `./tools/test-flutter-web.ps1`. Evidence includes `.tools/flutter-web-layouts.log`, `.tools/flutter-web-factory-native.log`, `.tools/flutter-web-native-package-build.log`, `.tools/flutter-web-native-5584.log`, `.tools/flutter-web-native-5586.log`, `.tools/flutter-web-checkout-layouts.log` and `.tools/flutter-web-checkout-layouts-retry.log`. Browser route records use the `nested-route` and `custom-assets` suffixes in `.tools/evidence`; `.tools/evidence/flutter-web-native-asset-check.json` records the native asset audit. The project emulators were shut down after verification.

The fixture uses Flutter's documented [loader configuration](https://docs.flutter.dev/platform-integration/web/initialization) and the factory calls [AssetManager.getAssetUrl](https://api.flutter.dev/flutter/dart-ui_web/AssetManager/getAssetUrl.html). Tests exercise pinned Flutter 3.47.9; newer documentation or APIs do not establish compatibility with newer versions or content-hashed deployments.

## Remaining verification

The checked layouts use same-origin assets. Content-hashed assets, cross-origin worker hosting, further loader configurations and other browsers remain unverified. Registry publication, physical devices, Apple collectors, other framework platforms and the complete field/version/platform acceptance matrix remain unfinished.
