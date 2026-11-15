# React Native mixed app/native inventories — 2026-11-15

App-owned inventory no longer suppresses removal detection for previously discovered native handles of the same entity kind. The controlled regression and actual RN/Hermes application scenarios now pass. The preceding [native inventory checkpoint](2026-11-15-react-native-inventory.md) retains its original scope and counts.

## Reproduced defect and change

The previous background refresh skipped a kind when the app owned that kind's inventory. An existing native watch therefore remained alive after native removal, even though the collector sent a change callback. The new regression timed out waiting for `EntityRemoved` on that implementation.

The binding now refreshes previously discovered native kinds through an internal worker-dispatched native inventory read. That read retains collection-level observer failure checks and failure-history validation. It does not change the app's public list, selected state or target namespace. The endpoint reconciles the returned native inventory against native tokens only.

The public API remains `get(Entity)`, `watch(Entity)` and typed discovery. No new public option is needed to keep an existing native handle usable after an app-provided inventory takes ownership of `list()`.

## Controlled regression

The test uses the native endpoint contract and a controlled `CpuCore` collector. It first discovers and watches a native target, then publishes an app target using exactly the same textual token in the observed namespace. The app's public list contains its own target. A native removal notification must then:

- terminate the native stream with `EntityRemoved`;
- preserve the app stream and deliver its subsequent value change;
- reject a later read through the removed native token;
- keep the app target readable and keep the public app list unchanged.

The regression fails before the fix and passes afterward. Kotlin passes **37/37** tests: access 12, native binding 9, native inventory 6, observer contracts 7 and snapshots 3.

## Actual RN application

The real RN 0.88.0/Hermes/JSI application adds a required `mixed-native-and-app-inventory` scenario. Within one DeviceAccess context it discovers an actual native CPU core, publishes an app CPU target, concurrently watches both, changes the app value, removes the app target and verifies the original native handle still works. It also verifies that the now-empty app inventory remains empty rather than returning native devices.

The rebuilt APK passes on **API 26 and API 36**, x86_64. Each run has **nine baseline scenarios** plus actual window-change and fresh-sensor-resume scenarios: **11 app-reported passes**. Independent kernel RAM agreement and native sensor release/restoration checks also pass. Both runs report native CPU logical index `0`, app values `99` then `100`, and an explicitly empty final app inventory.

The same APK was used for both runs. SHA-256:

`367e425b17d18d17aa5ff4f868a06f65c9972206798cab09063af14739c44e01`

Removal behavior in the presence of an app inventory is exercised by the controlled contract test. Physical CPU or sensor hotplug remains unverified. The app scenario verifies real cross-language coexistence, state updates, app removal and cleanup. Permission coordination and host responsiveness retain their earlier limits; deliberately blocked-native Hermes/UI responsiveness is still unverified.

## Commands and local evidence

```powershell
# Use the project-local Gradle home for the Kotlin command.
./kotlin/gradlew.bat -p kotlin :core:test --no-daemon --console=plain
./tools/build-react-native-app.ps1 -GradleHome 'C:/short/gradle-cache'
# Run once against each booted, project-owned API 26/36 AVD:
./tools/test-react-native-android.ps1 -SdkRoot 'C:/path/to/Android/Sdk' -Serial emulator-5584
```

Ignored local logs: `.tools/rn-mixed-inventory-red.log`, `rn-mixed-inventory-green.log`, `rn-mixed-inventory-kotlin-full.log`, `rn-mixed-inventory-app-build.log`, `rn-api26-mixed-inventory-validation.log` and `rn-api36-mixed-inventory-validation.log`. The per-AVD JSON reports and their application/kernel/sensor evidence contain the latest runs. Kotlin XML results contain all 37 passing cases.

## Remaining scope

Physical hotplug, rapid connection changes, more simultaneous failure/replacement cases, all-kind native notifications and full overload/detachment coverage remain required. The remaining RN framework/sensor-source adapters, OS permission integration, blocked-native Hermes/UI responsiveness, standalone distribution, other platform bindings and the complete SDK acceptance matrix are unchanged requirements.
