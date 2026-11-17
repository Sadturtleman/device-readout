# Dart and Flutter Windows runtime checkpoint — 2026-11-17

Windows `RuntimeSnapshot.hostArchitecture` now comes from a native OS query instead of remaining null. The public Dart test first reproduced `X64 != null` against an independent compiled C reference, then passed after the collector was implemented. This checkpoint also adds dedicated ProcessMemory and Runtime scenarios to the actual Flutter Windows release application.

## Mapping and execution

The collector uses the `pNativeMachine` output of [IsWow64Process2](https://learn.microsoft.com/en-us/windows/win32/api/wow64apiset/nf-wow64apiset-iswow64process2). Known x86, x64, ARM32 and ARM64 machine values map to existing typed Architecture values. Unknown output, a failed query, unavailable export or failed temporary allocation leaves the host field null while preserving readable process fields. Those failure paths have been inspected but not fault-injected.

The process architecture still comes from Dart's current ABI, and process bitness from the pointer size. Neither is copied into host architecture. `supportedAbis` remains null because these sources do not enumerate the supported ABI set. Other native operating systems still have no host-architecture collector in this Dart implementation. In particular, [GetNativeSystemInfo](https://learn.microsoft.com/en-us/windows/win32/api/sysinfoapi/nf-sysinfoapi-getnativesysteminfo) may report an emulated architecture on ARM64, so it is not used as the host source.

The collection isolate owns lazy library loading, the four-byte output allocation, the query and buffer cleanup. Capability inspection does not initialize the binding. Context disposal releases both runtime and memory library references after pending collection; the process pseudo handle is not closed. No UI getter, permission request, process launch or extra Dart dependency is introduced by production collection.

## Verification

Environment: Windows x64 build 10.0.26300.0, Dart 3.13.7 and Flutter 3.47.9. The native reference in `tools/windows-memory-probe/runtime.c` uses Windows SDK declarations and constants, without linking DeviceReadout. It checks the SDK's hand-declared FFI boundary and field mapping against a separately compiled native call. This is actual x64 execution, not evidence for emulated or ARM64 execution.

| Check | Result |
|---|---|
| Dart analysis | No issues |
| Dart JIT / compiled native contracts | 56/56 in each mode |
| Runtime get/watch | Native reference and SDK both report host X64; the x64 consumer reports process X64 / 64 bits and null supported ABIs |
| Repeated Runtime snapshots | Three equal architecture snapshots with increasing completion timestamps |
| Independent native contexts | Closing a runtime/RAM context preserves another context's subsequent Runtime read |
| Negative web boundary | Compiles and rejects unsupported host collection without invoking the host factory |
| Actual Flutter Windows release application | 8/8, including ProcessMemory and Runtime get/watch, RAM, screen observations and the held-isolate deadline scenario |
| Flutter package/example analysis and framework tests | Clean analysis; 24/24 tests |

The Flutter ProcessMemory sample was 22,368,997,376 bytes, equal to both adjacent independent Win32 readings inside process 30288. Three process-memory snapshots arrived while the Flutter timer advanced eight times. The comparison retains its 1 GiB volatility tolerance; equality in this run is not a simultaneous-measurement guarantee. Runtime independently matched X64 and delivered two equal architecture snapshots with distinct timestamps.

The existing controlled 500 ms collector hold still permits a native window callback and the 200 ms caller timeout before the collector returns. It records 49 total timer ticks and one metrics callback. Actual Win32 memory or architecture calls were not artificially held; no native crash isolation, zero overhead or universal frame-time bound is established.

```powershell
./tools/test-dart.ps1
./tools/test-flutter-windows.ps1
./tools/test-flutter.ps1
```

The Windows helper builds the test-only reference DLL, passes its absolute path to an owned hidden test application and rebuilds the regular example afterward. The reference DLL is not copied into the application's release directory. Visual Studio 2022 C++ tools and its CMake component are test prerequisites, not SDK dependencies.

Local evidence: `.tools/dart-windows-runtime-red.log`, `.tools/dart-windows-runtime-green.log`, `.tools/dart-windows-runtime-final.log`, `.tools/flutter-windows-runtime-final.log`, `.tools/flutter-windows-runtime-framework.log`, `.tools/flutter-windows-viewport-db8f2f3b78234639981ba39b6bdd0e80.json` and `.tools/evidence/dart-windows-runtime-checkpoint.json`. The initial native probe rebuild failed to overwrite a previously created import library in the restricted environment (LNK1114 / access denied). The same source built in the normal user environment before the SDK's missing-field failure was reproduced; the build-environment failure is separate from that SDK gap.

Browser application suites, Android APKs, Swift and .NET were not rerun in this checkpoint. ARM64 and emulation, native allocation/API failure injection, process memory job limits, other Dart/Flutter collectors, external distribution of these additions and the complete platform/device/version acceptance matrix remain pending. These are local implementation changes after the preceding GitHub upload, not a registry release.
