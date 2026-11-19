# Swift native Apple RAM checkpoint — 2026-11-19

Native `get(Entities.ram)` and polling `watch(Entities.ram)` now collect physical and free RAM on macOS/iOS. Values remain direct nullable fields with one snapshot completion timestamp. This checkpoint is partial: pressure, process allocation allowance, minimum-OS runtime and physical-device coverage remain pending.

## Field meanings and collection

| Field | Native source and meaning |
|---|---|
| `physicalBytes` | `ProcessInfo.processInfo.physicalMemory`: physical memory reported by the executing system |
| `freeBytes` | `host_statistics64(HOST_VM_INFO64).free_count` times `host_page_size`; speculative pages are already included |
| Other RAM fields | Remain nil until a source matching each field's meaning is implemented |

Free memory is not substituted for available memory, installed physical RAM is not renamed kernel-accessible/advertised RAM, and an application's allocation allowance belongs to ProcessMemory. No low-memory state or threshold is derived from a free-byte ratio.

The read runs on the collection worker. Each acquired `mach_host_self` send-right reference is released after the read, including failures. Failed queries, zero page size, an empty or oversized statistics response and multiplication overflow leave only freeBytes nil. A successfully read free count of zero remains zero. Reads use the reported page size rather than assuming 4 KiB or 16 KiB.

References: [Foundation physicalMemory](https://developer.apple.com/documentation/foundation/processinfo/physicalmemory), [Darwin VM statistics definition](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/mach/vm_statistics.h), [mach_host_self send-right contract](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/osfmk/man/mach_host_self.html).

## Physical RAM: observed red and green

The public test at [86b6b2e](https://github.com/Sadturtleman/device-readout/commit/86b6b2e14de7c885b5d74275b698ca0603d68eab) compiles and fails with UnsupportedEntity in [Intel Release job 135458742642](https://github.com/Sadturtleman/device-readout/actions/runs/44494679246/job/135458742642).

Implementation [5537810](https://github.com/Sadturtleman/device-readout/commit/553781044ac95db427ea8652b0e18ff09ab818df) passes all six jobs in [run 44495217906](https://github.com/Sadturtleman/device-readout/actions/runs/44495217906):

| Environment | Result |
|---|---|
| macOS ARM64/Intel, Debug/Release | 94 tests per configuration; Foundation, Power and OS consumer steps pass |
| iOS device and simulator SDK builds | Four builds pass |
| iOS simulator Debug/Release | 91 tests per configuration |
| Swift 5.9.2, Ubuntu 22.04 Debug/Release | 88 tests per configuration; native Apple code is excluded |

The public test compares physicalBytes with an independent Darwin `hw.memsize` query, verifies capabilities, and checks one read plus two equal watch values with fresh timestamps. ARM and simulator runners reported 7,516,192,768 bytes; Intel reported 15,032,385,536. Simulator values describe the executing environment, not a physical iPhone's RAM.

## Free RAM: native boundary consumer

A separate SwiftPM consumer uses test-only public Darwin interposition. It checks one get and two watch snapshots for each case, while retaining physicalBytes and verifying off-main native calls:

| Case | Expected freeBytes |
|---|---|
| 512 pages at 4 KiB, with speculative pages already included | 2,097,152 |
| 512 pages at 16 KiB | 8,388,608 |
| Valid free count zero | 0 |
| Page-size query failure | nil |
| Statistics query failure | nil |
| Empty statistics response | nil |
| Invalid zero page size | nil |
| Byte-count overflow | nil |

At [ac28744](https://github.com/Sadturtleman/device-readout/commit/ac2874421cff944b8f55b01bde310e42c30ede67), [ARM Release job 135468269070](https://github.com/Sadturtleman/device-readout/actions/runs/44497480669/job/135468269070) passes the 94-test suite, compiles the fixture and then fails with the consumer's `Failure.freeValue`. The failure occurs before the free-byte implementation.

At [560a89d](https://github.com/Sadturtleman/device-readout/commit/560a89d93801f208eb488d21e919fd98b808293b), [run 44498701620](https://github.com/Sadturtleman/device-readout/actions/runs/44498701620) has verified all eight cases and 94 tests in ARM Debug and both Intel configurations. All four iOS builds pass. At this record's cutoff, ARM Release remains in the SDK test step and iOS simulator testing is running; neither is counted as a pass. Linux Swift 5.9.2 passes 88 tests in both configurations.

## Remaining work

- Complete and audit the free-RAM matrix on its exact source.
- Integrate and verify the separately reproduced sensor activity/deadline deadlock fix in PR #4; the RAM collector does not fix that shared runtime issue.
- Add matching sources for remaining RAM fields and ProcessMemory without conflating field meanings.
- Verify further native boundaries, host-right cleanup, held reads, minimum Apple OS/compiler versions and physical devices.
- Finish native sensors, framework adapters and the complete SDK acceptance matrix.

This implementation never requests permission, reads UI state or changes process-wide settings. A synchronous native call may remain in its worker after the caller's deadline; the SDK does not claim forced native interruption or process crash containment.
