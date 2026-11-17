# Swift ratio and structured-value normalization — 2026-11-17

Scope: nullable field validation, grouped sensor samples, unit quaternions, nested display modes, generated completion timestamps and worker ownership. The objective remains all 46 entities/fields, bindings and complete platform/acceptance matrices.

## Environment and results

Swift 5.9.2 on Ubuntu 22.04 x86_64 under WSL passes **81/81 public-API tests in both Debug and Release**, with warnings treated as errors and no compiler diagnostics. Six [normalization tests](../../swift/Tests/DeviceReadoutTests/NormalizationTests.swift) extend the preceding 75 cases. These are controlled collector/observer/source fixtures, without an Apple SDK or physical sensor. Other-language and platform suites were not rerun for this Swift-only change.

```sh
node tools/generate-swift.mjs
sh tools/test-swift.sh --jobs 2 -Xswiftc -warnings-as-errors
sh tools/test-swift.sh --jobs 2 -c release -Xswiftc -warnings-as-errors
```

The generator was run twice and the output SHA-256 remained identical. Final logs, after the completion-timestamp correction, are retained locally in ignored `.tools/swift-normalization-completion-full.log` and `.tools/swift-normalization-completion-release.log`. Test execution took 4.639 and 4.552 seconds respectively, excluding compilation. Earlier normalization-only runs and the earlier full runs remain separate logs. Some WSL launches reported a systemd user-session warning; the same test processes completed successfully.

## Field behavior

The [Swift generator](../../tools/generate-swift.mjs) connects [SnapshotRules](../../swift/Sources/DeviceReadout/SnapshotRules.swift) to eighteen additional fields across eleven entities:

| Fields | Behavior and evidence |
|---|---|
| Display.brightness, Battery.level, RelativeHumidity.value | Require finite values in 0–1; preserve both endpoints and fractional values; cover native get, observed watch and sensor get |
| Display.logicalBounds/workAreaBounds/physicalSizeMillimeters; Viewport.size/visualViewportSize/safeAreaInsets | A nonfinite component invalidates the whole structure; independent fields survive; preserve negative screen origins, zero dimensions and valid fractional geometry; observed streams recover on the next valid snapshot |
| Accelerometer, LinearAcceleration, Gravity, Gyroscope, Magnetometer value | Whole-vector nil for any nonfinite axis; preserve signs, zero vectors and finite extreme values in get/watch; components remain grouped from one sample |
| RelativeOrientation, AbsoluteOrientation value | Whole-value nil for nonfinite components or zero norm; convert other finite inputs to unit quaternions; preserve axes and component signs; exercise both get/watch, identity, opposite-sign identity, 3–4–5 rotations, greatest-finite and subnormal inputs |
| Display.currentMode/supportedModes | Normalize optional refresh rates without discarding valid pixel size; retain list order, valid zero/fractional rates, empty lists and nil distinction; modifying a consumer copy does not change later snapshots |

Quaternion normalization scales by the largest absolute component before squaring. This avoids overflow/underflow of a direct norm while preserving the represented rotation. It does not infer coordinate frames, swap axes, change magnetic/relative reference semantics or validate physical sensor orientation; platform adapters still own those mappings.

The generated collection method prepares normalized fields before capturing one Date for collectedAt. This applies to all 46 snapshots and SensorDescription. Code inspection identified the old ordering, which passed Date into the generated method before potentially expensive normalization. Existing public timestamp checks cover a fresh timestamp within the query window; they do not use an injected clock to measure the precise internal statement order.

## Worker and lifetime evidence

A held native RAM read occupies the collection worker while the MainActor publishes a Display snapshot with 10,000 display modes. Publication returns independently, a MainActor heartbeat runs, and a 60 ms get deadline expires while normalization is queued. The caller completes before native release. After release, a fresh get normalizes all modes, retains their pixel sizes, returns nil for invalid brightness and leaves the supplied snapshot unchanged.

This characterizes queue waiting and recovery. It does not measure worst-case CPU cost during active normalization or impose a general payload-size limit. Native collection, structured normalization and final snapshot assembly remain on the worker; observer publication only supplies raw values.

## Defect evidence and limits

The five initial value tests reproduced escaping invalid ratios (15 assertions), screen geometry (6), vectors (10), rotations (26) and nested mode fields (2). Each test was written and run before its implementation change. The held-worker scenario passed as a characterization check. The timestamp ordering correction came from code inspection and was followed by the full Debug/Release suites; it is not claimed as a separately reproduced clock-fixture defect.

At this checkpoint, other bindings' generic quaternion rules only validated finite components. The subsequent [upload checkpoint](2026-11-17-upload-checkpoint.md) adds unit-quaternion tests/normalization in TypeScript, Kotlin and C#, fixes TypeScript completion ordering and inspects the already-correct Kotlin/C# ordering. Dart parity remains pending. Swift JSON/transport validation, native coordinate conversions, complete field-specific semantic range checks, Apple collectors/builds, framework adapters, native state/inventory events, external package consumption and the full physical/version/platform matrices also remain required.

An uncooperative native call still occupies its worker until return. Independent deadlines do not forcibly stop native code, guarantee zero host CPU cost or isolate native process crashes.
