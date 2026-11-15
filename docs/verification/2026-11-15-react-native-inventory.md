# React Native native inventory observation — 2026-11-15

The RN native endpoint now connects the collector's inventory notifications. A callback can retire an absent target and end its active requests without requiring another application `list()` call. This extends the preceding [explicit-list retirement checkpoint](2026-11-15-react-native-retirement.md).

Follow-up: the [mixed app/native inventory checkpoint](2026-11-15-react-native-mixed-inventory.md) fixes skipped native refresh under an app-owned inventory, adds a controlled regression and adds an actual application scenario on both Android APIs. The results and remaining items below describe this earlier checkpoint.

## Behavior and ownership

Construction and ordinary singleton reads remain inert with respect to inventory observation. The first native `list` or `current` registers a context-owned observer through the existing collector worker. App-owned inventories do not initiate registration. Registration uses the initiating query's deadline; the observer remains owned by the context until failure or final close.

Native callbacks enqueue only dirty entity kinds. Repeated pending invalidations for the same kind share one queue entry; this does not deduplicate or discard measurement snapshots. Only previously discovered kinds are refreshed. Refreshes run serially with explicit discovery, use the context access's read deadline (five seconds for the normal RN context), and perform native collection through the worker. A valid complete inventory is required before tokens are bound or retired. The existing Android collector supplies dynamic-sensor connection notifications; other native entity families still depend on their existing collectors and explicit discovery.

Successful absence detection cancels affected native requests with `EntityRemoved`, including an inactive sensor watch. Failed or malformed inventories preserve target identities and terminate affected work with their typed failure instead of claiming removal. A subsequent successful explicit refresh or new change notification can clear a per-kind refresh failure; terminated streams do not restart. Failure of the shared inventory observation itself releases that subscription and remains terminal for native discovery in that context. Ordinary singleton reads remain usable.

Registration and cleanup stay on the collection lane. Close does not join blocked registration, and a subscription returned after cancellation is still released by the worker. No new screen getter or permission prompt is introduced.

## Reproduced defects and contract evidence

Five tests exercise the same `NativeBindingEndpoint.send/next` contract used by the RN module, with controlled external collectors:

| Case | Evidence |
| --- | --- |
| Native notification removes an inactive sensor | Fails before integration; passes without a second list call. Registration and cleanup are off the caller thread, and a RAM read does not start inventory observation. |
| Malformed refresh | Duplicate native IDs produce `ReadFailed`, retain the original token, leave RAM reads working and permit recovery after a successful explicit list. |
| Blocked native registration | Read timeout and close finish while the registration gate is still held; its late subscription is released off the caller thread. |
| Failure reported synchronously during registration | Reproduced a false successful inventory; fixed to reject the initiating request with the original typed error and release the subscription before listing. |
| Cancellation-shaped error reported by the collector | Reproduced a silent observer exit with a surviving watch; fixed to deliver `ReadFailed`, release observation, preserve RAM reads and avoid silent restart. Caller/context cancellation remains separate. |

The first integration test failed on the preceding implementation. The synchronous-registration and cancellation-shaped callback cases also failed before their respective fixes. Kotlin now passes **36/36** tests: access 12, native binding 9, native inventory 5, observers 7 and snapshots 3.

## Actual RN application

The RN 0.88.0/Hermes/JSI example builds with the existing pinned toolchain and passes the existing harness on both **API 26 and API 36**, x86_64. Each run passes eight baseline scenarios plus actual window change and fresh-sensor-resume scenarios. Independent `/proc/meminfo` agrees with the SDK RAM value, and native sensor registrations disappear in background and return on resume.

The same rebuilt APK was used for both runs. SHA-256:

`24a657a1ad9d16edd82b1ca036f166293ea22946b3caea15de57b7a3d91a7b97`

These emulator runs establish that the new inventory registration coexists with the real native module and lifecycle path. They do **not** simulate physical dynamic sensor hotplug. Permission coordination remains controlled app-observer state, and the app heartbeat is ordinary-workload evidence rather than a deliberately blocked-native Hermes/UI responsiveness test.

## Reproduction and local evidence

From the repository root, using the project-local Gradle home for the Kotlin command:

```powershell
./kotlin/gradlew.bat -p kotlin :core:test --no-daemon --console=plain
./tools/build-react-native-app.ps1 -GradleHome 'C:/short/gradle-cache'
# Run once against each booted, project-owned API 26/36 AVD:
./tools/test-react-native-android.ps1 -SdkRoot 'C:/path/to/Android/Sdk' -Serial emulator-5584
```

Ignored local evidence includes `.tools/rn-inventory-red.log`, `rn-inventory-registration-red.log`, `rn-inventory-channel-red.log`, the corresponding green/contract logs, `rn-inventory-kotlin-full.log`, `rn-inventory-app-build.log`, `rn-api26-inventory-validation.log` and `rn-api36-inventory-validation.log`. The existing per-AVD JSON, application log, meminfo and native sensor dumps contain the latest runs. Kotlin XML results contain all 36 passing cases.

## Remaining scope

Physical dynamic sensor hotplug, rapid connection changes, mixed app-owned/native inventory replacement, all-kind notification coverage, callback/read races and full overload/detachment coverage remain unverified. Background refresh currently skips kinds whose inventory is app-owned; preserving native-handle observation alongside such overrides needs further work. The other RN sensor-source/framework adapters, OS permission integration, blocked-native Hermes/UI responsiveness, external distribution, other platforms and the full SDK acceptance matrix remain required.
