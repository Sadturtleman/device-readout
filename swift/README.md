# DeviceReadout for Swift

Initial Swift Package Manager foundation. The package declares iOS 16 and macOS 13 deployment targets, but Apple builds and native collectors have not yet been verified or implemented.

The shared schema generates all 46 snapshot types, nullable fields, enums and typed `Entities` constants. `DeviceAccess(collector:)` accepts an explicit collector and provides asynchronous `get(Entity)` on a serial utility queue. `withReadTimeout` returns a new configuration sharing the collector and queue; its default is five seconds. Timeout and caller cancellation complete independently of a blocked collector, and late results are discarded. `collectedAt` is stamped when the snapshot is assembled.

There is no bundled Apple collector. A consumer must provide a `DeviceCollector`; the tests use controlled collectors rather than hardware readings. Target discovery, watch streams, poll/sampling settings, observers, capabilities, permission coordination, value normalization, bounded work admission and context closure are still required. A timeout does not interrupt an uncooperative synchronous collector; later reads share that queue and may also time out.

Generate and test from the repository root with Node and Swift available:

```sh
node tools/generate-swift.mjs
sh tools/test-swift.sh
```

`SWIFT_BIN` may point to a specific Swift executable. The test script keeps build/cache artifacts in the ignored `.tools` directory. Root `npm run generate` currently covers the other four language generators; run the Swift command explicitly.

Swift 5.9.2 on Ubuntu 22.04 under WSL passes all three current public-API tests. See [verification details](../docs/verification/2026-11-17-swift-foundation.md). This evidence does not establish iOS/macOS support or the full acceptance matrix.
