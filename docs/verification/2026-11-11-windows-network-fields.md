# Windows network routes and IPv6 MTU — 2026-11-11

Windows NetworkInterface now returns route lists and reads MTU for IPv6-only adapters. All 67 .NET checks pass in sandbox and normal-user runs, with zero build warnings/errors. These are additional fields in the existing collector; the Windows collector count remains thirteen and the full SDK remains incomplete.

## Route mapping

The adapter converts the selected native adapter GUID to a NET_LUID with [ConvertInterfaceGuidToLuid](https://learn.microsoft.com/en-us/windows/win32/api/netioapi/nf-netioapi-convertinterfaceguidtoluid), then reads the visible IPv4/IPv6 table with [GetIpForwardTable2](https://learn.microsoft.com/en-us/windows/win32/api/netioapi/nf-netioapi-getipforwardtable2). Only rows for that LUID enter the selected interface's Routes field. The LUID is read again afterward; an observed identity change leaves Routes null. It is an association for this read, not a permanent physical-device identifier.

| Snapshot value | Native mapping |
|---|---|
| NetworkRoute.Destination | MIB_IPFORWARD_ROW2.DestinationPrefix.Prefix, decoded by its IPv4/IPv6 address family. |
| NetworkRoute.PrefixLength | DestinationPrefix.PrefixLength; 0 is preserved for a default route. |
| NetworkRoute.Gateway | NextHop, including an IPv6 scope ID when present. An unspecified all-zero address means no gateway and becomes null, even if its native scope ID is nonzero. |
| Routes = empty list | A complete successful table has no matching rows, or the native API reports ERROR_NOT_FOUND for the requested table. |
| Routes = null | Native query/association failure, malformed table, unsupported selected-row address family, inconsistent address families, invalid prefix length or observed LUID change. Other readable NetworkInterface fields remain available. |

[MIB_IPFORWARD_ROW2](https://learn.microsoft.com/en-us/windows/win32/api/netioapi/ns-netioapi-mib_ipforward_row2) defines an unspecified next hop for on-link and loopback routes. Destination and next-hop addresses use the [SOCKADDR_INET](https://learn.microsoft.com/en-us/windows/win32/api/ws2ipdef/ns-ws2ipdef-sockaddr_inet) family-specific layout, preserving network-order address bytes and native IPv6 scope IDs. Metric, age, routing protocol and site-prefix length are not substituted for the public destination prefix. Native rows are not deduplicated based on the smaller public model.

Malformed selected rows invalidate the whole Routes field rather than producing an apparently complete partial list. Unrelated-interface rows are filtered by their LUID. The native copy is bounded to 8 MiB. An empty successful native table is handled without copying a first-row/padding region. All returned native table allocations are released by FreeMibTable in a finally block, including validation and cancellation paths. Get/watch do not modify routing state or send network probes.

Route lookup, native table reads, decoding and cleanup execute on the collection worker. Existing IP notifications enqueue a fresh route read alongside the other network fields; serial polling remains enabled. Changes between separate native calls can still race: the LUID check detects an observed association change but does not make inventory and route collection atomic.

## MTU mapping

The previous implementation consulted IPv4 properties only, so an IPv6-only adapter returned null despite having readable MTU data. It now keeps the existing IPv4 path when available and falls back to [IPv6InterfaceProperties.Mtu](https://learn.microsoft.com/en-us/dotnet/api/system.net.networkinformation.ipv6interfaceproperties.mtu?view=net-10.0) when IPv4 is absent or unreadable. Unsupported IPv4 properties do not discard a readable IPv6 value.

The field remains a byte count. Reported zero is preserved; negative values or failed reads become null. If both native property paths have readable values, the existing IPv4 path takes precedence; no minimum, maximum or packet-size inference is applied. This mapping adds no public field or configuration setting.

## Evidence

Four public-API cases extend the preceding 63-check suite:

* Controlled native table bytes exercise default IPv4 routes, on-link IPv4, scoped IPv6 gateways, IPv6 loopback and filtering of another adapter's routes. Successful empty tables remain empty. A native-change input refreshes the Routes field before a one-hour poll interval elapses. Native calls stay on one worker distinct from the caller.
* Controlled invalid tables, unknown address families, family mismatch, invalid prefixes, access denial and LUID changes leave only Routes null. A regression exposed the scoped unspecified IPv6 address being returned as a gateway; it is now null.
* Controlled BCL property inputs verify IPv6-only MTU 1280, IPv4 failure with IPv6 MTU 1500, dual-stack MTU 9000, preserved zero, invalid negative MTU and retention of known empty address/DNS/gateway lists.
* Actual Windows public discovery/get returns readable route lists for 84 of 84 interfaces on this host. The combined result contains 61 rows: 35 IPv4 and 26 IPv6. Loopback includes 127.0.0.0/8 and ::1/128 with null gateways.

The separate read-only C program [verify-windows-routes.c](../../tools/verify-windows-routes.c) uses native header types and C member access, without the SDK's byte offsets. Built with the installed MinGW GCC, it reports row size 104, table offset 8, destination offset 12, prefix-length offset 40 and next-hop offset 44. These match the interop mapping. Its independent native query also reports 61 rows, 35 IPv4 and 26 IPv6 in both sandbox and normal-user runs. Matching totals corroborate the native layout and coverage on this host; they are not a row-by-row comparison of every live value.

```powershell
gcc -std=c11 -Wall -Wextra -Werror tools/verify-windows-routes.c -o .tools/verify-windows-routes.exe -liphlpapi -lws2_32
./.tools/verify-windows-routes.exe
./tools/test-dotnet.ps1
```

Final logs are `.tools/windows-network-fields-final.log` and `.tools/windows-network-fields-normal-user.log`; both report 67/67 passed. Independent C results are `.tools/windows-route-abi.json` and `.tools/windows-route-independent-normal-user.json`. Reproduced failures are recorded in `.tools/windows-network-routes-red.log`, `.tools/windows-network-routes-null-red.log` and `.tools/windows-network-mtu-red.log`. No other language/browser suites were rerun for this Windows-only change.

## Remaining work

Physical IPv6-only adapters, actual route/address changes, multiple network compartments, high-volume route tables and the Windows architecture/version matrix remain unverified. Controlled OS inputs establish the corresponding mapping behavior but do not establish physical transition behavior. Native allocation release is enforced by the finally path; the independent C query is not a fault-injection test of every SDK allocation path.

The [network generation/notification checkpoint](2026-11-11-windows-network.md) still has outstanding rapid same-ID removal/reappearance, adapter-level PnP association, physical hotplug and notification-scale coverage. Other native enum/field availability cases, remaining Windows collectors, Apple/Swift, Flutter/RN and the full cross-platform acceptance matrix remain in scope.
