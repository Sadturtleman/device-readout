# Swift app-observed sensor activity — 2026-11-17

Scope: app-supplied sensor activity, session suspension/resumption and original one-shot deadlines. The full 46-entity, binding and acceptance scope remains incomplete.

This historical checkpoint precedes the [capability checkpoint](2026-11-17-swift-capabilities.md), which adds inactive termination and independent-consumer evidence and raises the full suite to 75 tests. The original counts and limits below describe this earlier checkpoint.

## Results

Swift 5.9.2 on Ubuntu 22.04 x86_64 under WSL passes **66/66 public-API tests in both Debug and Release**, with warnings treated as errors. Five [sensor-activity tests](../../swift/Tests/DeviceReadoutTests/SensorActivityTests.swift) extend the preceding 61 cases. These use controlled sources and worker boundaries, without an Apple SDK or physical sensor.

```sh
sh tools/test-swift.sh --jobs 2 -Xswiftc -warnings-as-errors
sh tools/test-swift.sh --jobs 2 -c release -Xswiftc -warnings-as-errors
```

Upload verification logs are retained locally in ignored `.tools/swift-upload-full.log` and `.tools/swift-upload-release.log`. Full test execution took 4.364 and 4.466 seconds respectively, excluding compilation.

## Behavior and evidence

`observers.sensorActivity(false)` supplies application policy without reading UI, window or foreground state. It invalidates the current sensor session and schedules cleanup on the collection worker. `true` resumes continuing watches with new sessions. Initial activity is true; repeated identical activity is ignored. Desktop focus policy belongs to the application.

The five tests cover:

- Pause/resume on the same watch, resource cleanup and rejection of old-session samples and errors.
- Inactive get timeout without sensor activation, metadata/state availability and activation before a pending get expires.
- One original get deadline across pause and resume, rather than restarting its timeout.
- Pausing a held registration without waiting for it, canceling its first-value deadline and rejecting its late sample/error after resumption.
- Old buffered or queued samples behind a held native read not following the resumed session's value.

The inactive-get test first reproduced collection while inactive. Get now consumes a fresh sensor observation under one independent outer deadline. Paused watch sessions cancel their first-value deadline; resumed sample sessions receive a fresh first-value deadline. Final output acceptance checks the activity generation. Snapshots already accepted before suspension may still drain from the public stream buffer.

## Limits and remaining work

An uncooperative registration or cleanup still occupies the serial collection worker until it returns. Independent caller completion does not imply native interruption or process isolation. These tests do not cover every inactive permission/failure/removal/cancellation interleaving, shared-consumer race or activity-buffer overflow.

Framework lifecycle adapters, native Apple sources/builds, complete vector/quaternion/ratio normalization, coordinate conversion, capabilities, native state/inventory notifications, package consumption and physical/version/platform matrices remain required. The generic source contract does not establish hardware support for all sensor entities.
