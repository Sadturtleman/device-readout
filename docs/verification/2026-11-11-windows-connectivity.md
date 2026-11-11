# Windows preferred network path — 2026-11-11

NetworkPath now reads Windows preferred-profile connectivity and metering and observes native status changes. All 78 .NET checks pass in the normal-user process, with zero build warnings/errors. This adds the fifteenth Windows entity collector; remaining fields and the full platform scope are still incomplete.

```csharp
using var access = WindowsDeviceAccess.Create();
NetworkPathSnapshot path = await access.Get(Entities.NetworkPath, cancellationToken);
await foreach (var snapshot in access.Watch(Entities.NetworkPath, cancellationToken)) {
    Consume(snapshot);
}
```

## Native scope and fields

[GetInternetConnectionProfile](https://learn.microsoft.com/en-us/uwp/api/windows.networking.connectivity.networkinformation.getinternetconnectionprofile?view=winrt-26100) selects the local machine's preferred interface profile, which can have local or limited access without internet access. A null result means no suitable preferred profile. The SDK re-queries it for every read; it does not retain a previous profile when the preferred connection changes.

This mapping describes the Windows preferred/default path. It does not resolve a specific destination, inspect explicitly bound application sockets or prove which route a custom per-socket configuration uses. The broader application-path contract still needs coverage for those configurations. It does not select an arbitrary active interface or merge every connected adapter into the current path.

| Public value | Native mapping |
|---|---|
| ConnectionState | GetNetworkConnectivityLevel None (0) → Disconnected; LocalAccess (1), ConstrainedInternetAccess (2), InternetAccess (3) → Connected. Unknown values → null. No preferred profile → Disconnected. |
| InternetValidated | InternetAccess → true; None/LocalAccess/ConstrainedInternetAccess → false; unknown level → null. No preferred profile → false for this default path. |
| Metered | GetConnectionCost().NetworkCostType Unrestricted (1) → false; Fixed (2) or Variable (3) → true; Unknown (0), unknown values, absent cost or failed cost access → null. |
| CollectedAt | Common runtime collection-completion timestamp. |

[NetworkConnectivityLevel](https://learn.microsoft.com/en-us/uwp/api/windows.networking.connectivity.networkconnectivitylevel?view=winrt-26100) distinguishes local, limited and internet access. Its limited-access state can result from a portal or another condition; it does not establish captive-portal detection. It is also unrelated to the SDK's constrained-data-mode field. InternetValidated preserves the OS classification and does not promise that an application's server is reachable. [NetworkCostType](https://learn.microsoft.com/en-us/uwp/api/windows.networking.connectivity.networkcosttype?view=winrt-26100) supplies the usage-charge/limit classification; unknown cost is not treated as free or metered by policy.

Transports, Expensive, Constrained, SaveData, SupportsIpv4, SupportsIpv6, SupportsDns and CaptivePortal remain null in this adapter. The current implementation does not have a complete transport set across virtual/underlying paths or native values with the remaining fields' exact meanings. It does not infer them from a single adapter type, configured address/DNS list, roaming, cost or limited connectivity. These are explicit coverage gaps, not claims that all Windows APIs lack the information. NetworkPerformance and Wi-Fi/cellular connection entities remain separate work.

Connectivity and cost are independent read groups. A failed group leaves its fields null and retains the other group. If both groups actually fail, the whole query throws PermissionDenied when either reports E_ACCESSDENIED, otherwise ReadFailed. A successful unknown level or absent cost is still a successful read. Failure of GetInternetConnectionProfile is a whole-query error. Missing class/interface activation is UnsupportedEntity. No replacement network state is synthesized after an error.

## Observation and execution

Each active watch registers [NetworkInformation.NetworkStatusChanged](https://learn.microsoft.com/en-us/uwp/api/windows.networking.connectivity.networkinformation.networkstatuschanged?view=winrt-26100), then performs its initial read. The callback only enqueues a deferred collection request. Profile lookup, connectivity/cost getters and normalization run on the dedicated collection worker. No OS query, UI dispatch or permission prompt runs inside the native callback.

The notification has no connectivity-value payload. Its snapshot therefore contains state observed during the subsequent worker read, not a captured historical transition. Equal results are retained. Initial collection and serial polling remain enabled, with the existing immutable one-second default interval, to refresh state even without a native notification. E_NOTIMPL from event registration falls back to polling; registration denial or another error fails the stream instead of silently retrying.

Each stream owns its native event token. Closing one stream leaves others active. Handler dispatch is stopped before native unregistration; a retained callback after removal schedules no new read in the tested case. Callback exceptions are contained at the WinRT boundary. The event handler implements the native IUnknown-based interface with its single-sender Invoke ABI, as declared by Windows SDK 10.0.26100.0 `windows.networking.connectivity.h`.

Construction is inert. WinRT initialization, activation, event registration/removal, profile/cost reference release and runtime shutdown are worker-owned. The factory is retained for the context lifetime; report interfaces are released after each read, including failed getters that return nonzero pointers. Context closure releases remaining subscriptions before the factory and balances runtime initialization.

The caller's deadline does not wait for a stuck native call. After a timed-out profile call returns, the SDK releases the late profile without collecting its fields. Cleanup can still be delayed by a permanently blocked native call, and native process crashes are not isolated by a worker thread. The SDK does not send probe traffic, trigger a speed test or change routing, adapter or connection settings. App-owned UI/permission observers remain the only route for those states.

## Evidence

Six public-API cases extend the preceding 72-check suite:

* Controlled native interfaces cover all four known connectivity levels, unrestricted/fixed/variable/unknown costs, unknown enum values, absent preferred profiles, fresh polling, equal values and balanced worker-owned references.
* Two concurrent watches with a one-hour polling interval receive deferred native notifications, including equal notifications. Closing one retains the other; retained callbacks after removal do not schedule reads. Preferred-profile disappearance updates the remaining watch.
* Failed connectivity, failed cost acquisition and failed nested cost getters preserve independent fields. Both-group failures produce typed errors. A whole-query failure triggered by a native event terminates the watch and releases its registration; a later explicit get can recover. The regression first reproduced an unreadable connectivity field incorrectly discarding readable cost.
* E_NOTIMPL event registration preserves initial collection and polling. Access-denied registration fails without retry. An extra native reference to the failed handler confirms that the SDK released its own reference.
* A held native profile call lets the host continuation run and returns ReadTimeout before native completion. Context closure remains nonblocking; the late report is released without a connectivity-field query, and runtime cleanup balances after the call returns.
* Actual Windows get/watch returns Connected, InternetValidated=true and Metered=false on this host. A forwarding native ABI probe confirms successful NetworkStatusChanged registration and removal, fresh reads/polling and balanced factory/runtime lifetime on one worker distinct from the caller. This verifies native registration and cleanup, not an actual change in network state.

The separate [Windows PowerShell probe](../../tools/verify-windows-connectivity.ps1) uses the built-in WinRT projection and no SDK code or hand-coded vtable offsets. It reports `HasProfile=true, Connectivity=3, Cost=1`, corroborating the actual SDK result on this host. It prints no profile name, SSID or device identifier. Native profile/cost state was not changed for verification.

```powershell
# Normal-user Windows process; the existing identity-positive case requires it.
./tools/test-dotnet.ps1
powershell.exe -NoProfile -NonInteractive -File tools/verify-windows-connectivity.ps1
```

The final suite log is `.tools/windows-connectivity-final.log` (78/78, zero warnings/errors). Independent native output is `.tools/windows-connectivity-independent.json`. Red cases are recorded in `.tools/windows-connectivity-fields-red.log`, `.tools/windows-connectivity-events-red.log` and `.tools/windows-connectivity-partial-red.log`. The first field-test run also exposed an incorrect test-side total-read expectation; it was replaced by a before/after check for initial and polled reads. No production behavior was changed to meet that incorrect count.

Other language/browser suites were not rerun for this Windows-only implementation.

## Remaining verification

Actual default-interface changes, disconnect/reconnect, metering changes, captive/limited networks, multi-homing/VPN, explicitly bound sockets, packaged-app capabilities, high-volume native event delivery and Windows architecture/version coverage remain unverified. Controlled transitions establish behavior under those inputs, not real hardware/network transitions. The eight null path fields need further native coverage work. Remaining Windows collectors, Apple/Swift, Flutter/RN and the complete cross-platform matrix remain in the [implementation ledger](../implementation-status.md).

The subsequent [network performance checkpoint](2026-11-11-windows-network-performance.md) adds data-plan rates and typed mixed-entity observation using this WinRT context. The 78-check count above records this earlier NetworkPath checkpoint.
