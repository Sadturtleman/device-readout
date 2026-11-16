# .NET provider failure ownership and cancellation isolation

Recorded on 2026-11-17 (Asia/Seoul), using Windows 11 Home x64 build 26300, .NET SDK 10.0.403 and runtime 10.0.14. The complete .NET verification executable passes **115/115**, with zero build warnings or errors. This extends the [TypeScript/Kotlin observer ownership checkpoint](2026-11-17-observer-failure-ownership.md); other platform counts in that record remain historical.

## Public contract

`access.Observers.FailureSource(entity)` returns an inert `ObserverFailureSource : IDisposable`. `Publish(error)` reports a provider failure, `Publish(null)` clears only that provider, and `Dispose()` permanently releases only that handle. Repeated disposal and disposal after the context closes are safe. Publishing after disposal or creating a source on a closed context reports `EntityRemoved`.

The existing `Observers.Failure(entity, error)` remains the application policy channel. Application target/family failures take priority over provider target/family failures. A provider cannot clear application policy, sibling owners or a replacement owner. Active provider errors invalidate observed state, terminate affected streams and invalidate matching in-flight native Get/List/Current/Describe results even if the error clears before native completion. Recovery needs fresh state or a fresh native call. Independent targets and unrelated entities remain usable.

## Reproduced execution defects

The initial ownership test failed to compile because the public API was missing. After implementing it, the 110 existing/new checks passed.

A controlled collector then registered a native cancellation callback that waited for an explicit release. Reporting a provider error from a dedicated host thread blocked that thread beyond the test's 500 ms bound. Switching the failure path to asynchronous cancellation fixed this case. The same fixture exposed synchronous blocking in context disposal.

Making only context cancellation asynchronous returned control to the caller but still left stream termination waiting behind the native callback. The final implementation gives SDK operations and native subscriptions separate cancellation scopes. Upstream cancellation marks the downstream scope and schedules its callbacks without running them on the upstream caller. Native callbacks therefore do not share the SDK control token's callback queue. Callback exceptions are observed; native subscription/collector cleanup still runs on the collection worker. A scope retains its cancellation source until dispatched callbacks finish, and removes upstream registrations without joining running callbacks.

This uses the documented behavior of [CancellationTokenSource.CancelAsync](https://learn.microsoft.com/en-us/dotnet/api/system.threading.cancellationtokensource.cancelasync?view=net-10.0) and [CancellationTokenRegistration.Unregister](https://learn.microsoft.com/en-us/dotnet/api/system.threading.cancellationtokenregistration.unregister?view=net-10.0). It does not forcibly interrupt native code or provide process isolation.

## Six added public-boundary scenarios

| Scenario | Verified result |
| --- | --- |
| Provider owners, application policy and fresh recovery | Independent disposal/replacement; same-context configuration views share ownership; old state does not return; unrelated reads remain usable |
| Provider failure with blocked native cancellation | Host call returns before external release; pending stream receives the typed failure; cleanup stays on the worker; the context can read again after release |
| Context disposal with blocked collection and cancellation | Host Dispose returns and pending stream cancels while native work remains held; native resources are released after the fixture permits completion |
| Read deadline with blocked, throwing cancellation callback | Caller receives ReadTimeout before native release; the callback exception does not poison a later read |
| Caller cancellation with blocked, throwing native callback | Caller Cancel returns, pending read cancels before native release, and later reads succeed |
| Provider failure/recovery during native Get/List/Current/Describe | All four operations discard pre-failure results; subsequent queries succeed |

The blocking fixtures hold native work until the test explicitly releases it. They do not derive a timing guarantee from ordinary fast native operations. Tests exercise public DeviceAccess and IDeviceCollector boundaries; production cancellation scope internals are not called by tests.

## Battery regression test correction

The full suite exposed an intermittent battery-removal assertion: it assumed the very next stream item after a tag change must be an error. A controlled 75 ms consumer pause reproduced the failure because valid pre-removal snapshots were already queued. The stream contract retains every delivered snapshot, including equal values. The corrected test consumes those queued values and requires EntityRemoved within one total one-second cancellation deadline. It still verifies that old handles cannot recover and that native handles are released. Production battery behavior was not changed.

## Commands and evidence

`tools/test-dotnet.ps1` builds and runs all 115 cases in a normal-user Windows process. The helper now accepts `-Filter '<name fragment>'` for focused reproduction; an unmatched filter exits nonzero rather than claiming an empty pass. The final full run does not use a filter.

Ignored local logs include `.tools/dotnet-owner-cancellation-full.log`, `.tools/dotnet-owned-failure-red.log`, `.tools/dotnet-owned-cancellation-red.log`, `.tools/dotnet-dispose-cancellation-red.log`, `.tools/dotnet-dispose-cancellation-green.log`, `.tools/dotnet-read-cancellation.log`, `.tools/dotnet-provider-failure-contracts.log`, and `.tools/dotnet-battery-queued-removal-{red,green}.log`. Existing Windows native battery, CPU, network, identity, connectivity and cellular checks all remain in the full run.

## Remaining scope

The new isolation evidence uses controlled native boundaries on this Windows host. It does not prove every driver, synchronization context, overload or cancellation race. Physical battery/UPS, Wi-Fi/cellular transitions, other OS builds/architectures, complete field mappings, .NET sensor source/lifecycle integration and package-consumer validation remain required. Swift/Apple and the rest of the SDK's platform matrix also remain incomplete. The release scope is unchanged.
