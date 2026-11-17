# Swift observer failures and provider ownership — 2026-11-17

Scope: typed application errors, target/kind scope, independent provider ownership and invalidation of work crossing a failure. The complete objective remains all entities, fields, bindings and platform/acceptance matrices.

This is a historical checkpoint. The subsequent [Swift permissions checkpoint](2026-11-17-swift-permissions.md) adds app-observed permission checks and explicit requests, raising the Debug/Release suite to 51 tests.

## Environment and results

Swift 5.9.2 on Ubuntu 22.04 x86_64 under WSL. Debug and Release each pass **44/44 public-API tests**, with compiler warnings treated as errors and no compiler diagnostics. Six observer-failure tests extend the preceding 38 cases. Native boundaries are controlled collectors; no Apple SDK or physical device is used.

```sh
sh tools/test-swift.sh -Xswiftc -warnings-as-errors
sh tools/test-swift.sh -c release -Xswiftc -warnings-as-errors
```

Set `SWIFT_BIN` when the toolchain is outside PATH. Ignored logs: `.tools/swift-observer-failures-full.log` and `.tools/swift-observer-failures-release.log`. Other bindings were not rerun for this Swift-only change.

## Public behavior exercised

| Contract | Evidence |
| --- | --- |
| Typed failure and recovery | An observed Ram watch receives the supplied PermissionDenied. New get calls receive the same error. Clearing it leaves earlier app state invalid; get waits for new publication and can time out, without falling back to the native getter. |
| Target/kind scope | A failed app display leaves a same-ID native display and another app display usable. A kind failure covers targets and list/current. Clearing kind failure preserves an exact target error and does not retire target generations/current selection. |
| Held native work | Get, list and current each finish on failure before their held collector returns, using both direct errors and independent sources. Immediate direct clear or source close cannot turn the old query into success. Late empty discovery does not erase accepted handles. |
| Provider independence | Registration is inert and leaves native collection usable. Clearing one source retains another's error; closing one source retains another source and direct app policy. Closed sources reject publication. Clearing all errors does not restore stale app state. |
| App policy precedence | A later provider update cannot replace a direct application error. Exact app errors precede kind app errors; provider slots preserve their own activation ordering. |
| Idle native watch | An error source ends a watch waiting on a 30-second poll interval immediately. Clearing the source allows a fresh native get and does not take ownership of its state. |
| Generation/context lifetime | An old app target's source does not fail the same-ID native target or a new app generation. Removed targets, foreign contexts and closed contexts reject invalid source operations. Source close remains safe and idempotent after context closure. |

The full suite retains the earlier state, source-handoff, target discovery, cancellation, timeout, overflow and bounded-work tests.

## Failures reproduced and changes

The direct failure and independent-source tests first failed compilation because their APIs were absent. After adding direct errors, the kind-scope test reproduced list/current returning normally while the kind was failed. Discovery now registers the same failure signals and validates failure history before accepting a result or changing the inventory.

The policy-precedence regression reproduced a newer provider ReadFailed masking an application's PermissionDenied. Selection now follows the established binding order: exact direct error, kind direct error, exact provider errors, then kind provider errors. An active provider keeps its activation order across updates; clearing and reactivating it starts a new activation.

Queries capture failure ordering before source selection. Registered SDK signals finish operations independently of the collection worker. Acceptance also checks failure history under the context lifetime gate, so a failure followed by immediate recovery cannot commit old work. Clearing an error does not delete that history for reads already in progress.

Observed value ownership is separate from its latest snapshot. Failure clears prior values and ends subscriptions while retaining ownership; recovery cannot silently fall back to native state. Notifications run after releasing the lifetime gate. Failure-source closure clears only that source's active slot, and never reinstates invalidated values or streams.

Held-native, idle-watch and source-generation cases passed as follow-up characterization checks; they are not separate reproduced-defect claims.

## Remaining scope and limits

These inputs represent whole-operation failures. Partial unavailable fields still use nil. Reporting PermissionDenied here does not request permission or implement permission-status observation.

Still required: permission checks/requests through an app coordinator, lifecycle/activity integration, capabilities, native event/inventory adapters, sensor sources/descriptions/sampling, remaining structured/ratio normalization, Apple collectors and Apple builds, independent package consumption and the full physical/platform matrix. Error completion does not forcibly interrupt native code or provide process/crash isolation. Native collection and normalization retain the existing worker admission and timeout limits.
