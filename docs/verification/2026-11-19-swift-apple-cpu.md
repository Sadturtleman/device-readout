# Swift native Apple CPU checkpoint — 2026-11-19

Native `get(Entities.cpu)` and polling `watch(Entities.cpu)` now provide logical processor counts on macOS/iOS. The two fields use the collection worker, remain nullable, and share the snapshot completion timestamp. CPU identity, physical topology and SoC information are still being implemented; this checkpoint is not a complete CPU support claim.

## Count sources

| Field | Public Foundation source | Independent test reference |
|---|---|---|
| `logicalProcessorCount` | `ProcessInfo.processorCount` | Darwin `hw.ncpu` |
| `availableLogicalProcessorCount` | `ProcessInfo.activeProcessorCount` | Darwin `hw.logicalcpu` |

Only positive counts are exposed. No process affinity, power mode or global configuration is changed. Simulator values describe its executing environment. Model identity is not inferred from an architecture name or the device manufacturer.

References: [processorCount](https://developer.apple.com/documentation/foundation/processinfo/processorcount), [activeProcessorCount](https://developer.apple.com/documentation/foundation/processinfo/activeprocessorcount), [Apple's sysctl field meanings](https://github.com/apple-oss-distributions/xnu/blob/main/libkern/libkern/sysctl.h).

## Observed red and verified count implementation

The public test was published at [aa7ee1b](https://github.com/Sadturtleman/device-readout/commit/aa7ee1b08c7833d3db9cc251377c4f86b06d3d26) before implementation. [ARM Debug job 135495283142](https://github.com/Sadturtleman/device-readout/actions/runs/44505320221/job/135495283142) compiled successfully and then failed with UnsupportedEntity: 95 tests, exactly one failure.

Implementation [a74cd8d](https://github.com/Sadturtleman/device-readout/commit/a74cd8d98bfde0708447ddf0479961884bdabcba) passed all six jobs in [run 44507408189](https://github.com/Sadturtleman/device-readout/actions/runs/44507408189):

| Environment | Result |
|---|---|
| macOS ARM64/Intel, Debug/Release | 95 public SDK tests per configuration |
| iOS device/simulator SDK builds | Four successful builds targeting iOS 16 |
| iOS simulator, Debug/Release | 92 public SDK tests per configuration |
| Swift 5.9.2 / Ubuntu 22.04, Debug/Release | 88 tests per configuration; Apple-native code excluded |

The CPU test checks an independent reference, capabilities, one get and two watch snapshots with fresh timestamps. ARM and simulator runners reported three logical/available processors; Intel reported four. The same four macOS jobs also pass their Foundation, Power, OS, eight RAM boundary cases and 1,000-cycle sensor activity/deadline consumer. The audit compares all 599 non-Markdown source inputs and raw job records; Linux compiler-version and complete suite records are included.

## Next native boundaries

The new physical-topology test compares `physicalCoreCount` and `processorPackageCount` with a separate `sysctl` process. Its proposed public sources are `hw.physicalcpu_max` and `hw.packages`, preserving the system's boot-time topology instead of treating currently active cores as total physical cores. Apple publishes both selectors in [XNU's hardware sysctls](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_mib.c). This test is added before connecting those fields; its actual failure and subsequent implementation are not yet claimed here.

Remaining work includes physical topology and CPU/SoC identity, native unavailable/malformed/held-call behavior, Apple minimum compiler/OS runtime, physical devices, CPU-core discovery and the complete SDK acceptance matrix. No public API reads UI state or opens a permission prompt.
