# Swift state-watch handoff and singleton removal — 2026-11-17

Scope: switching an existing native polling stream to app-published state, preserving ordering/deadlines, and removing a singleton within one DeviceAccess context. The complete SDK objective remains all entities, fields, bindings and support/acceptance matrices.

The subsequent [observer-failure checkpoint](2026-11-17-swift-observer-failures.md) extends this scope to 44 Debug/Release tests. The results and remaining-work list below describe the earlier 38-test checkpoint.

## Environment and verification

Swift 5.9.2 on Ubuntu 22.04 x86_64 under WSL. Debug and Release each pass **38/38 public-API tests**, with warnings treated as errors and no compiler diagnostics. Four handoff tests and two singleton tests extend the prior 32 cases. Native boundaries use controlled collectors; no Apple SDK or physical device was used.

```sh
sh tools/test-swift.sh -Xswiftc -warnings-as-errors
sh tools/test-swift.sh -c release -Xswiftc -warnings-as-errors
```

Set `SWIFT_BIN` to the desired Swift executable when it is outside PATH. Ignored logs: `.tools/swift-handoff-singletons-full.log` and `.tools/swift-handoff-singletons-release.log`. Other bindings were not rerun for this Swift-only change.

## Public behavior exercised

| Scenario | Evidence |
| --- | --- |
| Handoff during a long poll interval | A native first value followed by app publications yields 1, 2, 2, 3 with a 30-second polling interval. The app values arrive without a second native read, and event waiting outlives the configured read timeout. |
| Original first-read deadline | A first native call is held, and app state arrives 140ms into a 200ms deadline. Worker normalization remains blocked; the watch reports ReadTimeout at the original deadline instead of restarting another 200ms. |
| Late native success/failure | A second poll is held while the app publishes 2, 2, 3. After release, a native value of 999, PermissionDenied or EntityRemoved cannot enter or end the app stream. Native collection stops at two calls, and fresh get sees the latest app value. |
| Cancellation and context close during handoff | Both finish the watch before the held native call returns. Cancellation leaves cached app state usable by a fresh request. |
| Singleton removal | Removing Ram ends its observed watch, rejects future reads and ignores late publications. Duplicate removal is harmless; DeviceInfo and a separate context remain usable. |
| Held singleton get and handoff watch | Removing Ram finishes both operations before native return. Queued native reads never enter the source, and neither the eventual native result nor a late app publication revives the entity. |

The complete suite also retains the preceding overflow, polling, discovery, target-generation, bounded-worker and context-lifetime checks.

## Reproduced failures and implementation

The idle-handoff test first failed at its 500ms cancellation fail-safe because source selection was fixed when watch began. Each state watch now subscribes to app input before native collection. When the first publication arrives, it cancels its SDK polling task and consumes the app buffer in order. It does not join the actual native call. Acceptance of native output/error is serialized with app publication, preventing late native output from following the new source.

The initial-deadline test then reproduced a 340ms completion for a configured 200ms first read. The watch now keeps the original monotonic deadline until any first snapshot is delivered and gives handoff normalization only the remaining time. Later publications have their own read deadline for normalization; waiting for the next event has no read deadline.

Singleton removal initially threw InvalidConfiguration because removal required a bound target. The registry now stores singleton removal per context and registers the same independent SDK termination signals for singleton and bound-target reads. Late publications fail validation and are ignored. Singleton constants remain removed in that context; a separate context has its own state.

The late-native and held-completion cases passed as follow-up characterization checks. They are not separate reproduced-defect claims.

## Remaining work and limits

Native calls and snapshot normalization still share the collection worker. Canceling a native request ends its SDK wait but does not force the native function to return. App state queued behind that call can time out. This design does not provide process/crash isolation or zero overhead.

Still required: native state/inventory event adapters; complete typed failure, permission and lifecycle inputs; capabilities and explicit permission coordination; sensor sources, metadata and sampling; remaining structured/ratio normalization; Apple collectors and Apple builds; external package consumption and the complete physical/platform matrix. These portable tests do not establish iOS or macOS support.
