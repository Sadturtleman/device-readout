# Swift app-owned sensor sources — 2026-11-17

Scope: sensor source registration, typed get/watch, passive metadata, immutable sampling requests and operation/resource lifetime. The objective remains all 46 entities and fields, all bindings and the complete platform/acceptance matrices.

This historical checkpoint precedes the [sensor-activity checkpoint](2026-11-17-swift-sensor-activity.md), which adds pause/resume and raises the full suite to 66 tests. The counts and pending scope below describe this earlier checkpoint.

## Environment and results

Swift 5.9.2 on Ubuntu 22.04 x86_64 under WSL. Debug and Release each pass **61/61 public-API tests**, with warnings treated as errors and no compiler diagnostics. Ten [sensor tests](../../swift/Tests/DeviceReadoutTests/SensorTests.swift) extend the preceding 51 cases. Sources and native boundaries are controlled fixtures; no Apple SDK or physical sensor is used.

```sh
sh tools/test-swift.sh --jobs 2 -Xswiftc -warnings-as-errors
sh tools/test-swift.sh --jobs 2 -c release -Xswiftc -warnings-as-errors
```

Set `SWIFT_BIN` when the toolchain is outside PATH. Ignored final logs: `.tools/swift-sensors-full.log` and `.tools/swift-sensors-release.log`. Other bindings were not rerun for this Swift-only change. One earlier compiler process terminated with signal 11 while compiling the existing ObserverTests file; the same sources subsequently built with two jobs, and both final configurations passed. This was a compiler process failure, not a reported SDK runtime failure.

## Public behavior exercised

| Contract | Evidence |
| --- | --- |
| Inert registration and one-shot demand | Registration invokes no source callback. Two get calls independently start collection, return distinct actual pressure samples and release each resource once. Setup and cleanup are off the main thread; timestamps are assembled at collection. |
| Cold sample watch | Creating a stream does not subscribe. Iteration retains ordered equal values and null-normalizes a non-finite scalar. A 30-second polling interval does not delay samples. Breaking iteration releases the source even while the stream value remains alive. |
| Event waiting | Event get times out without an occurrence. Event watch remains subscribed beyond a 40ms read timeout, then receives the actual occurrence after 120ms. Event registration work still has a deadline. |
| Event payload validity | False/nil StepDetected and SignificantMotion payloads fail get and watch with ReadFailed; they never become fabricated initial occurrences. |
| Metadata | Describe reads all eleven registered metadata fields without starting collection. Sensor kind comes from the typed target; non-finite numbers and negative intervals become nil, and valid zero values remain. |
| Sampling configuration | PlatformDefault is preserved in the original access and for get/event watches. A configured sample watch receives 60Hz, retained across other immutable configuration changes. Zero, negative and non-finite requests are rejected. |
| Held registration | Twelve combinations cover get, sample watch and event watch under timeout, cancellation, source removal and context closure. Caller completion precedes native callback return. Sessions stop and resources returned later are released once; cleanup exceptions stay contained. |
| Held cleanup | The one-shot result returns before a held cleanup finishes. Metadata/read requests queued behind it retain their deadlines; context closure returns without joining it. Expired queued work does not start afterward. |
| Errors and ownership | Typed source failures reach get and idle watch; unexpected setup exceptions become ReadFailed. Duplicate/state/foreign-target source registrations are rejected. Closing the source retires its target; a replacement generation ignores the old registration and late stopped-session samples. |
| Bounded buffers | A 4096-sample burst cannot normalize while its registration callback occupies the worker. The bounded raw queue accepts at most 2048 pending samples plus one awaiting normalization, preserves accepted order, then reports ReadFailed and releases its source. |

## Reproduced failures and implementation

Source registration, descriptions and sampling tests initially failed compilation because the APIs were absent. The sample-watch test reproduced UnsupportedEntity. The event-watch test then reproduced a ReadTimeout while waiting for its first actual occurrence. Registration readiness is now separate from event waiting: startup remains bounded, event idle time does not.

The invalid-event test reproduced eight false/nil payloads escaping through get/watch across the two event kinds. Worker-side event validation now requires true. Held-work, cleanup, ownership and burst cases passed as follow-up characterization tests rather than separate reproduced-defect claims.

Observed sensor records are keyed by the existing context-owned target generation and namespace. A registration owns one source callback and immutable metadata; each demand owns its own session. Setup and cleanup run through the collection worker, with cleanup admitted independently of bounded read admission. The session buffers only supplied snapshots; normalization and timestamping remain worker-owned. Stop invalidates the session immediately and queues cleanup. Cleanup arriving after stop is also queued exactly once.

First sample/get deadlines cover startup, waiting and normalization. Event watch startup has its own read limit, and each received occurrence's normalization has a read limit. First source failures, external observation failures, removal and context closure propagate through the existing typed-error/lifetime paths. Neither sensor get nor watch calls a state getter or polls for synthetic samples.

## Remaining scope and limits

Sensor activity input and pause/resume are still required, including stale-session rejection across inactivity and desktop focus policy. Also pending: native sensor sources/discovery adapters, Apple collectors/builds, complete vector/quaternion/ratio normalization and coordinate conversion, capabilities, native state/inventory events, independent package consumption and the full physical/version/platform matrix.

The generic source API does not establish physical support for every sensor entity. Pressure and the two event kinds are representative controlled inputs; hardware units, coordinate frames and other field mappings need adapter-specific evidence. Metadata currently requires a registered app source. No Apple authorization, hardware access, UI getter or prompt was added. An uncooperative setup or cleanup continues occupying its serial worker until return; independent caller completion does not forcibly interrupt native code or provide process/crash isolation.
