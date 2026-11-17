# Swift app-observed permissions — 2026-11-17

Scope: common permission status inputs, passive checks, explicit app-coordinated requests and their lifetimes. The full objective remains all 46 entities, every field, all bindings and the platform/acceptance matrices.

This is a historical checkpoint. The subsequent [sensor-source checkpoint](2026-11-17-swift-sensor-sources.md) adds app-owned sensor collection and raises the Debug/Release suite to 61 tests.

## Environment and results

Swift 5.9.2 on Ubuntu 22.04 x86_64 under WSL. Debug and Release each pass **51/51 public-API tests**, with warnings treated as errors and no compiler diagnostics. Seven [permission tests](../../swift/Tests/DeviceReadoutTests/PermissionTests.swift) extend the preceding 44 cases. Native boundaries and permission UI are controlled application/collector seams; no Apple SDK or physical device is used.

```sh
sh tools/test-swift.sh -Xswiftc -warnings-as-errors
sh tools/test-swift.sh -c release -Xswiftc -warnings-as-errors
```

Set `SWIFT_BIN` when the toolchain is outside PATH. Ignored final logs: `.tools/swift-permissions-full.log` and `.tools/swift-permissions-release.log`. Other bindings were not rerun for this Swift-only change.

## Public behavior exercised

| Contract | Evidence |
| --- | --- |
| App-observed checks | Fresh state is nil. Kind defaults are inherited, but an explicit target status, including nil, overrides the kind. All five typed statuses are preserved across configured views. No native read is needed. |
| Explicit requests | Only `permissions.request` invokes the registered app coordinator. Non-granted requests without a coordinator report UnsupportedEntity. An already-granted request returns without a coordinator. The coordinator receives kind, target ID and app/native namespace. |
| Response waiting | A coordinator can return before publishing a result. The request waits 80ms with a 1ms read timeout, then completes from an observed grant. Callback completion does not imply a grant. |
| Cancellation isolation | Caller cancellation, target removal and context closure each finish before a deliberately held application cancellation handler returns. Cancellation handlers run away from the main thread. |
| Native collection isolation | A synchronous collector is held while the app coordinator dispatches to MainActor and publishes a grant. The permission request completes before native collection returns. |
| Scope and generations | Same-ID native and app targets have independent concurrent requests. A kind grant finishes only the target that inherits it; an explicit nil app override waits for its own response. A replacement target does not inherit its retired predecessor's denied status. Removed, foreign-context and closed-context handles are rejected. |
| Coordinator ownership | Duplicate registration reports InvalidConfiguration. Closing an old registration does not remove its replacement. Closing the context releases unused callback captures while the registration handle remains alive. |
| Error and prompt behavior | Typed app errors are retained; unexpected errors become ReadFailed. A synchronous observer response wins over a later callback error. Check/get/watch/list/current do not invoke the coordinator. |

## Reproduced failures and implementation

The status/check and request tests first failed compilation because their public APIs were absent. The lifetime test then reproduced an unused app coordinator remaining retained after context closure; its captured object's release expectation timed out. Context closure now releases permission state and unused coordinator captures on a background queue independently of native collection.

Permission state is shared by immutable configured views and keyed by the existing context-owned target generation and namespace. Explicit nil is stored as a value rather than deletion. Requests install their response listener before invoking app code, so synchronous publication is retained. State publication selects applicable listeners and claims their results before releasing the lifetime gate. Target validity is rechecked at response acceptance; notifications and task cancellation run outside locks.

The coordinator runs on a detached utility task. Only application code chooses a UI executor or opens a permission prompt. The SDK request has no read timer and never waits for the collection worker. Its caller can complete independently of a held coordinator or cancellation handler; cancellation of app work is scheduled on a background queue and remains cooperative.

The isolation, scope, error and replacement cases passed as follow-up characterization checks; they are not additional reproduced-defect claims. The full suite retains earlier discovery, failure, source handoff, queue bounds, timeout and snapshot-stream tests.

## API semantics and remaining work

`PermissionStatus` has granted, denied, notDetermined, restricted and unavailable; unreadable state is nil. Permission inspection remains distinct from whole-operation errors and field availability. An adapter supplies PermissionDenied through its failure source only when the operation as a whole cannot run.

Retain the `PermissionCoordinatorRegistration` for as long as future requests should use it. Its close/deinitialization unregisters future calls; already-dispatched calls retain their captured coordinator. A request returns the first applicable observed status, including nil. Removing a target or closing the context ends pending requests; ordinary coordinator unregistration alone does not terminate them.

Still required: actual Apple permission and UI adapters/builds, lifecycle/activity inputs and integration, native event/inventory observation, capabilities, sensor sources/descriptions/sampling, remaining structured/ratio normalization, Apple collectors, external package consumption and the full physical/platform matrix. These tests do not establish iOS/macOS support, forced interruption of app/native code, zero host overhead or process/crash isolation.
