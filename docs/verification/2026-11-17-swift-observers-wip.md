# Swift observer work in progress — 2026-11-17

This record describes the source uploaded at the user's request, including the unfinished observer regression. It is not a release-readiness claim.

Historical checkpoint: commit `0b078395d30d10bac51edc5b3a0533944a79b091`. The subsequent [state-observer checkpoint](2026-11-17-swift-state-observers.md) fixes the first-value regression and passes 32 Debug/Release tests. The results below describe the upload-time source.

## Implemented and exercised

- `DeviceAccess.observers.target(Entity, id:)` registers typed app-owned state targets in a separate identity namespace from native discovery.
- `observers.publish(entity, snapshot:)` supplies state without calling a native getter. Immutable configuration views share these inputs.
- Observed watch subscriptions deliver the cached initial value and each later publication, including duplicate values, without waiting for the polling interval. Waiting between publications does not expire the read timeout.
- The existing context, worker admission, state polling and discovery tests remain in the suite.

## Current verification

Environment: Swift 5.9.2, Ubuntu 22.04 under WSL. No Apple host or SDK was used.

Command from the repository root, with `SWIFT_BIN` set to the local Swift 5.9.2 executable:

```sh
sh tools/test-swift.sh -Xswiftc -warnings-as-errors
```

The Debug build completes. Of 25 test cases, 24 pass and one fails with three assertions. The failing case is `ObserverTests.testInitialObservedReadsWaitForPublicationAndKeepTheirDeadline`:

1. A get started before the first app publication returns `ReadFailed` instead of waiting for that publication.
2. A get for an unpublished target returns `ReadFailed` instead of the configured `ReadTimeout`.
3. A watch for an unpublished target does not enforce the first-value deadline and reaches the test's cancellation fail-safe.

These are known implementation gaps, not unexpected new regressions from uploading. The test remains enabled. Current Release tests were not rerun; the preceding context checkpoint passed 22 tests in both Debug and Release.

## Remaining work

Implement first-publication waiting within the read deadline without occupying or joining the native worker. Subsequent event waiting must remain unlimited, with cancellation and context closure releasing subscriptions independently of blocked native work.

Complete app-current selection, removal and generation handling, failure/permission/lifecycle inputs, source handoff, sensor sources, remaining normalization, Apple collectors and the full platform/physical acceptance matrix. This portable Swift checkpoint does not establish iOS or macOS support and does not promise process isolation or forced interruption of native code.
