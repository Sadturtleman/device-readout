# React Native Android installed-package checkpoint — 2026-11-17

The Android binding now builds and runs from npm tarballs in an independent consumer. Shared Kotlin sources are included in the package, and Codegen resolves the consumer's actual React Native installation. This closes the previously documented monorepo-path dependency for the tested Android consumer; it does not complete the full platform, field, device or version matrix.

## Reproduced failures and changes

The first installed consumer passed TypeScript checking and autolinking, then failed Codegen because Gradle referenced a development-only `.tools/react-native-0.88` path. After resolving the installed React Native/Codegen packages, the same consumer failed Kotlin compilation because the tarball did not contain the shared runtime and Android collectors.

The package's `prepack` script now copies the 26 canonical Kotlin source files into `android/shared`, with a SHA-256 manifest. These staged copies are ignored by Git and refreshed from the common source before development builds or packaging. They are included by the npm allowlist; build caches, generated Codegen output, local.properties and example signing keys remain excluded. Repacking an installed artifact verifies the existing source manifest without requiring the original repository. A developer must build the JavaScript/declaration output before a direct npm pack; the installed-Android verification command performs that build itself.

The library's Gradle source sets reference only its packaged source directories. Codegen comes from the consuming application's installed RN and @react-native/codegen packages, including non-sibling Codegen resolution. A packaged Node script accepts paths as arguments because inline JavaScript expressions lost their quotes through Windows Gradle. An explicit RN-root override remains available for the monorepo's standalone development build; the installed consumer clears that override and NODE_PATH.

The consumer installs real tarballs of core, web and the RN binding. It has its own node_modules, ordinary Metro resolution, default CLI autolinking and no SDK source aliases, junctions or Gradle source paths back into the checkout. The copied verification app continues using the public package import. React Native is 0.88.0, React is 19.3.0 and its consumer/build TypeScript is 5.9.3; this is the framework toolchain, not evidence of the independent SDK's TypeScript 5.0 target.

## Runtime evidence

The Debug APK passes fifteen application scenarios on each project-owned API 26 and API 36 x86_64 emulator. This includes real Hermes imports, native RAM/get/watch, immutable settings, discovery, app-owned viewport, exact integer transport, independent failures, app sensor sources, framework focus loss, window resizing and native sensor suspension/resume. The host independently compares the RAM snapshot with `/proc/meminfo` and verifies native sensor registrations before/background/after resume. Focus loss from the notification drawer retains collection while AppState remains active.

The separately built Isolation APK passes three held-native scenarios on each emulator: get deadline, watch deadline and context closure. Both JS timers and Android UI callbacks advance while native work remains held. Each caller settles and closes before an external broadcast releases the collector; the worker then terminates. This is controlled blocking-collector evidence through the installed TurboModule and Hermes, not physical sensor latency or a hard UI frame-time guarantee.

The final package-building command passes the existing 12/12 RN framework/transport contracts and installed TypeScript consumer checking before producing the APK. The final Debug APK's fifteen cases and Isolation APK's three cases were rerun on both APIs, with their exact APK hashes retained in the reports. The expanded npm package also passes the RN Web installed-consumer regression: seven application scenarios each in Chrome/Edge, strict TypeScript 5.0 browser declarations and inert Node web imports (3/3 parent tests). No mobile RN dependency appears in that web consumer.

The existing standalone Android library command also passes Kotlin and generated Java compilation after preparing packaged sources. Ordinary `npm pack` executes the prepack hook successfully both in the checkout and in the installed consumer; each produces 53 entries including the 26 shared Kotlin sources, with no build caches or example signing keys. The first metadata-reader attempt treated the hook's progress output as JSON; correcting that verifier parsing is not counted as an SDK defect.

## Reproduction

Prepare the normal repository dependencies and pinned RN runtime, then run:

```powershell
./tools/build-react-native-android-packages.ps1
./tools/build-react-native-android-packages.ps1 -SkipPrepare -Variant Isolation
./tools/test-react-native-android.ps1 -SdkRoot .tools/android-sdk -Serial emulator-5584 -InstalledPackage
./tools/test-react-native-isolation.ps1 -SdkRoot .tools/android-sdk -Serial emulator-5584 -InstalledPackage
```

Repeat the two runtime commands for a project-owned API 36 emulator. `-SkipPrepare` uses the already installed tarballs and app sources; omit it to rebuild and install current source. Reports include the APK hash and `installedConsumer=true`. Tarball records include their SHA-256 digests. No registry publication is performed.

On this Windows checkout, the first Isolation rebuild hit Ninja's 260-character dependency-path limitation. The verifier accepts `-GradleHome <short-path>`; a project-owned short junction to the existing Gradle cache resolved it after removing only stale `.ninja_deps` files under the consumer's `.cxx` directory. This cache alias contains dependencies, not SDK source. No global tool configuration was changed. The build retains AGP deprecation and Kotlin warnings; it is not warning-free. The initial sandbox DNS failure during npm installation is also an environment issue, not an SDK regression.

Local logs include `.tools/rn-installed-red.log`, `.tools/rn-installed-sources-red.log`, `.tools/rn-installed-package-final.log`, `.tools/rn-installed-isolation-package-final.log` and `.tools/rn-package-web-regression.log`. Runtime reports are `.tools/rn-installed-android-DeviceReadout_API*.json` and `.tools/rn-installed-isolation-DeviceReadout_API*.json`. All generated artifacts and raw logs remain excluded from Git.

## Remaining scope

Only the pinned npm/Metro/Gradle consumer and two emulator APIs/one ABI are covered. Physical devices, OS permission UI, full entity/field coverage, other package managers and layouts, remaining RN platforms, clean registry distribution and the complete acceptance matrix remain required. Swift/Apple collectors, other binding/platform gaps and supported-version matrices are not made complete by Android packaging. The app still owns screen, permission and lifecycle inputs.

Codegen integration follows the consumer-version principle documented in [React Native Using Codegen](https://reactnative.dev/docs/the-new-architecture/using-codegen). The package uses explicit Gradle tasks to invoke those installed tools; it does not ship generated native glue from a different RN version.
