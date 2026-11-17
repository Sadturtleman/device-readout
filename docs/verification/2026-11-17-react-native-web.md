# React Native Web application and package checkpoint — 2026-11-17

The React Native binding now selects the existing browser worker through a web entrypoint. It retains the shared get/watch/settings API and explicit application-owned framework observers. This is representative RN Web integration and local package-consumer evidence, not completion of all 46 entities, platforms, physical devices or version matrices.

## Changes and evidence

The former package entrypoint imported TurboModuleRegistry unconditionally. An actual RN Web application importing the package failed to bundle because RN Web does not export that native API. The package now has a browser-conditioned entrypoint and an explicit `@device-readout/react-native/web` entrypoint. Native resolution retains its original entrypoint. The generated browser bundle is checked to exclude the SDK's native entrypoint, transport and TurboModule specification.

The browser factory delegates to `createWebDeviceAccess`, including its typed optional worker URL. Common models and existing web observer adapters remain available. Creation is inert; ordinary browser collection runs in a dedicated module worker. Screen, permission, lifecycle and app sensor inputs remain explicit observations. React Native and RN Web are optional platform peers, so installing for web does not pull in the mobile framework.

The existing RN Dimensions observer is reused with a web-specific mapping: `size` follows RN's logical window dimensions, while textScaleFactor is null. The pinned RN Web implementation assigns fontScale a constant 1, which is not a measured system text preference. The actual browser snapshot initially returned 1 and failed the corrected-null expectation in both browsers before this mapping was fixed. Native fontScale mapping is unchanged. Safe-area and visual viewport fields remain null in this RN adapter; a separate explicit web viewport observer can provide browser visual viewport values.

The local package check also found Android build and Gradle cache files inside the React Native tarball. Its file allowlist now includes only SDK source/output, Android source/configuration and documentation. The three tested packages include the repository's MIT license text. The consumer verifier rejects build caches and missing licenses before installation.

## Verified consumers

The pinned combination is React Native Web 0.21.4, React/React DOM 19.3.0 and TypeScript 5.0.4 for browser declarations and consumer types. Official package peer metadata accepts React 19. These are tested versions within the agreed 0.21.x policy, not a claim that every patch or future version was exercised. The existing native declaration check continues using its separately documented RN 0.88.0 / TypeScript 5.9.3 environment.

```powershell
./tools/prepare-react-native-web.ps1
./tools/test-react-native-web.ps1
./tools/test-react-native-web-packages.ps1
npm run test:react-native
```

The package command packs core, web and the RN binding locally, uses content-derived tarball filenames, installs them into a separate consumer, and compiles copied application sources against the installed packages. No SDK directory aliases or source junctions are used in this installed-consumer build. It also verifies that React Native mobile was not installed. This is a local tarball test; no registry publication occurred. Monorepo smoke builds use separate package directory links only to reproduce normal package resolution.

Chrome 158.0.8127.37 and Edge 157.0.4341.60 each pass seven actual application scenarios:

1. RN Text renders typed browser CPU and observed viewport values through one shared worker. The host navigator CPU getter is guarded against SDK reads.
2. A real browser resize changes RN Dimensions, useWindowDimensions and the SDK viewport to the same logical dimensions.
3. Real RN AppState listeners consume controlled visibility events, release an app-owned orientation source while inactive and create a fresh session on resume. An inactive get times out while CPU reads remain available.
4. App-published permission denial plus its separately owned read failure stops collection without implicit coordination. An explicit request waits for an app response beyond readTimeout; a subsequent sample succeeds.
5. A controlled worker holds collection for 800 ms. The 160 ms read deadline completes before release while React rendering, animation callbacks and host timers advance.
6. Disposing the viewport observation retires its handle and removes it from discovery.
7. React unmount removes observations, stops the app source and releases all SDK workers created by the consumer.

The same run passes a separate Node consumer: importing the explicit web entrypoint and constructing access/streams requires neither DOM nor Worker. Collection then fails with typed UnsupportedEntity. This is an inert server/pre-render boundary check, not server-side device collection or a full SSR hydration test. The runner reports 3/3 Node parent tests: this check plus the two seven-scenario browser applications.

The existing RN transport/framework suite passes 12/12, including native window font-scale handling, event ordering, independent failures and lifecycle settings. Strict TypeScript 5.0 browser consumer checks cover both conditional and explicit entrypoints and preserve typed Entity/worker URL arguments.

The bundle resolver additionally checks that the `react-native` condition still selects the native source entrypoint and excludes the web entrypoint. This is a package-resolution check, not an Android Metro/APK rebuild.

## Fixtures and limits

Browser CPU collection, resizing, React rendering, package resolution and worker lifetimes are actual integration. Visibility transitions are explicitly dispatched platform-event fixtures consumed by RN AppState; they are not evidence of native hidden-tab transitions or background throttling. Orientation values, permission coordination and held collection are controlled fixtures, not physical sensors or OS permission dialogs.

The initial package-resolution attempt lacked local workspace links, and the first example teardown passed a DOM element to an API that expected the returned React root. Those consumer setup errors were corrected and are not counted as SDK failures. The example now unmounts the root returned by AppRegistry.runApplication.

The browser worker asset must be served with the application. The example copies it beside app.js; deployments with different asset routing can pass an explicit URL. Browser conditions select the web entrypoint; server toolchains without that condition should use the explicit `/web` import. Mixed worker/SDK release versions, arbitrary bundlers, additional browsers, native visibility transitions, physical sensors, complete field coverage and the full acceptance matrix remain unverified. iOS, Windows and macOS RN collectors/framework integration remain unfinished. Android application evidence is unchanged; native APKs were not rebuilt here, and Android package publication still depends on replacing monorepo source paths.

Local evidence is written under `.tools/evidence/react-native-web-*.json`, including installed-consumer mode and package hashes. Logs include `.tools/react-native-web-entry-red-real.log`, `.tools/react-native-web-font-red.log`, `.tools/react-native-web-package-contents-red.log`, `.tools/react-native-web-native-regression.log` and `.tools/react-native-web-package-final.log`. Raw evidence, tarballs, runtime dependencies and build output are excluded from source control.

Primary references: [RN Web setup and aliasing](https://necolas.github.io/react-native-web/docs/setup/), [Dimensions](https://necolas.github.io/react-native-web/docs/dimensions/), [AppState](https://necolas.github.io/react-native-web/docs/app-state/) and [framework compatibility](https://necolas.github.io/react-native-web/docs/react-native-compatibility/). The fixed fontScale and root teardown mappings were checked against the installed 0.21.4 source under `dist/exports/Dimensions`, `AppRegistry`, `render` and `unmountComponentAtNode`.
