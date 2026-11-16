# Windows native acceleration family checkpoint

Recorded on 2026-11-17 (Asia/Seoul), on Windows 11 Home x64 build 26300 with .NET SDK 10.0.403 and runtime 10.0.14. The complete `tools/test-dotnet.ps1` run passes **144/144** with zero build warnings or errors. The focused native sensor suite passes **15/15**. This extends the [140-case vector sensor checkpoint](2026-11-17-windows-vector-sensors.md). The complete 46-entity SDK, all fields/bindings and the full acceptance matrix remain the goal.

## Mappings and sign convention

Accelerometer, LinearAcceleration and Gravity now use Windows.Devices.Sensors.Accelerometer through distinct Standard, Linear and Gravity selectors. The native factory and enumeration runtime are cached together, while target identity and observation sources retain the entity kind. Descriptions supply kind, available device name and minimum report interval without taking a reading or subscribing.

All three families return one Vector3 from a single native reading. Components in G are multiplied by **-9.80665** to match the common Android/Generic Sensor acceleration convention in m/s². In particular, Windows' stationary face-up Z of -1 G becomes common Z of +9.80665 m/s²; a zero-G reading stays zero. This changes the reported acceleration sign convention, not the device reference axes or display orientation. The same conversion applies to the three reading kinds exposed by the native Accelerometer class; physical cross-platform comparison remains pending.

The Standard native measurement includes the gravity contribution. Linear selects the native measurement without that contribution; Gravity selects the native gravity contribution. No SDK filter, cross-sensor subtraction or fabricated default replaces an unavailable kind. Native current readings and ReadingChanged events retain the existing initial-sample, repeated-value, immutable configuration and cleanup contracts.

The sign choice follows the existing Android collector and Microsoft's documented Windows face-up behavior, corroborated by Chromium's Windows-to-Generic-Sensor accelerometer conversion. The references below provide the source contracts; controlled numeric cases verify this implementation, not physical device orientation.

## Reproduced failures and implementation

The first Standard and Linear/Gravity public-API cases failed at discovery because those Windows collectors were absent. Adding their parameterized native selector, factory/event ABI and double-component decoding made all three paths available.

A subsequent test returned a native object whose ReadingType differed from the selected entity. The initial implementation accepted it and could mislabel a measurement. Each acceleration open now queries IAccelerometer4.ReadingType before metadata or measurement access. A different or unknown native kind raises EntityRemoved and permanently retires the old handle. After native recovery, discovery supplies a fresh handle. The type interface, async result and sensor references are released on both success and rejection.

Partial component failures and held-call cancellation tests now also cover all three acceleration kinds. One unreadable component makes the whole Value null; the next complete sample recovers. If a native X call returns after cancellation, Y/Z are not queried. The public read deadline, host timer progress and nonjoining context disposal complete before that held native call returns.

## Observer integration

The native acceleration lifecycle test verifies that observed inactivity releases the listener and restores its original report interval. An inactive watch waits beyond its read timeout without restarting collection. Reactivation opens a fresh session, reads a fresh sample and retains the original configured sampling request.

Permission status and a failure that blocks collection remain separate inputs, as documented in the .NET package. The application's permission observer publishes Denied plus its owned PermissionDenied failure when the entire measurement is inaccessible. This terminates the native stream and releases its listener; a subsequent read fails before taking a native measurement. Publishing Granted and clearing that failure permits a fresh request. No permission coordinator is invoked by these ordinary reads or state changes. The first integration test incorrectly assumed status alone blocked collection and was stopped; it was corrected to exercise the existing two-input contract, without changing production permission semantics.

## Evidence and limits

| Scenario | Evidence |
| --- | --- |
| Standard native ABI | Parameterized Standard selector, passive description, native double values, literal signed m/s² expectations, stationary face-up and zero-G samples, duplicate delivery and interval/reference cleanup |
| Linear and Gravity native ABI | Correct distinct selector arguments and descriptions; distinct stationary measurements; native events and unchanged driver-default intervals |
| Native type mismatch | All three families reject another known kind before subscribing/reading; old handles remain retired; fresh discovery recovers; unknown kind on description also retires the target |
| Activity and blocking permission observation | Native detach/reacquire, suspended timeout, retained requested cadence, explicit failure/recovery, no implicit permission coordination and balanced native listeners |
| Partial values and held reads | Existing vector tests extended to every acceleration kind; null recovery and caller deadlines remain valid through the native ABI |
| Actual Windows inventory | All seven sensor kinds enumerate successfully; six cached factories and one MTA initialization/shutdown balance on the collection worker |

Actual SDK and independent PowerShell WinRT discovery both report **zero devices** for Illuminance, Pressure, Gyroscope, Magnetometer, Accelerometer, LinearAcceleration and Gravity. Counts are logged without device identifiers or measurements. These checks establish real selector/async-enumeration/runtime integration. Numeric measurements and event delivery use unmanaged Windows SDK ABI fixtures.

Physical measurements, cross-platform sign/orientation comparisons, native driver cadence, actual sensor hotplug, real permission transitions/UI synchronization contexts, more concurrent native failures, additional metadata, remaining Windows sensors and the complete architecture/OS/framework/package matrix remain required. A synchronous native call that never returns can still retain resources and block its worker; this is not process crash isolation or a zero-overhead guarantee.

Local ignored logs include `.tools/windows-acceleration-{red,green}.log`, `.tools/windows-acceleration-families-{red,green}.log`, `.tools/windows-acceleration-type-{red,green}.log`, `.tools/windows-acceleration-focused.log` and `.tools/dotnet-windows-acceleration-full.log`. Other-language and browser suites were not rerun for these Windows/.NET changes.

## Primary references

The Windows SDK 10.0.26100.0 WinRT headers define the selector signature, ReadingType interface, reading components and event IIDs. Microsoft documents [the three reading kinds](https://learn.microsoft.com/en-us/uwp/api/windows.devices.sensors.accelerometerreadingtype), [the parameterized selector](https://learn.microsoft.com/en-us/uwp/api/windows.devices.sensors.accelerometer.getdeviceselector), and [Windows G-force/face-up behavior](https://learn.microsoft.com/en-us/windows/apps/develop/devices-sensors/sensors). Android's [SensorEvent contract](https://developer.android.com/reference/android/hardware/SensorEvent) defines the common stationary positive-Z value and acceleration/gravity/linear relationship. Chromium's [WinRT sensor reader](https://github.com/chromium/chromium/blob/main/services/device/generic_sensor/platform_sensor_reader_winrt.cc) corroborates negating Windows G components when converting to Generic Sensor acceleration units.
