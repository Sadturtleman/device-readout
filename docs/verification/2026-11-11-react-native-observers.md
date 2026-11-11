# React Native observer protocol — 2026-11-11

This checkpoint connects app-owned state, current-target selection, permission state and coordination, lifecycle, observer errors and target removal to the Kotlin native endpoint introduced in the [foundation checkpoint](2026-11-11-react-native-foundation.md). It is not a complete React Native platform claim. Actual RN/Hermes application execution and framework observer adapters remain required.

The SDK does not obtain an Activity, read screen state or open permission dialogs. Applications publish their observations through the shared `access.observers` API. The native command actor decodes these values on its worker; generated decoders cover all 46 snapshot shapes. Native get/watch then use the same typed Kotlin runtime and collection worker as standalone Android. Exported schema coverage does not imply native availability of every field.

An explicit permission request emits a `permissionRequest` message to the app's coordinator. The coordinator can ask the app to perform its platform action. Returning from that callback does not grant permission or finish the request: only an observed permission state completes it. The request has no read deadline. Cancellation still cancels the native request and its permission listener. SDK reads never trigger this coordinator implicitly.

Sensor activity comes from an app-owned lifecycle observer. Inactivity releases native observations and suspends the JavaScript first-sample deadline. Resumption reports `reading` for continuous sensors and creates a new Kotlin observation. Event sensors do not acquire a deadline merely while waiting for an occurrence. Failures and removal remain observable during inactivity; stopping measurement does not stop those notifications.

## Reproduced and corrected defects

| Defect | Correction and evidence |
|---|---|
| Native endpoint rejected observer commands | Register/state/current/remove/failure/permission and entity-independent sensorActivity inputs now have native handlers. A screen test reads, watches updates and receives removal while the underlying screen collector throws on any access. |
| App names and native target IDs occupied the same identity namespace | Kotlin addresses and internal TS wire bindings retain an observed-target discriminator. Discovery/current round trips preserve it; permission maps, failure listeners, cached inputs and app sensor sources use it. Tests deliberately reuse a name and preserve distinct values, permissions and errors. |
| Selecting an existing native target as current hid its native inventory | Explicit native current selection no longer substitutes an empty observer inventory. Explicitly observed empty inventories remain supported. |
| A paused Kotlin sensor missed observer failure/removal until resumption | A lifetime failure subscription now remains active independently of measurement sessions. A native endpoint test reproduced the timeout, then passes for both PermissionDenied and EntityRemoved while inactive. |

Observed inventory does not retire previously issued native aliases solely because the app supplies its own inventory. Direct native-handle observations keep their native identity, while app-created handles keep their app identity. The public API still exposes typed Entity handles; consumers do not compare the internal discriminator or identifiers.

## Verified contracts

| Check | Result |
|---|---|
| Core TypeScript / browser collector Node tests | 33/33, including native/app identity, current/list behavior, scoped failure during an independent native watch and input replay after worker reconnection |
| TS compatibility | Core and consumer compilation with TypeScript 5.0.4; RN package with its existing official 0.88.0 configuration and TypeScript 5.9.3 |
| Actual browser tests | 38/38 on Chrome 158.0.8127.18 and Edge 157.0.4341.46; screen, sensor, lifecycle, cancellation and worker heartbeat regressions |
| React Native asynchronous transport tests | 5/5; adds permission coordination beyond the read deadline, target identity and native suspended/reading messages controlling the JS first-sample deadline |
| Kotlin contracts | 30/30, including eight native endpoint tests and a public native/app identity contract |
| Android service contracts | 15/15; shared Kotlin changes compile and pass existing native service tests |
| Android build | AAR, instrumentation APK assembly and lint pass; no emulator/device test was run for this checkpoint |
| Final RN Android compilation | TurboModule, actual generated Java interface and final shared Kotlin runtime compile successfully against RN 0.88.0 |
| Dependent Flutter Android bridge | 12/12 native bridge contracts pass after the shared Kotlin changes; example Dart analysis reports no issues |

The generated input decoder preserves exact decimal ByteCount values above JavaScript's safe-integer range, zero and false, and nested category maps. Unsafe numeric integers become null. An unknown enum element invalidates its entire set; an actually empty set remains empty. Thermal state retains its platform type. Input collectedAt does not override the collection-completion timestamp. These are exercised through the endpoint, not only through decoder helper tests.

Kotlin tests use controlled native collectors and the real binding/runtime. RN transport tests use the external asynchronous native-module seam. These checks do not execute JNI, JSI or Hermes. The browser tests exercise actual installed browsers, but they are not RN Web certification. The previously documented RN dependency-declaration and Android application-toolchain limits still apply.

Artifacts under `.tools`: `rn-observed-screen-red.log`, `rn-observed-screen-validation.log`, `observer-target-identity-kotlin-red.log`, `observer-target-identity-ts-red.log`, `observer-target-identity-kotlin-validation.log`, `observer-target-identity-ts-validation.log`, `rn-permission-observer-red.log`, `rn-permission-observer-validation.log`, `rn-lifecycle-observer-red.log`, `rn-lifecycle-observer-validation.log`, `rn-inactive-observer-failure-red.log`, `rn-observer-android-regression.log`, `observer-origin-core-final.log`, `observer-origin-browser-validation.log`, `rn-observer-transport-final.log`, `rn-observer-android-final.log` and `rn-observer-flutter-bridge-regression.log`.

The final RN compile retains the foundation's limited source-compilation harness. Flutter emits existing Gradle/Kotlin future-support and SDK XML warnings; its analysis and bridge contracts pass without dependency-validation bypasses. No actual Flutter or RN application was launched in this checkpoint.

## Remaining acceptance work

Implement and run app-owned RN screen/lifecycle integration, app sensor-source sessions, native inventory changes and active-stream retirement. Verify malformed input, saturation, module invalidation and pending-reply races. Exercise actual RN 0.88/Hermes APKs on the supported Android matrix, then Codegen/JSI/autolinking, standalone package consumption and the iOS/Windows/macOS/web bindings. Complete the original 46-entity field/version/physical-device matrix. This checkpoint does not narrow that scope or count the missing platforms as supported.
