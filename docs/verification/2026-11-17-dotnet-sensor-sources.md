# .NET application sensor sources and lifecycle

Recorded on 2026-11-17 (Asia/Seoul), using Windows 11 Home x64 build 26300, .NET SDK 10.0.403 and runtime 10.0.14. The final complete .NET/Windows run passes **121/121**, with zero build warnings or errors. This follows the [115-case observer/cancellation checkpoint](2026-11-17-dotnet-observer-cancellation.md).

## Public API

`access.Observers.SensorSource(sensor, subscribe, description)` registers an application sensor source and returns `IDisposable`. The sensor must be an app-registered sensor target; ordinary state entities and duplicate registrations are rejected. Registration, discovery, capability checks and `Describe` do not start measurement. The supplied metadata retains the entity's actual sensor kind and is normalized/stamped on the worker.

`subscribe` receives a typed `SensorObserverSession<T>` with `SamplingRate`, `CancellationToken`, `Publish(T)` and `Fail(DeviceReadoutException)`. Each active request has its own session. The callback and returned cleanup run on the collector worker; callback code must use the application's dispatcher if its platform requires UI-thread registration. SDK calls do not query UI or request permission. Snapshot normalization and `CollectedAt` remain worker-owned.

Get uses platform-default sampling. Continuous Watch uses its own immutable configuration's requested rate, while event Watch uses the platform default. Samples are not synthesized or deduplicated. A session failure ends only that observation; application/provider-wide failure inputs retain their separate scope. Disposing the source permanently retires its target and ends its observations. A replacement needs a new target identity.

`access.Observers.SensorActivity(active)` receives the application's activity policy; the default is active. An inactive sensor Watch retains its subscription intent without a first-sample timer or active native session. Resume creates a fresh session with the original watch settings. Stale session samples are ignored. Get retains its overall read deadline while inactive. State queries remain available. Desktop focus loss alone does not trigger SDK inactivity; the app chooses when to publish a transition.

An event Watch waits for a real event without a first-event deadline after registration. An event Get still has its overall read deadline. Observer errors and target removal can terminate watches even while inactive.

## Execution and resource ownership

A separate sensor pump processes lifecycle changes while the application is between stream reads. Each active generation has its own cancellation scope and input queue. Native registration, normalization and cleanup stay on the existing worker. Cancellation scopes preserve the preceding nonblocking native-callback contract. Get waits for the iterator's canceled move to finish before disposing that iterator, preserving `OperationCanceledException` rather than leaking `NotSupportedException`.

Registration result ownership is recorded independently from completion of the caller's await. An atomic handoff releases a subscription even when cancellation wins immediately after native setup returns. If setup is still blocked, caller deadlines and context disposal finish first; a late resource is released on the worker after setup returns. Source removal and registration state retirement occur together under the collector's synchronization gate.

Per sensor watch, lifecycle input is bounded to 64 entries, sample input to 2048 and output to 2048. Saturation reports ReadFailed. Existing state streams retain their own queues and polling behavior. These bounds do not constitute a completed overload/concurrency audit.

## Six added scenarios

| Public-boundary scenario | Evidence |
| --- | --- |
| Passive registration and independent get/watch demand | Metadata/capabilities start no source; get uses platform default; watch requests 60 Hz; equal values remain observable; source removal retires the handle |
| Lifecycle suspension/resume | Inactive get times out; watch waits beyond its 100 ms setting without registration; pause releases resources even between consumer reads; resume creates a new 55 Hz session; inactive permission failure ends the stream |
| Caller cancellation | Correct cancellation exception and session cleanup; a later get needs a fresh sample; the case repeats 24 times to exercise registration-completion races |
| Scoped failure/deadline | One source session's PermissionDenied and another request's timeout leave a sibling watch alive; an invalid vector becomes one null value on the worker |
| Event source | No fabricated initial event or watch timeout; no numeric sampling request; one-shot event timeout releases only its session; removal ends the pending watch |
| Blocked registration | An explicitly held subscribe callback does not prevent the 100 ms caller deadline, host timer progress or context disposal; its late cleanup executes on the same collector worker |

Initial source/lifecycle tests failed because their public APIs were absent. Cancellation testing then reproduced iterator disposal during an unfinished move. The first full run additionally exposed a missed subscription handoff: the caller canceled successfully but native session cleanup never arrived. The iterator completion and atomic ownership corrections resolve both failures; the final full run includes all six scenarios and the existing native Windows checks.

## Verification

The final command was `tools/test-dotnet.ps1` without a filter. Focused runs used `-Filter` for individual sensor-source cases. Local logs include `.tools/dotnet-sensor-source-{red,green,full}.log`, `.tools/dotnet-sensor-lifecycle-{red,green}.log`, `.tools/dotnet-sensor-cancel-{red,green,race}.log`, `.tools/dotnet-sensor-scoped.log`, `.tools/dotnet-sensor-event.log` and `.tools/dotnet-sensor-registration.log`. These are ignored local artifacts.

## Remaining scope

Source samples, app activity and blocked registration use controlled public-boundary fixtures. Native Windows sensor enumeration/measurements, physical permission/lifecycle integration, all sensor kinds on hardware, source replacement/overload stress, additional reentrant and normalized-sample invalidation races, native/app target namespace separation and external package consumption remain required. Ordinary state registration/cancellation handoff also needs a broader audit. No Apple, Android, Flutter, RN or browser tests were rerun for these .NET-only changes. The full SDK objective and support matrix remain unchanged.
