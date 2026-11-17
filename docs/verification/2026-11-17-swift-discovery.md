# Swift target discovery verification — 2026-11-17

Scope: portable Swift native-source discovery, current selection and target identity/lifetime. The SDK goal still includes every specified entity, field, binding and platform/acceptance matrix.

## Environment and result

Swift 5.9.2 on Ubuntu 22.04 x86_64 under WSL. Debug and Release both pass all **17 public-API tests**, with compiler warnings treated as errors. Seven target tests extend the earlier ten foundation/state-stream tests. Collectors in these tests are controlled public `DeviceCollector` implementations; they are not Apple APIs or real devices.

```sh
sh tools/test-swift.sh -Xswiftc -warnings-as-errors
sh tools/test-swift.sh -c release -Xswiftc -warnings-as-errors
```

Use `SWIFT_BIN` for a toolchain outside PATH. Local ignored logs are `.tools/swift-discovery-full.log` and `.tools/swift-discovery-release.log`. Other language/platform suites were not rerun for this Swift-only change.

## Public behavior

| Scenario | Evidence |
| --- | --- |
| Typed discovery | StorageVolume handles return matching snapshots through get, preserve equality/hash identity across repeated inventories, work with immutable configured views and are rejected by a different DeviceAccess context |
| Current selection | Native selection of the second target returns that exact handle; no selection returns nil without choosing the first target or retiring the formerly selected device |
| Read-time removal | EntityRemoved retires the old handle; rediscovery under the same native ID produces a new generation; unaffected handles remain equal |
| Inventory removal | A watch configured with a thirty-second interval receives EntityRemoved immediately after successful discovery omits its target, rather than waiting for its next poll |
| Held inventory | Timeout and caller cancellation complete before native return; a late empty result cannot erase accepted handles; subsequent get/list recover |
| Invalid results | Empty/duplicate inventory IDs and an empty current ID report ReadFailed without invalidating previously accepted targets; bound handles and singleton kinds are rejected as collection arguments |
| Held current query | Both timeout and caller cancellation complete before native return, preserve existing handles, and allow a subsequent current/get after release |

The held list/current tests run four combinations and require caller completion within 500 ms while the native boundary remains held. A one-second test fail-safe prevents an incorrect joining implementation from hanging indefinitely. These tests run from a main-actor caller and assert native discovery/read execution off the main thread.

## Defects reproduced and corrected

Initial discovery/current tests failed to compile before the new API existed. A subsequent read-removal test failed because the old handle regained access when its native ID reappeared. Target identity now includes context ownership and a fresh generation after detected removal.

Another test failed because an existing watch waited for its next thirty-second poll after removal; its 500 ms fail-safe canceled it. Registry removal notifications now finish affected continuations outside the registry/completion locks and cancel the producer's wait. Notification registration is tied to the iterator lifetime. Follow-up malformed-result and held-call cases characterize the resulting behavior.

## Implementation boundaries

`DeviceCollector.list` returns a complete native inventory; `current` returns an explicit native selection or nil. These calls must not query UI-only state or display permission prompts. Named resource collections and `sensors.list(Entity)` are typed wrappers over the common discovery mechanism; their presence does not establish a native platform collector.

Inventory validation and map construction run on the collection worker. Registry replacement is accepted atomically with the request result; cancellation or timeout that wins first prevents that replacement. Notifications run afterward, outside locks. A successful current selection adds or reuses its handle without treating other devices as removed.

Removal is currently learned from accepted complete inventories or explicit read-time EntityRemoved. Autonomous native hotplug observation, app-owned inventories/target namespaces and invalidation during held native work remain future integration work. All scalar/state collection remains in the existing process; no native call is forcibly interrupted.

## Remaining requirements

Apple collectors and iOS/macOS compilation, physical measurements and hotplug, app-owned display/permission/lifecycle inputs, native state-event supplementation, sensor streams and metadata, capability/permission APIs, remaining value normalization, bounded work admission, shared-context closure, external package consumption and the complete support/acceptance matrix remain required. This checkpoint does not narrow the original goal or establish Apple platform support.
