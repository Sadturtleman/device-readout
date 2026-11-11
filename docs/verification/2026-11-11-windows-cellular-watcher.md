# Windows cellular account observation

This checkpoint adds native account-change observation to the [cellular field implementation](2026-11-11-windows-cellular.md). The normal-user .NET suite now passes **109/109 checks**, with zero build warnings or errors. The Windows collector count remains eighteen; this work completes additional lifecycle behavior within CellularSubscription.

## Native source and context ownership

Microsoft's [account enumeration guidance](https://learn.microsoft.com/en-us/windows-hardware/drivers/mobilebroadband/enumerate-available-mobile-broadband-accounts) states that separate account watchers may receive different events and recommends one watcher per app. DeviceReadout therefore shares one native MobileBroadbandAccountWatcher among its Windows contexts. The first cellular inventory attaches before enumeration; subsequent contexts join the same source. Closing the creating context leaves the source alive for the others. The last context detaches and releases it.

The source registers AccountAdded, AccountUpdated, AccountRemoved, EnumerationCompleted and Stopped, then calls Start. These are the [watcher's defined events and operations](https://learn.microsoft.com/en-us/uwp/api/windows.networking.networkoperators.mobilebroadbandaccountwatcher?view=winrt-26100). Native activation, registration, status reads, Start/Stop, unregistration and release run on initialized MTA collection workers. Shared ownership permits the last worker to differ from the creating worker; the actual two-context test verifies that lifetime.

Native account callbacks copy only the supplied event's bounded account ID. They do not look up accounts, profiles, modems, permissions or UI. Each context records removal versions and schedules its own selected reads. Normalization and snapshot timestamps remain worker-owned. Native IDs remain internal.

The control lock serializes source creation and destruction. Callbacks do not acquire that lock, and native calls are never made while holding the callback-state lock. Each source instance has an internal generation. A callback already in progress when its source closes cannot deliver a removal or failure to a subsequently created source.

## Handle and stream behavior

An observed removal permanently invalidates that context's old handle, including between get-only calls. A removal immediately fails matching watches even when the next poll is an hour away. A later AccountAdded allows a fresh inventory to create a new handle; it cannot revive the old one. Updates enqueue full selected-account snapshots without deduplicating equal values.

Inventory and read results crossing an observed removal are discarded. A stale inventory cannot rediscover an account still marked absent. A failed inventory cannot erase positive removal evidence. Native AccountWatcher events supplement NetworkStatusChanged and serial polling; they do not remove the existing polling path for uncovered fields.

If the watcher class/interface is unavailable, or registration/Start returns E_NOTIMPL, partially acquired registrations are cleaned up and supported account reads/polling remain available. There is no repeated activation attempt. Permission denial and ordinary registration/start failures remain typed errors rather than being disguised as unsupported events.

Malformed event identities and an unexpected Stopped event fail affected observation with ReadFailed. A context whose source lost continuity does not silently recover old handles or restart streams. After releasing the failed source's contexts, an explicit new context can create a fresh source. Windows documents automatic watcher stop/restart around app suspension; the full application suspend/resume integration is still unverified, and this checkpoint does not claim transparent recovery through it.

Cleanup reads the native watcher status. Created, Stopped and Aborted states do not receive an invalid second Stop; Started and EnumerationCompleted are stopped before unregistration. All acquired event registrations are attempted for removal and their owner references are released even after a cleanup failure. An unresolved cleanup failure prevents creating another source that might overlap the old one.

## Defects reproduced and corrected

* A removed account that reappeared before the next inventory reused its old handle. The new removal history makes it permanently invalid and rejects reads crossing the change.
* Cleanup called Stop after a failed start or an already reported stop. The native API rejects that operation; cleanup now consults the native state.
* An old callback held inside its event-payload getter could finish after a fresh source was created and invalidate the fresh context. Source generations now reject both late removal and late failure delivery.
* E_NOTIMPL from an event operation prevented otherwise supported account discovery. It now releases partial ownership and retains polling, as required by the watch contract.

## Verification

Eight public-API cases extend the preceding 101-check suite:

1. Removal/reappearance between reads, native updates, immediate watch failure and mid-read removal.
2. Two contexts sharing one native ABI source, including closing its creating context first.
3. Actual native activation, all five event registrations, Start, shared lifetime, Stop and unregistration.
4. Partial failure at each registration, failed start, malformed payload, unexpected stop and unavailable-source polling.
5. Stale, failed and racing inventories plus a read crossing source failure.
6. Held native registration, Start and Stop calls with caller deadlines/host progress and late worker cleanup.
7. Held old-source removal and malformed callbacks crossing disposal and source recreation.
8. E_NOTIMPL at each registration and Start, preserving reads and equal polled snapshots without activation loops.

The actual Windows source registered five handlers, reached status 2 (EnumerationCompleted), remained active after its creating context closed, then reached status 3 (Stopped) and removed all five handlers when the last context closed. Native operations stayed off the caller thread. There are still no physical cellular accounts on this host, so account-event payloads and SIM transitions use controlled OS-boundary fixtures.

The independent [Windows PowerShell probe](../../tools/verify-windows-cellular-watcher.ps1) uses the OS's WinRT projection and a compiled no-op enumeration handler, not the SDK's unmanaged ABI declarations. It independently returns `{"StartedStatus":2,"StoppedStatus":3}`. The initial no-handler probe exposed the native requirement that at least one handler be registered before Start; it also confirmed that Stop rejects a watcher that never started. The final probe registers and removes its handler and changes no network or permission settings.

```powershell
./tools/test-dotnet.ps1
powershell.exe -Mta -NoProfile -NonInteractive -File tools/verify-windows-cellular-watcher.ps1
```

Final evidence is `.tools/windows-cellular-watcher-final.log` (109/109, zero warnings/errors) and `.tools/windows-cellular-watcher-independent.json`. Regressions were observed in the history, shared-source, stop-state, late-source and fallback `*-red.log` files before their fixes. Other language/browser suites were not rerun for this Windows-only change.

## Remaining work

Physical account removal/reappearance, SIM and slot transitions, modem/radio fields, account-event delivery, supported packaging/version/architecture combinations and full suspend/resume behavior remain unverified. Slot-manager-specific events and a verified CountryCode source remain unimplemented. If an application creates its own independent account watcher, the OS's event-distribution limitation still applies; DeviceReadout cannot promise observation of changes consumed by another watcher. Polling cannot reconstruct an entirely unobserved rapid removal/reappearance.

Collection threads do not isolate native process crashes or forcibly interrupt stuck native calls. Caller timeouts and nonjoining context disposal are verified; an indefinitely blocked native call can still delay cleanup and shared-source access on collection workers. The [full implementation ledger](../implementation-status.md) remains incomplete across the required platforms and bindings.
