# C# Windows network fields and cross-binding inventory — 2026-11-18

The Windows C# collector now retains MTU values for interfaces without enabled IP protocols, unsigned MTU values, scoped IPv6 DNS addresses and additional known interface types. Public Entity/Snapshot APIs and the existing worker and handle lifetimes are unchanged. The full [implementation objective](../implementation-status.md) remains incomplete.

The subsequent [notification ownership checkpoint](2026-11-18-dotnet-network-notifications.md) retains failed native cleanup handles and preserves the original registration error. Its 215/215 aggregate includes the field evidence below plus fourteen additional C notification cases.

## Findings and implementation

The first inventory test passed before any production change: .NET 10 already returned all **84 NDIS interfaces** on this host. The earlier nine-interface PowerShell reference uses a different .NET runtime and is a subset, not the inventory of the C# SDK. The [.NET implementation](https://github.com/dotnet/runtime/blob/v10.0.0/src/libraries/System.Net.NetworkInformation/src/System/Net/NetworkInformation/SystemNetworkInterface.cs) includes all interfaces. The SDK retains that enumerator.

The independent Windows SDK C reference then reproduced missing MTU values: C# returned null for the native unsigned value 4,294,967,295 and for 75 interfaces whose BCL IP properties did not expose MTU. The new supplementary [GetAdaptersAddresses](https://learn.microsoft.com/en-us/windows/win32/api/iphlpapi/nf-iphlpapi-getadaptersaddresses) query reads the selected adapter's native MTU. It uses the same source as Dart. The BCL fallback preserves the unsigned bits of its signed int result, matching the [Windows .NET implementation](https://github.com/dotnet/runtime/blob/v10.0.0/src/libraries/System.Net.NetworkInformation/src/System/Net/NetworkInformation/SystemIPv4InterfaceProperties.cs). Zero and uint.MaxValue remain values.

Normal-user testing additionally reproduced scope loss in eight interfaces' site-local IPv6 DNS lists. The C reference returned three scoped addresses per affected interface; the previous C# values contained the same number of addresses without their scope IDs. The supplementary native decoder now preserves IPv4 and IPv6 DNS addresses, including the full numeric IPv6 scope. An empty native DNS list remains empty. A failed or malformed native DNS read remains null; it cannot fall back to the scope-losing BCL conversion. MTU and other readable fields survive DNS-only failure.

Known native types 26, 243, 244 and 209 now map to Ethernet, Cellular, Cellular and Bridge respectively. Their values follow the [IANA interface-type registry](https://www.iana.org/assignments/ianaiftype-mib/ianaiftype-mib); Windows SDK headers also define the Ethernet and WWAN constants. Unknown types still become null. No public enum member was added.

Native supplementary buffers start at 15 KiB, grow at most three attempts and remain bounded to 8 MiB. The decoder checks node lengths, pointer bounds, cycles and duplicate adapter identities before accepting data. DNS chains are checked independently, with cancellation checks during traversal. Query, copying, decoding and allocation release run on the collection worker. No OS pointer escapes into a public snapshot. This decoder is limited to 64-bit processes; x64 is verified here and ARM64 remains unverified.

## Verification

| Gate | Evidence |
|---|---|
| `./tools/test-dotnet.ps1`, ordinary user | Build with zero warnings/errors; **199/199 checks pass** on .NET runtime 10.0.14, Windows x64. |
| Independent actual native comparison | **84 interfaces, all nine fields and 61 routes** agree with Windows SDK C structures. Repeated discovery retains handles. |
| Owned-child native boundary cases, included above | **28/28** cases covering native MTU values/growth/failures, bounded malformed responses, DNS scope/empty/invalid data, fallback rules, watch recovery and held calls. |
| Held native calls, included above | **7/7** get/watch deadline, cancellation and disposal cases complete publicly before the C function returns. Caller timers progress while the native worker remains blocked. |
| Dart `native_windows_network_faults.dart`, ordinary user | **21/21 existing scenarios** pass with the extended shared C fixture, including its four held-call cases and zero remaining fixture query buffers. |
| Dart `native_windows_network.dart`, ordinary user | Fresh actual reference comparison passes for **84 interfaces**, with three polling snapshots and caller heartbeat progress. |

`tools/test-dotnet.ps1` now builds the independent Windows probe and fixtures before its Windows tests. Reproducing these tests requires Visual Studio 2022 C++ tools and the Windows SDK. Production SDK reads do not build or launch these helpers, and the .NET consumer package has no new native asset dependency.

The actual comparison establishes current-host field and inventory agreement with the native reference used by Dart. It does not establish synchronized atomic snapshots across bindings or physical transition behavior. The controlled native cases load the fixture only in retained child processes, with a 15-second parent deadline and six-second native hold failsafe. Fixture tests do not change network configuration.

## Recorded failures and limits

Local red evidence is retained in `.tools/dotnet-network-fields-red.log`, `dotnet-network-mtu-unsigned-red.log`, `dotnet-network-types-red.log`, `dotnet-network-dns-red.log`, `dotnet-network-dns-diagnostic.log` and `dotnet-network-dns-fallback-red.log`.

An earlier restricted aggregate returned **189/194**, failing five existing publisher-ID, Wi-Fi and cellular native tests. Its log is `.tools/dotnet-network-final.log`. The first ordinary-user aggregate returned **193/194**, exposing the DNS scope discrepancy while those five existing tests passed. The final ordinary-user result is **199/199** in `.tools/dotnet-network-normal.log`; the tests were not weakened to hide either result.

The source/artifact audit is `.tools/evidence/dotnet-windows-network-checkpoint.json`. It checks 107 code/build/schema inputs against the pre-gate hashes and records built assembly, fixture and log hashes. Dart follow-up logs are `.tools/dart-network-after-dotnet-fixture.log` and `.tools/dart-network-after-dotnet-reference.log`. These local artifacts are excluded from Git.

Physical interface/address/DNS/route transitions, rapid adapter reuse, additional native failure and callback-cleanup races, other routing compartments/VPN configurations, other address classes, 32-bit/ARM64 evidence and separately installed .NET consumers remain pending. Dart compiled/Flutter aggregate gates and the separate C# power-native gate were not rerun for this change. Remaining entities, languages, platforms and the full version/physical/consumer acceptance matrix are still required. This checkpoint does not claim process crash isolation or zero shared-process resource use.
