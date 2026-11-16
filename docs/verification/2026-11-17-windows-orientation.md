# Windows native orientation checkpoint

Recorded on 2026-11-17 (Asia/Seoul), Windows 11 Home x64 build 26300, .NET SDK 10.0.403 and runtime 10.0.14. The complete `tools/test-dotnet.ps1` run passes **148/148**, with zero build warnings or errors. The focused native sensor suite passes **19/19**. This extends the [144-case acceleration checkpoint](2026-11-17-windows-acceleration.md). All 46 entities, their complete fields and every specified binding remain in scope.

## Native mappings and reference frames

AbsoluteOrientation and RelativeOrientation use OrientationSensor.GetDeviceSelector with Absolute and Relative reading types, respectively. FromIdAsync opens the selected device, and IOrientationSensor2.ReadingType validates the resulting reference kind before description or subscription. Their targets and active sources remain separate even though the native factory is shared.

Each native reading supplies one Quaternion object. Its float W/X/Y/Z getters become the named public x/y/z/w components of one unit Quaternion. The adapter preserves native signs and the right-handed device-to-reference rotation direction. Absolute orientation uses east, magnetic north and up. Relative orientation preserves the native session's reference; it neither rebases the first SDK sample to identity nor carries an offset into a recreated session. It does not query display orientation or set ReadingTransform.

Microsoft's [reading-type contract](https://learn.microsoft.com/en-us/uwp/api/windows.devices.sensors.sensorreadingtype) defines magnetic versus session-relative references. The [MAUI orientation documentation](https://github.com/dotnet/docs-maui/blob/main/docs/platform-integration/device/sensors.md#orientation) gives ENU axes and worked quaternion rotations; its [Windows implementation](https://github.com/dotnet/maui/blob/main/src/Essentials/src/OrientationSensor/OrientationSensor.windows.cs) passes native components through unchanged. Those sources support the chosen mapping. Physical natural-orientation checks remain required; documented rotations and ABI fixtures are not physical device evidence.

An unreadable or missing Quaternion, an unreadable component, a zero norm or any nonfinite component makes the complete Value null. A later valid sample recovers without restarting the stream. Native reading acquisition errors retain the existing typed operation-error behavior. Every acquired Quaternion reference is released, including when its getter reports failure or cancellation wins during a component call.

Descriptions expose kind, available device name and minimum report interval. Other metadata remains null. Discovery, capability queries and descriptions do not subscribe or measure. Get and watch retain the existing initial sample and native event path, equal-value delivery and immutable sampling configuration. Shared requests respect the native minimum interval and restore the original setting after their last owner leaves.

## Reproduced failures and evidence

The first absolute and relative public-API tests failed at discovery because these collectors were absent. Adding their native selector/factory/event ABI and Quaternion decoding enabled both paths. A subsequent native-type test showed that the first implementation accepted the wrong reference kind. Opening now validates ReadingType: a different or unknown kind raises EntityRemoved and permanently retires that handle. Fresh discovery after native recovery supplies a new handle.

All measurement scenarios enter through public DeviceAccess, with unmanaged native interfaces built from Windows SDK 10.0.26100.0 ABI declarations. They exercise actual decoding and native reference ownership rather than injecting finished SDK snapshots.

| Scenario | Evidence |
| --- | --- |
| Absolute frame and component order | Passive metadata; native W-first float ABI; unit normalization; documented identity, positive X/Z and negative Y examples; rotating device +Y into world west checks the device-to-reference direction independently |
| Relative reference and lifecycle | Distinct selector, four unequal named components, native first-sample reference, observed inactivity release, suspension beyond read timeout, fresh resumption and duplicate event delivery |
| Reference-kind mismatch | Both families reject another known kind before measurement, retire old handles, recover through new discovery and reject unknown kinds during description |
| Partial and invalid fields | Each of four component getters fails separately; zero/nonfinite values, failed Quaternion acquisition and missing object yield null; later samples recover; no watch restart; all references balance |
| Held native component | Existing held-read test extended to both orientation families: public deadline, host timer and nonjoining context disposal finish while W remains held; late return releases nested references and performs no X/Y/Z queries |
| Actual inventory and worker lifetime | All nine sensor selectors enumerate; seven cached factories and one MTA initialization/shutdown balance on the collection worker |

The actual SDK inventory and independent `tools/verify-windows-sensors.ps1` projection both report **zero devices** for Illuminance, Pressure, Gyroscope, Magnetometer, Accelerometer, LinearAcceleration, Gravity, AbsoluteOrientation and RelativeOrientation. These checks verify real runtime activation and asynchronous discovery. They log counts only, without identifiers or measurements.

Ignored local logs: `.tools/windows-orientation-{absolute,relative,type}-{red,green}.log`, `.tools/windows-orientation-properties.log`, `.tools/windows-orientation-focused.log` and `.tools/dotnet-windows-orientation-full.log`. Other-language/browser suites were not rerun for these Windows/.NET changes.

## Remaining work

Physical quaternion measurements, landscape-first and portrait-first devices, cross-platform axis/reference comparisons, native driver cadence, true native relative-reference recreation, actual UI contexts, sensor hotplug, permission transitions, broader concurrent lifecycle/failure cases, additional metadata, remaining sensor families and the complete architecture/OS/framework/package matrix remain required. Twenty-seven Windows collectors are implemented only to their documented field scope. A synchronous native call that never returns can still retain resources and block its worker; worker execution does not establish process crash isolation or zero overhead.
