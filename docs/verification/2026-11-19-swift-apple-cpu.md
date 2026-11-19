# Swift native Apple CPU checkpoint — 2026-11-19

Native `get(Entities.cpu)` and polling `watch(Entities.cpu)` now provide CPU model/vendor where available, logical processor counts, physical core count and processor package count on macOS/iOS. macOS additionally reads the direct device-tree SoC model. The fields use the collection worker, remain nullable, and share the snapshot completion timestamp. iOS SoC identity, SoC manufacturer and CPU-core discovery remain pending; this checkpoint is not a complete CPU support claim.

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

## CPU model and vendor: native strings and caller isolation

`model` reads public Darwin `machdep.cpu.brand_string`; `manufacturer` reads `machdep.cpu.vendor`. Each string uses a size query followed by one bounded data read. Sizes outside 2–4096 bytes, read failures, reported growth, missing/empty NUL termination and invalid UTF-8 leave only that field nil. Valid Unicode, a shrinking response and a 4095-byte payload are preserved. Unwritten buffer bytes cannot fabricate a terminator. No SDK read runs a command, prompts for permission or infers a vendor from the model text.

Apple's [ARM implementation](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/dev/arm64/sysctl.c) can supply either the product SoC name or a generic processor description as the CPU brand. The SDK therefore does not copy that field into `socModel`. The [Intel implementation](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/dev/i386/sysctl.c) publishes the CPUID model/vendor strings. These are platform-provided strings rather than normalized company names.

Before implementation, [3dd1a6f / ARM Release](https://github.com/Sadturtleman/device-readout/actions/runs/44513730551/job/135524644525) compiles and fails three model assertions against the independent `Apple M1 (Virtual)` reference. [Intel Debug](https://github.com/Sadturtleman/device-readout/actions/runs/44513730551/job/135524644599) fails six model/vendor assertions against the independent Intel model and `GenuineIntel`. Each suite contains 98 tests. Implementation c642f75 then passes the 98-test suite in all four macOS configurations and all four iOS builds; that intermediate simulator job was cancelled when boundary validation was published and is not counted as a pass.

Final source [504e3c4](https://github.com/Sadturtleman/device-readout/commit/504e3c4a1b36f53044d147b319714634524f6755) passes all six jobs in [run 44515283127](https://github.com/Sadturtleman/device-readout/actions/runs/44515283127):

| Environment | Result |
|---|---|
| macOS ARM64/Intel, Debug/Release | 99 public SDK tests per configuration; independent system-command and one-call Darwin references agree |
| iOS simulator, Debug/Release | 94 public SDK tests per configuration; one-call Darwin reference agrees |
| iOS device/simulator SDK builds | Four successful builds targeting iOS 16 |
| Swift 5.9.2 / Ubuntu 22.04, Debug/Release | 88 tests per configuration; Apple-native code excluded |

Each macOS configuration also runs 18 separate CPU-identity consumer cases: known strings, Unicode, shrinking data, maximum accepted size, each field failing, data-read failure, zero/one/oversized/overflowing sizes, empty/missing termination, a partial write, invalid UTF-8, reported growth, held get and held watch. Invalid size responses must not trigger a data read. Value cases preserve all four native counts and verify one get plus two fresh watch snapshots. Held calls require the read timeout, close, another context's read and MainActor progress to complete before explicit native release. The interposition library is injected only into the child consumer; an external watchdog bounds each test process.

The final audit matches all 608 non-Markdown source inputs and the raw logs, including both identity failures. It verifies 72 identity cases, the existing 36 topology cases, 32 RAM cases, 12 OS cases, Power/Foundation consumers and 4,000 sensor activity/deadline cycles across the four macOS configurations. ARM and iOS simulator runners expose `Apple M1 (Virtual)` and no vendor; Intel exposes its CPUID brand and `GenuineIntel`. Simulator values describe its executing environment, not a physical iPhone.

## macOS SoC model and IOKit ownership

The macOS collector reads `product-soc-name` directly from `IODeviceTree:/product` through public IOKit APIs. It accepts a 2–4096-byte Data value containing a nonempty, NUL-terminated UTF-8 string. Missing entries/properties, wrong types, empty data, invalid text and oversized data leave `socModel` nil. Every acquired registry entry is released on the collection worker, including failed reads. iOS `socModel` and `socManufacturer` remain nil.

Apple's [device-tree implementation](https://github.com/apple-oss-distributions/xnu/blob/main/iokit/Kernel/IODeviceTreeSupport.cpp) exports raw properties as OSData, and the [public IOKit header](https://github.com/apple-oss-distributions/IOKitUser/blob/main/IOKitLib.h) defines the entry and property ownership rules. The independent test uses a separate `ioreg` process; the product collector does not run a command.

At test-only source [3f424f4](https://github.com/Sadturtleman/device-readout/commit/3f424f431b57054b81c9b648218ece55006f8e72), [ARM Release](https://github.com/Sadturtleman/device-readout/actions/runs/44517149421/job/135537352510) compiles and fails three get/watch assertions: ioreg reports `Apple M1 (Virtual)`, while SDK `socModel` is nil. Implementation 9f113fa passes all 100 tests and 17 SoC consumer cases in ARM Debug. Both Intel configurations pass the 17 cases but fail the independent reference parser: ioreg emits an empty response when its product search has no match. The [ioreg source](https://github.com/apple-oss-distributions/IOKitTools/blob/main/ioreg.tproj/ioreg.c) confirms that a missing archive is a successful empty response. Test correction 5a986db accepts only that empty case; malformed nonempty responses still fail, and the SDK collector is unchanged.

The 17 consumer cases cover known/Unicode/maximum-sized values, absent entries/properties, wrong types, empty data/strings, missing termination, invalid UTF-8, oversized data, and held lookup/property/release calls for both get and watch. They require fresh snapshots, preserved CPU fields, off-main native calls and balanced entry release. Held calls must allow the caller timeout, close, MainActor progress and another context's read before explicit release. Each fixture is confined to its child consumer.

Verification of source [5a986db](https://github.com/Sadturtleman/device-readout/commit/5a986db8167bb2b7d1401af77c7a74357ef41fe4) is in progress in [run 44519407054](https://github.com/Sadturtleman/device-readout/actions/runs/44519407054). All four ARM64/Intel Debug/Release configurations each pass 100 tests and all 17 SoC cases. All four iOS SDK builds and Swift 5.9.2/Linux 88-test Debug/Release suites pass. The initial ARM Release and iOS simulator jobs never acquired a runner and were cancelled; GitHub reported macOS ARM64 capacity constraints. Only those two jobs were retried: [ARM Release](https://github.com/Sadturtleman/device-readout/actions/runs/44519407054/job/135553323407) now passes, while [iOS simulator](https://github.com/Sadturtleman/device-readout/actions/runs/44519407054/job/135553322873) is still running. All 612 non-Markdown source inputs match the tested commit. The complete matrix and final raw-log audit remain pending.

## Remaining work

The remaining SoC matrix/audit, iOS SoC and SoC manufacturer sources, native minimum-OS and physical-device boundaries, actual minimum Apple compiler, CPU-core discovery and the complete SDK acceptance matrix remain pending. Native iOS package-count and identity behavior also need physical-device evidence. No public API reads UI state, opens a permission prompt or changes process settings. A deadline does not forcibly interrupt a synchronous OS call; the verified guarantee is caller progress while that call remains held.
