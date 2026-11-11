# Windows Wi-Fi signal strength — 2026-11-11

WifiConnection now also supplies RssiDbm through get/watch. The normal-user .NET suite passes 94/94 checks with zero build warnings/errors. Windows Wi-Fi has three of its seven fields implemented: Ssid, Security and RssiDbm. Bssid, FrequencyHz and both current-link rates remain pending; the overall SDK goal remains incomplete.

```csharp
using var access = WindowsDeviceAccess.Create();
var target = await access.Current(Entities.WifiConnection, cancellationToken);
if (target is not null) {
    WifiConnectionSnapshot snapshot = await access.Get(target, cancellationToken);
    double? rssiDbm = snapshot.RssiDbm;
}
```

## Collection and field semantics

The selected WinRT profile supplies the adapter GUID. Each selected read opens a version-2 Native Wi-Fi client and calls [WlanQueryInterface](https://learn.microsoft.com/en-us/windows/win32/api/wlanapi/nf-wlanapi-wlanqueryinterface) with [wlan_intf_opcode_rssi](https://learn.microsoft.com/en-us/windows/win32/api/wlanapi/ne-wlanapi-wlan_intf_opcode), then frees its output and closes the client. Discovery/current selection do not query signal strength. The result is the native interface's signed RSSI value in dBm; the SDK neither clamps it to a display-quality range nor converts signal bars/percentages into this field. Successful zero is retained.

The native result must be a nonnull four-byte LONG. Malformed lengths, absent buffers, unsupported service/API/client version and native access failures leave RssiDbm null while readable SSID/security remain available. RSSI can independently succeed when those two fields fail. If every field read actually fails, the whole read fails with the existing typed error policy, preferring PermissionDenied when present. A successfully absent WinRT field source remains a successful null field, as in the preceding checkpoint.

For this query, ERROR_NOT_FOUND and ERROR_INVALID_STATE indicate that the selected interface/connection is no longer available. They raise EntityRemoved and permanently retire its target, even when the WinRT profile still reports a connection. A later list may discover a fresh generation; the old handle cannot issue another native query. The final fresh profile inventory also rejects a network replacement occurring during signal collection. Rapid changes never observed by either query remain outside this evidence.

The implementation uses only the RSSI opcode. It adds no scan, BSSID/current_connection query, location access request or MSM notification registration. Microsoft's [Wi-Fi location-access changes](https://learn.microsoft.com/en-us/windows/win32/nativewifi/wi-fi-access-location-changes) identify the current_connection opcode and BSSID-related calls as gated operations. The app-owned permission observer/coordinator contract from the [profile checkpoint](2026-11-11-windows-wifi.md) is unchanged.

Existing NetworkStatusChanged observations enqueue fresh selected reads on the worker. Serial polling remains enabled, including equal values; no separate signal-quality subscription is introduced. A partial signal failure produces null in that snapshot and does not replay the previous RSSI. The next event/poll reads again according to the existing stream settings.

## Execution and cleanup

Native client opening, query, result validation, LONG reading, WlanFreeMemory and WlanCloseHandle all execute on the same collection worker as WinRT profile access. Construction remains inert. Each read owns its client and result; there is no native session left active between polls.

Output buffers and client handles are released in nested finally blocks, including failed calls returning nonzero output values and caller timeout/cancellation. A successful read followed by a close failure makes the signal field unavailable. A close error does not mask a primary read, removal or cancellation error.

Controlled calls hold native open, query and close separately, for both get and an event-triggered read. In all six cases the caller's 250ms deadline completes while the native operation remains held, and context disposal does not join it. When released, a late open performs no query; late query/close work performs no subsequent profile inventory. Native buffers, clients, event registrations and WinRT references then balance on the worker. A native call that never returns can still retain resources and delay that worker; this is not process-crash isolation.

## Evidence

Five public-API cases extend the preceding 89-check suite:

* Distinct adapters return -67 and -110; zero, a later -73 native event and equal events/polls preserve the selected signed value. All WLAN operations share the profile collection worker and release their native resources.
* Open/query/close failures, unsupported version, missing handles/buffers and malformed lengths remain field-local. Both WinRT fields can fail while RSSI succeeds. Whole-query failure and partial failure/recovery behave according to the existing nullable-field contract.
* Native disconnected/not-found results retire targets, preserve EntityRemoved across a close error and stop native observation. Old targets remain invalid after rediscovery. A changed network ID during RSSI collection discards the racing snapshot.
* The six delayed native operations described above preserve caller responsiveness and complete late cleanup without retry or follow-up collection.
* An actual Windows WLAN session queries a synthetic absent adapter, returns ERROR_NOT_FOUND (1168) with zero output bytes and closes successfully on the worker. A controlled stale WinRT profile supplies that target, so this proves the real WLAN failure/lifetime path, not physical SSID or RSSI collection.

The independent [C probe](../../tools/verify-windows-wifi-signal.c) includes the Windows WLAN headers and calls the native APIs without SDK code or managed ABI declarations. It confirms `sizeof(LONG)=4`, RSSI opcode 268435714, successful client version 2, one WLAN interface with no connected signal values, and the same absent-adapter result 1168/zero bytes. The probe closes its native client, reports no SSIDs/native identifiers and changes no network settings.

```powershell
./tools/test-dotnet.ps1
& 'C:/mingw64/bin/gcc.exe' -std=c11 -Wall -Wextra -Werror `
  tools/verify-windows-wifi-signal.c -lwlanapi -o .tools/verify-windows-wifi-signal.exe
./.tools/verify-windows-wifi-signal.exe
```

Evidence is `.tools/windows-wifi-rssi-final.log` (94/94, zero warnings/errors) and `.tools/windows-wifi-signal-independent.json`. The missing RSSI mapping first failed in `.tools/windows-wifi-rssi-red.log` (89/90). Intermediate signal/error/removal/deadline suites passed. Other language/browser suites were not rerun for this Windows-only change.

## Remaining work

This host has no active Wi-Fi connection. Physical signal values, real RF changes, Wi-Fi-specific notification delivery, multi-link driver behavior and the Windows version/architecture matrix remain unverified. The independent C query and real absent-adapter test do not replace that evidence.

BSSID needs an app-coordinated path that respects the no-implicit-UI requirement. Frequency and both current-link rates still need verified mappings. The newer quality API's [frequency member documentation](https://learn.microsoft.com/en-us/windows/win32/api/wlanapi/ns-wlanapi-wlan_realtime_connection_quality_link_info) describes kHz despite its Mhz name, while the [connection-quality rate documentation](https://learn.microsoft.com/en-us/windows/win32/api/wlanapi/ns-wlanapi-wlan_realtime_connection_quality) does not specify rate units. No value-magnitude heuristic or guessed conversion is introduced. Those mappings and multi-link semantics remain required work, alongside the [full implementation ledger](../implementation-status.md).
