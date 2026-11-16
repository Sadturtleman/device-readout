# Observer failure ownership and inactive permission loss

Recorded on 2026-11-17 (Asia/Seoul). This checkpoint follows the [Generic Sensor adapter](2026-11-16-web-generic-sensors.md) and [React Native framework observers](2026-11-16-react-native-framework-observers.md). It does not complete the full SDK support matrix.

## Contract

TypeScript and Kotlin expose `access.observers.failureSource(entity)`. Each returned handle owns an independent error slot. `publish(error)` reports a typed failure; `publish(null)` clears only that slot; `close()` releases only that owner. Repeated close and close after context disposal are safe. Publishing after handle closure fails with `EntityRemoved`. Creating a handle is inert.

The existing `observers.failure(entity, error)` remains the application policy channel. Current reads prioritize application target/family policy, then provider target/family failures. Removing one provider cannot erase application policy, another provider or a replacement owner. Failure publication invalidates cached state and reaches affected pending streams, including inactive sensors. Clearing an error does not revive a terminated stream or restore a pre-failure cached value; a new read/watch needs fresh state. Unrelated entities remain usable.

The React Native protocol carries independently scoped owner IDs into Kotlin. It rejects invalid IDs, releases owners on endpoint disposal and preserves the public ownership rules across the worker boundary.

## Browser permission behavior

The Generic Sensor adapter publishes authorization failure through its own target-scoped owner, including while native sensor sessions are stopped by app-reported inactivity. Permission loss therefore ends a pending watch without needing a native sample or sensor error event. Reauthorization clears only the adapter's failure, leaving application policy intact.

Missing, unreadable, prompt or denied permission dependencies block measurements and sensor descriptions with `PermissionDenied`. Discovery, capability and permission inspection remain separate passive operations. After authorization, descriptions expose the sensor kind and unavailable metadata as null without constructing native sensors. SDK calls do not query permissions, request permission UI or read screen state. The app supplies observable permission and lifecycle state.

## Verification

| Check | Result | Evidence scope |
| --- | --- | --- |
| TypeScript 5.0.4 library/consumer compilation and common/collector tests | 34/34 | Independent ownership, policy precedence, fresh state, reconnect and disposal |
| Chrome 158.0.8127.37 and Edge 157.0.4341.60 | 56/56 total | Full browser suite, including controlled inactive permission loss and actual native permission revoke/regrant while sensors are stopped |
| Kotlin 2.1.21 / coroutines 1.10.2 JVM contracts | 43/43 | Public failure handles and native binding ownership, invalid IDs and inactive sensor failure |
| React Native transport/framework contracts | 12/12 | Existing public binding and framework observer checks |
| RN 0.88.0 / Hermes / JSI Android API 26 app | 15/15 | Twelve baseline scenarios plus actual focus loss, window change and sensor resume |
| Same APK on Android API 36 | 15/15 | Same scenarios, independently rerun |

The new RN ownership scenario observes `ReadFailed`, application `PermissionDenied`, a remaining owner's `UnsupportedEntity`, `ReadTimeout` for invalidated old state, and inactive sensor `PermissionDenied`. Fresh viewport state then succeeds. Both emulator runs also verify independent kernel-memory agreement, sensor release in the background, restoration on resume and retention during focus loss.

The browser regression initially left the inactive stream pending after permission loss. The native endpoint initially rejected the new observer input. Both reproduced failures pass after connecting the independent ownership channel. Actual browser permission tests first establish that native sampling frequencies are zero, then revoke permission and confirm stream failure. They regrant permission, resume with fresh samples and verify final native resource release.

Commands used: `npm test`, `node --test packages/web/test/browser.test.mjs`, `npm run test:react-native`, `kotlin/gradlew.bat -p kotlin :core:test --no-daemon --console=plain`, `tools/build-react-native-app.ps1` and `tools/test-react-native-android.ps1` for each emulator. The final RN APK SHA-256 is `ee138b211d3e6d2d67e59e9823bbd642282e1cbc75bcca403cbc4296a8c57a92`.

Local detailed logs use `.tools/owned-failure-*.log`; emulator reports are `.tools/rn-android-DeviceReadout_API26.json` and `.tools/rn-android-DeviceReadout_API36.json`. Browser inactive native-permission evidence is under `.tools/evidence/generic-sensor-permission-*-paused.json`. Generated binaries, logs, profiles and SDK caches remain ignored local artifacts.

## Limits

The native browser sensors use DevTools virtual hardware. Application inactivity is explicitly supplied; these checks do not establish real browser visibility/BFCache behavior, physical sensor accuracy or the Firefox/Safari/latest-two-version matrix. Magnetometer and light still require the separately recorded experimental Chromium configuration. RN error sources are controlled application inputs, not physical permission plugins. Other bindings, native platforms, broader concurrency/overload cases and the complete field/support matrix remain required. Prior held-collector isolation evidence remains historical; that separate APK was not rebuilt for this checkpoint.
