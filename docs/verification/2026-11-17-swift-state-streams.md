# Swift state-stream verification — 2026-11-17

Scope: portable Swift one-shot reads and untargeted state polling. The complete SDK scope remains all entities, fields, bindings and support/acceptance matrices.

## Environment and commands

Swift 5.9.2, Ubuntu 22.04 x86_64 under WSL. No Apple SDK or native hardware collector is used in this checkpoint.

```sh
npm run generate
sh tools/test-swift.sh -Xswiftc -warnings-as-errors
sh tools/test-swift.sh -c release -Xswiftc -warnings-as-errors
```

Set `SWIFT_BIN` to the toolchain executable when necessary. Both Debug and Release pass all ten public-API tests. The build treats compiler warnings as failures. All five language generators run; other generated language files have no content changes. Other platform suites were not rerun for this Swift-only runtime change.

## Evidence

- The existing read tests preserve nullable RAM fields, worker collection, timestamps, immutable deadlines, caller cancellation and late-result rejection.
- A new network read initially failed because NaN and a negative duration escaped into its snapshot. Scalar numbers now require finiteness and duration fields require nonnegative values; zero and false remain valid.
- State `watch` returns a cold typed sequence: constructing it performs no collection. Iteration performs an immediate read, even with a thirty-second polling interval.
- Equal snapshots are delivered again with fresh collection times. Polling is serial and waits the configured delay after each read. Breaking a loop stops its polling while the reusable sequence remains referenced.
- A fast configured view does not change an existing slow stream or its read timeout. The slow stream remains subscribed while idle beyond its individual read deadline.
- A held second poll preserves main-actor caller cancellation and independent `ReadTimeout`. Neither waits for native return. Releasing the collector allows a fresh read; the terminated stream does not retry or deliver a late result.
- A slow consumer fills the 2048-snapshot delivery buffer. Accepted values remain ordered, overflow stops collection, and the consumer receives `ReadFailed` after the accepted buffer drains. No implicit conflation or silent loss policy is applied.
- Zero and negative configuration intervals fail immediately with `InvalidConfiguration`; existing defaults remain unchanged.

The first watch test failed to compile because the API was missing, then passed after implementation. Follow-up lifecycle/configuration/overflow tests characterize the implemented behavior. The full warning gate exposed unnecessary escaped argument labels in generated Swift and was corrected. A test-only attempt to change an XCTest expectation after waiting caused an XCTest precondition failure; the corrected fixture never changes that property after waiting.

The implementation uses the Swift standard library's documented [AsyncThrowingStream buffering and termination behavior](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0314-async-stream.md). A separate iterator-owned lifetime cancels the producer on loop exit; delivery overflow is converted into the SDK's typed error.

## Remaining requirements

Native state notifications and mixed event/poll collection, typed targets and discovery, sensors and sampling, app-owned display/permission/lifecycle observers, capabilities, explicit permission coordination, ratio/structured normalization, bounded work admission and context closure remain required in Swift. Current sensor watches fail with `UnsupportedEntity`; they do not synthesize sensor events by polling.

No Apple native collectors or iOS/macOS builds were validated. Actual UI responsiveness, device measurements, exact minimum toolchain compatibility and the complete cross-platform acceptance matrix remain unproven. A blocked synchronous collector still occupies its worker until it returns; caller completion is independent, but subsequent operations on that worker may also time out. The work does not establish zero overhead or process/crash isolation.
