# React Native app-owned sensor sources — 2026-11-15

The existing typed `access.observers.sensorSource(target, source)` API now connects through the Android TurboModule to Kotlin collection demand. Kotlin passes 41 tests, including four new native source contracts. The actual RN 0.88.0/Hermes/JSI app passes thirteen reported scenarios on each API 26 and API 36 x86_64 emulator, plus independent kernel-memory and native sensor-registration checks.

## Reproduced gap and implementation

The first native contract failed with an `UnsupportedEntity` observer error: JS could register a source, but the native endpoint did not implement the `sensorSource` observer command or sensor sample replies. The new binding connects those messages to the existing Kotlin sensor lifecycle instead of treating source registration as a cached measurement.

Registration and metadata/capability queries are inert. Each get/watch observation allocates its own session and requests the application's subscription through the native response queue. Continuous watches receive their configured sampling rate; gets and event sensors use the platform-default rate. Kotlin decides when demand starts, stops or resumes. JS owns its callback, AbortSignal and returned cleanup function.

Native session IDs are not reused within a context. Old or stopped session samples cannot alias resumed/sibling observations. The binding retains at most 2048 active source sessions and reports `ReadFailed` on exhaustion. Sample decoding and Kotlin normalization/stamping occur off the UI/JS execution path. The JS source callback and cleanup still run on JS and must remain short and nonblocking; no SDK code requests permission or opens a UI.

Sensor descriptions use a generated decoder from the shared schema. Kind comes from the typed entity, unknown reporting-mode values become null, and Duration metadata retains milliseconds. No field wrapper or extra timestamp was added. The new Kotlin source-registration seam is internal to bindings; the public TypeScript API is unchanged.

## Contract evidence

Four native endpoint contracts cover:

- inert description/capability queries, metadata units/unknown enums, concurrent get/watch sessions, default versus configured sampling, one-shot cleanup and late-sample isolation;
- suspension/reacquisition with a fresh session, no initial-sample timeout while inactive, and observer failure ending an inactive stream;
- request-scoped source failure, malformed sample failure and read timeout while a sibling watch survives, followed by explicit target removal and cleanup;
- event watches waiting beyond the first-read timeout without a fake event, actual occurrence delivery, event sampling default and a timed one-shot event read.

The complete Kotlin suite passes **41/41**: access 12, native binding 9, inventory 6, sensor source 4, observer 7 and snapshot 3. The initial source contract was run before the implementation and failed, then passed after the connection was added. Existing contracts remain passing.

## Actual application evidence

Two required scenarios were added to the ordinary app. On both APIs:

| Scenario | Observed result |
| --- | --- |
| App source lifecycle | Metadata starts no observation; watch requests 60 Hz; get uses a separate platform-default session; suspension aborts the first watch session; resume creates the third session; removal ends the watch and cleans sessions 1, 2 and 3. |
| App source failures and close | Four attempts produce PermissionDenied, ReadFailed, ReadTimeout and EntityRemoved. Returned cleanup functions run for attempts 1, 3 and 4; attempt 2 throws before returning cleanup. All four AbortSignals are aborted. |

These are controlled application source callbacks running in the real Hermes application and crossing the actual native protocol. They do not prove integration with a third-party physical sensor plugin. Existing native SensorManager observation, Activity pause/resume registration and fresh resumed samples also pass separately.

Each run has eleven baseline scenarios plus actual window change and sensor resume: **13 app-reported passes**. Kernel RAM still agrees with `/proc/meminfo`. The same APK was used on both APIs; SHA-256:

`4d9e6af8b1390ca13c73deb2cf05e2c45c1c51119e6cb6026979b307f1f40114`

## Reproduction

```powershell
# Use the project-local Gradle home for the Kotlin command.
./kotlin/gradlew.bat -p kotlin :core:test --no-daemon --console=plain
./tools/build-react-native-app.ps1 -GradleHome 'C:/short/gradle-cache'
# Run against each booted, project-owned API 26 / API 36 emulator:
./tools/test-react-native-android.ps1 -SdkRoot 'C:/path/to/Android/Sdk'
```

Ignored local logs: `.tools/rn-sensor-source-red.log`, `rn-sensor-source-green.log`, `rn-sensor-source-kotlin-full.log`, `rn-sensor-source-app-build.log`, `rn-api26-sensor-source-validation.log` and `rn-api36-sensor-source-validation.log`. Per-AVD JSON, app logs, kernel data and sensor dumps contain the latest thirteen-scenario runs. Kotlin XML contains the 41 passing tests. Both project-owned emulator processes were shut down after verification.

The preceding [held-collector checkpoint](2026-11-15-react-native-isolation.md) and [mixed-inventory checkpoint](2026-11-15-react-native-mixed-inventory.md) retain their original APK hashes and test counts. The held-collector fixture was not rebuilt or rerun in this source-session checkpoint.

## Remaining requirements

Reusable RN framework observer adapters, physical sensor-source plugins and permission integration, source registration/replacement and overload interleavings, broader native protocol/detachment coverage, all-kind inventory notifications, external package consumption and every other RN platform remain incomplete. The full SDK field/version/platform/acceptance matrix is still required; this checkpoint does not establish a complete release.
