# React Native framework observers — 2026-11-16

Explicit application-owned Dimensions and AppState adapters now feed the existing observer API. The transport/framework suite passes **12/12**. The rebuilt RN 0.88.0/Hermes/JSI example passes **14 reported scenarios on each API 26 and API 36** x86_64 emulator, with independent kernel-memory and native sensor-registration checks. This is an Android implementation checkpoint; it does not establish the remaining RN platform or field matrix.

## Public contract

`observeReactNativeViewport(access, Dimensions)` returns a typed Viewport entity and an idempotent `close()`. Setup attaches the listener before reading the initial window metrics. Later callbacks copy their supplied payload without another Dimensions read, and a reentrant newer event takes precedence over an older initial value. The adapter provides logical `size` and `textScaleFactor`. `visualViewportSize`, `visualViewportScale` and `safeAreaInsets` remain null. Partial invalid fields become null without erasing other valid fields or an application-owned failure. Closing detaches the listener, gates late callbacks and retires only the adapter's own target.

`observeReactNativeSensorActivity(access, AppState, policy?)` publishes initial and changed lifecycle state. The default typed `ForegroundOnly` policy enables sensors only while active; `AllowInactive` explicitly includes inactive. Unknown/null initial state suspends sensors. Focus/blur events alone do not change activity. Register one lifecycle owner per shared context before starting sensor work, and close adapters before the SDK. Ownership is an application requirement, not an enforced multi-owner arbitration mechanism.

SDK get/watch/list do not query framework UI state. Only explicit attachment and framework callbacks feed that state. Adapter callbacks perform bounded copying/publication on JS; native collection retains its worker. This is not process isolation or zero JS-thread overhead. A broken host listener remover can fail to release its resource even though disposed callbacks remain gated.

Implementation: [framework-observers.ts](../../packages/react-native/src/framework-observers.ts), [public exports](../../packages/react-native/src/index.ts) and [example application](../../packages/react-native/example/src/App.tsx). The [binding README](../../packages/react-native/README.md) contains usage and cleanup order.

## Controlled contracts

Seven new framework contracts run against the actual SDK and a collection worker, alongside five transport contracts:

- window values are copied, get/watch and subsequent events do not re-read Dimensions, duplicate updates remain observable, and close retires the target;
- lifecycle changes suspend and restart source sessions without re-reading currentState;
- the optional inactive policy is explicit and unknown state suspends collection;
- partial nullable fields preserve independent values and application-owned failure state;
- newer synchronous events win over older initial state for both adapters;
- failed attachment detaches listeners and retires only its own target;
- unknown/inactive initial lifecycle pauses sensor demand, with safe disposal and late callbacks.

The initial missing implementation failed its contract before the adapter was added. TypeScript 5.0 checks the independent source/API, while the actual RN declaration/app checks use the pinned RN toolchain. `npm run test:react-native` passes all 12 tests. Kotlin's **41/41** source-binding result remains evidence from the preceding [sensor-source checkpoint](2026-11-15-react-native-sensor-sources.md); Kotlin was not rerun for this adapter-only change.

## Actual application evidence

Both emulator runs use the same debug APK SHA-256:

`12cd0f039a8a0b15258d13dc4b2261da0bd1cbef18b2f8dca51bcd26f53acd40`

| Check | API 26 | API 36 |
| --- | --- | --- |
| Eleven baseline app scenarios | Passed | Passed |
| Fresh sensor sample after notification-drawer focus loss | Passed | Passed |
| Native sensor registration retained during focus loss | Passed | Passed |
| Window changes from 320 × 640 to 640 × 320 logical units | Passed | Passed |
| Native sensor registration removed on background transition | Passed | Passed |
| Registration restored and fresh sample received after resume | Passed | Passed |
| Native RAM agrees with independent kernel data | Passed | Passed |

The test distinguishes focus loss from backgrounding: notification expansion leaves AppState active, and both a new sample timestamp and the native sensor registration are checked. Home/resume separately verifies removal and restoration. The normal APK was rebuilt successfully. The older held-collector isolation APK was not rebuilt or rerun for this checkpoint.

Reproduce with `npm run test:react-native`, `tools/build-react-native-app.ps1`, then `tools/test-react-native-android.ps1` against each project-owned AVD. The external harness restores its window override, collapses its notification panel and force-stops its own app during cleanup.

Local evidence (ignored build/test artifacts): `.tools/rn-framework-observers-full.log`, `.tools/rn-framework-observers-app-build.log`, `.tools/rn-api26-framework-observers-validation.log`, `.tools/rn-api36-framework-observers-validation.log`, and `.tools/rn-android-DeviceReadout_API26.json` / `DeviceReadout_API36.json`, with foreground/unfocused/background/resumed sensor dumps. Repository scripts and this result summary are published; local binaries and raw logs are excluded.

## Remaining scope

Display physical metrics, safe-area and visual viewport sources, OS permission integration, physical sensor plugins, multi-owner/replacement/concurrency cases, external package consumption and all other RN platforms remain unverified. Full platform/version/field coverage and broader overload, callback failure and detachment cases remain required. These helpers do not reduce the release scope.
