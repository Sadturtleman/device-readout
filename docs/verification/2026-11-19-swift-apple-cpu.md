# Swift native Apple CPU checkpoint — 2026-11-19

Native `get(Entities.cpu)` and polling `watch(Entities.cpu)` now provide logical processor counts, physical core count and processor package count on macOS/iOS. The four fields use the collection worker, remain nullable, and share the snapshot completion timestamp. CPU/SoC identity and CPU-core discovery are still being implemented; this checkpoint is not a complete CPU support claim.

## Count sources

| Field | Public native source | Independent test reference |
|---|---|---|
| `logicalProcessorCount` | `ProcessInfo.processorCount` | Darwin `hw.ncpu` |
| `availableLogicalProcessorCount` | `ProcessInfo.activeProcessorCount` | Darwin `hw.logicalcpu` |
| `physicalCoreCount` | Darwin `hw.physicalcpu_max` | Separate macOS sysctl process and Mach HOST_BASIC_INFO on macOS/iOS |
| `processorPackageCount` | Darwin `hw.packages` | Separate macOS sysctl process |

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

## Physical topology: observed red and native boundary checks

At [3b2dd02](https://github.com/Sadturtleman/device-readout/commit/3b2dd025c734e8caccddf545187d2b65198aec97), [ARM Debug job 135508739264](https://github.com/Sadturtleman/device-readout/actions/runs/44509215704/job/135508739264) compiles, then compares nil SDK values with the independent three physical cores/one package reference. The new test produces six failed assertions across get and two watch snapshots; the complete suite contains 96 tests.

Implementation [6114c0f](https://github.com/Sadturtleman/device-readout/commit/6114c0fca5665ef010b17e62710f1639fb969820) passes all 96 tests in [ARM Debug](https://github.com/Sadturtleman/device-readout/actions/runs/44509657834/job/135511343618), both Release configurations and the four iOS SDK builds. Swift 5.9.2/Linux passes 88 tests in each configuration. The intermediate iOS simulator and Intel Debug jobs were cancelled when the boundary tests were published; they are not counted as passes.

Physical topology uses the system's boot-time physical core count, not its currently active core count. Both native integers require a successful read, exactly four response bytes and a positive signed 32-bit value. A failed field remains nil while the other topology field and logical counts are preserved. [Apple's hardware sysctls](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_mib.c) publish the two selectors.

Source [6586829](https://github.com/Sadturtleman/device-readout/commit/65868292964e6c7d8c4ad02851b081f8a8a589d3) adds a separate consumer with test-only public Darwin interposition. The library is injected only into that child consumer. Its nine cases are:

| Case | Required behavior |
|---|---|
| Known topology | Two physical cores and one package, with native logical counts preserved |
| Physical query failure | Only physicalCoreCount is nil |
| Package query failure | Only processorPackageCount is nil |
| Zero or negative counts | Both topology fields are nil |
| Short or oversized reported response | Both topology fields are nil; the fixture never writes outside the actual buffer |
| Held get | Deadline, close, other-context read and MainActor progress complete before native release |
| Held watch | First-read deadline, close, other-context read and MainActor progress complete before native release |

The seven value/failure cases verify get and two fresh watch snapshots. Every case verifies off-main native calls. Held calls use an explicit release gate, and each child process has an external 15-second watchdog.

All six jobs in [run 44510495856](https://github.com/Sadturtleman/device-readout/actions/runs/44510495856) complete successfully on source 6586829. Each macOS ARM64/Intel Debug/Release configuration passes 97 public SDK tests and all nine CPU boundary cases: 36 cases total. iOS simulator Debug/Release each pass 93 tests, including the independent Mach physical-core reference. All four iOS SDK builds and Swift 5.9.2/Linux 88-test Debug/Release suites pass.

The final audit compares all 604 non-Markdown source inputs with the captured source, each job's commit and raw result records, and both pre-implementation failures. The same four macOS jobs pass 32 RAM boundary cases, 12 OS consumer cases, the Power/Foundation consumers and 4,000 sensor activity/deadline cycles. Simulator runs target the executing simulator environment; these results do not establish physical iPhone or minimum-OS runtime behavior.

## Remaining work

CPU/SoC identity, native minimum-OS and physical-device boundaries, actual minimum Apple compiler, CPU-core discovery and the complete SDK acceptance matrix remain pending. Native iOS package-count behavior also needs physical-device evidence. No public API reads UI state, opens a permission prompt or changes process settings. A deadline does not forcibly interrupt a synchronous OS call; the verified guarantee is caller progress while that call remains held.
