# Windows live CPU availability verification — 2026-11-11

Windows Cpu.availableLogicalProcessorCount now reads current process scheduling configuration instead of the runtime's startup-cached count. All 57 .NET checks pass in sandbox and normal-user runs. The Windows collector count remains thirteen; this field correction does not complete the platform or the full SDK.

## Field meaning and native mapping

The field counts distinct logical processors in the process's default scheduling pool, considering process affinity, default CPU-set selection and CPU-set reservations. It does not convert a CPU-time percentage into an equivalent processor count. That interpretation preserves the design's logical-processor unit; the optional user clarification about CPU-time conversion remains unanswered at this checkpoint. Explicit thread-specific overrides are not aggregated into a process-wide union.

[Environment.ProcessorCount](https://learn.microsoft.com/en-us/dotnet/api/system.environment.processorcount?view=net-10.0) is fixed at runtime startup and may incorporate CPU-utilization limits. The native regression first reproduced the stale result: after changing the owned child's affinity to one logical processor, the existing SDK returned 32. Merely replacing that source with the affinity mask then left the default-CPU-set case incorrect; the second native regression expected one and received 32.

| Input | Mapping |
|---|---|
| GetActiveProcessorGroupCount / GetActiveProcessorCount | Establish whether the current process-mask representation can describe the supported single active group. |
| GetProcessAffinityMask | Current process and system masks; count only processors within the process mask. Job affinity restrictions reflected in this mask are included. |
| GetProcessDefaultCpuSets | Current process-default CPU-set IDs, including a successful empty selection. |
| GetSystemCpuSetInformation | Resolve IDs to group/home logical processor and reservation flags, using the current process handle for allocation ownership. |

[CPU Sets](https://learn.microsoft.com/en-us/windows/win32/procthread/cpu-sets) are soft selections. Hard affinity takes precedence when it conflicts with a selection; a set reserved for another process is unavailable to this process. The adapter intersects eligible selected processors with hard affinity and falls back to the eligible affinity pool when the selection has no usable intersection. Multiple set IDs with the same home logical processor count once. Parked processors remain eligible and are not treated as removed or offline. This count is not a guarantee about where a particular thread will run at every instant.

The variable-size [SYSTEM_CPU_SET_INFORMATION](https://learn.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-system_cpu_set_information) records are checked for bounds, duplicate IDs, logical index and known reservation flags. Unrelated native record types are skipped by their declared size; incomplete home-processor coverage still makes the field null. Unresolvable selected IDs, invalid records and native query failures leave this field null while independent Cpu fields remain available.

Affinity and default selection are read again after metadata collection. Observed disagreement produces null without an automatic retry. This detects the covered concurrent changes, but is not an atomic OS snapshot and cannot rule out every change-and-restore race or reservation change between native calls.

The [GetProcessDefaultCpuSets](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-getprocessdefaultcpusets) and [GetSystemCpuSetInformation](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-getsystemcpusetinformation) size protocols use bounded buffer growth: at most three growing-buffer attempts, 65,536 selected IDs and 8 MiB of metadata. They are buffer-size negotiations, not hidden retries of failed get/watch operations. Cancellation checks surround collection.

## Execution and isolation

Construction is inert. Queries, parsing and counting run on the existing collection worker. Get reads current state; watch serially polls it and retains equal-value snapshots. Existing immutable poll settings, cancellation, cleanup and independent caller deadlines remain in effect.

Production code contains no affinity, CPU-set or Job setters. Native mutation tests run in an owned child process; setters affect only that child, with restoration in finally blocks. The fixture uses an unnamed Job and no kill-on-close policy. The parent waits with a deadline and can terminate only its owned child if the fixture fails to finish. No application outside the fixture, system-wide policy, UI state or permission prompt is changed.

Public tests read affinity and default CPU-set settings back after SDK queries to confirm they remain unchanged. Controlled OS seams record all availability getter calls on one collection thread distinct from the caller. These checks do not claim zero CPU overhead or native process-crash isolation.

## Evidence

Three public-API cases extend the preceding 54-check suite:

| Case | Evidence |
|---|---|
| Actual Windows child process | One SDK instance observes affinity 32 → 1 → 32, default CPU set → 1, clearing the selection → 32, and conflicting hard/soft selections → 1. A 25 ms polling view observes affinity → 2 and preserves the following equal value. |
| Actual private child Job | A 50% CPU-time hard cap leaves the logical count at 32; changing Job affinity to two processors produces 2. Limits are restored on exit. |
| Controlled reservation and parsing inputs | Parked/other-process-reserved/own-reserved sets, selected subsets, disjoint hard affinity and duplicate home processors have distinct expected results. These fixtures are not actual hardware-reservation evidence. |
| Controlled unavailable or racing inputs | Multi-group ambiguity, wide WOW64 masks, invalid affinity, missing IDs, malformed metadata, access denial and affinity/selection changes during collection produce null only for availability. Other Cpu topology fields remain readable. |

The Job tests distinguish [affinity limits](https://learn.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-jobobject_basic_limit_information) from [CPU rate control](https://learn.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-jobobject_cpu_rate_control_information). The SDK reads the effective process affinity and does not query or calculate a nested-Job CPU-time quota.

`tools/test-dotnet.ps1` finishes with zero build warnings/errors and 57/57 passed in `.tools/windows-cpu-availability-final.log`. Executing the same built test assembly in a normal-user process finishes with 57/57 passed in `.tools/windows-cpu-availability-normal-user.log`. Initial failures are recorded in `.tools/windows-cpu-availability-red.log` and `.tools/windows-cpu-sets-red.log`. No other language/browser suites were rerun for this Windows-only change.

## Remaining work

* Multi-active-group availability currently returns null. On Windows 11, [GetProcessAffinityMask](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-getprocessaffinitymask) alone cannot establish the whole-process mask across groups. Cpu topology remains separately available under its documented mapping.
* A 32-bit mask on a system with more active group processors than it can represent returns null. Actual WOW64 and ARM64 execution still need verification.
* Thread-specific affinity/CPU-set overrides are outside the process-default count. No all-thread aggregate or capacity-equivalent quota is provided.
* Actual exclusive CPU reservations, multi-group hardware, CPU hotplug and the full Windows version matrix remain unverified. Concurrent read checks do not make the native snapshot atomic.
* The earlier [CPU topology checkpoint](2026-11-11-windows-cpu.md) still lists incomplete multi-group/sparse clock mapping and physical topology evidence. Remaining Windows entities/events, Apple/Swift, Flutter/RN and the cross-platform acceptance matrix remain in scope.
