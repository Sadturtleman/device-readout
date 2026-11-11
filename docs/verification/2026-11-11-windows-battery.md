# Windows battery collection verification — 2026-11-11

Windows now implements Battery discovery, get and polling watch through the common typed API. This brings the Windows adapter to twelve mapped entities. The overall 46-entity, all-platform release goal remains incomplete and active.

```csharp
using var access = WindowsDeviceAccess.Create();
foreach (var battery in await access.Batteries.List(cancellationToken)) {
    BatterySnapshot snapshot = await access.Get(battery, cancellationToken);
    Render(snapshot.Level, snapshot.Charging, snapshot.RemainingEnergyMilliwattHours);
}
```

## Mapping and lifetime

Discovery uses SetupAPI's present battery interfaces and a zero-wait query for each battery tag. Empty slots are excluded. Device files open with read access and sharing; the adapter issues only QUERY_TAG, QUERY_INFORMATION and QUERY_STATUS. Native buffer layouts and control codes were checked against Microsoft's [poclass.h](https://raw.githubusercontent.com/microsoft/win32metadata/main/generation/WinSDK/RecompiledIdlHeaders/shared/poclass.h) and the installed Windows SDK 10.0.26100.0 header.

| Field | Mapping |
|---|---|
| present | A valid, unchanged native tag and successful battery data query |
| level | Current capacity / full capacity, when the denominator is positive; common ratio validation still applies |
| charging / state | Native charge/drain bits; unknown or contradictory charge/drain flags yield null; idle/full/not-charging are distinguished from remaining capacity and online state |
| voltageMillivolts | Native voltage; unknown sentinel becomes null |
| chargeRateMilliwatts | Signed native rate only when capacity/rate units are absolute |
| currentMicroamps | Derived from that sample's mW / mV × 1,000,000, only with known power and positive voltage |
| remaining/full/design energy | Native capacities only when units are mWh |
| temperatureCelsius | Native tenths of kelvin / 10 − 273.15 |
| timeToEmpty | Native seconds at the current drain rate; unknown sentinel becomes null |
| technology / cycleCount | Four-byte chemistry string and cycle count; the native zero cycle-count sentinel becomes null |

TimeToFull, AverageCurrentMicroamps, ChargeCounterMicroampHours and Health remain null. A critical-drain bit does not become a health diagnosis. Native relative capacity can supply a ratio, but is never relabeled as mWh/mW. These mappings use [BATTERY_STATUS](https://learn.microsoft.com/en-us/windows/win32/power/battery-status-str), [BATTERY_INFORMATION](https://learn.microsoft.com/en-us/windows/win32/power/battery-information-str) and [query information levels](https://learn.microsoft.com/en-us/windows/win32/power/battery-query-information-str).

Targets represent a context-local device-path/tag generation. Every read verifies its tag and pins subsequent queries to it. Removal or a changed tag retires the handle; re-discovery produces a new handle even if the old tag later recurs. Tags can also change when battery characteristics change, so this handle is not a permanent physical battery identity. Microsoft's [battery tag contract](https://learn.microsoft.com/en-us/windows/win32/power/battery-information) requires treating such changes as a new battery generation.

An incomplete inventory does not turn inaccessible devices into an empty collection. It still retains removal or generation changes already positively observed before another device fails. Reading one known battery does not require opening every other battery. Individual unavailable data queries become null; if every data query fails, the operation returns a typed error. Removal during any query invalidates the entire snapshot. Malformed fixed-size responses fail rather than being decoded as zero-filled data.

## Evidence

`tools/test-dotnet.ps1` passes 25 checks with zero build warnings/errors. Six battery checks use public DeviceAccess get/watch/discovery/capability APIs, replacing only the Windows device transport with documented binary driver responses. They cover field units and signs, partial availability, relative units, sentinels, real zero/false, contradictory flags, malformed replies, replacement and tag reuse, failed-inventory retirement, equal polling samples, cancellation, independent deadlines and native handle disposal.

The blocked-device case holds a native status response while the caller continues ticking and its 80 ms read deadline expires. Releasing the native operation permits a later read and closes all handles. This proves scheduling responsiveness for the exercised path, not process-crash isolation or zero resource cost.

The real SetupAPI/IOCTL discovery path returns zero inserted batteries on this host. An independent, normal-user `Win32_Battery` CIM query also returns zero. The full .NET suite passes both inside the sandbox and in a normal-user Windows process. The sandbox denied the separate CIM query; its error was not counted as empty-inventory evidence. No device configuration or power settings were changed.

Logs: `.tools/windows-battery-final.log` and `.tools/windows-battery-native.log`; the preceding red regression logs are retained alongside them. TypeScript, Kotlin/Android and browser suites were not rerun for these Windows-only changes.

## Remaining evidence and implementation

There is no physical battery on this host. Actual battery field reads, laptop/UPS/multiple-pack behavior, charging transitions, physical replacement and additional Windows versions/architectures remain unverified. Controlled protocol tests do not replace that evidence.

This initial checkpoint used serial polling and zero-wait native status reads. Subsequent checkpoints add [power-setting callbacks](2026-11-11-windows-power-events.md), [context-owned interface hotplug observation](2026-11-11-windows-battery-hotplug.md) and [OS aggregate battery access](2026-11-11-windows-aggregate-battery.md). Current now selects the OS aggregate when available, including a Present=false snapshot on a batteryless host. The subsequent [individual status checkpoint](2026-11-11-windows-battery-status.md) adds driver status waits and cancellation. Physical-driver evidence and unavailable field mappings remain pending; changes without a delivered native observation can remain undetected. These are outstanding parts of the Windows goal, not a reduction of the design scope.
