# Windows human-presence checkpoint — 2026-11-17

Environment: Windows 11 Home build 26300 x64, .NET SDK 10.0.403 and runtime 10.0.14. The complete `tools/test-dotnet.ps1` run passes **161/161**, with zero build warnings or errors. This adds five public scenarios to the [156-case hinge checkpoint](2026-11-17-windows-hinge.md). All 32 native sensor scenarios pass within the complete run. The full 46-entity and binding scope remains unchanged.

## Native mapping and access

HumanPresence uses HumanPresenceSensor.GetDeviceSelector, selected synchronous FromId, GetCurrentReading and ReadingChanged. The SDK reads Presence only: Present (1) becomes true, NotPresent (2) becomes false, and Unknown (0) or an unrecognized enum becomes null. An unreadable property also becomes null and can recover on the next event. Engagement, distance, logged-in status and idle time are not substitutes for presence. Equal native events remain visible.

The description contains Kind and available inventory Name. Other fields remain null; the Boolean entity has no invented distance range or sampling interval. Native events retain platform cadence even when an explicit sampling rate is configured. Discovery and metadata do not subscribe or collect measurements. Synchronous opening uses IHumanPresenceSensorStatics2, separately from the discovery factory, and executes on the collection worker.

Microsoft documents the [presence enum](https://learn.microsoft.com/en-us/uwp/api/windows.devices.sensors.humanpresence), [synchronous selected opening](https://learn.microsoft.com/en-us/uwp/api/windows.devices.sensors.humanpresencesensor.fromid) and [humanPresence device capability](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/app-capability-declarations#device-capabilities). A consuming packaged app must declare the capability as applicable to its packaging and security context. The SDK does not edit its manifest or invoke request-access, presence settings, screen or lock-control APIs. Permission/lifecycle observation and explicit UI coordination remain application-owned. Actual native consent behavior has not been verified on presence hardware.

Runtime availability is checked through native factory activation rather than a hard-coded OS build. A missing class or required interface produces UnsupportedEntity; it does not mean false or an empty measured value. Discovery may succeed while a required opening interface is unavailable. Native opening denial produces PermissionDenied; whole reading failure produces ReadFailed. No automatic permission request or retry is introduced.

## Reproduced failures and corrections

The first public presence scenario failed because target discovery was not implemented. Adding the native mapping and typed snapshot enabled discovery, passive metadata and get/watch.

A held-call cancellation test exposed internal linked tokens escaping through get/watch cancellation exceptions. Sensor get/watch now preserve the caller token when that caller cancels, while retaining asynchronous cleanup. The existing app-source cancellation assertion now checks the token as well as the exception type. The timer assertion in the new held-call fixture was synchronized to an actual host timer callback before cancellation; otherwise a fast cancellation could finish before the first timer tick.

A second failure delivered an old synchronous initial presence value after a newer absence event. Initial-sample publication now uses the same event-order guard for synchronous and asynchronous Windows sensor APIs. Native getters stay outside the short publication lock; duplicate subsequent events remain intact.

The wider native suite then reproduced continued axis reads after a caller deadline: cancellation traversed asynchronous links too late to stop a returning native getter from reading its remaining axes. Sensor registration now exposes a private cancellation handle before entering native code. Session teardown sets that native token directly before returning, while external token callbacks still execute asynchronously. The late-registration ownership handshake also handles teardown that wins before that handle is installed. Caller disposal still does not join native work or callbacks.

## Evidence

All controlled measurement cases enter through public DeviceAccess and native vtable fixtures based on Windows SDK 10.0.26100.0 declarations.

| Scenario | Observed behavior |
| --- | --- |
| Mapping and metadata | True/false/null, unknown signed enum values, passive descriptions, separate discovery/open factory interfaces, duplicate events and balanced listeners |
| Failures and app observers | Native denial and whole read failure are typed errors; property denial/failure yields null; event silence does not poll or time out; app inactivity releases the sensor and resumption reads fresh data; explicit blocking permission failure terminates collection and recovery permits a fresh get |
| Held native calls | Twelve combinations of open/current-reading/presence-property calls × get/watch × deadline/caller cancellation preserve host timer progress, caller termination and nonjoining disposal; late references/listeners are released and canceled readings do not query further properties |
| Initial ordering | A held initial true value is suppressed after a newer false event; later true events and duplicates remain visible |
| Runtime absence | Missing discovery/open interfaces return UnsupportedEntity; failed activation is not cached as a valid factory; a later available interface permits a new read |
| Existing regressions | All prior Windows sensor cases, blocked callback/cleanup cases, app sensor source cases and .NET state/observer contracts pass in the full run |
| Actual runtime | SDK and independent Windows PowerShell WinRT enumeration both report zero devices for all thirteen implemented sensor entities; ten cached factories and one MTA lifetime balance on the collection worker |

Ignored local evidence: `.tools/windows-human-presence-red.log`, `.tools/windows-human-presence-green.log`, `.tools/windows-human-presence-failures.log`, `.tools/windows-human-presence-held.log`, `.tools/windows-human-presence-held-green.log`, `.tools/windows-human-presence-order-{red,green}.log`, `.tools/windows-human-presence-existing-held{,-green}.log`, and `.tools/dotnet-windows-human-presence-full.log`. The first wider focused run was 31/32; its held-axis failure was investigated and corrected before the complete 161/161 run. `tools/verify-windows-sensors.ps1` independently reports API absence when the runtime type is missing. Other-language and browser suites were not rerun for this .NET change.

## Remaining work

Physical presence measurements, event cadence and native consent behavior; packaged/full-trust access combinations; actual OS permission changes; older Windows runtime availability; hotplug/multiple devices; additional metadata; remaining Windows sensors; and the full OS/architecture/framework/distribution matrix remain required. Thirty-one Windows entity collectors are implemented only to their documented field scope. A stuck synchronous native call can still occupy its worker and retain resources until it returns. This checkpoint does not establish process-crash isolation, zero overhead or complete platform support.
