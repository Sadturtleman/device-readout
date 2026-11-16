# Windows native hinge-angle checkpoint

Recorded on 2026-11-17 (Asia/Seoul), Windows 11 Home x64 build 26300 with .NET SDK 10.0.403 and runtime 10.0.14. The complete `tools/test-dotnet.ps1` run passes **156/156**, with zero build warnings or errors. The focused native sensor suite passes **27/27**. This extends the [152-case proximity checkpoint](2026-11-17-windows-proximity.md); the full 46-entity and binding scope remains unchanged.

## Mapping and metadata

HingeAngle uses HingeAngleSensor.GetDeviceSelector, FromIdAsync and GetCurrentReadingAsync. Native double AngleInDegrees becomes the public Value in radians. Zero remains zero and a full 360-degree turn remains 2*pi rather than being wrapped to zero. An unreadable or nonfinite angle yields null; a later valid native event recovers without restarting the stream.

The description exposes sensor kind and available inventory name. Other metadata remains null. MinReportThresholdInDegrees is an angular reporting threshold; it is not relabeled as MinimumInterval or Resolution. The adapter neither reads nor changes native threshold settings. This API has no report-interval control, so configured sampling rates retain native event cadence. Equal ReadingChanged events are retained. No screen query, display mutation or permission request is introduced.

Microsoft documents [the hinge sensor API](https://learn.microsoft.com/en-us/uwp/api/windows.devices.sensors.hingeanglesensor), [selected asynchronous opening](https://learn.microsoft.com/en-us/uwp/api/windows.devices.sensors.hingeanglesensor.fromidasync), and [the double angle property](https://learn.microsoft.com/en-us/uwp/api/windows.devices.sensors.hingeanglereading.angleindegrees). The installed Windows SDK 10.0.26100.0 headers define the factory, asynchronous reading and event ABI. Independent native inspection of GetDeviceSelector returned an enabled-interface filter for `{82358065-F4C4-4DA1-B272-13C23332A207}`, matching GUID_SensorType_HingeAngle in SensorsDef.h; the adapter enumerates sensor interfaces, not display panels.

## Reproduced failures and fixes

The initial public hinge test failed at discovery because the collector was absent. Adding its native definition, passive metadata, asynchronous first reading and degree-to-radian mapping enabled get/watch.

A subsequent test held GetCurrentReadingAsync pending and delivered a real ReadingChanged event. The initial implementation still waited for the asynchronous operation and reported ReadTimeout despite having a valid sensor sample. A native event now satisfies the first sample, and the unused pending initial operation receives Cancel and Close without consuming its result.

An in-flight initial angle getter can also finish after a newer event. The initial-sample path and event publication now coordinate so that this older initial value is not emitted afterward. Native property reads run outside that short publication lock, and subsequent native events, including duplicates, remain visible.

## Evidence

All controlled measurement checks enter through public DeviceAccess and use native vtable fixtures based on Windows SDK declarations. They exercise actual native decoding and reference management, not prebuilt SDK snapshots.

| Scenario | Evidence |
| --- | --- |
| Native mapping | Passive discovery/description, asynchronous current readings, literal 0/90/180/360-degree expectations in radians, equal events, null property/nonfinite values, recovery, balanced read operations and event listeners |
| First native event | A real event completes get while the initial operation remains pending; that operation is canceled/closed without GetResults; a subsequent read recovers |
| Deadline and caller cancellation | Both get and watch terminate correctly while initial native reads are pending, release their operations/listeners and permit a fresh read; deadline cases preserve host timer progress |
| Late initial value | A held older initial angle finishes after a newer event; it is suppressed, while later equal native events are retained |
| Held native angle getter | Existing nonjoining-disposal test extended to HingeAngle: deadline and host timer complete before native return, then owned reading/listener references are released |
| Actual inventory | Twelve sensor entity selectors enumerate successfully; nine cached factories and one MTA initialization/shutdown balance on the collection worker |

Actual SDK and independent `tools/verify-windows-sensors.ps1` inventories both report zero devices for all twelve implemented sensor entities, including HingeAngle. Counts are logged without identifiers or measurements. These are real runtime and discovery checks; numeric values, event timing and ownership races use controlled native fixtures.

Ignored local logs: `.tools/windows-hinge-{red,green}.log`, `.tools/windows-hinge-first-event-{red,green}.log`, `.tools/windows-hinge-focused.log`, `.tools/windows-hinge-all-sensors.log` and `.tools/dotnet-windows-hinge-full.log`. Other-language and browser suites were not rerun for this Windows/.NET change.

## Remaining work

Physical hinge angle/cadence measurements, actual native pending-operation and cancellation behavior, multiple hinges, real app UI contexts, hotplug, permission transitions, broader concurrent driver/lifecycle failures, additional metadata, remaining sensor families and the complete OS/architecture/framework/package matrix remain required. Thirty Windows collectors are implemented only to their documented field scope. An uncooperative synchronous native call can still retain resources and block its worker; this is not process crash isolation or zero overhead.
