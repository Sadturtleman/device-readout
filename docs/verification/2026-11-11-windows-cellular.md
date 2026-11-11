# Windows cellular account collection

Follow-up: [account observation verification](2026-11-11-windows-cellular-watcher.md) adds the shared native account watcher, removal history, source-generation isolation and 109/109 passing checks. The 101-check evidence below describes this earlier field checkpoint.

The Windows collector now supports `CellularSubscription` discovery, current selection, get/watch and capabilities. Seven public-API cases extend the preceding 94-check checkpoint to **101/101 passing checks**, with zero build warnings or errors. This implements six of seven nullable snapshot fields; it does not complete the Windows platform or physical cellular verification.

## Account and field semantics

Discovery uses MobileBroadbandAccount.AvailableNetworkAccountIds. Each account receives a context-local typed handle; provider names, APN profiles and modem adapters are not subscription identities. Multiple APNs do not duplicate an account. Native account IDs stay private, and neither the collector nor its verification output publishes SIM/account identifiers. Microsoft documents account identity and explicitly distinguishes Win32 desktop access from privileged UWP access in its [mobile broadband API overview](https://learn.microsoft.com/en-us/windows-hardware/drivers/mobilebroadband/list-of-mobile-broadband-windows-runtime-apis). This checkpoint tests an unpackaged .NET desktop process, not every Windows packaging model.

| Snapshot field | Native source and interpretation |
|---|---|
| CarrierName | The selected account's ServiceProviderName; successful empty strings remain empty. This is the account provider, not an APN label or visited-network display name. |
| SlotIndex | Account.CurrentDeviceInformation → IMobileBroadbandDeviceInformation4.SlotManager.CurrentSlotIndex. Zero is valid; negative indices, a missing source or an unavailable optional slot interface yield null. No slot setter is called. |
| MobileCountryCode | First three ASCII digits of a consistent five- or six-digit home provider ID, only when the account device reports CellularClass.Gsm. |
| MobileNetworkCode | Remaining two or three digits of that same home provider ID; leading zeros are preserved. |
| RadioTechnology | Associated active WWAN profiles' GetCurrentDataClass values, using the explicit mapping below. Disconnected profiles do not supply an active data technology. |
| Roaming | CurrentNetwork.NetworkRegistrationState: Home=false, Roaming/Partner=true; all other states yield null. |
| CountryCode | Null. The adapter does not infer a country from MCC, locale or provider name. |

Home provider IDs come from the account's [associated connection profiles](https://learn.microsoft.com/en-us/uwp/api/windows.networking.networkoperators.mobilebroadbandaccount.getconnectionprofiles?view=winrt-26100), via WwanConnectionProfileDetails.HomeProviderId. All applicable profiles must agree. Missing, malformed or conflicting IDs make both MCC and MNC null. CDMA provider IDs represent SIDs and are not split into MCC/MNC. Microsoft's [registration-state contract](https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/wwan/ns-wwan-_wwan_registration_state) also defines Partner as roaming on a preferred partner.

The [WwanDataClass values](https://learn.microsoft.com/en-us/uwp/api/windows.networking.connectivity.wwandataclass?view=winrt-26100) map as follows:

| Native value | Public value |
|---|---|
| Gprs / Edge / Umts / Hsdpa / Hsupa | Gprs / Edge / Umts / Hsdpa / Hsupa |
| LteAdvanced | Lte; this does not assert active carrier aggregation |
| NewRadioNonStandalone / NewRadioStandalone | NrNsa / NrSa |
| Cdma1xRtt / Cdma1xEvdo / Cdma1xEvdoRevA / Cdma1xEvdoRevB | Cdma1x / Evdo0 / EvdoA / EvdoB |
| None, Custom, unmapped flags or multiple flags | null |

If several active profiles disagree or one supplies an unavailable technology, RadioTechnology is null. The collector never substitutes supported device data classes, a registered-but-idle radio, a signal indicator or a display override for the current data connection.

`Current` matches the Windows preferred active WWAN profile's adapter to the selected accounts' associated active profiles. Exactly one account must match. Preferred Wi-Fi/Ethernet, no active default path, or ambiguous account association returns null. The account inventory and preferred adapter are re-read before returning a matching handle. This describes the Windows preferred/default path, not a per-socket route or a universal SIM default.

## Errors, events and lifetimes

Partial field failures yield null without discarding independently readable fields. If all field groups fail, the existing common typed error is raised, preferring PermissionDenied when present. Successfully absent optional sources remain successful nulls. Unrecognized enum/flag values remain null.

Inventories and strings are bounded. A missing, failed, canceled, duplicate or malformed inventory does not become a successful empty inventory and does not retire existing handles. A successfully observed absence permanently retires a handle; later rediscovery of the same native account produces a new generation. Reads validate the selected native account ID and refresh the inventory before and after field collection.

Each watch registers NetworkStatusChanged, whose callback enqueues a selected-account read on the shared worker. Serial polling supplements this event, retaining equal snapshots. Native failures terminate the affected stream and release its registration. There is no implicit retry or reuse of the preceding field values. MobileBroadbandAccountWatcher and slot-specific native notifications are not implemented in this checkpoint; changes between successful inventories can still be missed.

NetworkInformation and MobileBroadbandAccount use separate activation factories on one initialized collection worker. Factory activation, HSTRING conversion/deletion, profile/device/network/slot getters, reference release, event registration/removal and runtime shutdown all execute there. Construction performs no native collection. Cleanup uses finally blocks even for failed calls returning nonnull outputs.

Six controlled scenarios hold account inventory, account creation or provider-field reads, separately for get and event-driven reads. The caller's 250ms deadline and host continuation proceed before native completion; disposing DeviceAccess does not join the blocked native call. Once released, late results are disposed without subsequent field collection, and native event/reference/runtime ownership balances. A native call that never returns can still hold worker resources. Thread isolation is not process-crash isolation or a promise of zero overhead.

The SDK does not invoke connection UI, permission dialogs or modem/network setters. An app observer supplies permission state and any blocking collection failure. Get/watch do not invoke the app permission coordinator. Only explicit Permissions.Request delegates that interaction; completion follows observed permission state outside ReadTimeout. Clearing an app failure allows a fresh explicit read and does not restart a failed stream.

## Verification evidence

The added public-API cases cover:

* Distinct accounts sharing a provider, selected reads, empty names, initial/equal polling, capabilities and generation retirement.
* Multiple APNs, slot zero, two-/three-digit MNCs, CDMA and malformed IDs, current radio mappings, unknown/combined/disagreeing technologies, disconnected profiles and roaming states.
* Preferred account changes, ambiguous associations, Wi-Fi/no-path results, native status refreshes and equal events.
* Independent field availability, whole-read errors, optional interfaces, denied/malformed inventories, identity mismatch, failed-watch cleanup and explicit recovery.
* Six held native call scenarios with host progress, deadlines and late worker cleanup.
* App-owned permission status/failure inputs and explicit request completion.
* Actual native account inventory/current selection and balanced activation/runtime cleanup.

The actual Windows process reports **zero available cellular accounts and no current cellular account**. The independent [Windows PowerShell projection](../../tools/verify-windows-cellular.ps1) reports `{"Accounts":0,"States":[]}` without SDK code or its unmanaged declarations. This validates available API activation and empty discovery on this host, not physical account fields or radio transitions.

```powershell
./tools/test-dotnet.ps1
powershell.exe -NoProfile -NonInteractive -File tools/verify-windows-cellular.ps1
```

Evidence files: `.tools/windows-cellular-lifetime.log` (101/101, zero build warnings/errors) and `.tools/windows-cellular-independent.json`. The account, field and current-selection tests first failed in the corresponding `windows-cellular-*-red.log` files, then passed after implementation. Intermediate account/field/current/failure checkpoints passed. Other language/browser suites were not rerun for this Windows-only change.

## Remaining work

Physical LTE/5G/CDMA fields, roaming changes, multi-SIM slot association, multiple APNs, native account changes and the supported Windows version/architecture/packaging matrix remain unverified. AccountWatcher and slot events are needed to retain account-removal history beyond inventory observations; rapid same-ID removal/reappearance is not covered. CountryCode has no verified source. These limits and the remaining Wi-Fi, network, sensor and binding work remain part of the [full implementation ledger](../implementation-status.md).
