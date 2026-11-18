# GitHub checkpoint: Windows storage and CPU — 2026-11-18

This checkpoint preserves the current design and implementation. The [design](../design.ko.md), [collector mappings](../collector-mappings.md) and [implementation ledger](../implementation-status.md) retain the complete scope. DeviceReadout remains in development; this is not a completed SDK release or a claim that every supported platform has passed its acceptance matrix.

## Included changes

- Windows Dart and Flutter storage collection now has independent native comparisons, typed volume discovery, optional-field failure handling and controlled removal/failure/stall coverage. A bundled Windows C helper captures a Win32 result and its error before returning to Dart. See the [storage checkpoint](2026-11-18-dart-windows-storage.md) and [native-boundary follow-up](2026-11-18-dart-windows-storage-native.md).
- Windows CPU collection adds typed get/watch and capability reporting. Binding, native calls, bounded buffer parsing, normalization and cleanup stay on the existing collection isolate. Polling retains duplicate snapshots with fresh collection timestamps.
- Package preparation includes the Windows build hook and production C source. Windows CLI consumers use `dart build cli` to bundle the native asset. Compiler execution occurs during builds, never during SDK reads.
- Screen, permission and lifecycle observations remain app-owned inputs. CPU/storage reads do not query UI getters, request permissions or change process/system policy.

## CPU field contract

| Field | Windows source and meaning |
|---|---|
| `model` | `ProcessorNameString` in the 64-bit `HARDWARE\DESCRIPTION\System\CentralProcessor\0` registry key; this describes the primary registry processor entry. |
| `manufacturer` | `VendorIdentifier` from that same key. |
| `logicalProcessorCount` | Unique logical processors in the native topology; active all-group count is the fallback when topology is unavailable. |
| `physicalCoreCount` | Native processor-core relationships. |
| `processorPackageCount` | Native processor-package relationships. |
| `availableLogicalProcessorCount` | Current process-default availability from hard affinity, process-default CPU sets and system allocation state on a single-group host. A CPU-time quota is not converted into a processor count. Thread-specific overrides are not aggregated. |
| `socModel`, `socManufacturer` | Null; CPU identity is not substituted for SoC identity. |

Partial failures leave the affected fields null. Multi-group process availability remains null, while topology counts use group-aware masks on 64-bit processes. WOW64 topology is not interpreted through truncated affinity masks. Actual multi-group, WOW64 and ARM64 execution remain unverified.

The current host independently reports model `Intel(R) Core(TM) i9-14900KF`, vendor `GenuineIntel`, 32 logical processors, 24 cores and one package. The SDK's get/watch values agree with a separate Windows SDK C reference; standalone tests also compare applicable topology/registry fields with CIM and PowerShell.

## Verification on upload sources

| Command | Result |
|---|---|
| `./tools/test-dart.ps1` | Clean static analysis; **104/104 JIT** and **104/104 CLI-bundle** checks; negative browser boundary passed. |
| `./tools/test-flutter-windows.ps1` | Clean example analysis; **16/16 actual Windows release-app scenarios**; ordinary application entrypoint rebuilt afterward. |

Each Dart execution mode includes 29 storage native-fixture cases and four CPU policy cases. The CPU fixture changes only its retained child process, verifies that SDK reads leave the selected policy intact, restores it and observes recovery through the same watch. The parent process's readings remain unchanged.

| Child CPU policy | Expected process availability | Verified outcome |
|---|---:|---|
| Hard affinity restricted to one processor | 1 | Get/watch agree; restoring the policy yields 32 in the same watch. |
| Two-processor affinity with one default CPU-set preference | 1 | Whole-system logical count remains 32. |
| One-processor hard affinity conflicting with the default CPU-set preference | 1 | Hard affinity remains effective. |
| Two-processor affinity with a 50% job CPU-time cap | 2 | Time quota does not become a fractional or reduced processor count. |

The Flutter CPU scenario compares all six readable fields, verifies three polling snapshots and records ten host timer ticks during polling. The storage scenario also retains ten timer ticks. The existing held-isolate scenario records 49 timer ticks and one native window metrics callback while the public read deadline completes. The controlled storage native stalls verify deadlines/cancellation before native return. These are specific boundary checks, not process crash isolation or a universal UI latency guarantee.

The initial aggregate runs found two tests that still assumed CPU was unsupported. Capability expectations now reflect Windows CPU support and retain a separate unsupported Battery probe; the missing-collector read check uses the still-unimplemented standalone NetworkPath collector. The final complete rerun above passes. These were stale test expectations, not a reason to suppress failures.

Local evidence is retained under ignored `.tools/`: `dart-storage-cpu-upload-final.log`, `flutter-storage-cpu-upload.log` and `flutter-windows-viewport-e4908223b70a43e5a81d56337284a324.json`. Source fixtures and reproduction commands are included in Git; local toolchains, dependencies, binaries and raw execution logs are excluded.

## Remaining verification

The earlier storage follow-up records installed-Pub Windows 15/15, Flutter framework 27/27, sixteen browser scenarios per Chrome/Edge and an Android consumer build. Those runs predate the CPU addition; they are not fresh CPU consumer/platform evidence. This upload reruns standalone Dart and the checkout Windows application only.

CPU-specific malformed native responses and held CPU calls, multiple processor groups/packages, ARM64/WOW64, physical storage hot-plug/quotas, CPU package installation and the full version/platform matrix remain pending. Apple collectors, remaining framework bindings and other unfinished SDK work remain tracked in the implementation ledger. No package registry release is published by this GitHub checkpoint.
