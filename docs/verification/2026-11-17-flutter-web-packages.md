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

## Remaining verification

The example uses `/` and the contract application uses `/contracts/`. Nested client-side routes, custom asset-base configurations, hashed assets, cross-origin worker hosting and other browsers have not been exercised by this checkpoint. The newly exported web factory has not yet received its separate non-web regression check; earlier Android framework/native/APK results remain evidence for the preceding Android package checkpoint. Registry publication, physical devices, Apple collectors, other framework platforms and the complete field/version/platform acceptance matrix remain unfinished.
