# Swift context closure and work admission — 2026-11-17

Scope: shared Swift context lifetime, caller completion and bounded native read admission. The complete SDK objective remains all specified entities, fields, bindings and support/acceptance matrices.

## Environment and verification

Swift 5.9.2 on Ubuntu 22.04 x86_64 under WSL. Debug and Release both pass **22/22 public-API tests**, with compiler warnings treated as errors. Five context tests extend the prior seventeen read/state/discovery tests. Native boundaries are controlled `DeviceCollector` implementations; no Apple collector or physical device is used.

```sh
sh tools/test-swift.sh -Xswiftc -warnings-as-errors
sh tools/test-swift.sh -c release -Xswiftc -warnings-as-errors
```

Use `SWIFT_BIN` for a toolchain outside PATH. Ignored local evidence: `.tools/swift-context-full.log` and `.tools/swift-context-release.log`. Other language/platform suites were not rerun for this Swift-only runtime change.

## Public scenarios

| Scenario | Evidence |
| --- | --- |
| Shared context closure | Closing one configured view finishes a held get through another view with EntityRemoved; later get/list/current reject work; repeated close schedules native cleanup once and off the main thread |
| Sleeping watch and held cleanup | A thirty-second polling watch ends promptly on close while native cleanup remains held; a stream created earlier cannot start after closure; a controlled cleanup exception stays contained |
| Bounded work and recovery | With one native read held, 256 additional requests produce explicit ReadFailed overload errors; canceling accepted queued requests prevents source invocation, and a fresh read works after release |
| Held discovery | Both list and current finish with EntityRemoved before their native boundary returns; cleanup runs once after release |
| Saturated closure | Closing a full queue finishes held and queued callers without waiting for native return; cleanup still runs once when the native call is released, and queued work does not invoke the source |

Tests use a one-second fail-safe release for held native calls. Caller completion must occur within 500 ms, or 400 ms for the sleeping-watch case, while the native boundary has not returned. Main-actor callers and off-main native execution/cleanup assertions cover this portable execution boundary; they are not an actual Apple UI test.

## Reproduced failures

The initial close test failed to compile because the API was missing. After read closure was implemented, a sleeping-watch test failed: the stream waited for its thirty-second polling delay and was canceled by its 500 ms fail-safe. Watches now register a context-close signal tied to their iterator lifetime.

The overload test then failed because all requests entered an unbounded native queue. A serial collection worker now admits at most 128 waiting reads in addition to an executing read and reports ReadFailed when full. Follow-up discovery and saturated-cleanup cases characterize the resulting behavior.

## Lifetime and queue contract

Immutable configured views share one context. `close()` is idempotent, completes SDK callers and stops producers without joining native work. Valid later requests fail with EntityRemoved. Native `DeviceCollector.close()` is scheduled once on the same serial collection lane, after preceding work returns; its errors do not escape into the host. Close is not a native-cleanup completion barrier.

Prepared result acceptance and registry-map replacement are serialized with the context's closed state. Continuation resumption, delivery notifications, collection and native cleanup execute outside control locks. Close listeners are SDK control signals, not arbitrary native cleanup callbacks.

Canceled queue entries are skipped when dequeued, but retain their queue slots until then. A blocked native call can therefore keep the lane saturated. Cleanup has a separate admission path so owned resources are not abandoned solely because reads filled the queue. Existing delivery buffers retain their documented drain-before-error behavior; the producer stops without waiting for that drain.

## Remaining requirements

Apple collectors/builds and actual UI/physical tests, app-owned target/display/permission/lifecycle observers, native hotplug and state-event supplementation, sensor streams/metadata and sampling, capability/permission APIs, remaining value normalization, external package consumption and the complete support/acceptance matrix remain required. Native calls are not forcibly interrupted and this work does not establish process/crash isolation or zero overhead.
