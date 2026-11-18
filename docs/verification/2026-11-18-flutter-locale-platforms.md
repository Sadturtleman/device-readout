# Flutter locale observation across web, Android and installed packages — 2026-11-18

The app-owned locale observer from the [preceding checkpoint](2026-11-18-flutter-locale-observer.md) now has actual Flutter web and Android consumer coverage, including separately installed Pub packages. No SDK implementation change was required by these runs. The native application fixture was renamed from locale_observer_windows.dart to locale_observer_native.dart, with identical contents, and reused on Android.

## What was exercised

The Android application selects actual Localizations scopes for zh-Hant-TW and fr-FR. get/watch deliver the resolved app values, preserve explicit region/script, and leave unavailable system/formatting fields null. Disposing the observer ends its watch with ReadFailed; a new get returns the same native locale fields captured before attachment, excluding only collectedAt. The external ADB verifier checks the reported locale sequence, native restoration and typed detach error rather than only counting scenarios.

The browser application uses Localizations.override within its live widget tree. Chrome and Edge observe zh-Hant-TW, fr-FR and a second identical fr-FR publication. get and watch agree, unspecified script and formatting fields remain null, and disposal restores the original browser locale without changing navigator.language. Worker lifetime assertions still require every owned worker to be terminated. No system language, application language policy or browser preference is changed by the SDK.

The existing application suites run alongside the new locale scenario. They cover viewport resize, app-observed permission handling, native Activity/focus lifecycle, sensor registration/release, cancellation, held-collector deadlines and cleanup. Android's independent verifier compares native memory, OS/device and CPU/network inventory fields, triggers a fixture-owned power transition, checks sensorservice registration, and verifies that late native replies do not crash the test process.

## Results and scope

Host: Windows x64. Flutter 3.47.9 / Dart 3.13.7. Android devices are project-owned x86_64 Google APIs emulators at API 26 and API 36. Chrome is 158.0.8127.37; Edge is 157.0.4341.60.

| Consumer | Result |
|---|---|
| Checkout Flutter Android APK, API 26 | 34/34 |
| Checkout Flutter Android APK, API 36 | 34/34 |
| Installed Pub consumer APK, API 26 | 34/34 |
| Installed Pub consumer APK, API 36 | 34/34 |
| Checkout Flutter web, Chrome and Edge | 8/8 Node tests total; 10 application scenarios per browser |
| Installed Pub consumer web, Chrome and Edge | 8/8 Node tests total; 10 application scenarios per browser |
| Checkout and installed application analysis | Clean |

Each web run includes a rendered example, seven contract scenarios and two deployment layouts per browser. The deployment cases use a nested route and a separate same-origin asset base and verify the actual package worker URL and bytes. During the controlled 800 ms worker hold, all four browser consumer runs preserve ten rendered frames and sixteen host timer ticks; their read deadlines complete in 160–161 ms. These measurements demonstrate the controlled fixture, not zero host overhead, forced worker/native interruption or a universal frame-time guarantee.

The installed consumers download both SDK archives from a loopback Pub fixture, resolve them under the hosted Pub cache and compile without monorepo path dependencies. The audit compares every installed Dart library file with its checkout counterpart and verifies archive, worker and APK hashes. These remain development version 0.1.0 packages, not pub.dev releases. Android builds retain the existing Flutter advisories about future AGP/Kotlin minimums; no validation bypass was introduced.

The Dart SDK and Flutter adapter library bytes are unchanged from the preceding 68/68 JIT/native, 27/27 framework and 13/13 Windows application checkpoint. Those suites were not rerun here. The renamed native fixture retains its previous content hash, and the updated Windows import is included in example analysis.

## Reproduction and evidence

```powershell
./tools/test-flutter-web.ps1
./tools/test-flutter-web-packages.ps1
./tools/build-flutter-android.ps1 -SdkRoot .tools/android-sdk
# Start the project-owned API 26/36 AVDs with tools/start-android-emulator.ps1.
./tools/test-flutter-android.ps1 -SdkRoot .tools/android-sdk -Serial emulator-5584
./tools/test-flutter-android.ps1 -SdkRoot .tools/android-sdk -Serial emulator-5586
./tools/build-flutter-packages.ps1 -Platform Android -SdkRoot .tools/android-sdk
./tools/test-flutter-android.ps1 -SdkRoot .tools/android-sdk -Serial emulator-5584 -InstalledPackage
./tools/test-flutter-android.ps1 -SdkRoot .tools/android-sdk -Serial emulator-5586 -InstalledPackage
```

Logs use `.tools/flutter-locale-web-final.log`, `.tools/flutter-locale-installed-web-final.log`, `.tools/flutter-locale-android-build.log`, `.tools/flutter-locale-installed-android-build.log`, and the four `flutter-locale[-installed]-android-api26/api36.log` files. Browser reports are `.tools/evidence/flutter[-installed]-browser-contracts-chrome/edge.json` with separate demo/deployment reports. Android reports are `.tools/flutter[-installed]-android-DeviceReadout_API26/API36-sensors.json`. Package installation metadata is in `.tools/evidence/flutter-installed-packages.json` and `.tools/evidence/flutter-web-installed-packages.json`. The consolidated source/artifact audit is `.tools/evidence/flutter-locale-platforms-checkpoint.json`.

All new application scenarios passed on their first completed run; there was no reproduced SDK defect in this checkpoint. After testing, both emulators' battery overrides were confirmed restored, their test apps were force-stopped, and the two emulator sessions launched for this work exited successfully. An initial cleanup identity command was corrected to capture the complete ADB response before checking its exit status; it made no device mutation before the identity checks passed.

Physical devices, Safari/Firefox, iOS/macOS applications, framework-specific system/preferred/application language feeds, broader locale/format configurations, additional framework/OS versions, Apple collectors and the complete 46-entity/binding acceptance matrix remain required. Windows installed-package consumption and public registry publication are not established by these Android/web runs. This work remains local after GitHub commit 0efdcde.
