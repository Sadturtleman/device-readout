# Swift state observer inputs — 2026-11-17

Scope: app-published state, initial deadlines, typed current selection and target removal. The complete objective remains all 46 entities, all specified fields and bindings, and the full support and acceptance matrices.

The subsequent [watch handoff and singleton checkpoint](2026-11-17-swift-watch-handoff.md) extends this scope to 38 Debug/Release tests. The results and remaining-work list below describe the earlier 32-test checkpoint.

## Environment and results

Swift 5.9.2 on Ubuntu 22.04 x86_64 under WSL. Debug and Release each pass **32/32 public-API tests**, with compiler warnings treated as errors and no compiler warnings or errors. Ten observer tests run alongside the preceding 22 read, state-stream, discovery and context tests. Native boundaries use controlled `DeviceCollector` implementations. No Apple SDK, Apple collector or physical device was used.

```sh
sh tools/test-swift.sh -Xswiftc -warnings-as-errors
sh tools/test-swift.sh -c release -Xswiftc -warnings-as-errors
```

Set `SWIFT_BIN` for a toolchain outside PATH. Ignored local logs: `.tools/swift-observers-full.log` and `.tools/swift-observers-release.log`. Other bindings were not rerun for this Swift runtime change.

## Behavior verified through the public API

| Contract | Evidence |
| --- | --- |
| Initial state and deadline | A get started before app publication waits for that value. An unpublished app target times out in both get and first watch delivery. Later event waiting outlives the read timeout. |
| Event delivery | Publications with values 1, 2, 2, 3 arrive in order with a 30-second polling interval; no native getter is invoked for that app state. |
| Shared context, separate identities | Configured views read the same app values. App and native targets with identical IDs keep separate handles and values; app discovery owns its inventory. |
| Current target | App inventory does not invoke a native current getter. Explicit app/native selection, clearing, empty inventory ownership and foreign-context rejection are covered. |
| Waiting leaves the worker available | A native singleton get completes on the same access while a separate app get waits for its first publication. |
| Independent completion | Get and watch each finish by cancellation, context close or timeout while an unrelated native read is held. Fresh requests still use the app source after cancellation or timeout. |
| Removal and replacement | Removal finishes unpublished get/watch, clears current selection, preserves the same-ID native target, and keeps the app inventory empty. Re-registering creates a distinct handle; old publications and duplicate removals do not change it. |
| Queued reads | Both app and native target gets waiting behind held native work finish on removal before the worker returns. |
| Executing native read | Removing a native target finishes its held get before the getter returns and preserves the same-ID app state. |
| Late discovery | Held native list/current calls begun before removal cannot recreate that target. A new discovery after removal creates a different generation, while the original remains invalid. |

## Reproduced failures and changes

The [upload-time checkpoint](2026-11-17-swift-observers-wip.md) had three failing assertions in its initial-value test: premature `ReadFailed` for get, the wrong timeout error, and an unbounded first watch wait. First-publication preparation now runs asynchronously under the same read operation as worker normalization. Completion cancels this preparation without joining native work. Subsequent watch event waiting remains outside the read deadline.

The queued-removal regression initially reached a 400ms cancellation fail-safe for both app and native targets. Each target get now registers an SDK removal signal before native/observed work; result completion and subscription release do not depend on the collection worker returning.

The late-discovery regression initially returned a recreated target from both list and current. Native discovery now captures removal ordering before calling its source and excludes IDs removed during that query. Retired generations remain invalid even if a prepared native map still references them. Later discovery can establish a fresh generation.

Current selection and removal first failed compilation because their public observer inputs were absent. Follow-up controlled checks for worker availability and executing-read removal passed after implementation; these are characterization evidence, not claims that separate defects were reproduced.

## Execution and remaining scope

The app supplies already-observed state. Registration, current selection and removal do not invoke screen APIs, permission prompts or native getters. Snapshot normalization and timestamp assembly stay on the worker. Initial publication waiting does not occupy that worker. SDK state changes use short locks, and removal completion signals run outside the lifetime gate. Removal, cancellation and context closure do not forcibly interrupt a blocked native call or provide process/crash isolation.

Still required: native event/inventory observation; handoff from an already-running native watch to newly app-published state; complete failure, permission and lifecycle inputs/adapters; singleton removal; sensor source/metadata/sampling APIs; capabilities and permission coordination; remaining structured/ratio normalization; Apple collectors and real Apple builds; external package consumption and the full physical/platform matrix. The observer API is not yet a complete Swift implementation of every cross-language contract.
