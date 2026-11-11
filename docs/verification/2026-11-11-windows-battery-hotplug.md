# Windows battery interface lifetime verification — 2026-11-11

Windows battery discovery now starts context-owned device-interface notifications before its first inventory. Removal history remains active between get calls and after individual watches close. The common .NET context now also disposes collector-owned resources on its background worker. All 38 .NET checks pass; this is another implementation checkpoint, not completion of the full SDK.

## Handle and stream behavior

The adapter registers once for the battery device-interface class before enumerating existing interfaces. It retains the registration until DeviceAccess closes, even when the inventory is empty. This closes the gap where a device could disappear and return between two reads with the same path and battery tag. Registering before enumeration follows the ordering described by [CM_Register_Notification](https://learn.microsoft.com/en-us/windows/win32/api/cfgmgr32/nf-cfgmgr32-cm_register_notification); registration itself does not enumerate existing devices.

Each interface removal advances a context-local version for that path. Paths are matched case-insensitively. Target generations include the version as well as the native tag. Existing handles keep returning EntityRemoved after a same-path/same-tag arrival; stable rediscovery provides a fresh handle. Arrival alone does not invalidate a healthy target, and one pack's removal does not invalidate unrelated packs.

A positive removal also marks the interface absent until a native arrival clears that state. A regression reproduced stale enumeration/tag data creating a new phantom target after removal; retaining the absence marker now prevents that. A later successful query alone does not erase the observed removal.

The callback only copies a bounded native path, records removal history and signals matching streams. It does not query or open a battery, enumerate devices, normalize snapshots or unregister its notification. An active watch receives removal without waiting for its next poll. Get checks the target generation before and after collection; a result spanning removal is discarded. Inventory queries spanning removal are excluded instead of becoming a fresh handle based on stale tag data.

Native callback decoding checks action, filter type, reserved header, class GUID, payload length and a nonempty terminated UTF-16 path. Unrelated actions/classes are ignored. Malformed notifications fail affected battery operations because identity continuity can no longer be trusted. That failure persists for the context; the SDK does not silently retry registration or claim that the lost interval was observed. A new DeviceAccess can start a new observation context. Unsupported registration (CONFIGRET 0x34) retains polling behavior; access denied (0x33) becomes PermissionDenied and other registration errors become ReadFailed.

The filter layout was checked against the installed Windows SDK 10.0.26100.0 header and Microsoft's [CM_NOTIFY_FILTER](https://learn.microsoft.com/en-us/windows/win32/api/cfgmgr32/ns-cfgmgr32-cm_notify_filter) definition. Payload decoding follows [CM_NOTIFY_EVENT_DATA](https://learn.microsoft.com/en-us/windows/win32/api/cfgmgr32/ns-cfgmgr32-cm_notify_event_data) and the native [interface arrival/removal actions](https://learn.microsoft.com/en-us/windows/win32/api/cfgmgr32/ne-cfgmgr32-cm_notify_action).

## Ownership and execution

IDeviceCollector now extends IDisposable with a default no-op implementation. DeviceAccess owns its collector and invokes its cleanup once, after stopping tracked subscriptions. Cleanup stays on the collection worker, including when a context is closed before its first read. Immutable configuration views share this ownership; closing one closes the shared context.

Windows uses CM_Register_Notification and CM_Unregister_Notification directly, without creating a window or UI message loop. A single rooted callback and never-reused numeric contexts prevent callbacks from dereferencing a freed managed context. Detaching a registration makes late callbacks inert. Unregistration runs outside the callback, as required by [CM_Unregister_Notification](https://learn.microsoft.com/en-us/windows/win32/api/cfgmgr32/nf-cfgmgr32-cm_unregister_notification), which waits for pending callbacks.

Callback state updates use a short lock; native I/O and unregistration occur outside it. Main-thread screen and permission access remain app-owned observer inputs. The SDK does not change device configuration, eject devices, veto device removal or issue battery write IOCTLs. Native reads remain synchronous on the background lane: deadlines protect the caller, but a permanently blocked native call can still delay worker-owned resource release. This is not process-crash isolation or zero resource cost.

## Evidence

The build succeeds with zero warnings/errors. `tools/test-dotnet.ps1` and the same built verification executable in a normal-user Windows process both pass 38/38 checks. Six checks were added since the power-event checkpoint:

* Collector cleanup runs once on the worker for both unused and previously read contexts; configuration views share the same closure.
* A selected pack's removal ends its watch, preserves unrelated packs and permanently rejects the old handle despite immediate path/tag reuse. Closing a watch retains context observation.
* The real Configuration Manager API registers before battery discovery and successfully unregisters when the context closes. The native inventory is still empty on this host.
* Controlled native binary callback payloads exercise production decoding, case-insensitive paths, get-only handles, unrelated actions/classes, malformed payload failures and late callbacks after closure.
* Removal during a held battery status call invalidates the returned result. Removal during tag discovery excludes that unstable generation. Stale inventory data cannot create another target while the interface remains observed absent; a native arrival and stable inventory recover with a fresh handle.
* Registration errors retain typed failures without retry or device acquisition. An unavailable notification API retains working polling.

Tests invoke public DeviceAccess get/watch/list/capability/disposal APIs. Controlled fixtures replace only battery device transport or the raw Configuration Manager API. The real registration probe forwards all native operations and records registration/unregistration results; it does not fabricate native arrivals or removals.

Logs: `.tools/collector-lifetime-red.log`, `.tools/collector-lifetime-green.log`, `.tools/windows-battery-hotplug-red.log`, `.tools/windows-cm-native-red.log`, `.tools/windows-cm-payload.log`, `.tools/windows-cm-races.log`, `.tools/windows-cm-stale-inventory-red.log`, `.tools/windows-cm-final.log` and `.tools/windows-cm-normal-user.log`. Regressions failed on missing collector cleanup, missing interface registration or stale inventory repopulation; final runs pass. TypeScript, browser and Kotlin/Android suites were not rerun for .NET/Windows-only changes.

## Remaining work

No physical battery is installed on this host. Actual removal/reinsertion callback delivery, laptop/UPS/multiple-pack transitions and additional Windows versions/architectures remain unverified. A battery pack can change inside a still-present interface: tag queries detect observed changes, and the subsequent [individual status checkpoint](2026-11-11-windows-battery-status.md) adds driver waits that retain removal evidence even when path/tag values later recur. Physical replacement and notification delivery remain unverified. The subsequent [aggregate checkpoint](2026-11-11-windows-aggregate-battery.md) adds default OS aggregate access and WinRT report events. Unavailable fields and remaining Windows collectors are pending. Volume hotplug and network adapter generation tracking remain separate outstanding work. Swift/Apple, Flutter/RN and the full support matrix are also still incomplete.
