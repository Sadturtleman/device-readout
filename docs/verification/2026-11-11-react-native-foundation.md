# React Native transport and Android binding foundation — 2026-11-11

The subsequent [observer checkpoint](2026-11-11-react-native-observers.md) connects app-owned state/permission/lifecycle protocol inputs and separates app/native target identities. The counts and remaining work below describe this earlier foundation checkpoint.

This checkpoint adds the first React Native package and asynchronous Android TurboModule. It preserves the original all-platform scope; it does not establish complete React Native support. The preceding Flutter sensor work remains in [its verification record](2026-11-11-flutter-android-inventory.md).

## Implemented paths

`createReactNativeDeviceAccess()` returns the existing TypeScript DeviceAccess, generated entities, configuration objects and AsyncIterable snapshots. A lazy native-module lookup and context creation start on first use. The binding shares one native owner across configuration views and temporary transport connections. Final SDK closure disposes that owner once, even if native creation returns after the caller's deadline.

The new Kotlin NativeBindingEndpoint uses the existing DeviceAccess collector runtime. It connects get/watch, list/current, capabilities and describe. Native discovery returns opaque context-local handles, keeps unchanged targets stable and retires them after observed absence. A reappearing native identity receives a new public generation. This endpoint is not yet the full observer/sensor-source protocol.

The Android module implements the actual RN 0.88.0 generated NativeDeviceReadoutSpec. Entrypoints schedule coroutine work; JSON parsing and Kotlin operations run off the calling app entrypoint. The module never obtains an Activity, invokes screen getters or requests permission. One pending native receive bounds response forwarding; native response/command queues and JSON payloads also have explicit limits. Kotlin collection, deadlines and cleanup reuse the worker runtime. JavaScript still performs bounded encoding/decoding and value construction; native crashes are not isolated in another process.

The implementation follows the [official TurboModule specification and Codegen workflow](https://reactnative.dev/docs/turbo-native-modules-introduction). This references the workflow only; local compilation and tests are the implementation evidence.

## Reproduced defects

| Defect | Correction and regression |
|---|---|
| Native JSON decimal integers remained strings in TypeScript snapshots | Hydration restores declared ByteCount/Int64 values as exact bigint, including nested category maps, while preserving zero and false. A value of 9007199254740993 is checked explicitly. Both scalar and nested-map regressions failed before the fixes. |
| Transport shutdown could not distinguish idle disconnection from final native-owner disposal | Optional ConnectionFactory.dispose supplies a final nonblocking cleanup hook. Configuration views share it; final closure invokes it once, including an unused context without opening a connection. |
| A delayed native create let an already-disposed request execute afterward | The sender rechecks ownership after awaiting creation. The regression failed with one unwanted native request; it now issues none and disposes the late native context once. |

## Direct evidence

| Check | Evidence |
|---|---|
| Core and browser-collector Node contracts | 32/32 after the common integer/lifetime changes; TypeScript 5.0.4 library and consumer builds pass |
| Actual browser contracts | 38/38 after the final common changes, including worker/observer/sensor/deadline regressions on Chrome and Edge |
| RN transport contracts | 3/3; lazy construction, exact integers, captured interval, idle reconnect with shared context, cancellation, late-create disposal and scoped typed failure |
| Kotlin contracts | 24/24, including three new binding tests for native reads/polling off the caller thread, discovery/current/removed generations, and deadlines/closure while a native collector remains blocked |
| RN Codegen | Actual 0.88.0 compiler generates the Java and C++ interface sources from the checked-in TypeScript spec |
| Android source compilation | TurboModule/package plus generated Java and shared Kotlin/Android sources compile against com.facebook.react:react-android:0.88.0 |
| RN package type/build checks | TypeScript 5.9.3 with RN 0.88.0's official configuration; ES2020 package entrypoint builds |
| Locked tooling preparation | prepare-react-native.ps1 installs 214 packages from the checked-in lock with lifecycle scripts disabled |
| Documentation and helper scripts | 71 local links and both PowerShell scripts' parser checks pass |

The transport fixture models the external asynchronous native ABI. It does not execute Hermes or JNI. Kotlin tests use controlled collectors through the real endpoint and collection worker. Android compilation checks actual RN superclass/method signatures but does not execute the module. Native get/watch connections inherit the existing collectors' mappings in source; no React Native hardware/field result is claimed from that alone.

RN type checking uses the official package's skipLibCheck setting. With dependency-declaration checks enabled, TypeScript 5.9.3 reports errors in RN's AnimatedProps, VirtualizedList and ReactNativeDocument declarations. Those diagnostics are retained; the run is not reported as passing. Core and transport-only TypeScript 5.0 checks retain strict dependency checking. The original standalone-language floor and framework-specific toolchain requirements remain distinct.

The development Android harness compiles with Gradle 8.14.3, AGP 8.11.1, Kotlin 2.2.20, compile SDK 36 and min SDK 26. RN's installed version declares newer application build tools; this partial compile is not proof of its full application build. There was no dependency-validation bypass. The checked-in runtime package/lock under tools/react-native-runtime pins React Native 0.88.0, React/types 19.3.0, TypeScript 5.9.3 and the RN TypeScript configuration. Installation is project-local.

Artifacts under `.tools`: `rn-core-web-regression-final.log`, `rn-browser-regression-final.log`, `rn-transport-final.log`, `rn-native-endpoint-final.log`, `rn-android-binding-compile.log`, `rn-types-official-config-validation.log`, `rn-types-5.9-validation.log`, `rn-codegen-schema.json`, `rn-runtime-prepare-validation.log`. Earlier failing regressions are `rn-json-integers-red.log`, `rn-json-map-red.log`, `rn-context-lifetime-red.log`, `rn-late-create-red.log`, `rn-native-binding-red.log` and `rn-native-discovery-red.log`.

## Required next work

Connect app-owned screen, permission and lifecycle observations before claiming the native binding satisfies the user's complete execution contract. Add permission coordination, native/app target identity separation and sensor-source routing; verify cancellation and removal of active streams, malformed/large requests, overload and module invalidation races. Then run an actual RN 0.88/Hermes APK on the supported Android matrix, including observed UI/lifecycle transitions and a blocked-native heartbeat. Verify Codegen/JSI/autolinking, standalone package consumption, iOS, Windows, macOS and web bindings. Existing Kotlin/Flutter results are not substitute evidence for these React Native gates.
