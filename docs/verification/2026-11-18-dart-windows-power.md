# Dart and Flutter Windows power — 2026-11-18

Windows `DeviceAccess.native().get(Entities.power)` and `watch(Entities.power)` now use an isolate-owned power collector. Capability queries advertise both operations without opening the native binding. The public read first failed with UnsupportedEntity and then passed against independent Windows SDK and Windows Forms references.

## Field contract

| Field | Windows mapping |
|---|---|
| powerSource | ACLineStatus 1 becomes External. Offline status 0 becomes Battery only when GetPwrCapabilities confirms system batteries, no UPS and no short-term batteries. Otherwise null. |
| powerSaveMode | SystemStatusFlag 0 becomes false, 1 becomes true; other values become null. |
| thermalState | null; Windows values are not relabeled as an Android or Apple thermal stage. |

[GetSystemPowerStatus](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-getsystempowerstatus) provides a single native status structure. Its [documented fields](https://learn.microsoft.com/en-us/windows/win32/api/winbase/ns-winbase-system_power_status) distinguish AC/DC and battery-saver state. An active power-saver scheme, CPU throttling or a charging flag is not substituted for powerSaveMode.

AC/DC status alone does not supply the distinct onboard-battery/UPS classification available through [SYSTEM_POWER_CONDITION notifications](https://learn.microsoft.com/en-us/windows/win32/api/winnt/ne-winnt-system_power_condition). For offline status, the optional [GetPwrCapabilities](https://learn.microsoft.com/en-us/windows/win32/api/powerbase/nf-powerbase-getpwrcapabilities) query checks [SystemBatteriesPresent, UpsPresent and BatteriesAreShortTerm](https://learn.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-system_power_capabilities). Only the unambiguous onboard-only combination fills Battery. UPS-capable, mixed, absent, failed or unknown capability results leave the source null. This collector does not infer the active UPS from its presence; a distinct UPS source and native change notifications remain follow-up work.

GetSystemPowerStatus failure or failure to allocate its required storage is a whole-read ReadFailed. Optional DC disambiguation failure affects only powerSource, preserving an available saver flag. Successful but unknown native field values remain null. No permission request, power-plan change, battery-saver toggle or other system setting write is performed.

## Execution and lifetime

The collector lazily loads kernel32 on the collection isolate and allocates a bounded 12-byte SYSTEM_POWER_STATUS buffer per read. Offline disambiguation uses the 76-byte SYSTEM_POWER_CAPABILITIES layout; its optional PowrProf DLL is resolved through GetSystemDirectoryW, without relying on the app's DLL search directory. The directory buffer is bounded to 32768 UTF-16 units. All buffers are freed in finally blocks and each context releases its owned library references.

The Dart adapter currently uses immediate first collection and serial polling, with the configured immutable poll interval. Equal values are retained and every snapshot receives a fresh completion timestamp. It does not attach a window or run a UI message loop. The existing host cancellation/deadline path does not join native work; cleanup remains worker-owned. This is not native crash isolation or a zero-overhead guarantee.

## Verification

Host: Windows x64 10.0.26300.0, Dart 3.13.7 / Flutter 3.47.9. The read-only C reference uses the Windows SDK's native structure declarations and functions. It corroborates the status structure size and capability structure size/field offsets. A separate PowerShell process checks Windows Forms PowerLineStatus. Current readings are External, powerSaveMode=false and thermalState=null; native battery capability flags are all zero on this desktop.

| Check | Final result |
|---|---|
| Dart analysis | Clean |
| Dart JIT / compiled native contracts | 69/69 each |
| Negative Dart web boundary | Passed |
| Native current power fields | Agree with Windows SDK; source also agrees with Windows Forms |
| State watch | Three equal readings with increasing collection timestamps |
| Context lifetime | Sibling disposal preserves power, locale and RAM reads |
| Actual Flutter Windows release application | 14/14 |
| Flutter package/example analysis and framework suite | Clean analysis; 27/27 |

The release application adds native power get/watch and host timer progress to the existing screen, state and locale coverage. Its held-isolate scenario still delivers a native window callback and the caller deadline before the held collector returns. The regular example executable is rebuilt afterward and does not contain the independent test DLLs.

Evidence: `.tools/dart-windows-power-red.log`, `.tools/dart-windows-power-green.log`, `.tools/dart-windows-power-final-2.log`, `.tools/flutter-windows-power-final-2.log`, `.tools/flutter-windows-power-framework.log`, `.tools/flutter-windows-viewport-7ae35101609141b6ab9275891abdf63d.json`, and `.tools/evidence/dart-windows-power-checkpoint.json`. The earlier `*-final.log` files precede the DC/UPS ambiguity guard. That guard followed a documentation review, not a reproduced UPS hardware failure. The current host exercises external power; it does not execute the SDK's offline-only capability branch. Native layout checks do not substitute for that missing execution evidence.

```powershell
./tools/test-dart.ps1
./tools/test-flutter-windows.ps1
./tools/test-flutter.ps1
```

On-battery and UPS/mixed-source hardware, saver-on transitions, unknown native flags, required/optional API and allocator failures, actual blocked power calls, ARM64/emulation and installed Windows consumers remain unverified. The existing C# direct power read still uses its older AC/DC projection and needs the same ambiguity/parity follow-up; this checkpoint does not modify or rerun that SDK. Android/browser applications, Apple builds and public package publication were not rerun or performed. The complete 46-entity/binding/platform/version/physical-device acceptance scope remains unfinished. These changes are local after GitHub commit 0efdcde.
