# React Native blocked-collector fixture — 2026-11-15

This records the build-only checkpoint. At that stage the isolation fixture had not been executed on an emulator or device. The subsequent [runtime verification](2026-11-15-react-native-isolation.md) executes it on API 26 and API 36 and records the exact scope and results separately.

The example application's `Isolation` variant uses its own application ID suffix, `.isolation`. It replaces the native package provider with a controlled collector while retaining the production TurboModule, native endpoint and Hermes application path. The module accepts an access factory; its default remains the Android collector and factory invocation stays inside the existing background execution scope.

The fixture holds a RAM read until an explicit broadcast releases it, with a fifteen-second safety limit. Three app scenarios prepare to check get timeout, watch's first-value timeout and context close while collection remains blocked. JS timers and Android main-loop callbacks report progress independently. The release receiver is declared only in the example's isolation manifest, not in the shipping SDK or the ordinary debug manifest.

## Build evidence

The initial isolation build failed because the native module had no factory constructor parameter. After adding the parameter, the TypeScript checks and both `assembleIsolation` and ordinary `assembleDebug` tasks succeeded. The Kotlin core verification task also succeeded, reusing its up-to-date passing test outputs; this was not a fresh execution of its 37 tests.

```powershell
./tools/build-react-native-app.ps1 -GradleHome 'C:/short/gradle-cache' -Variant Isolation
./tools/build-react-native-app.ps1 -GradleHome 'C:/short/gradle-cache' -Variant Debug
```

Ignored local build logs: `.tools/rn-isolation-build-red.log`, `.tools/rn-isolation-build-green.log`, `.tools/github-upload-rn-debug-build.log` and `.tools/github-upload-kotlin-tests.log`.

## Follow-up checks

The subsequent runtime checkpoint adds an external harness for each scenario in a fresh app process, both event loops while collection is held, timeout/close before external release and collector-thread exit after release. It also repeats ordinary-app regressions after the launch-routing changes. Physical-device behavior and broader scheduling/overload cases remain outstanding.
