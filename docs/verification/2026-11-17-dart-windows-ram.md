# Dart and Flutter Windows RAM checkpoint — 2026-11-17

`DeviceAccess.native().get(Entities.ram)` and `watch(Entities.ram)` now collect Windows RAM through Win32 APIs. A real public-API test first failed with `UnsupportedEntity`; it now agrees with an independent OS probe. The same implementation runs in the actual Flutter Windows release application. Other standalone Dart native collectors remain pending; this checkpoint does not complete the platform matrix.

## Field meanings and execution

| Field | Windows mapping |
|---|---|
| `physicalBytes` | Firmware-backed `GetPhysicallyInstalledSystemMemory`, KiB converted to exact `BigInt` bytes |
| `kernelAccessibleBytes` | `GlobalMemoryStatusEx.ullTotalPhys` |
| `availableBytes` | `GlobalMemoryStatusEx.ullAvailPhys` |
| `lowMemory` | The current `LowMemoryResourceNotification` state from `QueryMemoryResourceNotification` |
| `advertisedBytes`, `freeBytes`, `lowMemoryThresholdBytes` | null; these meanings are not supplied by the selected APIs |

Installed RAM can exceed the OS-accessible total because some memory is reserved. Available RAM includes reusable standby, free and zeroed pages, so it is not copied into `freeBytes`. These distinctions follow Microsoft's [installed-memory API](https://learn.microsoft.com/en-us/windows/win32/api/sysinfoapi/nf-sysinfoapi-getphysicallyinstalledsystemmemory) and [MEMORYSTATUSEX](https://learn.microsoft.com/en-us/windows/win32/api/sysinfoapi/ns-sysinfoapi-memorystatusex) contracts.

The native collector advertises RAM get/watch support on Windows independently of permissions and current values. Native bindings are created lazily by the existing collection-isolate factory, not on the application's calling path or during capability inspection. Allocation, system queries, snapshot preparation and resource cleanup remain on that isolate. No Flutter channel, UI getter, permission prompt, subprocess or additional Dart dependency is used by the production collector.

State watch uses the existing serial polling path: immediate first read, default one-second interval, immutable overrides and repeated snapshots even when fields remain equal. Every successful read receives its collection-completion timestamp through the existing normalization path. The low-memory object is queried for its present state rather than waited on; it does not represent notifications for every RAM field. Microsoft documents the [state query](https://learn.microsoft.com/en-us/windows/win32/api/memoryapi/nf-memoryapi-querymemoryresourcenotification) as nonblocking.

Each read owns one zeroed native allocation and, when available, one notification handle. `finally` releases the handle and allocation. Context disposal releases an initialized dynamic-library reference after pending worker work; disposing a runtime-only collector does not initialize the memory binding. Individual OS-query failures leave dependent fields null while independent values remain usable; no usable query result or allocation failure reports `ReadFailed`. Failure branches have been inspected but not exercised by native fault injection in this checkpoint.

## Verification

The environment is Windows x64, OS build 10.0.26300.0, Dart 3.13.7 / Flutter 3.47.9. The three new Dart scenarios use only the public SDK API. A separate PowerShell/C# Win32 probe neither imports nor calls DeviceReadout.

| Check | Result |
|---|---|
| Dart analysis, JIT contracts and compiled native contracts | Clean analysis; 54/54 in each execution mode |
| Native RAM against independent OS queries | Installed and accessible bytes match exactly; available bytes checked against nearby volatile samples; stable low-memory state agrees |
| Repeated polling and 100 reads | Host timer progresses; process handle count stays 159 → 159 in JIT and 180 → 180 in the native executable |
| Independent context lifetime | Eight short-lived RAM contexts can close while another continues reading |
| Actual Flutter Windows release application | 6/6 scenarios, including RAM get/watch, screen observations and held-isolate deadline checks |
| Flutter framework regression | 24/24 |
| Dart browser regression | 16 scenarios each in Chrome 158.0.8127.37 and Edge 157.0.4341.60 |
| Negative browser isolate boundary | Compiles and rejects unsupported closure-based collection without invoking its host factory |
| Rebuilt Flutter Android checkout application | 33/33 scenarios on each API 26/36 emulator |

The physical-memory value is 51,539,607,552 bytes (48 GiB); the OS-accessible value is 51,317,346,304 bytes. Available RAM changes between samples. Its independent comparison allows a 1 GiB difference from either adjacent OS probe; it is not an exact simultaneous measurement claim. The native cleanup check permits small unrelated process-handle variation but observed no growth. It does not prove every heap-allocation or native failure path.

The Flutter application receives three real RAM polls while its timer progresses. Its separate existing 500 ms controlled-collector scenario still delivers a 200 ms caller deadline and native window callbacks before the collector returns. That controlled case verifies the shared isolation mechanism; no actual Win32 memory function was artificially held. Neither result promises zero host overhead, native crash isolation or a universal frame-time bound.

The Android APK SHA-256 is `5f21132b91dc2be138424922d65783048066e83a1f074745f288914a06cf6da5`. These are checkout-based regressions (`installedConsumer=false`), not newly published or downloaded package evidence. Android tests retain native state, sensor registration, real Activity suspension/resumption and late-reply checks. Existing Gradle/AGP/Kotlin support-removal warnings remain. No native bridge unit suite, .NET suite or Swift suite was rerun because their implementation is unchanged.

```powershell
./tools/test-dart.ps1
./tools/test-flutter-windows.ps1
./tools/test-flutter.ps1
./tools/test-dart-browser.ps1
./tools/build-flutter-android.ps1 -SdkRoot .tools/android-sdk
./tools/test-flutter-android.ps1 -SdkRoot .tools/android-sdk -Serial emulator-5584
./tools/test-flutter-android.ps1 -SdkRoot .tools/android-sdk -Serial emulator-5586
```

The test helper starts only an owned hidden Windows test process and rebuilds the regular example afterward. Both project Android emulators were shut down after verification. Local logs include `.tools/dart-windows-ram-red.log`, `.tools/dart-windows-ram-final.log`, `.tools/flutter-windows-ram-final.log`, `.tools/flutter-dart-windows-ram-framework-final.log`, `.tools/dart-windows-ram-browser.log`, `.tools/dart-windows-ram-android-build-final.log` and `.tools/dart-windows-ram-android-5584.log` / `5586.log`. The final Windows report is `.tools/flutter-windows-viewport-48aa82a73ef94330818a072e17414f37.json`. Generated evidence and binaries are not committed.

Windows ARM64, native API failure/allocator fault injection, broader memory-pressure conditions, external package consumers for this new collector and other native Dart/Flutter collectors remain unverified or unimplemented. Apple collectors/adapters, React Native's remaining platforms, physical devices, version coverage and the full 46-entity acceptance matrix remain part of the active implementation scope.
