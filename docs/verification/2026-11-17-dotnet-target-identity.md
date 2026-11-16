# .NET native and app target identity

Recorded on 2026-11-17 (Asia/Seoul), on Windows 11 Home x64 build 26300 with .NET SDK 10.0.403 and runtime 10.0.14. The full `tools/test-dotnet.ps1` run passes **125/125**, with zero build warnings or errors. This follows the [121-case sensor-source checkpoint](2026-11-17-dotnet-sensor-sources.md).

## Defects reproduced

A native target returned by List and an app target registered with the same kind and ID previously shared one address. Publishing the app target then changed the value returned through the existing native handle. The first public-boundary test reproduced this through Display Get before the implementation change.

After addresses were separated, two permission requests still produced identical `PermissionRequest` records. The app coordinator could not distinguish their intended targets. A second failing test reproduced this independently. A third test showed that publishing an observed value on an existing native sensor handle allowed an application sensor source to replace that native handle.

## Resulting contract

Entity identity includes the owning context, kind, target ID and whether the target is app-observed. `EntityAddress.Observed` is false for native collectors and true for handles created by `Observers.Target`. Handle equality and hash-based collections retain this distinction. Snapshots and entity fields are unchanged.

DeviceAccess preserves complete addresses when returning List and Current handles. An app-owned inventory takes precedence for that kind; it is not merged with native discovery. Existing native handles remain usable. Explicit Current selection preserves either namespace. Removing the selected app target yields null Current and does not silently select a native target with the same ID. Publishing to a previously discovered native handle does not create an app-owned inventory.

`PermissionRequest` now carries `(Kind, TargetId, Observed)`, with Observed defaulting to false for explicit construction. Coordinators can route same-name requests using all three components. Target permission inputs and pending responses remain independent; family inputs preserve explicit target overrides. Both EntityAddress and PermissionRequest gain a positional record component, so consumers deconstructing the previous two-component records need updating. Treat this as a public API compatibility change when packaging this implementation.

Target-specific application/provider errors, failure history, metadata, capabilities and removal use the same complete identity. Family errors continue to apply to both namespaces. `Observers.Target` accepts an unbound multi-target kind, not an already bound handle. `Observers.SensorSource` requires an app-registered sensor target, including when a native handle has previously received an observer publication.

## Four public-boundary scenarios

| Scenario | Evidence |
| --- | --- |
| State and inventory identity | Native/app Display values and streams remain distinct; typed equality and hash membership distinguish them; List and explicit Current retain app/native identity; app removal leaves native reads and polling alive |
| Permission requests | Same-name requests differ at the coordinator boundary; app response finishes only its request; native status stays unchanged; later family status preserves both target overrides |
| Registration ownership | A published native sensor cannot acquire an app source; bound handles cannot be passed as a kind to Target; native publications preserve native discovery |
| Sensor identity and failure scope | Same-name descriptions, one-shot samples and watches retain their sources; app failure leaves native observation running; native failure leaves app collection available; family failure gates both; app source disposal leaves native metadata, collection and capabilities intact |

Native/app collisions use controlled `IDeviceCollector` and app sensor sources through the public DeviceAccess API. The full run also retains the existing actual Windows collector and held-native cancellation/deadline checks. No UI getter, permission prompt, extra timer or native collection is added to observer callbacks. Collection, normalization and subscription cleanup stay on the existing worker.

## Evidence and remaining scope

Focused logs are `.tools/dotnet-target-identity-{red,green}.log`, `.tools/dotnet-target-permission-{red,green}.log`, `.tools/dotnet-target-source-{red,green}.log` and `.tools/dotnet-target-sensor-scopes.log`. The complete run is `.tools/dotnet-target-identity-full.log`. These logs are ignored local artifacts.

This closes the same-name namespace gap recorded in the preceding .NET sensor-source checkpoint. Native Windows sensor collectors, physical sensor/permission/lifecycle integration, inventory changes during pending discovery, broader replacement/overload/normalization races, state-stream registration/cancellation handoff, external package consumption and the full OS/architecture matrix remain required. Browser, Kotlin, Dart, Flutter, React Native and Apple tests were not rerun for this .NET-only change. The full SDK goal remains active.
