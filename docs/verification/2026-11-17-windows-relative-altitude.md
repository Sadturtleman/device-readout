# Windows relative-altitude checkpoint — 2026-11-17

Environment: Windows 11 Home build 26300 x64, .NET SDK 10.0.403 and runtime 10.0.14. The complete `tools/test-dotnet.ps1` run passes **165/165**, with zero build warnings or errors. This adds four public native-ABI scenarios to the [161-case human-presence checkpoint](2026-11-17-windows-human-presence.md); all 36 native sensor scenarios pass in the complete run. The 46-entity and binding scope is unchanged.

## Mapping and default-device scope

RelativeAltitude uses Windows Altimeter.GetDefault, its DeviceId, GetCurrentReading and ReadingChanged. Native double AltitudeChangeInMeters becomes Value without unit conversion, rebasing, sign inversion or pressure-derived calculations. Negative values and zero remain valid. Nonfinite or unreadable values become null; a later valid event recovers without restarting the stream. Equal native events are retained. The baseline belongs to the native collection session and is not assumed to persist across reopening.

Microsoft describes [Altimeter as a relative-altitude sensor](https://learn.microsoft.com/en-us/uwp/api/windows.devices.sensors.altimeter), documents its [meter-valued reading](https://learn.microsoft.com/en-us/uwp/api/windows.devices.sensors.altimeterreading.altitudechangeinmeters), and specifies that [GetDefault returns null without available hardware](https://learn.microsoft.com/en-us/uwp/api/windows.devices.sensors.altimeter.getdefault). This WinRT class exposes only its default sensor, with no selector or selected-device factory. Accordingly, Sensors.List returns zero or one native target and current() resolves that same target. This is not a claim to enumerate every physical altimeter.

Every native open validates the returned DeviceId against the selected handle before subscribing or measuring. A different/missing default cannot silently replace that handle: get/describe return EntityRemoved. Observed absence retires existing streams; reappearance receives a new generation. Malformed or failed identity reads do not erase an existing inventory. Native names and other unavailable metadata remain null; descriptions expose Kind and readable MinimumReportInterval.

Discovery/default selection/description acquire and release the native object without collecting readings, installing listeners or changing its interval. Native access errors remain typed failures. Sampling requests share the existing source ownership: the fastest requested interval respects the driver minimum, removing a fast subscriber retains a slower request, and removing the last subscriber restores the original setting. App activity and permission inputs retain the existing observer contract; no SDK UI query, prompt or setting flow is added.

## Evidence

The first test failed because RelativeAltitude target discovery was absent. Adding default-only discovery, identity validation, typed mapping and native stream support made it pass. The following additional cases exercised that implementation and existing runtime contracts through public DeviceAccess. Native vtables are independently based on Windows SDK 10.0.26100.0 declarations.

| Scenario | Observed behavior |
| --- | --- |
| Values and passive metadata | Literal 7.5 and -2.25 meter values, zero, duplicates, nonfinite nulls, recovery, native minimum interval, missing metadata and balanced one-shot/watch leases |
| Default identity | Empty inventory/current null without hardware; malformed identity preserves old inventory; changed default is rejected before measuring under an old handle; removal terminates streams; same-ID return creates a fresh handle |
| Held native boundaries | Nine cases cover list default/identity, get default/identity/current reading/value and describe default/identity/minimum interval. Host timers and read deadlines finish while native calls remain held. Context disposal does not join them; returned objects/listeners are released afterward. Canceled default/current-reading results do not trigger further property queries |
| Failure and shared sampling | Native default denial is PermissionDenied; unreadable metadata/value fields are null; concurrent 20/60 Hz requests retain native 50/20 ms ownership and restore 100 ms after the last subscriber; app suspension/restart preserves fresh native relative values rather than inventing a zero baseline |
| Actual runtime | SDK and independent Windows PowerShell WinRT discovery agree that all fourteen implemented sensor entities have no devices on this host; the default altimeter is null. Eleven cached factories and one MTA lifetime balance on the collection worker |

Ignored local logs: `.tools/windows-altimeter-red.log`, `.tools/windows-altimeter-green.log`, `.tools/windows-altimeter-targets.log`, `.tools/windows-altimeter-held.log`, `.tools/windows-altimeter-recovery.log`, and `.tools/dotnet-windows-altimeter-full.log`. `tools/verify-windows-sensors.ps1` now includes a passive default-altimeter probe. No identifiers or measurement values are logged by the actual runtime inventory checks. Other language/browser suites were not rerun for this Windows/.NET change.

## Pedometer mapping remains unresolved

Investigation before this change did not establish that Windows Pedometer.CumulativeSteps has the boot-based lifetime required by StepCountSinceBoot. Microsoft documents a [cumulative step count](https://learn.microsoft.com/en-us/uwp/api/windows.devices.sensors.pedometerreading.cumulativesteps), and its [driver fields include an explicit reset indication](https://learn.microsoft.com/en-us/windows-hardware/drivers/sensors/pedometer-data-fields). The official [current-count sample](https://github.com/microsoft/Windows-universal-samples/blob/main/Samples/Pedometer/cs/Scenario3_CurrentStepCount.xaml.cs) adds step-kind totals, while the [event sample](https://github.com/microsoft/Windows-universal-samples/blob/main/Samples/Pedometer/cs/Scenario1_Events.xaml.cs) accounts for decreases before calculating increments. These sources do not prove the required boot baseline. No mapping, synthetic individual-step events or implementation credit was added for StepCountSinceBoot/StepDetected. Establishing a faithful native/history mapping remains work; the SDK contract was not weakened.

## Remaining work

Physical relative-altitude measurements, baseline/cadence/permission behavior, default-device transitions on real hardware, broader concurrent lifecycle/driver failures, additional metadata, older OS/architecture validation, remaining Windows sensors and the full binding/distribution matrix remain required. Thirty-two Windows entity collectors are implemented only to their documented field scope. A permanently stuck native call can retain its worker and resources. This checkpoint does not establish process-crash isolation, zero overhead or release readiness.
