# Dart and Flutter Windows battery status observation

Individual Battery watches now supplement interface notifications and serial polling with native driver status observation. This extends the [individual pack checkpoint](2026-11-19-dart-windows-battery-packs.md); aggregate Battery behavior and the public API remain unchanged. The complete 46-entity, language, platform, version and physical-device acceptance matrix remains unfinished.

## Runtime behavior

Each subscribed individual watch owns a read-only overlapped device handle and a dedicated native thread. A zero-timeout status query establishes the driver's baseline; subsequent queries wait for changes to the observed power flags or capacity bounds. Drivers returning unsupported-function/not-supported errors retain ordinary polling. Each native result is captured, including equal values, and the remaining metadata is collected on the Dart isolate before the typed snapshot is delivered. A later direct status read cannot overwrite the event's captured level, voltage or signed power/current inputs.

The native wait does not occupy the shared collection isolate. Cancellation signals its stop event without joining the driver. That native thread requests cancellation and retrieves completion before releasing the OVERLAPPED structure, input/output storage and handle. The path, target retirement state and native module remain owned independently of the access context, so the context can close before delayed completion. Device close also runs on the native thread. A failed close retains ownership instead of claiming release; automatic recovery of that retained owner is not implemented by this checkpoint.

Native status removal atomically retires the target before deferred Dart delivery. An information read held across that removal is rejected, and later path/tag reuse creates a new handle. Interface removal continues to use the existing context-owned observer. Status queues are bounded and report overflow instead of silently dropping values. Polling retains its configured cadence and supplements fields without status notifications.

The wait conditions follow [BATTERY_WAIT_STATUS](https://learn.microsoft.com/en-us/windows/win32/power/battery-wait-status-str). Buffer ownership follows Microsoft's [cancellation contract](https://learn.microsoft.com/en-us/windows/win32/api/ioapiset/nf-ioapiset-cancelioex) and [completion guidance](https://learn.microsoft.com/en-us/windows/win32/fileio/canceling-pending-i-o-operations): requesting cancellation alone does not complete the operation.

## Reproduction and verification

The first public `watch()` regression uses a one-hour poll interval and an OS-boundary fixture that supports pending status operations. Before implementation it fails because the watch never subscribes to a native status operation. After implementation, two equal charging events arrive before the poll, with their own capacity, power/current and completion timestamps. A subsequent direct query intentionally returns discharging, proving that captured events survive later native state changes.

| Verification | Evidence |
| --- | --- |
| Full Dart script | Analysis, 244/244 JIT contracts, native CLI-bundle build, 244/244 compiled contracts and the web boundary check pass in one complete script run. |
| Pack native cases | Nine per mode, eighteen passing child reports. The five previous pack cases remain passing alongside four status scenarios. |
| Event delivery | Captured changes and equal events retain their values. A pending status wait leaves the same access context available for RAM queries. |
| Delayed cancellation | Public cancellation completes while the driver remains pending. The same context still reads RAM; context disposal releases its interface observer before status completion. Caller timers progress, and later completion safely closes the status handle. |
| Removal during read | A native status removal completes while the collection isolate is held in an information query. The eventual report is rejected, the old watch fails with EntityRemoved and same-tag rediscovery produces only the replaced handle anew. |
| Actual kernel completion | An exclusively created process-owned local named pipe drives real ReadFile, GetOverlappedResult and CancelIoEx operations through the public watch. Both updates and cancellation complete; pending buffers are drained before handle closure. This verifies Windows kernel completion, not a physical battery driver's protocol. |
| Flutter framework | 27/27 checks pass. |
| Checkout Windows app | Complete script passes 22/22 and restores the ordinary example. |
| Installed Windows app | Complete script passes 22/22 and restores the ordinary example. |
| Installed source parity | Forty-four Dart runtime/build/native files, twelve Flutter package files and five application reference/support files match the verified checkout. Real Pub requests download the local archives; packages remain unpublished. |

All 569 non-Markdown source inputs match the capture made before the final Dart script and remain unchanged through framework and consumer verification. Each native child scenario checks resource cleanup, including status handles and outstanding operations where applicable. Both actual applications report zero individual packs and one logical aggregate endpoint on this host, agree with independent native references and retain UI timer progress. Their battery checks are regression and integration evidence; individual status events use the native fixture and kernel-pipe cases above.

The audit manifest is stored locally at `.tools/evidence/dart-windows-battery-status-checkpoint.json`, with source hashes, child reports, consumer results, package parity and artifact hashes. Logs, binary fixtures and archives remain ignored. Previous pack archives and their checkpoint are preserved under `.tools/evidence/battery-pack-package-history/` before package rebuilding.

Reproduce with `tools/test-dart.ps1`, `tools/test-flutter.ps1`, `tools/build-flutter-packages.ps1 -Platform Windows`, and `tools/test-flutter-windows.ps1` for the checkout and `.tools/flutter-windows-installed` consumer. The focused native scenarios run through `dart/device_readout/test/native_windows_battery_packs.dart`.

## Remaining work

Physical battery status/capacity transitions, driver-specific cancellation behavior, additional architectures and the full platform/version matrix remain unverified. Further status error, saturation, held-open/held-close and retained-close recovery cases are still required. Earlier compiler/build failures remain preserved in the preceding checkpoint; this successful run does not establish their root cause or a tooling fix. Worker execution preserves the tested deadlines and progress; it does not provide native-crash containment or zero process overhead. Apple collectors and other unfinished bindings remain part of the original goal.
