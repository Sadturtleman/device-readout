# Windows native proximity checkpoint

Recorded on 2026-11-17 (Asia/Seoul), Windows 11 Home x64 build 26300 with .NET SDK 10.0.403 and runtime 10.0.14. The complete `tools/test-dotnet.ps1` run passes **152/152**, with zero build warnings or errors. The focused native sensor run passes **23/23**. This extends the [148-case orientation checkpoint](2026-11-17-windows-orientation.md); all 46 entities, complete fields and specified bindings remain required.

## Mappings and API behavior

ProximityNear and ProximityDistance use the native ProximitySensor selector and synchronous FromId, with distinct typed targets and independent subscription lifetimes. The common worker performs discovery, opening, initial reads, subscription management and cleanup. ReadingChanged supplies the selected native reading for subsequent snapshots. Get/watch do not call CreateDisplayOnOffController, query screen state or request permission UI.

ProximityNear preserves the native IsDetected Boolean, including false. A failed getter or an invalid native Boolean byte yields null. ProximityDistance reads the nullable unsigned DistanceInMillimeters value and divides by 1000 to produce meters. Zero remains zero; a missing value remains null. Neither entity is inferred from the other.

Descriptions expose Kind and the available inventory Name. ProximityDistance additionally reads native MaxDistanceInMillimeters into MaximumRange in meters. That distance field is not copied into ProximityNear's Boolean metadata. Native minimum distance is not a sampling interval or a resolution and is not relabeled as either. Other metadata stays null.

The native proximity API has no report-interval controls. Explicit sampling-rate settings therefore retain the original native event cadence, without a fabricated timer, dropped duplicate events or sensor-setting writes. Equal native events are delivered. Closing either entity's stream leaves the other entity subscribed.

Microsoft documents [ProximitySensor's methods and events](https://learn.microsoft.com/en-us/uwp/api/windows.devices.sensors.proximitysensor), [the reading's independent state and distance properties](https://learn.microsoft.com/en-us/uwp/api/windows.devices.sensors.proximitysensorreading), and [DistanceInMillimeters as nullable UInt32](https://learn.microsoft.com/en-us/uwp/api/windows.devices.sensors.proximitysensorreading.distanceinmillimeters). Windows SDK 10.0.26100.0 headers supply the synchronous factory ABI, event IID, Boolean representation and nullable-reference slots used by the native adapter and its independent fixture.

## Reproduced failures and evidence

The initial near and distance cases each failed at public discovery because the Windows mappings were absent. The sensor runtime now supports synchronous opening, entity-specific current-reading slots and native classes without report-interval properties, while preserving existing asynchronous sensor behavior.

All measurement scenarios enter through public DeviceAccess and use unmanaged native vtables at the Windows API boundary; they do not inject completed SDK snapshots.

| Scenario | Evidence |
| --- | --- |
| Boolean state | Passive discovery/metadata/capability lookup, initial false, true/false transitions, equal native events and balanced native listeners; display controller never invoked |
| Nullable distance | Literal millimeter-to-meter expectations, zero, null and full unsigned range; passive maximum-range metadata; independent near/distance watches with different requested rates |
| Property failure recovery | Failed Boolean, nullable-reference and reference-value getters return null; invalid Boolean bytes remain unavailable; later samples recover without restarting either watch; metadata failures stay null and recover |
| Held synchronous opening | Both entities return ReadTimeout and allow context disposal before native FromId returns; late sensor references are released before subscription or measurement |
| Held field/metadata calls | Near Boolean, distance reference/value and range reference/value calls are held separately. Host timer and caller deadline progress; context disposal does not join native work. Late references are released, and reference values are not queried after a property call returns canceled |
| Actual Windows inventory | Eleven sensor entity selectors enumerate successfully; eight cached factories and one MTA initialization/shutdown balance on the collection worker |

The held-call scenario covers seven separate native boundaries. Native readings, nullable values, factories and event references are all balanced after normal closure, property failure and delayed completion. The complete suite also reruns existing orientation, acceleration, vector/scalar, state, observer and cancellation checks.

Actual SDK and independent `tools/verify-windows-sensors.ps1` inventories both report zero devices for Illuminance, Pressure, Gyroscope, Magnetometer, Accelerometer, LinearAcceleration, Gravity, AbsoluteOrientation, RelativeOrientation, ProximityNear and ProximityDistance. Counts are logged without identifiers or measurements. These checks verify real factory activation and asynchronous discovery, not physical proximity measurements.

Ignored local logs include `.tools/windows-proximity-{near,distance}-{red,green}.log`, `.tools/windows-proximity-held.log`, `.tools/windows-proximity-properties.log`, `.tools/windows-proximity-focused.log` and `.tools/dotnet-windows-proximity-full.log`. Other-language and browser suites were not rerun for this Windows/.NET change.

## Remaining work

Physical Boolean/distance measurements, real driver cadence and range metadata, actual UI contexts, dynamic sensor hotplug, permission transitions, broader concurrent native errors/lifecycle behavior, additional metadata, remaining Windows sensor families and the complete OS/architecture/framework/package matrix remain required. Twenty-nine Windows collectors are implemented only to the documented field scope. A native function that never returns can still retain resources and block its worker; this is not process crash isolation or zero overhead.
