# Windows Wi-Fi connections — 2026-11-11

This initial profile checkpoint is followed by [RSSI collection and the 94-check suite](2026-11-11-windows-wifi-signal.md). The fields and 89-check results below describe this earlier checkpoint.

Windows WifiConnection now supports typed discovery/current selection, SSID and selected authentication through get/watch. All 89 .NET checks pass in the normal-user process with zero build warnings/errors. This is the seventeenth Windows entity collector; its other five fields and the full platform matrix remain pending.

```csharp
using var access = WindowsDeviceAccess.Create();
var connections = await access.List(Entities.WifiConnection, cancellationToken);
var current = await access.Current(Entities.WifiConnection, cancellationToken);
if (current is not null) {
    WifiConnectionSnapshot value = await access.Get(current, cancellationToken);
    await foreach (var snapshot in access.WithPollInterval(TimeSpan.FromSeconds(1))
        .Watch(current, cancellationToken)) {
        Consume(snapshot);
    }
}
```

## Discovery and identity

The worker obtains fresh [GetConnectionProfiles](https://learn.microsoft.com/en-us/uwp/api/windows.networking.connectivity.networkinformation.getconnectionprofiles?view=winrt-28000) output, checks IsWlanConnectionProfile and includes only profiles with LocalAccess, ConstrainedInternetAccess or InternetAccess. Disconnected remembered profiles and non-WLAN profiles are excluded. An unknown activity value cannot establish membership and fails the inventory instead of retiring targets from an incomplete result.

The context privately keys a connection by NetworkAdapterId and its NetworkItem.NetworkId. Public handles remain opaque, context-owned generations; neither native GUID is a permanent device identifier. A successful inventory observing absence retires the old handle. Reappearance creates a fresh handle, and a different network ID on the same adapter also replaces the connection. Failed/canceled inventories leave existing generations intact. A connected profile lacking the required identity fails with ReadFailed rather than disappearing silently. Duplicate keys are rejected as ambiguous.

Current uses the Windows preferred profile, as described by [NetworkInformation](https://learn.microsoft.com/en-us/uwp/api/windows.networking.connectivity.networkinformation?view=winrt-28000). If that profile is absent or non-WLAN, Current returns null even if another Wi-Fi connection is active. List ordering carries no priority. A read re-enumerates after obtaining fields and checks that its selected generation remains present. Native objects are released after each operation, never retained as live-updating profiles.

This detects observed changes, not every physical connection episode. A disconnect/reconnect with the same native identities occurring entirely between inventories can be missed. Native notifications trigger a later worker query and contain no connection-history payload. Rapid reuse and physical roaming/disconnection behavior still require additional work and evidence.

## Fields

| Field | Current Windows implementation |
|---|---|
| Ssid | WlanConnectionProfileDetails.GetConnectedSsid; successful empty strings are retained. ProfileName is not substituted. |
| Security | Current NetworkSecuritySettings authentication; mapping below. |
| Bssid | null; permission-sensitive collection remains pending. |
| RssiDbm | null; native signal-quality collection remains pending. Signal bars are not substituted. |
| FrequencyHz | null; native frequency mapping remains pending. |
| ReceiveLinkSpeedBps / TransmitLinkSpeedBps | null; current-link rate mapping remains pending. Adapter maximum capacity is not substituted. |
| CollectedAt | Common runtime collection-completion timestamp. |

[NetworkAuthenticationType](https://learn.microsoft.com/en-us/uwp/api/windows.networking.connectivity.networkauthenticationtype?view=winrt-28000) maps WPA/RSNA enterprise to Eap, their PSK variants to Psk, WPA3 SAE to Sae, OWE to Owe, and the two WPA3 enterprise modes to their corresponding SDK enums. Native value 10, including its Wpa3 alias, means EapWpa3Enterprise192Bit. SharedKey80211 maps to Wep. None/Open80211 requires the encryption value: None maps to Open, Wep/Wep40/Wep104 to Wep, and other/unknown encryption values to null. WpaNone, IHV and unrecognized authentication remain null.

An individual SSID/security failure leaves that field null while preserving the other. Successfully absent detail/security objects are successful null fields. If both field reads fail, the operation throws PermissionDenied when either reports E_ACCESSDENIED, otherwise ReadFailed. Inventory and target-identity failures are whole-query errors. All nonzero output interfaces are released even when their producing native calls fail; HSTRING values are deleted in finally blocks. Enumerations are bounded to 4,096 profiles, and string copying has a 65,536-character safety bound.

## Permission and execution contract

Microsoft documents that some [Wi-Fi calls can trigger a location-consent prompt](https://learn.microsoft.com/en-us/windows/win32/nativewifi/wi-fi-access-location-changes), and recommends GetConnectedSsid for SSID-only access. This collector uses that route. It does not call WlanScan, WlanGetAvailableNetworkList, WlanGetNetworkBssList, current_connection, GetLanIdentifiers, Windows.Devices.WiFi or a permission-request API. BSSID access remains explicitly unimplemented rather than entering an implicit consent path.

The application supplies permission status through Observers.Permission. If an observed restriction prevents the intended collection, it also supplies Observers.Failure with PermissionDenied. That failure terminates the affected native stream and prevents subsequent reads until cleared. Permission status alone remains separate from collection failure: denial of a richer capability does not imply that every prompt-free field is unavailable. An explicit Permissions.Request invokes only the registered app coordinator and completes from the app's permission observation; it is outside ReadTimeout. The SDK does not choose when to show UI or dispatch UI operations.

Profile enumeration, QueryInterface, field access, string conversion, native notification registration/removal and cleanup run on the shared collection worker. Each watch owns a NetworkStatusChanged subscription. The callback only enqueues the selected connection's read. Initial collection, native notifications and serial polling all retain equal snapshots. Closing one watch leaves another active; late callbacks after removal enqueue no work. The existing unavailable-event polling fallback and typed registration errors are shared with NetworkPath.

Held inventory calls verify independent get/event deadlines and continued host execution. After native completion, canceled results are released without further field reads. Context closure does not join borrowed native work. As with other collectors, an indefinitely blocked native call can delay worker cleanup; this is not native crash isolation or a zero-overhead guarantee.

The ABI was checked against Windows SDK 10.0.26100.0 `windows.networking.connectivity.h`: profile vector slots 6/7 for GetAt/Size; IConnectionProfile2's byte-valued WLAN flag and details at slots 7/9; profile adapter/security slots 11/14; adapter NetworkItem/ID slots 9/10; network ID at slot 6; security authentication/encryption slots 6/7.

## Evidence

Six public-API cases extend the previous 83-check suite:

* Multiple active connections, inactive/wired filtering, preferred selection, empty SSID, current authentication mappings and balanced worker-owned references.
* Initial/polled/equal native values, per-target notification routing, independent watch lifetime, disconnection, reconnection and same-adapter network replacement. Old handles remain invalid.
* Partial field errors, whole-query errors, failed nonzero output references, unknown activity, missing identity objects and bounded malformed inventories. Failed inventories do not retire valid targets.
* Held get and event reads: the caller receives ReadTimeout before native return, then late inventory and subscription resources are released on the worker without further field getters.
* App-owned permission observations, explicit request coordination outside the read timeout, observer failure gating and recovery. Get/watch never invoke the registered permission coordinator.
* Actual Windows profile enumeration/current selection and worker-owned WinRT lifetime. The host has **zero connected Wi-Fi profiles**, so actual SSID/security reads and Wi-Fi-specific watch registration are not claimed as physical evidence.

The independent [PowerShell WinRT probe](../../tools/verify-windows-wifi.ps1), using neither SDK code nor handwritten vtable offsets, returned `KnownProfiles=3, ConnectedWifi=0, PreferredWifi=false, Fields=[]`, agreeing with the SDK. The probe logs neither SSIDs nor native identifiers and changes no connections/settings.

```powershell
./tools/test-dotnet.ps1
powershell.exe -NoProfile -NonInteractive -File tools/verify-windows-wifi.ps1
```

Evidence: `.tools/windows-wifi-validation.log` (89/89, zero warnings/errors), `.tools/windows-wifi-independent.json`. Red tests reproduced missing discovery in `.tools/windows-wifi-fields-red.log` and missing native subscription in `.tools/windows-wifi-events-red.log`. Other language/browser suites were not rerun for this Windows-only change.

Physical SSID/security values, permission configurations, simultaneous WLAN adapters, native transitions, rapid same-ID reuse, the remaining five fields and Windows version/architecture coverage remain pending. Location-free quality APIs need verified units and multi-link semantics before mapping their fields. Full SDK release scope remains tracked in the [implementation ledger](../implementation-status.md).
