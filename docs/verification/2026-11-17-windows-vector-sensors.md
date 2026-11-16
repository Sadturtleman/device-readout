# Windows native Gyroscope and Magnetometer checkpoint

Recorded on 2026-11-17 (Asia/Seoul), on Windows 11 Home x64 build 26300 with .NET SDK 10.0.403 and runtime 10.0.14. The complete `tools/test-dotnet.ps1` run passes **140/140** with zero build warnings or errors. The focused native sensor suite passes **11/11**. This extends the [136-case scalar sensor checkpoint](2026-11-17-windows-scalar-sensors.md); all 46 entities and all specified bindings remain in scope.

## Native mappings

Gyroscope uses Windows.Devices.Sensors.Gyrometer. Three native double AngularVelocity components from one reading become a Vector3 in radians per second by multiplying degree/s values by pi/180. Magnetometer uses the three native float MagneticField components from one reading and retains their microtesla units. Signed axes and zero are preserved. Device axes stay in the native device reference frame; the SDK performs no screen orientation query or ReadingTransform mutation.

Both families use typed multi-target discovery, context-local handle generations, passive descriptions, capability queries and selected get/watch. Descriptions expose kind, available device name and minimum report interval; other fields remain null. The initial sample and native ReadingChanged events flow through the existing worker normalization and collection timestamp path. Equal events are retained. PlatformDefault and concurrent explicit sampling requests retain the shared-source ownership described in the scalar checkpoint.

## Reproduced failures and fixes

The initial Gyroscope and Magnetometer tests each failed at public discovery because the Windows entity had no adapter. Implementing their native selectors, factory/event interfaces and scalar component decoders made the complete read/watch paths available.

A later regression test made one native component getter fail with E_FAIL. The first implementation terminated the watch instead of returning a nullable measurement. Property failures now leave the entire vector null, just like nonfinite components; the next complete native reading recovers without restarting the stream or retaining old components. A failure to acquire the native reading itself still follows the existing typed operation-error path.

A held native X-property call exposed unnecessary work after the consumer deadline. The caller already received ReadTimeout and context disposal already returned while the native call remained held, but Y and Z were queried when X finally returned. Native sample decoding now checks cancellation around component getters. Late completion releases the reading and listener without querying the remaining axes. This does not forcibly interrupt an uncooperative native function or establish process crash isolation.

## Evidence

All new scenarios enter through public DeviceAccess. Unmanaged vtable fixtures implement Windows SDK 10.0.26100.0 ABI definitions at the native runtime boundary; they do not supply pre-normalized SDK snapshots.

| Scenario | Evidence |
| --- | --- |
| Gyroscope native ABI | Passive discovery/metadata, native double components, literal signed rad/s expectations, initial sample, duplicate events, nonfinite whole-vector null, recovery and balanced event/reference cleanup |
| Magnetometer native ABI | Passive metadata/capability queries, native float values in microteslas, signs and zero, requested cadence, duplicate events, nonfinite null and restoration of the original interval |
| Partial native component failures | Each X/Y/Z getter fails separately for both families; each watch emits null and then recovers on a complete sample; one-shot reads also return a null Value |
| Held native component | For both families, a 150 ms public deadline completes while X remains blocked on the worker; the host timer advances and context disposal returns without joining the call; late cleanup balances native ownership and does not read Y/Z |
| Actual Windows inventory | Four sensor classes and the shared enumeration factory initialize/release on one collection worker; actual selectors and asynchronous inventories succeed |

Actual SDK discovery reports **Illuminance=0, Pressure=0, Gyroscope=0, Magnetometer=0**. The independent Windows PowerShell WinRT projection in `tools/verify-windows-sensors.ps1` reports the same counts. Inventory checks log no device identifiers or measurements. Native ABI fixtures establish decoder and ownership behavior, not physical sensor measurements or physical axis orientation.

Local ignored logs: `.tools/windows-gyroscope-{red,green}.log`, `.tools/windows-magnetometer-{red,green}.log`, `.tools/windows-vector-property-{red,green}.log`, `.tools/windows-vector-deadline-red.log`, `.tools/windows-vector-focused.log` and `.tools/dotnet-windows-vectors-full.log`. The complete run includes all existing scalar, state, observer, deadline and native Windows checks. Other-language/browser suites were not rerun for these Windows/.NET changes.

## Remaining verification

Physical measurements, real sensor-driver cadence, landscape/portrait-first device orientation checks, actual UI synchronization contexts, hotplug, native permission transitions, broader concurrent lifecycle/error cases, additional metadata, the remaining Windows sensor families and the full architecture/OS/framework/distribution matrix remain required. Twenty-two Windows entity collectors are implemented only to their documented field scope. The complete SDK goal remains active.

## Primary references

Windows SDK WinRT headers specify the interface slots, component ABI types and event IIDs. Microsoft's [GyrometerReading contract](https://learn.microsoft.com/en-us/uwp/api/windows.devices.sensors.gyrometerreading) specifies degree/s components; [MagnetometerReading](https://learn.microsoft.com/en-us/uwp/api/windows.devices.sensors.magnetometerreading) specifies microteslas. The [sensor orientation guide](https://learn.microsoft.com/en-us/windows/apps/develop/devices-sensors/sensor-orientation) distinguishes device reference axes from display orientation. The adapter keeps device axes and performs no display compensation.
