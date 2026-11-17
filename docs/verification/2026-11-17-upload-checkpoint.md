# DeviceReadout upload checkpoint — 2026-11-17

This checkpoint publishes the current design, implementation and verification records. The scope remains all 46 entities, all specified bindings and the complete platform/acceptance matrix. It is not a completed SDK release.

## Included changes

Swift adds passive typed capability queries, independent app/native support handling, additional sensor-lifecycle checks and normalization of ratios, geometry, vectors, quaternions and nested display modes. Generated snapshots capture their completion timestamp after normalized values are prepared. Details and limits are recorded in the [capability checkpoint](2026-11-17-swift-capabilities.md) and [normalization checkpoint](2026-11-17-swift-normalization.md).

TypeScript, Kotlin and C# now normalize finite, nonzero orientation quaternions to unit length. A maximum-component scale avoids overflowing the norm or losing an entirely subnormal input. Zero-length or nonfinite rotations become null. Axes and signs are preserved; this is not a coordinate-frame conversion.

Each binding exercises both RelativeOrientation and AbsoluteOrientation through public get/watch paths. Cases include unavailable values, each nonfinite component, zero, signed identity, signed 3–4 rotations, maximum finite components and the smallest positive component. The new tests failed before their respective normalization changes and pass afterward.

TypeScript also moves collectedAt after field preparation. A collector fixture with a delayed final field getter reproduced the previous premature timestamp through public get. Kotlin's generated stamp function and C#'s DeviceAccess.Stamp already normalize before reading the clock; that conclusion comes from code inspection, without a new clock-fixture regression claim.

The existing browser family test compared normalized quaternion decimals with exact equality. After the new normalization, 0.6 can become 0.5999999999999999. It now checks component direction within 1e-15 and unit length, while retaining exact object keys, vector/scalar values, null handling and native reference-frame options.

## Verification

| Suite | Result | Evidence scope |
| --- | --- | --- |
| TypeScript 5.0.4 common/collector and consumer checks | 36/36 | Root generation, build, type checks and Node worker contracts |
| Chrome 158.0.8127.37 / Edge 157.0.4341.60 | 64/64 | Full existing browser suite, including native virtual sensors, observers and held-worker heartbeat |
| Kotlin/JVM contracts | 44/44 | Complete core suite including the new two-entity rotation case |
| .NET/Windows | 166/166 | Complete suite; build reports zero warnings and errors |
| Swift 5.9.2 Linux Debug and Release | 81/81 in each | Preceding normalization checkpoint, warnings treated as errors; no subsequent Swift implementation change |

Commands: `npm test`; `node --test packages/web/test/browser.test.mjs`; `./tools/test-kotlin.ps1`; `./tools/test-dotnet.ps1`. Swift commands and earlier evidence are preserved in its linked checkpoint. The root generator ran for all five languages during upload verification without changing the generated Swift implementation from that tested version.

The first browser attempt could not navigate to its localhost test server because the sandbox returned ERR_NETWORK_ACCESS_DENIED. A focused check confirmed that boundary; the interrupted run is not counted as test evidence. With localhost access, the full run initially passed 62/64 and exposed the two exact-float comparisons described above. After the assertion correction, all 64 pass. Existing held-worker fixtures report 30 host timer ticks in each browser.

Local logs are `.tools/upload-npm-test.log`, `.tools/upload-browser-launch-check.log`, `.tools/upload-browser-verified.log`, `.tools/upload-browser-green.log`, `.tools/rotation-kotlin-green.log`, `.tools/rotation-dotnet-full.log` and the Swift logs linked from its checkpoint. Logs, downloaded toolchains, build output and browser profiles remain ignored local artifacts.

## Remaining work

Follow-up: the [Dart normalization checkpoint](2026-11-17-dart-normalization.md) resolves the two Dart gaps below and reruns the Flutter framework and Android applications. The following paragraphs preserve the scope at upload time.

Dart's generic quaternion decoder still checks only finite components, and prepareSnapshot/prepareDescription still supply a clock value before decoding. Unit normalization and completion-order corrections there remain pending. This upload does not claim five-language parity for those two details.

Flutter and React Native apps were not rebuilt for this checkpoint; their earlier evidence remains historical. Apple native collectors/builds, physical sensor readings and coordinate/reference verification, remaining adapters/fields, external package consumption, minimum-version validation and the complete platform/acceptance matrix remain unfinished. Worker execution does not guarantee zero host overhead, forced interruption of stuck native calls or process-crash isolation.
