# Dart and Flutter Windows DeviceInfo checkpoint — 2026-11-17

Windows `DeviceAccess.native().get(Entities.deviceInfo)` and `watch(Entities.deviceInfo)` now collect four device-information fields. The public test first failed with `UnsupportedEntity`, then passed against independently compiled Win32 queries and CIM metadata. The same collector runs in the actual Flutter Windows release application.

## Field mapping

| Field | Source |
|---|---|
| `manufacturer` | `HKLM\HARDWARE\DESCRIPTION\System\BIOS\SystemManufacturer` |
| `modelName` | `SystemProductName` under the same BIOS key |
| `board` | `BaseBoardProduct` under the same BIOS key |
| `deviceName` | `GetComputerNameW`, the current Windows NetBIOS computer name |
| `brand`, `modelCode`, `product`, `formFactor` | null; separate mappings remain pending |

The system manufacturer/model meanings agree with Microsoft's [Win32_ComputerSystem mapping](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-computersystem). The board value identifies the baseboard product/part, consistent with [Win32_BaseBoard.Product](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-baseboard). No firmware serial number or SKU is substituted for these fields.

The computer name follows [GetComputerNameW semantics](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-getcomputernamew): it is the active NetBIOS name, can reflect a cluster virtual server, and a pending rename normally takes effect after restart. It is not a permanent hardware identifier. Cluster and actual rename transitions are not exercised here.

## Execution and failure behavior

The collection isolate owns lazy Kernel32/Advapi32 bindings, native allocations, reads, decoding and cleanup. Capability inspection reports DeviceInfo get/watch support without loading the bindings. Production code reads registry values and the computer name; it writes no registry value, starts no process and performs no UI or permission operation.

BIOS reads use [RegGetValueW](https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-reggetvaluew) with REG_SZ restriction and the 64-bit registry view. A size query precedes collection; output buffers are capped at 64 KiB, with at most three attempts if the value grows. Decoding stays within the returned byte count, requires even-sized terminated UTF-16 and rejects invalid surrogate sequences. Empty strings are preserved. The predefined registry handle is borrowed; every SDK-owned buffer and DLL reference is released by its owning collection context.

An unreadable/malformed field remains null while independent fields are retained. If none of the four sources is readable, the entity fails with `ReadFailed`. These native failure, large-buffer, growth-race and non-ASCII paths have been inspected but not exercised with controlled native inputs. The present fixture verifies actual ordinary-user values on this host.

State watch retains the existing immediate first read, serial polling, immutable interval settings and equal-value delivery. Each completed snapshot gets one fresh collection timestamp. Closing another context preserves subsequent DeviceInfo and Os reads in the live context.

## Verification

Environment: Windows x64 build 10.0.26300.0, Dart 3.13.7 / Flutter 3.47.9. A separate C probe uses Windows SDK declarations and reads the native fields without DeviceReadout. A test-only PowerShell process obtains system manufacturer/model and baseboard product through CIM. The board comparison is made when CIM reports exactly one board.

| Check | Result |
|---|---|
| Dart analysis | No issues |
| Dart JIT / compiled native contracts | 58/58 in each mode |
| DeviceInfo actual fields | SDK, independent Win32 and applicable CIM values agree |
| Capabilities, polling and timestamps | Read/watch available; three equal readings with increasing completion times |
| Context lifetime | Independent context disposal preserves the live device and OS collectors |
| Negative web boundary | Compiles and rejects unsupported host collection without invoking its factory |
| Actual Flutter Windows release application | 10/10, including DeviceInfo, OS, runtime, memory, screen observations and held-worker deadlines |
| Flutter package/example analysis and framework suite | Clean analysis; 24/24 |

The actual manufacturer is `Micro-Star International Co., Ltd.`, model `MS-7E25`, and board `MAG Z790 TOMAHAWK MAX WIFI (MS-7E25)`. The computer name matches the independent native query; its raw value is omitted from reports. The Flutter DeviceInfo watch delivers three snapshots while the app timer advances eight times. The existing controlled 500 ms collector hold still permits a native window callback and the 200 ms caller timeout before collection returns. No actual registry call was artificially held; this does not establish native crash isolation, zero overhead or a universal frame-time bound.

```powershell
./tools/test-dart.ps1
./tools/test-flutter-windows.ps1
./tools/test-flutter.ps1
```

Evidence: `.tools/dart-windows-device-info-red.log`, `.tools/dart-windows-device-info-green.log`, `.tools/dart-windows-device-info-final.log`, `.tools/flutter-windows-device-info-final.log`, `.tools/flutter-windows-device-info-framework.log`, `.tools/flutter-windows-viewport-46a43ed0dc0b4fd9a173c1111f68f81c.json` and `.tools/evidence/dart-windows-device-info-checkpoint.json`. The test-only native DLL remains outside the regular release directory. The Windows helper runs an owned hidden process and rebuilds the regular example afterward.

Brand/model-code/product/form-factor mappings, native faults/encoding/size races, ARM64/emulation, other hardware and Windows versions, cluster/rename behavior, external distribution and the complete acceptance matrix remain pending. Android APKs, browser application suites, Swift and .NET were not rerun for this Windows Dart addition. The full 46-entity and binding scope remains active; this local checkpoint has not been uploaded since the preceding GitHub publication.
