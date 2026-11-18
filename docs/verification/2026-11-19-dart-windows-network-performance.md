# Dart and Flutter Windows network performance — 2026-11-19

The Windows collector implements `get(Entities.networkPerformance)` and `watch(Entities.networkPerformance)` through the same collection isolate and native status source as NetworkPath. Checkout and independently installed Flutter consumers now pass the complete Windows application gate, including restoration of the ordinary example entrypoint. This extends the [upload checkpoint](2026-11-19-upload-connectivity-performance.md); all 46 entities, bindings and the full platform acceptance matrix remain the objective.

## Field and stream contract

| Field | Windows mapping |
|---|---|
| `downlinkBps` | Preferred connection profile → `GetDataPlanStatus()` → nullable `InboundBitsPerSecond` |
| `uplinkBps` | The same plan's nullable `OutboundBitsPerSecond` |
| `roundTripTime`, `effectiveType`, `browserOnline` | Null; these meanings are not inferred from the plan |

These are provider-supplied nominal plan rates in bits per second, as described by [DataPlanStatus](https://learn.microsoft.com/en-us/uwp/api/windows.networking.connectivity.dataplanstatus?view=winrt-28000). They are not sampled transfer counters, network-adapter link capacity or active speed-test results. The collector does not send probe traffic or modify network configuration.

Missing profiles, plans or nullable rate references yield null fields; a valid zero remains zero. One failed rate getter does not discard the independently readable rate. If both rate getters fail, or plan acquisition fails, the operation reports a typed error; a permission-denied field error takes precedence when both fields fail. Successful absence is not a failed getter. Native `UInt64` values are converted to the public floating-point Number representation before crossing the Dart boundary, avoiding a signed reinterpretation; large values retain floating-point precision rather than exact 64-bit integer precision.

Snapshots contain direct nullable values and one completion timestamp. No FieldResult, event wrapper, changed-field list or new public configuration is introduced. Native status invalidations and serial per-watch polling trigger fresh reads. Equal polling values are delivered with fresh timestamps. The existing default/configurable poll interval and per-read timeout apply.

Path and performance watches share one native status registration within a context but keep separate snapshots, timers and cancellation lifetimes. A failed performance read terminates that stream while a path stream can continue; explicit resubscription permits recovery. Event-registration unavailability retains polling. The native event source is documented in [NetworkStatusChanged](https://learn.microsoft.com/en-us/uwp/api/windows.networking.connectivity.networkinformation.networkstatuschanged?view=winrt-26100).

## Execution and native ownership

The bundled C helper performs activation, profile/plan lookup, nullable-reference reads, unsigned-to-double conversion and release on the collection worker. It balances same-thread WinRT initialization around each native call and releases returned interfaces, including non-null failure outputs, before returning values to Dart. The context and observation retain the MTA ownership established by the [connectivity implementation](2026-11-18-dart-windows-connectivity.md).

Public deadlines, cancellation and context disposal do not join blocked native operations. Late native completion releases its objects; canceled results do not reach the application. Controlled held calls verify that the caller timer and an independent collection context remain usable. This is not a native-crash boundary or a guarantee of zero process overhead. Screen, permission and lifecycle state continue to enter through application-owned observations; get/watch do not invoke UI getters or permission prompts.

## Verification

| Gate | Result |
|---|---:|
| `tools/test-dart.ps1`, JIT contracts | 203/203 |
| Same contracts in the compiled CLI bundle, including native assets | 203/203 |
| Dart analysis and negative browser boundary | Pass |
| `tools/test-flutter-windows.ps1`, checkout Release application and ordinary-entrypoint restoration | 20/20 |
| `tools/build-flutter-packages.ps1 -Platform Windows`, archive installation and independent consumer build | Pass |
| `tools/test-flutter-windows.ps1 -ExampleRoot .tools/flutter-windows-installed`, installed application and restoration | 20/20 |
| `tools/test-flutter.ps1`, framework and observer contracts | 27/27 |

These runs use Windows x64, Flutter 3.47.9 and Dart 3.13.7. The native reference/fixture builds use the Windows SDK and C++/WinRT projection separately from the production C ABI helper.

Twenty-six native connectivity/performance child scenarios run in each Dart mode: the previous fourteen path/lifetime scenarios and twelve performance scenarios. Performance coverage includes seventeen literal field fixtures, a mixed path/performance subscription, failure isolation with explicit recovery, polling fallback, and eight held-operation cases. The held cases cover plan lookup, nullable-reference lookup, value access, initial watch, subsequent poll, subsequent native-event read, cancellation and context disposal. They record caller/worker thread identities, advancing timer ticks, public completion before native return and a separately readable RAM context. Fixture getter/release calls confirm the MTA apartment. Ordinary cases release all synthetic objects and registrations; the existing deliberate persistent-refusal path case still records its retained native owner.

The field fixtures cover absent profile/plan/references, partial failures and permission errors, known zero, `UInt64` values above the signed range, and actual Windows-boxed `IReference<UInt64>` objects. The production helper reads those real boxed references through the native ABI. Controlled callbacks verify shared registration and independent stream lifetimes; they do not prove physical network transition delivery.

Independent PowerShell WinRT reads corroborate the Dart result. Each actual Flutter application compares against a separate C++/WinRT native projection, receives three equal snapshots with fresh timestamps, and records an advancing UI timer. This host exposes a preferred profile and data plan with both rates absent; SDK nulls match the reference. Non-null rate values are currently verified through the native fixtures.

## Evidence and tooling failures

The initial unsupported-capability failure is retained in `.tools/dart-network-performance-red.log`. Final logs are `dart-network-performance-final.log`, `flutter-network-performance-checkout.log`, `flutter-network-performance-packages.log`, `flutter-network-performance-installed.log` and `flutter-network-performance-framework.log`, all under `.tools`.

The audit `.tools/evidence/dart-windows-network-performance-checkpoint.json` verifies **549 unchanged code/build/schema inputs** against the capture taken before the Dart gates. It records native-child reports, actual application reports, archive downloads and artifact hashes. Installed packages match **38 Dart runtime/build/native-source files** and **12 Flutter runtime files** byte-for-byte, and installed application test sources match the checkout. Logs, SDK downloads and generated artifacts remain ignored rather than becoming package contents.

An earlier complete Dart attempt aborted inside the Dart JIT compiler while loading SDK metadata in an existing registry child (`runtime_entry.cc:3477`, `BinaryBuilder.readStringTable`). Its owned registry key was cleaned up. The focused child and subsequent full JIT/CLI-bundle gates passed without implementation changes. The failure remains recorded in `dart-network-performance-compiler-abort.log`; its cause and relationship to the earlier time-zone checkpoint failure are not established.

The first Flutter checkout build failed in `flutter_assemble` with `MSB8066`; a subsequent attempt passed all application scenarios but failed while restoring the ordinary example. Verbose builds of both entrypoints succeeded. The final unchanged-source invocation of the original script completed successfully from start to finish, as did the installed consumer. The earlier failures remain in `flutter-network-performance-build-failed.log` and `flutter-network-performance-restore-failed.log`; successful reruns do not establish a root-cause fix. No automatic retry or failure suppression was added to either runner.

## Remaining acceptance work

Non-null physical-provider rates, real profile/plan transitions, explicitly bound application routes, additional native races, sustained overload and supported Windows versions/architectures require further evidence. The three unavailable performance fields remain null. The .NET suite and Android/browser application matrices were not rerun for this Dart addition. Apple collectors, remaining entities/bindings, physical devices, minimum-version consumers and the complete SDK acceptance matrix remain incomplete.
