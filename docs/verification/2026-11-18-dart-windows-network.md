# Dart and Flutter Windows network interfaces — 2026-11-18

The later [native-notification follow-up](2026-11-18-dart-windows-network-events.md) extends this checkpoint's polling implementation and supersedes its pending-notification item. The results below describe the earlier field-collection artifacts.

`NetworkInterface` is the twelfth standalone Windows collector kind. Its nine fields now come from native adapter and route queries through the collection isolate. Typed discovery, get/watch, explicit current selection and observed-removal lifetimes use the existing DeviceAccess runtime. This is progress toward the complete [implementation scope](../implementation-status.md), which remains unfinished.

```dart
final access = DeviceAccess.native();
final interfaces = await access.networkInterfaces.list();
if (interfaces.isNotEmpty) {
  final snapshot = await access.get(interfaces.first);
  final samples = access
      .withPollInterval(const Duration(milliseconds: 500))
      .watch(interfaces.first);
}
```

## Inventory and field meaning

Discovery uses [GetAdaptersAddresses](https://learn.microsoft.com/en-us/windows/win32/api/iphlpapi/nf-iphlpapi-getadaptersaddresses) with AF_UNSPEC, unicast/DNS collection, gateways and INCLUDE_ALL_INTERFACES. This exposes the NDIS inventory, including entries beyond the IP interfaces returned by .NET Framework's NetworkInterface API. The current host has **84 NDIS entries** and **9 .NET IP interfaces**; the latter are independently cross-checked as a subset. No adapter is selected from the worker thread or default route: `current()` stays null until the app publishes a selection.

AdapterName plus native LUID identifies a target inside the collection context. SDK handles remain opaque and context-owned; they are not persistent device identifiers. A confirmed disappearance retires the handle generation, and reappearance does not revive the old handle. Failed inventory queries preserve known handles. A fresh inventory after route collection rejects targets removed or replaced during that read; it does not make the separate OS queries atomic.

| Field | Windows mapping |
|---|---|
| `name` | Adapter FriendlyName, bounded UTF-16 decoding. |
| `interfaceType` | Known native IfType codes, without adapter-name heuristics; unmapped types are null. |
| `operationalState` | Known native OperStatus values; native Unknown is null. |
| `hardwareAddress` | The exposed physical-address bytes, uppercase colon notation; absent or invalid length is null. |
| `ipAddresses` | Unicast IPv4/IPv6 addresses and OnLinkPrefixLength; unknown prefix length is null while the address remains available. |
| `dnsServers` | Native per-adapter DNS address list. |
| `gateways` | Native per-adapter gateway address list. |
| `routes` | IPv4/IPv6 route rows matching the adapter LUID: destination, prefix and next hop. All-zero next hop becomes a null gateway for an on-link route. |
| `mtuBytes` | The native unsigned 32-bit MTU, represented as BigInt. Zero and UINT32_MAX remain valid numeric data. |

IPv6 addresses retain a nonzero numeric scope suffix. A successful empty address/route list remains empty; malformed pointers, linked-list cycles or an unknown address family invalidate the affected list rather than silently dropping an item. Optional-field failures preserve independent fields. Whole inventory access denial becomes PermissionDenied, invalid/native-failed inventory becomes ReadFailed, and confirmed missing targets become EntityRemoved.

Routes come from [GetIpForwardTable2](https://learn.microsoft.com/en-us/windows/win32/api/netioapi/nf-netioapi-getipforwardtable2) with AF_UNSPEC. [MIB_IPFORWARD_ROW2](https://learn.microsoft.com/en-us/windows/win32/api/netioapi/ns-netioapi-mib_ipforward_row2) supplies the LUID, destination prefix and next hop. The tested 64-bit layout includes table/row padding; the independent reference and fixtures compile against Windows SDK structure definitions rather than reproducing Dart offsets. A failed or malformed route table makes only `routes` null.

## Execution and observation

DLL binding, queries, native allocations, pointer traversal, string/address conversion, polling and cleanup run on the collection isolate. Reads neither change routes/adapter settings nor spawn processes, request permissions or query UI state. PowerShell and native reference libraries are used only by verification tools. Public get/watch deadlines do not join a held native call; resources are released when the actual native work completes.

Caller buffers and route tables are bounded to 8 MiB. Adapter sizing growth has a three-attempt limit. Every adapter-owned pointer is checked against its query buffer, and linked traversals detect cycles. Native route tables are freed through FreeMibTable, including the fixture's failed-call-with-output case.

State watch currently uses the shared serial polling path: immediate first read, default one-second interval, immutable interval configuration and duplicate-value delivery with one completion timestamp per snapshot. **Native network-change notifications are not connected yet.** Rapid changes between observations can therefore remain unseen. The current implementation is restricted to a 64-bit Windows process; x64 is verified, ARM64 execution is not. Thirty-two-bit collection reports UnsupportedEntity.

## Red cases and independent verification

The public test first failed with UnsupportedEntity (`.tools/network-red.log`). After native inventory and address fields were added, a route comparison failed because routes were still null (`.tools/network-routes-red.log`); the completed collector passes the native comparison.

Two reference issues were corrected before relying on those comparisons: PowerShell UTF-8 output needed explicit decoding, and .NET Framework's signed MTU property needed unsigned reinterpretation to compare the native UINT32_MAX value. All NDIS entries are checked against the Windows SDK reference, and the nine IP entries are additionally checked through .NET. The reference process has a retained handle and bounded lifetime.

The first aggregate run exceeded the test harness's generic 12-second case guard. A separate measurement completed all 84 targets in 12.517 seconds, with 354 ms spent obtaining references. This full-inventory case now has a 45-second harness guard. **Each SDK read still uses the unchanged default five-second deadline**, and the held-call cases still demand a 200 ms public timeout. Final JIT and bundled inventory checks took approximately 15 seconds each on this host. No universal collection-latency claim follows from these measurements.

| Controlled native coverage | Cases per mode | Verified behavior |
|---|---:|---|
| Known fields, unknown enums/prefix/family, malformed Unicode/pointers/lists, failed/malformed routes, buffer growth, unsigned MTU and scoped IPv6 | 12 | Nullable fields preserve independent values; valid numbers, addresses and on-link routes retain their meaning. |
| Failed/denied/cyclic/oversized inventory responses | 4 | Typed whole-query errors preserve known target lifetimes and recover. |
| Removal and reappearance | 1 | Existing watch fails with EntityRemoved; replacement gets a new handle and the old handle stays retired. |
| Held adapter/route query during get and initial watch | 4 | Public timeout precedes native return, caller timers progress on a different thread, reads recover and buffers return to zero. |

All **21 scenarios run in both JIT and CLI-bundle mode**, in retained child processes with an eight-second outer deadline and a six-second native hold failsafe. Their 42 reports include eight held-call reports. These are controlled native-adapter responses, not physical network changes.

## Completed gates

| Command | Result |
|---|---|
| `./tools/test-dart.ps1` | Clean analysis; **157/157 JIT** and **157/157 CLI-bundle** checks; negative browser boundary passed. |
| `./tools/test-flutter-windows.ps1` | **18/18 checkout Windows application scenarios**; ordinary entrypoint rebuilt. |
| `./tools/build-flutter-packages.ps1 -Platform Windows` | Separate hosted-Pub consumer downloaded new archives, analyzed and built. |
| `./tools/test-flutter-windows.ps1 -ExampleRoot .tools/flutter-windows-installed` | **18/18 installed Windows application scenarios**; ordinary entrypoint rebuilt. |
| `./tools/test-flutter.ps1` | Clean analysis and **27/27 framework checks**. |

Both actual Windows apps compare all nine fields for 84 interfaces and 61 routes, then collect three polling snapshots while the UI-isolate timer progresses. The report stores counts rather than actual network identifiers or addresses. Production examples contain the normal native asset, without the reference or fixture DLLs.

The local source/artifact audit matches 34 core-package runtime files and 12 Flutter-package runtime files against the installed consumer, verifies both downloaded archive hashes and the copied network verification entrypoints, and checks 365 local documentation links. Its evidence is `.tools/evidence/dart-windows-network-checkpoint.json`; it does not imply verification of untouched platforms.

Local final logs are `.tools/dart-network-final.log`, `flutter-network-checkout.log`, `flutter-network-packages.log`, `flutter-network-installed.log` and `flutter-network-framework.log`. Application reports are `flutter-windows-viewport-27b2716393b241798efbd1d484172924.json` and `flutter-windows-viewport-659891bb6df749b2b4784c6350d3b087.json`. Raw logs/build artifacts remain excluded from Git; no package release or additional GitHub upload is performed by this checkpoint.

Native notifications, physical connect/disconnect and configuration changes, additional buffer/race/failure combinations, routing compartments/VPN configurations, ARM64 and the complete version/platform/consumer matrix remain pending. Discovery-scope parity with the existing C# binding also needs reconciliation and verification. Android/browser apps, C#, Kotlin and Swift were not rerun for this Dart Windows collector. Remaining entities and bindings continue to be part of the full implementation objective.
