# .NET state stream termination and subscription ownership

Recorded on 2026-11-17 (Asia/Seoul), on Windows 11 Home x64 build 26300 with .NET SDK 10.0.403 and runtime 10.0.14. The final complete `tools/test-dotnet.ps1` run passes **129/129**, with zero build warnings or errors. This follows the [125-case target identity checkpoint](2026-11-17-dotnet-target-identity.md).

## Reproduced failures and fixes

A state watch previously awaited native subscription cleanup before completing a canceled pending stream read. With native cleanup deliberately held and the default five-second read timeout, the caller failed to receive cancellation within 500 ms. State termination now queues cleanup on the collection worker and finishes without awaiting that native operation. The same behavior applies to explicit iterator disposal and observer errors. A native call that never returns can still retain its resources and block that collection lane; the SDK does not forcibly interrupt native code.

A separate registration/cancellation test exposed a missed subscription handoff: native registration returned a resource, but cancellation won the caller's await before that resource was assigned to the producer's local variable. The context retained the resource until closure instead of releasing it for the canceled watch. The producer now records the returned subscription independently of its await and uses an atomic release request/exchange to transfer cleanup ownership exactly once. A late return and the producer's finally path can both request release without duplicating it.

These corrections extend the preceding sensor-stream lifetime approach to state streams. They do not change get/watch payloads, polling intervals, read deadlines, error types or field nullability.

## Stream and native cleanup contract

`DisposeAsync` ends that iterator's SDK collection and schedules native cleanup; it is not a native-cleanup completion barrier. Caller cancellation and observer errors likewise finish without waiting for a held native disposer. Applications can keep processing while cleanup remains queued or running. Context disposal remains nonjoining, and the collector worker owns remaining tracked resources.

Late state callbacks cannot enqueue another native read after termination. Cleanup failures remain contained by the existing worker cleanup path. A new request can use the same context after the held native operation finishes. The four new scenarios verify public `DeviceAccess.Watch`, cancellation, observer failure and `IDeviceCollector` ownership boundaries rather than private producer fields.

| Scenario | Evidence |
| --- | --- |
| Cancellation during held cleanup | Pending MoveNext receives cancellation within 500 ms while the native disposer remains held; host timer advances; exactly one release runs on the registration worker; later Get succeeds |
| Registration/cancellation handoff | 128 watches in one still-open context each release their own returned native subscription; no duplicate/missing release; final Get remains available |
| Explicit disposal during held cleanup | DisposeAsync finishes before native release; a deliberately late callback performs no subsequent collection; cleanup completes on its original worker |
| Observer error during held cleanup | PermissionDenied reaches the pending consumer before native release; late callbacks are rejected; clearing the provider slot permits an independent later Get |

## Existing native evidence

The first complete run passed 123/129. Six existing Windows tests failed because they asserted native removal immediately after iterator completion. The direct state-event test had the same assumption in an earlier focused run. These checks now wait for observable native-boundary completion, bounded to two seconds, before retaining the original registration/removal counts, native result-code, reference and thread assertions. Similar immediate assumptions in power, individual/aggregate battery, connectivity, performance and Wi-Fi paths were updated consistently.

The final 129-case run retains actual Windows power current-setting callbacks/unregistration, aggregate battery ReportUpdated registration/removal, network-path and performance native status registration/removal, existing native collector field checks and held-native deadline/cancellation evidence. The test completion helper is test-only; it adds no SDK polling or timers.

## Verification artifacts and limits

Local ignored logs: `.tools/dotnet-state-cleanup-{red,green}.log`, `.tools/dotnet-state-registration-{red,green}.log`, `.tools/dotnet-state-lifetime-related.log`, the initial complete `.tools/dotnet-state-lifetime-full.log`, and the final `.tools/dotnet-state-lifetime-full-green.log`. The related state subset passes 10/10 and the final complete run passes 129/129.

Held cleanup and registration races use controlled native-boundary fixtures. The 128 repetitions provide observed race coverage, not an exhaustive proof of all scheduler interleavings. Actual UI synchronization contexts, additional held-registration/error interleavings, overload and normalization races, physical sensor/permission/lifecycle integration, native Windows sensor collectors, external package consumption and the full OS/architecture/platform matrix remain required. Other-language and browser suites were not rerun for these .NET-only changes. The full SDK goal remains active.
