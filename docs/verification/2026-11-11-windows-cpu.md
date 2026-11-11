# Windows CPU topology and logical-core verification — 2026-11-11

Windows now implements CpuCore discovery/get/watch and adds physical-core/package counts to Cpu. All 54 .NET checks pass in sandbox and normal-user runs. This is the thirteenth Windows entity collector; the platform and full SDK remain incomplete.

```csharp
using DeviceReadout;
using DeviceReadout.Windows;

using var access = WindowsDeviceAccess.Create();
var cpu = await access.Get(Entities.Cpu, cancellationToken);
foreach (var target in await access.CpuCores.List(cancellationToken)) {
    CpuCoreSnapshot core = await access.Get(target, cancellationToken);
    Console.WriteLine($"{core.LogicalIndex}: {core.CurrentClockHz} Hz");
}
```

## Native mappings

The adapter reads the variable-size records from [GetLogicalProcessorInformationEx](https://learn.microsoft.com/en-us/windows/win32/api/sysinfoapi/nf-sysinfoapi-getlogicalprocessorinformationex), requesting RelationAll. Processor-core and processor-package [relationships](https://learn.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-processor_relationship) provide membership masks across processor groups. Unrelated relationship types are skipped by their declared size. Core flags/efficiency classes are not substituted for any public field.

| Field | Mapping |
|---|---|
| Cpu.logicalProcessorCount | Number of distinct active logical processors in the full system topology; existing GetActiveProcessorCount across all groups remains the independent fallback when topology is unavailable. |
| Cpu.physicalCoreCount | Number of native core relationships. |
| Cpu.processorPackageCount | Number of native package relationships, or null when that relationship is unavailable. |
| CpuCore.logicalIndex | Group × 64 + the bit number within that group's affinity mask. This SDK index can be sparse. |
| CpuCore.coreIndex / packageIndex | Relationship ordinals sorted by their lowest logical index. They are stable across record reordering, but may change when the topology changes. They are not hardware serial numbers. |
| CpuCore.online | True for processors exposed in the active topology. A target absent from a later complete inventory is retired. |
| CpuCore.currentClockHz | Native CurrentMhz × 1,000,000, when its processor number can be mapped without ambiguity. |
| CpuCore.maximumClockHz | Native MaxMhz × 1,000,000 under the same mapping conditions. |

Frequency data comes from read-only ProcessorInformation queries to [CallNtPowerInformation](https://learn.microsoft.com/en-us/windows/win32/api/powerbase/nf-powerbase-callntpowerinformation). [PROCESSOR_POWER_INFORMATION](https://learn.microsoft.com/en-us/windows/win32/power/processor-power-information-str) identifies each record by Number. CurrentMhz is the platform's reported clock value, defined using its processor throttle; MaxMhz is the specified maximum. MhzLimit is not substituted for either field. Zero remains zero, and multiplication uses floating-point Hz to avoid 32-bit overflow. No load generator or CPU policy change is performed to obtain values.

The power record has no group identifier. This implementation maps it only for a contiguous group-zero topology with at most 64 logical processors. Multi-group or sparse-numbered configurations still expose topology, while clock fields remain null pending a verified mapping. Failed, truncated, duplicate-numbered or out-of-range power records leave both clocks null without losing topology.

The existing Cpu model/vendor registry fields remain available independently. At this checkpoint, availableLogicalProcessorCount still came from Environment.ProcessorCount, which Microsoft documents as [fixed at runtime startup](https://learn.microsoft.com/en-us/dotnet/api/system.environment.processorcount?view=net-10.0). That dynamic-allocation defect was subsequently reproduced and corrected for the supported single-group process-default pool. See the [live CPU availability checkpoint](2026-11-11-windows-cpu-availability.md) for affinity/default-set/Job tests and remaining limits; it extends this historical 54-check suite to 57 checks.

## Lifetime, validation and execution

CpuCores.Current returns null: no logical CPU is chosen as an arbitrary default. Handles are context-owned and keyed by their group-aware logical identity. Successful inventories and reads retain generations for surviving processors. An observed absence permanently retires the previous handle; later reappearance creates a fresh handle. Polling a removed target ends with EntityRemoved. Failed or malformed inventories do not overwrite the last valid catalog.

Parsing checks record bounds, native mask width, group counts, nonzero affinity, duplicate logical membership and package consistency. A physical core cannot span different packages; partially covering package records are rejected. Missing package relationships can still produce core snapshots with null package fields. Unknown future native relationship kinds are not public enum values and are not returned as a fabricated field.

Native buffer sizing is bounded to 8 MiB and at most three growing-buffer attempts after the size probe. Cancellation is checked before and after native collection. All native calls, parsing, discovery, normalization and polling execute on the existing background collection worker. Construction is inert, and no affinity, CPU set, process default or power policy is modified. Existing caller deadlines remain independent of a native call's ability to return promptly.

WOW64 affinity masks can fold upper logical processors into lower mask bits, as documented for GetLogicalProcessorInformationEx. This adapter therefore does not expose CpuCore targets from a 32-bit process on a 64-bit OS yet. Those capabilities are false and discovery reports UnsupportedEntity; independent Cpu fields still return. A reliable WOW64 mapping is pending. Native x86-layout parsing alone is not a claim of tested x86 support.

## Evidence

Five public-API checks were added to the preceding 49-check suite:

* Controlled native relationship buffers distinguish five logical processors, three physical cores and two packages across two processor groups. SMT siblings, group-aware indices, stable record reordering, absent default selection and worker execution are verified.
* Controlled power records prove processor-number selection, MHz-to-Hz conversion above 32-bit integer range, preservation of zero, distinction from thermal frequency limits and partial availability.
* Actual native discovery and reads on every exposed logical processor agree with the separate GetActiveProcessorCount API. This host reports 32 logical processors, 24 physical cores and one package. Its first reported clocks are 3,200,000,000 Hz for current and maximum.
* Polling observes removal, preserves unrelated targets and assigns a new handle on reappearance. Access-denied inventories remain typed failures and do not erase earlier discovery. Independent Cpu data remains available on topology failure.
* Malformed/truncated/duplicate topology, inconsistent package membership, future unrelated relationship kinds and ambiguous power records exercise validation without corrupting valid handles.

An independent normal-user CIM query, unused by the implementation, returned one Win32_Processor instance: NumberOfCores=24, NumberOfLogicalProcessors=32, MaxClockSpeed=3200 MHz. The result is saved in `.tools/windows-cpu-independent.json`. It agrees with the native SDK counts and maximum-clock reading on this host; it does not prove dynamic clock behavior.

The final build reports zero warnings/errors. `.tools/windows-cpu-final.log` and `.tools/windows-cpu-normal-user.log` both finish with 54/54 passed. Red evidence is in `.tools/windows-cpu-topology-red.log`, `.tools/windows-cpu-clock-red.log` and `.tools/windows-cpu-package-red.log`; the latter exposed missing validation of incomplete package coverage. Other language/browser suites were not rerun for this Windows-only change.

## Remaining work

WOW64 mapping, multi-group/sparse clock association, actual CPU hotplug, ARM64 hardware and the complete Windows version/architecture matrix remain unverified or unimplemented. The subsequent availability checkpoint covers current single-group affinity/default-set/Job changes; multi-group availability and actual exclusive reservations remain unverified. This topology checkpoint uses controlled changes and a real single-package x64 host; it does not prove multi-socket or hotplug hardware support. Remaining Windows entities/events, Apple/Swift, Flutter/RN and the full cross-platform acceptance matrix remain in scope.
