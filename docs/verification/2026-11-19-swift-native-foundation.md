# Swift native Foundation collection and state notifications

Swift now provides an inert `DeviceAccess()` constructor backed by native Runtime and TimeZone collection. This is implementation progress toward the declared iOS 16/macOS 13 targets, not proof of Apple platform support. Verification uses the official Swift 5.9.2 Ubuntu 22.04 toolchain under WSL. Apple SDK builds, actual system-setting notifications and physical-device execution remain required.

## Field mapping

| Entity | Implemented fields and limits |
| --- | --- |
| Runtime | Compile-target process architecture for x86, x64, arm32 and arm64; pointer width supplies processBitness. Unknown architectures remain nil. hostArchitecture and supportedAbis remain nil; the process target is not substituted for a translated host's architecture. |
| TimeZone | Foundation's current system identifier resolves one immutable rule set. Offset and daylight-saving state use one instant. Known regional IANA identifiers and explicit tzdb UTC/GMT identifiers are preserved; generated numeric GMT-offset names are not presented as IANA IDs. windowsId remains nil. |

The native capability query reports readable/watchable support for these two entities without reading snapshots or registering listeners. Unconnected native entities report false; app-owned state and sensor capabilities retain their existing rules. Get and watch snapshot normalization, completion timestamps and per-read deadlines continue to use the shared collection worker.

The system source uses [TimeZone.autoupdatingCurrent](https://developer.apple.com/documentation/foundation/timezone/autoupdatingcurrent) and the [TimeZone offset/DST APIs](https://developer.apple.com/documentation/foundation/timezone). It does not change the process's default time zone or reset global Foundation caches. A real UTC regression showed that Foundation's known-identifier listing omitted a valid `Etc/UTC`; the collector now also recognizes the fixed identifiers defined in IANA's [etcetera](https://data.iana.org/time-zones/tzdb/etcetera) and [backward](https://data.iana.org/time-zones/tzdb/backward) files. This supplement supplies identifier validity, not time-zone rules or offsets.

## Native state observation

`DeviceCollector.observeChanges(_:notify:)` is an optional collector boundary whose default returns nil. Registration runs on the worker before the initial state read. Its callback only supplies an invalidation; subsequent device reads and snapshot preparation remain on the worker. The returned `NativeStateCleanup` also runs on that worker. This does not add an event wrapper to public get/watch snapshots.

TimeZone registers Foundation's system-time-zone notification. Notifications interrupt polling delays, including a one-hour configured interval, and equal events remain deliverable. Polling supplements native invalidations with at most one queued poll; reads remain serial and do not accumulate a backlog of timer ticks. Native invalidations have a bounded queue and explicit overflow failure.

Registration and the first read share the original first-value deadline. Idle event waiting has no read deadline. Native observation ends when the consumer cancels or drops its iterator, the context closes, a read fails or app-owned state takes over. Late invalidations cannot regain ownership after app handoff. Context close admits observation cleanup before collector close. If blocked registration returns after timeout/closure, its cleanup executes on that worker before the queued collector close. Blocking setup or cleanup does not make the caller join native execution.

## Verified behavior

| Check | Result |
| --- | --- |
| Complete Debug suite | 88/88 tests pass under `TZ=Etc/UTC`, with compiler warnings treated as errors. |
| Complete Release suite | 88/88 tests pass under `TZ=Asia/Kathmandu`, with compiler warnings treated as errors. |
| Runtime reference | Public get agrees with the running Linux executable's independently decoded ELF architecture/word-size header. |
| Time-zone reference | Public offset and DST agree with C-library localtime; UTC and Kathmandu identifiers remain readable. Equal polling values get fresh timestamps. |
| Foundation notification | Posting the real Foundation notification-center event wakes the native TimeZone watch before its one-hour poll. This is adapter wiring evidence, not an OS settings-change test. |
| Native invalidations | A public collector boundary sends a changed value and an equal event; snapshots arrive as 1, 2, 2, with one worker-owned registration and cleanup. |
| Held registration | The 60 ms deadline and MainActor progress precede native release. Context closure remains independent; late observation cleanup precedes collector close, and no expired read starts. |
| App handoff | Native observation cleans up once; late native invalidations cannot replace app values 7 and 8. |
| Held cleanup | Cancellation/context close, a MainActor pulse and a separate native Runtime context complete before blocked native cleanup returns. |
| Separate SwiftPM consumer | A distinct executable package imports the public product and passes Debug under UTC and Release under `Etc/GMT+4`. It checks typed reads, two fresh equal snapshots, immutable settings and shared context closure. The latter reports offset -14400, preserving IANA's sign convention. |

The initial Runtime and TimeZone tests reproduced UnsupportedEntity before their mappings were added. The native-invalidation test reproduced missing registration before the protocol/runtime connection. The Foundation notification test reached its bounded cancellation fail-safe before notification registration was implemented. The UTC test separately reproduced a readable valid ID being discarded. The initial invalidation test also had unused XCTest expectation diagnostics; the corrected test isolates the actual zero-registration failure. Cleanup-admission ordering was tightened by code review; it is not claimed as a separately reproduced race.

All 576 non-Markdown source inputs match the capture made before final Debug/Release and consumer verification. The local audit manifest is `.tools/evidence/swift-native-foundation-checkpoint.json`. Build logs, toolchains and binaries remain in ignored `.tools` paths. Existing Windows sources are unchanged by this Swift work; their preceding results are historical evidence, not newly rerun tests.

## Reproduction and remaining scope

Run `sh tools/test-swift.sh -Xswiftc -warnings-as-errors` and its `-c release` variant. Run `sh tools/test-swift-native-consumer.sh` and its `-c release` variant for the separate package. Set `SWIFT_BIN` to Swift 5.9.2 and use process-local `TZ=Etc/UTC`, `TZ=Asia/Kathmandu` or `TZ=Etc/GMT+4` for the corresponding cases; these do not modify host system settings.

Apple compilation, iOS/macOS runtime and minimum-version coverage, native notification delivery after actual settings changes, further identifier aliases/custom zones and DST transitions remain unverified. Native observation saturation, concurrent teardown races and additional native failures need broader evidence. Host architecture, remaining native entities, Swift Apple framework observers, Flutter/RN Apple bindings and the complete original acceptance matrix remain unfinished. Worker scheduling does not isolate native crashes or guarantee zero process overhead.
