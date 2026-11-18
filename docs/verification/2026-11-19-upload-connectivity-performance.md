# Windows connectivity and performance upload checkpoint

This checkpoint publishes the current implementation and its recorded verification on 2026-11-19. DeviceReadout remains in development; the complete 46-entity, language, framework and platform acceptance matrix is not complete.

Subsequent unchanged-source verification completed both Windows consumer scripts and the framework suite. See the [performance follow-up](2026-11-19-dart-windows-network-performance.md). The results below preserve what was established at upload time.

## Changes included

- Dart and Flutter Windows add typed `NetworkPath` and `NetworkPerformance` reads and streams. Together with the previous collectors, fourteen native entity kinds now have implementations.
- `NetworkPath` reads preferred-profile connectivity, internet validation and metering. Its verified baseline is documented in the [connectivity checkpoint](2026-11-18-dart-windows-connectivity.md).
- `NetworkPerformance.downlinkBps` and `uplinkBps` read the provider's nullable data-plan rates in bits per second. Other performance fields remain null. These values are not traffic measurements or speed-test results.
- Both entities share native network-status registration within their context, with independent snapshots, polling and subscription lifetimes. Equal polling results remain visible. Failed reads terminate the affected stream without automatically restarting it.
- Native activation, property access, reference cleanup and subscription management run through the collection isolate. App-owned permission, screen and lifecycle observations remain the integration contract; these collectors do not request permission, read UI state or modify network settings.
- Native fixtures cover partial values, zero, unsigned 64-bit values, actual Windows boxed references, shared subscriptions, failure recovery and blocked native operations. Public deadline/cancellation/disposal completion does not wait for a blocked native call to return. This is not a claim of native crash containment or zero process overhead.

## Verification available at upload

| Check | Recorded result |
| --- | --- |
| Dart analysis and contracts | 203/203 in JIT and 203/203 in compiled CLI-bundle mode |
| Native connectivity/performance cases | 26 cases per mode, including 12 performance cases |
| Performance field fixtures | 17 per mode, including genuine Windows boxed `UInt64` references |
| Held performance operations | Eight per mode; caller progress, completion before native return and an independent readable context verified |
| Flutter checkout application | Actual Windows release application reported all 20 scenarios passing, including comparison with an independent C++/WinRT projection |
| Ordinary Flutter example restoration | Separate verbose release build completed with exit code 0 and no build warnings/errors |
| Installed-package consumer and framework suite for the performance addition | Not yet rerun at this checkpoint; preceding connectivity results remain historical evidence |

The current host exposes a preferred network profile and data plan but no inbound or outbound rate values. SDK null values agree with independent native reads. Non-null physical-provider rates, actual network transitions and the remaining platform/architecture matrix still require verification.

## Unresolved tooling failures

The first full Dart run encountered a Dart 3.13.7 JIT compiler abort while loading SDK metadata in an existing registry-test child (`runtime_entry.cc:3477`, `BinaryBuilder.readStringTable`). Its fixture-owned registry key was cleaned up. The focused case and subsequent complete JIT/CLI-bundle runs passed with unchanged implementation sources. The cause is not established; no automatic retry or failure suppression was added to the runner.

The Flutter checkout script encountered `MSB8066` custom-build failures, first while building the test entrypoint and subsequently while restoring the ordinary example after the application's 20 passing scenarios. Separate verbose builds of both entrypoints succeeded. The full checkout script has not subsequently completed successfully from start to finish. These results do not establish that the intermittent build failure is fixed.

Detailed logs, downloaded SDKs, compiled artifacts and local evidence captures remain in the ignored `.tools` directory. Production sources, fixtures, test runners and this verification record are included in the repository. Use `tools/test-dart.ps1`, `tools/test-flutter-windows.ps1`, `tools/build-flutter-packages.ps1 -Platform Windows` and `tools/test-flutter.ps1` to continue verification.
