# Dart and Flutter Windows OS checkpoint — 2026-11-17

`DeviceAccess.native().get(Entities.os)` and `watch(Entities.os)` now return Windows OS snapshots. The public test first failed with `UnsupportedEntity`; after implementation, its version and build agree with both an independently compiled native reference and the Windows CIM provider. The actual Flutter Windows release application exercises the same collector.

## Fields and collection

| Field | Windows value/source |
|---|---|
| `family` | `OsFamily.windows` on the Windows adapter |
| `name` | `Windows` |
| `version` | Running NT major.minor.build from `RtlGetVersion` |
| `build` | Native build number as a decimal string |
| `kernelName` | `Windows NT` |
| `kernelVersion` | Running NT major.minor.build |

The native source returns numerical OS version components. Edition, marketing release and patch revision are not supplied by this mapping. For example, the measured Windows 11 host returns `version="10.0.26300"` and `build="26300"`. `kernelVersion` represents the same running NT version, not a file-version lookup. The Windows .NET collector already uses the same native version source through `Environment.OSVersion`; its existing formatting includes a trailing `.0`.

The user-mode NTDLL call follows the source used by the [.NET runtime](https://github.com/dotnet/runtime/blob/main/src/libraries/System.Private.CoreLib/src/System/Environment.Windows.cs) and its [native declaration](https://github.com/dotnet/runtime/blob/main/src/libraries/Common/src/Interop/Windows/NtDll/Interop.RtlGetVersion.cs). The Dart FFI structure preserves the Windows [OSVERSIONINFOW layout](https://learn.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-osversioninfow). Dart documents [Platform.operatingSystemVersion](https://api.dart.dev/dart-io/Platform/operatingSystemVersion.html) as unsuitable for parsing, so that display string is not split into SDK fields.

The collection isolate owns lazy DLL references, allocation, native collection, snapshot normalization and cleanup. Capability queries report OS get/watch support on Windows without initializing native bindings. Query failure, a missing version export or unavailable temporary allocation leaves the version/build/kernelVersion fields null while retaining independently known Windows identity. Native failure branches have been inspected but not fault-injected.

Each read frees its output buffer; context cleanup releases its NTDLL and Kernel32 references after pending work, and still attempts runtime/memory cleanup if another collector's disposal fails. Common polling provides the immediate first snapshot and preserves equal values with fresh completion timestamps. Production collection starts no subprocess, reads no UI object and requests no permission.

## Verification

Environment: Windows x64 build 10.0.26300.0, Dart 3.13.7 and Flutter 3.47.9. The C probe uses the Windows SDK structure declaration without linking DeviceReadout. The additional [Win32_OperatingSystem](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-operatingsystem) CIM reference runs in a test-owned PowerShell process and returns only version/build.

| Check | Result |
|---|---|
| Dart analysis | No issues |
| Dart JIT / compiled native contracts | 57/57 in each mode |
| SDK, independent C and CIM version/build | All return `10.0.26300` / `26300` |
| OS capabilities and watch | Read/watch available; three equal version/build snapshots with increasing completion timestamps |
| Native context lifetime | Closing another OS context preserves subsequent OS, Runtime and RAM reads in the live context |
| Negative web boundary | Compiles and rejects unsupported host collection without invoking the host factory |
| Actual Flutter Windows release app | 9/9, including native OS comparison, OS polling, memory/runtime queries, screen observations and held-worker deadlines |
| Flutter package/example analysis and framework tests | Clean analysis; 24/24 |
| Direct SDK read/watch in the restricted process | Passes without the CIM fixture |

The Flutter OS scenario delivered three snapshots while its timer advanced eight times. The existing controlled 500 ms collector hold still allows a native window callback and the 200 ms read timeout before collection returns; it records 49 total timer ticks. No actual OS-version API was held, so these checks do not establish native crash isolation, zero overhead or a universal frame-time bound.

```powershell
./tools/test-dart.ps1
./tools/test-flutter-windows.ps1
./tools/test-flutter.ps1
```

The native probe remains test-only. The Windows helper uses an owned hidden application, passes the probe path explicitly and rebuilds the regular example afterward. It does not copy the probe DLL into the release directory. Visual Studio 2022 C++ tools/CMake are test prerequisites; no new SDK runtime dependency is added.

Evidence: `.tools/dart-windows-os-red.log`, `.tools/dart-windows-os-green-normal.log`, `.tools/dart-windows-os-final.log`, `.tools/flutter-windows-os-final.log`, `.tools/flutter-windows-os-framework.log`, `.tools/dart-windows-os-direct-restricted.log`, `.tools/flutter-windows-viewport-b3fe2aaefd644fc69aab7811ffea642d.json` and `.tools/evidence/dart-windows-os-checkpoint.json`.

One restricted test run stopped at the independent PowerShell CIM script with an AuthorizationManager rejection, before invoking the SDK OS read. The unchanged test passes in the normal user environment, and a separate direct SDK get/watch check passes in the restricted environment. No execution policy was changed. The original unsupported-entity failure and this fixture authorization failure are separate observations.

Native allocation/API failure injection, ARM64/emulation, compatibility modes, other Windows versions, external package consumers and the complete platform/device/version matrix remain pending. Android APKs, browser application suites, Swift and .NET were not rerun for this Windows-only addition. Apple collectors/adapters, remaining Dart/Flutter/RN platforms and the rest of the 46-entity implementation scope remain active. These local additions have not been uploaded since the preceding GitHub checkpoint.
