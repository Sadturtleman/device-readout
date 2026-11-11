# Windows network generations and notifications — 2026-11-11

Windows NetworkInterface handles now survive ordinary updates and permanently retire after an inventory observes their removal. Native interface/address/route notifications supplement serial polling. All 63 .NET checks pass in sandbox and normal-user runs. The Windows collector count remains thirteen; complete network field, hotplug and platform coverage is still pending.

## Corrected target lifetime

The preceding collector exposed each native adapter ID directly as the target. A public list/get regression reproduced the defect: after observing an empty inventory and then the same native ID again, rediscovery returned the original handle. That allowed an old target to refer to a later resource.

Discovery now uses the context-local ResourceCatalog. A successful inventory creates generations for new native IDs and permanently retires absent IDs. A later occurrence of the same ID receives a new handle. Get also refreshes inventory, so removal found by a read has the same lasting effect. The native ID comparison is case-insensitive. Failed or malformed inventories do not overwrite the last successful inventory.

Observed removal terminates every active watch for that generation, including when a separate list/get operation discovers it before the next poll. Capabilities for an already retired handle are false. Current remains null because this collection has no unambiguous default interface.

Inventory still uses [.NET NetworkInterface.GetAllNetworkInterfaces](https://learn.microsoft.com/en-us/dotnet/api/system.net.networkinformation.networkinterface.getallnetworkinterfaces?view=net-10.0). A successful empty result is an empty inventory; access denial becomes PermissionDenied, and other native enumeration failures become ReadFailed. Duplicate or empty native IDs are rejected without fabricating removals.

## Native observation and execution

The first network inventory starts one context-owned registration for each native source, before reading adapters:

| Source | Scope and behavior |
|---|---|
| [NotifyIpInterfaceChange](https://learn.microsoft.com/en-us/windows/win32/api/netioapi/nf-netioapi-notifyipinterfacechange) | IPv4 and IPv6 interface-table changes; schedules a fresh snapshot for active network watches. |
| [NotifyUnicastIpAddressChange](https://learn.microsoft.com/en-us/windows/win32/api/netioapi/nf-netioapi-notifyunicastipaddresschange) | IPv4 and IPv6 unicast-address changes; schedules the same worker read path. |
| [NotifyRouteChange2](https://learn.microsoft.com/en-us/windows/win32/api/netioapi/nf-netioapi-notifyroutechange2) | IPv4 and IPv6 route changes; refreshes exposed network properties such as gateways. Routes was added by the subsequent field checkpoint linked below. |

Registration acknowledgements are ignored as state events. Actual change notifications enqueue reads, including equal-value updates. Partial, OS-owned callback rows are neither retained nor interpreted as complete snapshots. A deletion of one protocol's MIB instance is not proof that the whole adapter was removed; only a successful adapter inventory establishes absence in this implementation.

Callbacks perform no native follow-up query, UI lookup or permission request. Collection, property mapping, normalization and registration/cancellation run on the dedicated collection worker. Native callbacks only notify the stream input. Construction remains inert. The SDK does not change addresses, routes, DNS, adapter state or any application networking settings, and sends no probe traffic.

One set of native registrations is shared by watches and persists between reads and after individual streams stop, until DeviceAccess closes. Closing a stream removes its SDK listener. Context closure detaches dispatch state before calling [CancelMibChangeNotify2](https://learn.microsoft.com/en-us/windows/win32/api/netioapi/nf-netioapi-cancelmibchangenotify2) on the worker, without holding callback locks. It never unregisters from the native callback that the cancellation API waits for. Late callbacks cannot revive disposed dispatch state.

Serial polling remains enabled because these sources do not cover every exposed property. ERROR_NOT_SUPPORTED from a registration leaves polling available. Other registration failures preserve their typed error, roll back previously successful registrations and are not silently retried. Malformed native callbacks fail existing streams and subsequent network reads; context disposal still releases all registrations.

## Verification

Six public-API cases were added to the preceding 57-check suite. OS seams supply controlled adapters or native callback arguments; SDK reads, discovery, capabilities and streams remain real.

| Case | Evidence |
|---|---|
| Discovery generations | Empty inventory retires the old target. Same-ID reappearance creates a distinct readable target; old get remains EntityRemoved. |
| Failed inventory and read-time removal | Access-denied and duplicate-ID inventories preserve the earlier generation. Removal found by get stays permanent, including after rediscovery. |
| Shared worker observation | Two watches with one-hour polling intervals receive a native-triggered state change and its equal duplicate. Separate discovery of absence terminates both. Context retains one observation until closure; reads, registration and cleanup execute off the caller on one worker. |
| IP notification contract | Three native source registrations precede inventory. Initial acknowledgements add no snapshot. A protocol deletion does not remove an adapter still present in inventory. Address/route callbacks produce snapshots, and every registration is released. |
| Failure and fallback | Failure of the second native registration releases the first and remains PermissionDenied without retry. Unsupported notification sources retain polling. A malformed callback stops the stream, invalidates subsequent network operations and still permits all native cleanup. |
| Actual Windows integration | Public discovery/get read 84 interfaces on this x64 host. All three actual native initial acknowledgements arrive. A native watch yields its first state, and all three CancelMibChangeNotify2 calls succeed on the collection worker after context closure. |

`tools/test-dotnet.ps1` reports zero warnings/errors and 63/63 passed in `.tools/windows-network-native-contract.log`. Running the built test executable in a normal-user process also reports 63/63 passed in `.tools/windows-network-normal-user.log`. The failing regressions are recorded in `.tools/windows-network-generation-red.log`, `.tools/windows-network-inventory-red.log`, `.tools/windows-network-events-red.log` and `.tools/windows-network-native-events-red.log`.

The actual native check proves registration, acknowledgement, reads and cancellation on this host. Actual address/route mutation and physical adapter removal were not performed. Controlled callbacks and inventories establish the corresponding SDK behavior but are not physical hotplug evidence. Other language and browser suites were not rerun for this Windows-only change.

## Remaining work

* A remove-and-reappear cycle completed between inventories can still be missed, especially with get-only access. Native protocol notifications are wake-up signals and do not yet provide a verified adapter-level PnP removal history. Stable native IDs or NET_LUID values alone are not a permanent generation guarantee. A reliable PnP-to-adapter association and physical/virtual adapter hotplug fixtures remain required.
* Callback snapshots reflect the subsequent worker query, not a guaranteed capture of every transient native property. The partial callback rows do not provide a complete NetworkInterfaceSnapshot. Each accepted notification is delivered without value deduplication, subject to the existing bounded-queue failure contract.
* Notifications currently wake all active network-interface watches. Target filtering and the full notification/overload matrix remain to be verified; no full-scale latency claim is made.
* At this checkpoint Routes was null and MTU used IPv4 properties only. The subsequent [route and IPv6 MTU checkpoint](2026-11-11-windows-network-fields.md) implements those mappings and extends verification to 67 checks. Additional native enum/field availability cases still need implementation and tests.
* Physical hotplug, rapid same-ID replacement, actual protocol-only removal, real native state transitions, ARM64/WOW64 and the Windows version matrix remain unverified. Shared-worker native calls still cannot be forcibly interrupted; caller deadlines remain independent, but a stuck query can delay subsequent worker operations.
* Remaining Windows collectors, Apple/Swift, Flutter/RN and every platform acceptance requirement remain in scope. This checkpoint does not complete the SDK.
