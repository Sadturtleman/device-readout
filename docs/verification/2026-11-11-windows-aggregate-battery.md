# Windows aggregate battery verification — 2026-11-11

Windows now exposes the OS aggregate battery through Batteries.Current(), includes that target in Batteries.List(), and reads/watches it through the common typed API. Individual battery targets remain available. The full .NET suite passes 42 checks; the overall cross-platform SDK goal remains incomplete.

```csharp
using DeviceReadout.Windows;

using var access = WindowsDeviceAccess.Create();
var aggregate = await access.Batteries.Current(cancellationToken);
if (aggregate is not null) {
    var snapshot = await access.Get(aggregate, cancellationToken);
    Console.WriteLine(snapshot.Present);
}
foreach (var battery in await access.Batteries.List(cancellationToken)) {
    if (battery == aggregate) continue;
    var individual = await access.Get(battery, cancellationToken);
    Console.WriteLine(individual.Level);
}
```

## Target semantics

Current selects the OS [AggregateBattery](https://learn.microsoft.com/en-us/uwp/api/windows.devices.power.battery.aggregatebattery?view=winrt-26100), not the first physical pack. It can be queried without enumerating or opening individual battery devices. List includes the logical aggregate plus the available individual targets. Those views overlap; their capacities must not be summed as independent batteries. Ordering is not a selection contract.

The aggregate is a stable logical OS endpoint. A not-present report yields present=false and null measurement/status fields; it does not retire that endpoint. The same handle can observe later presence. This differs from individual path/tag generations, which continue to retire permanently after observed removal. If the runtime class/interface is unavailable, Current returns null and individual discovery remains usable. Other activation/read failures retain typed errors.

The new list/current usage exposed a .NET handle equality defect: two bindings for the same target compared as different object references. Entity<T> now compares and hashes by its typed entity identity, owning context and opaque target. Repeated discovery and immutable configuration views compare equal, while independent contexts and new physical generations remain distinct. Consumers can compare handles directly without string IDs.

## Fields

The adapter obtains a native [BatteryReport](https://learn.microsoft.com/en-us/uwp/api/windows.devices.power.batteryreport?view=winrt-26100). It reads the report's nullable values directly; it does not synthesize an aggregate by summing device reports.

| Snapshot field | Mapping |
|---|---|
| present | Known report status: false for NotPresent, true for Discharging/Idle/Charging, otherwise null |
| charging / state | Native Discharging, Idle and Charging states; unknown values become null |
| level | RemainingCapacityInMilliwattHours / FullChargeCapacityInMilliwattHours with a positive denominator; common ratio validation applies |
| chargeRateMilliwatts | Native signed ChargeRateInMilliwatts |
| designEnergyMilliwattHours | Native DesignCapacityInMilliwattHours |
| fullChargeEnergyMilliwattHours | Native FullChargeCapacityInMilliwattHours |
| remainingEnergyMilliwattHours | Native RemainingCapacityInMilliwattHours |
| timeToEmpty | Available GetSystemPowerStatus battery-life seconds; unknown sentinel, explicit absence and online AC state produce null |

Native [charge rate](https://learn.microsoft.com/en-us/uwp/api/windows.devices.power.batteryreport.chargerateinmilliwatts?view=winrt-26100) is positive while charging and negative while discharging. Zero values remain zero. [BatteryStatus](https://learn.microsoft.com/en-us/uwp/api/windows.system.power.batterystatus?view=winrt-26100) supplies the state; idle is not relabeled from a charge percentage.

The optional [SYSTEM_POWER_STATUS](https://learn.microsoft.com/en-us/windows/win32/api/winbase/ns-winbase-system_power_status) time query does not turn BatteryFullLifeTime into timeToFull: the former describes runtime on a full battery. A failed optional query leaves timeToEmpty null without discarding readable report fields. Independently available seconds remain usable when unrelated power flags are unknown. Voltage, current, temperature, chemistry, cycle count, health, charge counter, average current and timeToFull remain null for this aggregate source.

Failed individual report getters become null, including failed nullable-value access. If every report getter fails, the read returns a typed error. A report can legitimately contain nullable unknown values; successful null getters are not classified as a failed read. A not-present status suppresses stale numeric data. No estimate marker or FieldResult wrapper is added.

## Execution and ownership

The WinRT runtime is initialized lazily on the collection worker. Factory activation, report acquisition, nullable-value decoding, event registration/removal, COM reference release and runtime shutdown stay on that same lane. The implementation uses the Windows SDK ABI directly and adds no NuGet dependencies or UI dispatcher. IBatteryStatics, IBattery, IBatteryReport and the typed event handler layouts/IIDs were checked against Windows SDK 10.0.26100.0 headers.

Each successful [RoInitialize](https://learn.microsoft.com/en-us/windows/win32/api/roapi/nf-roapi-roinitialize), including S_FALSE, has a matching worker-owned shutdown after subscriptions and interfaces are released. The caller's COM apartment is not initialized or changed. Construction does not activate WinRT.

Watch registers native ReportUpdated notifications, plus the existing power-setting triggers, and retains serial polling for continuously changing fields. Callbacks enqueue a deferred report read rather than querying native data inline. Every acquired report yields its snapshot directly, including equal values. The OS report determines the capacity ratio; a legacy percentage notification is a refresh signal rather than a replacement value. Unsupported report-event registration falls back to polling. The typed native handler implements reference counting and clears callbacks before removal; managed exceptions do not unwind into WinRT.

Context closure removes active subscriptions, releases the aggregate interface and balances runtime initialization on the worker. One watch's closure does not tear down the shared context. Existing deadline and delayed-cleanup rules still apply to native calls that do not return promptly. This is not a promise of zero resource cost or process-crash isolation. Screen and permission UI remain app-owned observer inputs.

## Evidence

The final build has zero warnings/errors. All 42 tests pass in sandbox and normal-user Windows runs. Four aggregate checks were added to the previous 38-test suite:

* Typed current/list selection, distinct design/full/remaining capacities, signed rate, null unsupported quantities, worker execution and context cleanup. The same case covers handle equality, hashing, configuration views and context separation.
* Actual Windows aggregate reads on this batteryless host: present=false and null measurement fields. Actual ReportUpdated registration/removal succeeds, and activation, native reference release and runtime shutdown occur on one worker. No physical transition is fabricated to satisfy this test.
* Controlled native vtables exercise the production WinRT ABI path with non-null IReference<Int32> values, successful nulls, getter failures, unknown status, absent status, equal event callbacks and balanced COM/event references. This also checks S_FALSE initialization ownership.
* Remaining-time units, zero, unknown sentinel, AC state, independent availability and optional-query failure. Full-battery runtime is never returned as charging time.

The tests call public DeviceAccess APIs. Controlled fixtures replace the OS report, device transport or WinRT activation/reference boundary, not SDK get/watch internals. Existing individual-battery cases explicitly exclude the aggregate to keep their native-device counts meaningful. The real default collector's list now has one logical aggregate target on this host, while individual device discovery remains empty.

Logs: `.tools/windows-aggregate-fields-red.log`, `.tools/windows-aggregate-native-red.log`, `.tools/windows-aggregate-event-red.log`, `.tools/windows-aggregate-abi.log`, `.tools/windows-aggregate-runtime-red.log`, `.tools/entity-handle-equality-red.log`, `.tools/windows-aggregate-final.log` and `.tools/windows-aggregate-normal-user.log`. Red cases exposed the missing current target, report subscription, remaining-time mapping and handle equality; final runs pass. Other language/browser suites were not rerun for this .NET/Windows change.

## Remaining work

Actual non-null capacities, charge/discharge transitions, report-event delivery during physical changes, multiple packs/UPS behavior and the Windows version/architecture matrix remain unverified. Controlled ABI inputs are not physical-battery evidence. The subsequent [individual status checkpoint](2026-11-11-windows-battery-status.md) adds per-device driver waits and cancellation; physical-driver evidence remains pending. Additional Windows collectors, volume/network hotplug and the broader Swift/Apple, Flutter/RN and device support matrix remain pending. The existing power-setting and battery-interface implementations are retained.
