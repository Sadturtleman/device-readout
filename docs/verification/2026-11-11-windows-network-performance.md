# Windows network performance — 2026-11-11

NetworkPerformance now reads the Windows preferred profile's data-plan transfer rates through get/watch. All 83 .NET checks pass in the normal-user process, with zero build warnings/errors. This adds the sixteenth Windows entity collector. Other platform work and the full acceptance matrix remain incomplete.

```csharp
using var access = WindowsDeviceAccess.Create();
NetworkPerformanceSnapshot value =
    await access.Get(Entities.NetworkPerformance, cancellationToken);
await foreach (var snapshot in access.Watch(Entities.NetworkPerformance, cancellationToken)) {
    Consume(snapshot);
}
```

## Field mapping and scope

The adapter retrieves the preferred/default profile with GetInternetConnectionProfile and calls [GetDataPlanStatus](https://learn.microsoft.com/en-us/uwp/api/windows.networking.connectivity.connectionprofile.getdataplanstatus?view=winrt-26100) for each read. [DataPlanStatus](https://learn.microsoft.com/en-us/uwp/api/windows.networking.connectivity.dataplanstatus?view=winrt-28000) exposes the connection's inbound/outbound nominal transfer rates. This supplies platform-reported information; the SDK performs no throughput measurement or external reachability request.

| Snapshot field | Native mapping |
|---|---|
| DownlinkBps | DataPlanStatus.InboundBitsPerSecond, already in bit/s. |
| UplinkBps | DataPlanStatus.OutboundBitsPerSecond, already in bit/s. |
| RoundTripTime | null; this native query supplies no RTT. |
| EffectiveType | null; no performance class is derived from interface type, cellular RAT or rate. |
| BrowserOnline | null; a native connection's state is not browser-reported state. |
| CollectedAt | Common runtime snapshot-completion timestamp. |

The two native rate properties are nullable UInt64 references. Non-null values convert to the existing public Number/double fields without 32-bit truncation or unit multiplication. Number fields have floating-point precision; they are not the schema's exact 64-bit counter representation. Zero remains zero. Missing preferred profile, missing data plan or a missing rate produces null, not a measured zero. Adapter hardware speed, byte counters, plan limits and the previous sample are not substituted for unavailable rates.

As with the [NetworkPath mapping](2026-11-11-windows-connectivity.md), the selected profile describes the Windows preferred/default path. It does not inspect a destination-specific route or an application's explicitly bound socket. Multi-homed, VPN and custom routing cases still need coverage against the broader application-path contract.

An individual rate getter or its boxed-value getter can fail independently; the other rate remains available. If both rates actually fail, the whole read throws PermissionDenied when either reports E_ACCESSDENIED, otherwise ReadFailed. A successfully absent reference is a successful null field. Failure to acquire the profile or plan is a whole-query error. No native result is cached across reads or after failure.

## Observation and lifetime

NetworkPath and NetworkPerformance share the context's WinRT factory and collection worker. Each watch owns its native NetworkStatusChanged registration. The callback enqueues the correct entity's read function, so a performance stream receives NetworkPerformanceSnapshot even when a path stream is active in the same context. Initial collection and serial polling remain enabled; equal snapshots remain visible. Existing immutable poll-interval and read-timeout settings apply.

Native notifications contain no transfer-rate payload. A delivered snapshot contains values read later on the worker; the SDK does not reconstruct intermediate values that Windows never supplied. Polling supplements notifications, and the existing E_NOTIMPL event fallback/error behavior is shared with NetworkPath. One stream's closure does not close the other entity's observation or the context runtime.

All native profile/plan/reference calls, conversion, registration/removal and cleanup stay on the collection worker. Each rate's reference is released in a finally block, including failed calls returning nonzero output pointers. Plan and profile interfaces are released after the read; the factory and balanced WinRT initialization belong to the context lifetime.

A get or event-triggered read that exceeds its deadline releases the caller's wait. When the native plan call eventually returns, its result is discarded without further rate queries, and its interfaces and subscriptions are cleaned up on the worker. A permanently blocked native call can still delay worker cleanup; this is scheduling isolation, not process-crash isolation. No permission prompt, screen lookup, network setting change or probe traffic is added.

The ABI was checked against Windows SDK 10.0.26100.0 `windows.networking.connectivity.h`: IConnectionProfile.GetDataPlanStatus is slot 10; IDataPlanStatus inbound/outbound references are slots 8/9; each IReference<UInt64>.Value getter follows IInspectable at slot 6.

## Evidence

Five public-API cases extend the preceding 78-check suite:

* Controlled native interfaces return distinct rates of 1,234,567,890,123 and 32,000,000 bit/s, verifying direction, 64-bit reading and units. Zero, independently absent rates, absent plan/profile and unavailable RTT/class/browser fields are covered. All native references and runtime initialization balance on one worker distinct from the caller.
* Polling obtains fresh plans and retains equal values. Concurrent path/performance watches receive their own typed snapshots from native notifications before a one-hour poll interval. Plan disappearance clears previous rates; closing performance leaves path observation active.
* Failed reference and boxed-value getters preserve the other rate. Both-rate failures produce typed errors. An event-triggered plan acquisition failure closes the stream registration, and a later explicit get can recover. A regression first reproduced one failed rate incorrectly discarding the other.
* Actual Windows get/watch and native notification registration/removal succeed. The same context also reads NetworkPath and balances one factory/runtime lifetime. This host provides a plan object but no inbound or outbound rate, so the actual performance fields are null. This is native absence evidence, not verification of non-null carrier-provided rates.
* Held native plan calls cover both get and event-triggered deadlines. Host continuations and timeout results proceed before native completion. Late plan/profile/reference/subscription cleanup balances, with no further rate getter calls after timeout.

The independent [Windows PowerShell WinRT probe](../../tools/verify-windows-network-performance.ps1) uses no SDK code or hand-coded vtable offsets. It reports `HasProfile=true, HasPlan=true, InboundBps=null, OutboundBps=null`, agreeing with SDK output on this host. Its non-null integer outputs use decimal strings to preserve native values. It logs no profile name or identifier and creates no network traffic for measurement.

```powershell
# Run in a normal-user Windows process for the suite's native identity-positive case.
./tools/test-dotnet.ps1
powershell.exe -NoProfile -NonInteractive -File tools/verify-windows-network-performance.ps1
```

Final evidence is `.tools/windows-performance-final.log` (83/83, zero warnings/errors) and `.tools/windows-performance-independent.json`. Reproduced failures are in `.tools/windows-performance-fields-red.log`, `.tools/windows-performance-events-red.log` and `.tools/windows-performance-partial-red.log`. Other language/browser suites were not rerun for this Windows-only change.

## Remaining evidence

Physical profiles supplying non-null plan rates, actual data-plan updates/default-profile changes, carrier provisioning, virtual/multi-homed/custom routes, high-volume events and the Windows version/architecture matrix remain unverified. Controlled native interfaces prove mapping and lifecycle behavior under those inputs, not physical-provider support. The [implementation ledger](../implementation-status.md) retains the remaining Windows fields/entities, Apple/Swift, Flutter/RN and the full cross-platform acceptance scope.
