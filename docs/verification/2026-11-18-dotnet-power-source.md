# C# Windows power-source semantics — 2026-11-18

Subsequent evidence: the [native-call checkpoint](2026-11-18-dotnet-power-native.md) adds 23 scenarios through the production P/Invoke declarations, including controlled failures/holds and a real system-capability comparison. The verification limits below describe this earlier source-mapping checkpoint.

`DeviceAccess.Get(Entities.Power)` and polled `Watch(Entities.Power)` previously mapped every offline AC-line status to Battery. A public-API regression test reproduced that incorrect result when no information distinguished an onboard battery from a UPS. The Windows adapter now uses the same conservative direct-read classification as the [Dart power collector](2026-11-18-dart-windows-power.md).

## Native mapping

| Input | powerSource |
|---|---|
| ACLineStatus = 1 | External |
| ACLineStatus = 0, SystemBatteriesPresent = 1, UpsPresent = 0, BatteriesAreShortTerm = 0 | Battery |
| Other offline combinations, unavailable capability query, or unknown status/flags | null |

The optional [GetPwrCapabilities](https://learn.microsoft.com/en-us/windows/win32/api/powerbase/nf-powerbase-getpwrcapabilities) query runs only for offline status. A false return leaves the capability information absent and preserves the separate battery-saver field. The [SYSTEM_POWER_CAPABILITIES fields](https://learn.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-system_power_capabilities) describe battery and UPS presence; UPS presence alone does not identify the active power source. No source is inferred from charge percentage, a battery flag, a power plan or a thermal reading.

The P/Invoke declaration uses a one-byte BOOLEAN result and a 76-byte explicit structure with UPS, system-battery and short-term-battery flags at offsets 12, 30 and 31. These offsets were checked against the installed Windows SDK 10.0.26100 header. PowrProf is resolved from the system directory. Public entity models and signatures are unchanged; the added capability data stays inside the Windows adapter.

Exact source notifications retain their separate mapping: PoAc -> External, PoDc -> Battery, PoHot -> Ups. Unknown event values remain null. A source event overrides that event snapshot's coarse direct-read source; it does not install a cached source for later independent reads. Equal events and equal polled values remain observable. SystemStatusFlag still maps 0/1 to false/true and other values to null. Windows thermalState remains null.

## Verification

| Check | Result |
|---|---|
| Initial public get/watch regression | Failed before the fix: DC alone returned Battery |
| Initial regression after the fix | 1/1 passed |
| Focused Windows power checks | 6/6 passed, including the selected-battery notification test |
| Complete .NET suite, restricted execution environment | 163/168 passed |
| Same sources, normal Windows user environment | 168/168 passed; build has zero warnings and errors |

The controlled source test covers onboard-only, UPS, mixed, short-term, absent and unknown capability flags, external power with a UPS present, an unknown AC-line status and an unknown saver flag. Each case exercises public Get plus initial/polled Watch snapshots and duplicate values with fresh timestamps. It supplies raw native-adapter responses; it does not simulate physical hardware or prove the P/Invoke failure path.

The notification test now supplies an ambiguous direct-read source while delivering precise UPS and onboard-battery event payloads. It checks that payload values and duplicates survive, saver flags remain independent, unrelated reads keep the null source, and late callbacks perform no collection. The actual Windows notification test receives and unregisters source and saver callbacks without a window or UI message loop. Existing aggregate/individual battery, deadline, cancellation, saturation and lifetime checks pass in the complete suite.

The restricted run failed five existing native checks: publisher identity, Wi-Fi profile inventory, missing WLAN interface, cellular inventory and cellular watcher lifetime. Native errors included HRESULT 0x80070057, 0x80073D54 and 0x80004002; the WLAN test did not observe its expected EntityRemoved outcome. The unchanged suite subsequently passed under the ordinary Windows user context. No assertion, native error handling or test was weakened or skipped. These results establish the normal-user run, not support for that restricted environment.

Retained local logs:

- `.tools/dotnet-power-source-red.log`
- `.tools/dotnet-power-source-green.log`
- `.tools/dotnet-power-projection.log`
- `.tools/dotnet-power-source-final.log` (restricted run; failed)
- `.tools/dotnet-power-source-normal-user.log` (final passing run)
- `.tools/evidence/dotnet-power-source-checkpoint.json` (source and binary hashes)

Reproduce the full suite from an ordinary Windows user PowerShell session:

```powershell
./tools/test-dotnet.ps1
```

## Execution and remaining evidence

Native status collection, the optional capability query and snapshot normalization remain on the existing collection worker. Import/construction does not query native status. No UI getter, permission prompt, power-setting write or shared application policy change is introduced. Existing deadlines and cancellation stop the caller waiting without joining held native work; a permanently blocked native call can still hold its worker and delay cleanup. This is not process crash isolation or a zero-overhead guarantee.

The current desktop is externally powered, so this run does not execute the SDK's offline-only GetPwrCapabilities branch against hardware. Controlled values verify classification but do not replace native ABI, capability-query failure, real DC/UPS transition or held power-API evidence. Those cases, ARM64, installed .NET consumers, the remaining collectors/bindings and the full physical/version/environment matrix remain unfinished. Other language/framework suites were not rerun for this C# change. This checkpoint is local after GitHub commit 056ee70.
