# Swift support queries and sensor activity verification — 2026-11-17

Scope: passive typed capability queries, permission separation, target ownership, independent native-query completion and further sensor activity contracts. The full 46-entity, binding and acceptance scope remains incomplete.

This historical checkpoint precedes the [normalization checkpoint](2026-11-17-swift-normalization.md), which raises the full Swift suite to 81 tests. Counts and remaining scope below describe this earlier checkpoint.

## Environment and results

Swift 5.9.2 on Ubuntu 22.04 x86_64 under WSL passes **75/75 public-API tests in both Debug and Release**, with warnings treated as errors and no compiler diagnostics. Seven [capability tests](../../swift/Tests/DeviceReadoutTests/CapabilityTests.swift) and two additional [sensor-activity tests](../../swift/Tests/DeviceReadoutTests/SensorActivityTests.swift) extend the preceding 66 cases. Sources, collectors and held native boundaries are controlled fixtures. No Apple SDK or physical sensor was used; other language/platform suites were not rerun for this Swift-only change.

```sh
sh tools/test-swift.sh --jobs 2 -Xswiftc -warnings-as-errors
sh tools/test-swift.sh --jobs 2 -c release -Xswiftc -warnings-as-errors
```

Full logs are retained locally in ignored `.tools/swift-capabilities-full.log` and `.tools/swift-capabilities-release.log`. Test execution took 4.644 and 5.626 seconds respectively, excluding compilation. Some WSL launches reported a systemd user-session startup warning; the same processes completed successfully.

## Public contract

`access.capabilities.get(entity)` returns `EntityCapabilities` with nullable `readable` and `watchable` Boolean fields. These describe support for operations, not permission or complete field coverage. False means unavailable; nil means the provider cannot determine support. Singletons, unbound multi-target kinds and typed target handles are accepted.

Native state metadata comes from `DeviceCollector.capabilities(EntityRequest)` on the collection worker. The default returns nil/nil without reading state. Native calls use the configured timeout, cancellation, bounded worker admission and context lifetime. Typed provider errors are preserved, unexpected errors become ReadFailed and CancellationError remains cancellation.

Known app support is read from SDK-owned metadata without calling the collector or starting a sensor. Registered app state targets can receive future values. Observed singleton ownership survives cache invalidation. An explicitly app-owned state kind is available when its inventory is nonempty. Sensor support requires a registered source; a sensor target alone does not imply collection support, and native sensor execution remains unconnected in this runtime. Activity suspension and permission denial do not remove support.

Removed targets return false/false. Foreign handles are InvalidConfiguration; closed contexts are EntityRemoved. App/native namespaces and target generations remain distinct. A late native answer or provider failure yields to app support registered during that query; timeout and cancellation remain terminal. An already-running native query is not forcibly interrupted when app ownership changes.

## Evidence

| Contract | Observed result |
|---|---|
| Native singleton, kind and bound-target queries | Values and nil defaults preserved; collector runs off the main thread and does not probe state |
| Permission and observation failure separation | Support remains readable while get is PermissionDenied; coordinator is never invoked |
| App state/sensor registrations | Empty inventories, future state input, invalidated cache, inactive sensors, missing sources and removal produce the expected support |
| Held native query | Timeout, caller cancellation, removal and context closure complete before native return; app metadata remains queryable |
| Namespace and generation | Same-ID app/native targets remain distinct; foreign handles are rejected; old registrations cannot remove replacement support |
| Provider errors | Typed errors and cancellation preserved; unexpected errors wrapped |
| App ownership during native query | Fresh app support supersedes both a late unavailable answer and a late native failure |

Additional activity evidence covers eight combinations of get/watch and inactive cancellation, permission failure, source removal or context closure. An immediately cleared failure still ends the affected demand; reactivation does not restart it. A two-consumer test verifies independent cancellation and sampling settings, idempotent activity inputs, preserved duplicate values and per-session cleanup across pause/resume.

The initial capability test failed because the API was missing. Follow-up failing slices reproduced permission failures suppressing support, missing app-owned metadata/removal handling, worker cancellation wrapped as ReadFailed, and a late native error escaping after app ownership changed. The held-query, identity and additional activity cases passed as characterization checks; they are not separate reproduced-defect claims.

## Remaining scope

Apple collectors/builds, framework UI/permission/lifecycle adapters, remaining structured/ratio normalization and coordinate conversion, native state/inventory notifications, external package consumption and the physical/version/platform matrices remain required. Native capability metadata needs adapter-specific evidence when collectors are implemented. Broader simultaneous handoff/deadline races, activity overload and transport saturation are not established by these tests.

An uncooperative native call continues occupying its serial worker until return. Independent caller completion and short metadata lookups do not promise zero CPU cost, forced native interruption or process-crash isolation.
