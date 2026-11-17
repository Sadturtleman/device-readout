# DeviceReadout for Swift

Initial Swift Package Manager foundation. The package declares iOS 16 and macOS 13 deployment targets, but Apple builds and native collectors have not yet been verified or implemented.

**Observer work in progress:** `access.observers.target(Entity, id:)` registers an app-owned state target, and `access.observers.publish(entity, snapshot:)` supplies its value without a native getter. App and native handles with the same ID remain distinct. Observed watches deliver each publication, including equal values, independently of the polling interval. Initial-value waiting is unfinished: get on an unpublished target fails immediately and watch does not yet apply its initial read deadline. See the [current verification record](../docs/verification/2026-11-17-swift-observers-wip.md).

The shared schema generates all 46 snapshot types, nullable fields, enums and typed `Entities` constants. `DeviceAccess(collector:)` accepts an explicit collector and provides asynchronous `get(Entity)` on a serial utility queue. `withReadTimeout` returns a new configuration sharing the collector and queue; its default is five seconds. Timeout and caller cancellation complete independently of a blocked collector, and late results are discarded. `collectedAt` is stamped when the snapshot is assembled. Non-finite scalar numbers and negative duration fields become `nil`; valid zero and false values remain intact.

`watch(Entity)` returns a cold `DeviceStream<Snapshot>` for singleton or discovered state entities. Iteration performs an immediate read, then serial polling with a default one-second delay after each read. `withPollInterval` creates an independent immutable configuration. Equal values are delivered again with fresh timestamps. Breaking iteration or canceling its task stops that subscription; read failures terminate without retry. The delivery buffer holds at most 2048 pending snapshots; overflow ends collection with `ReadFailed` after already accepted snapshots are consumed. Waiting for a poll does not consume the read timeout.

`list(Entity)` and resource collections such as `storageVolumes.list()` return typed handles. `current(Entity)` uses the collector's explicit current selection; no selection returns nil without choosing the first device. Handles can be reused across configured views of the same context, but a separate `DeviceAccess` rejects them. Repeated discovery preserves identity until removal is detected. Accepted inventory removal or a read-time `EntityRemoved` retires that generation and ends its existing watches, including watches waiting for a long poll interval. Rediscovery creates a fresh handle even if the native ID is reused. Failed, malformed, canceled and timed-out inventories do not erase the last accepted handles.

Collections include `displays`, `viewports`, `cpuCores`, `batteries`, `networkInterfaces`, `wifiConnections`, `cellularSubscriptions`, `telephonyIdentities`, `storageVolumes`, and typed `sensors.list(Entity)`. These are generic discovery APIs, not native platform collectors. Native source IDs appear at the `DeviceCollector` boundary; consumers use the returned entity handles.

`close()` ends the shared context, including configured views, pending reads/discovery and idle state watches. It is idempotent and does not await native work or cleanup. Valid queries after closure fail with `EntityRemoved`; streams created earlier also reject later iteration. `DeviceCollector.close()` is scheduled once on the collection worker after preceding native work returns. Cleanup errors are contained on that worker. Already accepted stream buffers retain the existing drain-before-error behavior.

The worker admits at most 128 waiting reads in addition to any currently executing read. Excess requests fail with `ReadFailed`. Canceled or closed queued requests are skipped before invoking the source. Cleanup bypasses read admission, so a full queue cannot suppress resource release. Canceled queue entries retain their slots until the worker reaches them; a blocked native call can therefore leave the lane saturated until it returns.

There is no bundled Apple collector. A consumer must provide a `DeviceCollector`; the tests use controlled collectors rather than hardware readings. Autonomous native hotplug/state notifications, sensor streams/sampling settings, app-owned target and UI/permission/lifecycle observers, capabilities, permission coordination and remaining structured/ratio normalization are still required. A timeout or context closure does not forcibly interrupt an uncooperative synchronous collector. Current sensor watches report `UnsupportedEntity` rather than fabricating samples by polling.

Generate and test from the repository root with Node and Swift available:

```sh
npm run generate
sh tools/test-swift.sh -Xswiftc -warnings-as-errors
sh tools/test-swift.sh -c release -Xswiftc -warnings-as-errors
```

`SWIFT_BIN` may point to a specific Swift executable. The test script keeps build/cache artifacts in the ignored `.tools` directory. Root `npm run generate` runs all five language generators; `node tools/generate-swift.mjs` regenerates only Swift.

The current upload-time Debug run on Swift 5.9.2 / Ubuntu 22.04 under WSL passes 24 of 25 tests; one initial-observer regression test reports three failing assertions. Current Release tests have not been rerun. The preceding twenty-two-test context checkpoint passed Debug and Release with compiler warnings treated as errors. See [context lifetime verification](../docs/verification/2026-11-17-swift-context-lifetime.md), [target discovery](../docs/verification/2026-11-17-swift-discovery.md), [state streams](../docs/verification/2026-11-17-swift-state-streams.md) and the [foundation checkpoint](../docs/verification/2026-11-17-swift-foundation.md). This evidence does not establish iOS/macOS support or the full acceptance matrix.
