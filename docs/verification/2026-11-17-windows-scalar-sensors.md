# Windows native Illuminance and Pressure checkpoint

Recorded on 2026-11-17 (Asia/Seoul), on Windows 11 Home x64 build 26300 with .NET SDK 10.0.403 and runtime 10.0.14. The complete `tools/test-dotnet.ps1` run passes **136/136**, with zero build warnings or errors. The focused `-Filter 'Windows native sensor'` run passes **7/7**. This extends the [129-case state lifetime checkpoint](2026-11-17-dotnet-state-lifetime.md).

## Implemented behavior

Windows.Devices.Sensors.LightSensor and Barometer now support passive multi-target discovery, typed handles, descriptions and selected get/watch. Light readings retain lux. Barometer hectopascals are multiplied by 100 to return pascals. Both preserve zero and repeated values. Descriptions supply kind, available device name and minimum report interval; other metadata remains null. Current does not invent a default sensor.

Subscription registers native ReadingChanged and obtains one current reading. If that initial reading is absent, collection waits for a real event within the existing first-sample deadline. Native events copy the supplied scalar into the common sensor input path; snapshot normalization and collectedAt remain worker-owned. No synthetic periodic sensor readings are generated.

Each selected sensor has a shared native source within its collector. Numeric frequency requests become millisecond intervals, clamped to the native minimum. Concurrent subscribers use the fastest requested interval; releasing one recalculates the surviving request. The last release restores the interval observed when opening the source. PlatformDefault alone keeps that existing interval. Creating a configured DeviceAccess view changes no native state. Actual event cadence remains controlled by the operating system and driver.

Successful enumeration retires absent targets, and native EntityRemoved errors permanently retire the selected handle. Reappearance gets a fresh generation. The removal regression first failed because the old handle attempted to subscribe again and timed out; it now fails immediately with EntityRemoved.

## Execution and cancellation

WinRT initialization, activation, enumeration, sensor opening, interval configuration, native event registration/removal and reference cleanup execute on the collection worker. Runtime and cached factories close there after subscriptions stop. Construction is inert. No screen access, permission prompt or application UI dispatcher is added; existing application-owned permission and lifecycle inputs remain in effect.

Discovery awaits native asynchronous operations on that worker with cancellation checks. Cancellation requests IAsyncInfo.Cancel and closes/releases the owned operation. The capability regression exposed a missing token: the caller timed out, but native enumeration kept occupying the worker. A cancellation-aware IDeviceCollector.Capabilities overload now forwards the deadline through ObservedCollector to the Windows implementation. Existing collectors retain the default implementation delegating to their original capability method.

This does not forcibly interrupt arbitrary synchronous native calls, isolate native crashes or guarantee zero host overhead. A native call that never returns can still retain its resources and block the collection lane.

## Evidence

| Check | Result |
| --- | --- |
| Passive discovery and metadata | Controlled two-light/one-pressure inventory; no measurement subscription during list/describe/capabilities; correct selected target and independent session settings |
| Real WinRT inventory and lifetime | Actual selectors and asynchronous DeviceInformation enumeration; one worker-owned runtime initialization/shutdown, three cached factory releases |
| Permanent removal | A native removal error invalidates the old handle; rediscovery creates a fresh handle that can read |
| Native ABI measurements | SDK-header-based unmanaged vtable fixtures exercise float lux, double hPa, zero, initial readings and duplicate native events through public DeviceAccess; all references and event registrations balance |
| Concurrent sampling | 25 Hz requests 40 ms; 100 Hz clamps to the fixture's 20 ms minimum; default one-shot reads retain active requests; final cleanup restores the original 100 ms interval |
| Discovery deadline | Held native enumeration times out while host timers advance, then receives native Cancel/Close; later discovery succeeds |
| Capability deadline | The same held enumeration is canceled and closed when the capability query deadline expires |

Actual SDK discovery reports **Illuminance=0, Pressure=0**. The independent Windows PowerShell WinRT projection in `tools/verify-windows-sensors.ps1` reports the same counts. Neither inventory probe logs identifiers or measurement values. Controlled ABI samples are not evidence of a physical sensor measurement.

Local ignored logs are `.tools/windows-sensor-focused.log` and `.tools/dotnet-windows-sensors-full.log`; earlier red logs preserve the missing-removal and capability-cancellation regressions. The console harness exits nonzero on failure. Other-language and browser suites were not rerun for these .NET-only changes.

## Remaining scope

Physical light/pressure measurements, actual concurrent driver cadence, device hotplug observation, additional metadata, remaining Windows sensor families, broader cancellation/error interleavings, other architectures and the full OS/framework/package-consumption matrix remain required. The Windows collector count is now twenty, each limited to its documented fields. The complete 46-entity SDK and all language/framework targets remain the intended scope.

## Native references

ABI definitions are checked against Windows SDK 10.0.26100.0 WinRT headers. API semantics come from Microsoft's [LightSensor documentation](https://learn.microsoft.com/en-us/uwp/api/windows.devices.sensors.lightsensor), [ReportInterval contract](https://learn.microsoft.com/en-us/uwp/api/windows.devices.sensors.lightsensor.reportinterval) and [BarometerReading documentation](https://learn.microsoft.com/en-us/uwp/api/windows.devices.sensors.barometerreading).
