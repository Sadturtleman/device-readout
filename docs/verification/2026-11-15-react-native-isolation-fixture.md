# React Native blocked-collector fixture — 2026-11-15

This is a build checkpoint. The new isolation fixture has not yet been executed on an emulator or device, so it adds no runtime responsiveness or deadline guarantee to the preceding verification records.

The example application's `Isolation` variant uses its own application ID suffix, `.isolation`. It replaces the native package provider with a controlled collector while retaining the production TurboModule, native endpoint and Hermes application path. The module accepts an access factory; its default remains the Android collector and factory invocation stays inside the existing background execution scope.

The fixture holds a RAM read until an explicit broadcast releases it, with a fifteen-second safety limit. Three app scenarios prepare to check get timeout, watch's first-value timeout and context close while collection remains blocked. JS timers and Android main-loop callbacks report progress independently. The release receiver is declared only in the example's isolation manifest, not in the shipping SDK or the ordinary debug manifest.

## Build evidence

The initial isolation build failed because the native module had no factory constructor parameter. After adding the parameter, the TypeScript checks and both `assembleIsolation` and ordinary `assembleDebug` tasks succeeded. The Kotlin core verification task also succeeded, reusing its up-to-date passing test outputs; this was not a fresh execution of its 37 tests.

```powershell
./tools/build-react-native-app.ps1 -GradleHome 'C:/short/gradle-cache' -Variant Isolation
./tools/build-react-native-app.ps1 -GradleHome 'C:/short/gradle-cache' -Variant Debug
```

Ignored local build logs: `.tools/rn-isolation-build-red.log`, `.tools/rn-isolation-build-green.log`, `.tools/github-upload-rn-debug-build.log` and `.tools/github-upload-kotlin-tests.log`.

## Required next checks

An external harness must run each scenario in a fresh app process, verify that both event loops advance while collection is held, verify timeout/close before external release, and verify collector-thread exit after release. Run the ordinary app regression checks again after the launch-routing changes. API 26 and API 36 emulator execution, physical-device behavior and broader scheduling/overload cases remain outstanding for this fixture.
