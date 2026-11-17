# Dart Windows process-memory checkpoint — 2026-11-17

`DeviceAccess.native().get(Entities.processMemory)` and `watch(Entities.processMemory)` now return Windows `ProcessMemorySnapshot` values. A public-API test first failed with `UnsupportedEntity`; the implemented collector passes the same test against an independently compiled native query in the consumer process.

## Field and execution contract

`allocationRemainingBytes` maps to `GlobalMemoryStatusEx.ullAvailPageFile`. Microsoft defines this as the maximum memory the calling process can currently commit, bounded by system commit availability. It is distinct from physical available RAM, unreserved virtual address space, and current process memory usage. See [MEMORYSTATUSEX](https://learn.microsoft.com/en-us/windows/win32/api/sysinfoapi/ns-sysinfoapi-memorystatusex). The existing C# Windows collector uses the same field mapping.

The value is an exact unsigned `BigInt` byte count, including zero. Native allocation or a failed whole query yields `ReadFailed`. The shared normalization path stamps one collection-completion timestamp. State watch uses existing immediate-first-read, serial polling and immutable interval settings; native capabilities report read/watch support on Windows.

Binding creation, allocation, OS collection and buffer cleanup occur on the collection isolate. The RAM and ProcessMemory collectors share their context-owned library reference; the process query does not create memory-notification handles or call installed-RAM APIs. Existing host deadlines and cancellation remain independent of held worker work. The SDK performs no UI reads, permission requests or subprocess launches for this collector.

## Verification

Environment: Windows x64 build 10.0.26300.0, Dart 3.13.7 from Flutter 3.47.9, Visual Studio 2022 C++ tools. The reference DLL in `tools/windows-memory-probe` includes Windows headers and calls Win32 directly without linking SDK code. Its reported process ID must equal the Dart consumer's ID. `tools/test-dart.ps1` builds it with the Visual Studio CMake component before running contracts; it is a test prerequisite, not an SDK runtime dependency.

| Check | Result |
|---|---|
| Dart analysis | No issues |
| JIT public-API contracts | 55/55 |
| Compiled native public-API contracts | 55/55 |
| Process-memory query | Same-process native comparison, exact nonnegative bytes and fresh completion time |
| Process-memory capabilities and polling | Read/watch available; three snapshots with increasing completion times |
| Shared collector lifetime | RAM remains readable after process-memory get/watch; existing repeated-read and independent-context checks pass |
| Negative web boundary | JavaScript compilation succeeds; unsupported host collection is rejected without invoking the host factory |

The JIT SDK sample was 24,413,270,016 bytes; adjacent independent readings were 24,415,367,168 and 24,413,270,016 bytes. The compiled sample and both adjacent independent readings were 24,588,242,944 bytes. The reference comparison allows 1 GiB variation from either adjacent sample because available commit changes over time; it does not claim simultaneous measurement. Physical available RAM was separately 20,945,100,800 and 21,093,007,360 bytes in the respective runs.

```powershell
./tools/test-dart.ps1
```

Local logs are `.tools/dart-process-memory-red.log`, `.tools/dart-process-memory-probe-build.log` and `.tools/dart-process-memory-green.log`. An earlier Visual Studio discovery pipeline failed before SDK execution and was corrected in the fixture; it is separate from the reproduced unsupported-entity failure. Generated logs, binaries and probe build output are excluded from Git.

The [preceding RAM checkpoint](2026-11-17-dart-windows-ram.md) records Flutter Windows, framework, browser and Android runs. Those suites were not rerun for this ProcessMemory addition, and its dedicated Flutter Windows release-app scenario is not yet implemented. Native allocator/API fault injection, process job-limit scenarios, ARM64, physical memory-pressure transitions, external distribution of this addition and the full platform/device/version acceptance matrix remain pending. No native process crash isolation or universal frame-time bound is claimed.
