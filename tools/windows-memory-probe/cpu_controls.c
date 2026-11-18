#include <windows.h>
#include <stdint.h>
#include <string.h>

/* Controls affect only an explicitly owned test child. The SDK never links this
   library or invokes any affinity, CPU-set or job setter. */
static ULONG_PTR original_mask, system_mask, first_bit, second_bit, expected_mask;
static ULONG first_id, second_id, original_count, expected_count;
static ULONG *original_ids;
static HANDLE job;
static DWORD expected_rate;
static BOOL started;

static DWORD default_ids(ULONG **ids, ULONG *count) {
    *ids = NULL; *count = 0;
    if (GetProcessDefaultCpuSets(GetCurrentProcess(), NULL, 0, count)) return *count ? ERROR_INVALID_DATA : 0;
    DWORD error = GetLastError();
    if (error != ERROR_INSUFFICIENT_BUFFER || !*count || *count > 65536) return error ? error : ERROR_INVALID_DATA;
    ULONG capacity = *count;
    *ids = HeapAlloc(GetProcessHeap(), 0, capacity * sizeof(ULONG));
    if (!*ids) return ERROR_NOT_ENOUGH_MEMORY;
    if (!GetProcessDefaultCpuSets(GetCurrentProcess(), *ids, capacity, count) || *count > capacity) {
        error = GetLastError(); HeapFree(GetProcessHeap(), 0, *ids); *ids = NULL;
        return error ? error : ERROR_INVALID_DATA;
    }
    return 0;
}

__declspec(dllexport) DWORD readout_cpu_controls_begin(DWORD parent) {
    if (!parent || parent == GetCurrentProcessId() || started || GetActiveProcessorGroupCount() != 1) return ERROR_INVALID_PARAMETER;
    if (!GetProcessAffinityMask(GetCurrentProcess(), &original_mask, &system_mask)) return GetLastError();
    DWORD error = default_ids(&original_ids, &original_count);
    if (error) return error;
    ULONG length = 0;
    if (GetSystemCpuSetInformation(NULL, 0, &length, GetCurrentProcess(), 0) || GetLastError() != ERROR_INSUFFICIENT_BUFFER || !length || length > 8 * 1024 * 1024) return ERROR_INVALID_DATA;
    BYTE *data = HeapAlloc(GetProcessHeap(), 0, length);
    if (!data) return ERROR_NOT_ENOUGH_MEMORY;
    ULONG capacity = length;
    if (!GetSystemCpuSetInformation((void *)data, length, &length, GetCurrentProcess(), 0) || length > capacity) {
        error = GetLastError(); HeapFree(GetProcessHeap(), 0, data); return error ? error : ERROR_INVALID_DATA;
    }
    for (ULONG offset = 0; offset < length;) {
        if (length - offset < 8) break;
        PSYSTEM_CPU_SET_INFORMATION info = (void *)(data + offset);
        if (info->Size < sizeof(*info) || info->Size > length - offset) break;
        if (info->Type == CpuSetInformation && info->CpuSet.Group == 0 && info->CpuSet.LogicalProcessorIndex < sizeof(ULONG_PTR) * 8 &&
            (!info->CpuSet.Allocated || info->CpuSet.AllocatedToTargetProcess)) {
            ULONG_PTR bit = (ULONG_PTR)1 << info->CpuSet.LogicalProcessorIndex;
            if (original_mask & bit) {
                if (!first_bit) { first_bit = bit; first_id = info->CpuSet.Id; }
                else if (!second_bit && bit != first_bit) { second_bit = bit; second_id = info->CpuSet.Id; }
            }
        }
        offset += info->Size;
    }
    HeapFree(GetProcessHeap(), 0, data);
    if (!first_bit || !second_bit) return ERROR_NOT_SUPPORTED;
    started = TRUE;
    return 0;
}

__declspec(dllexport) DWORD readout_cpu_controls_apply(DWORD mode) {
    if (!started || mode < 1 || mode > 4) return ERROR_INVALID_PARAMETER;
    expected_mask = mode == 1 || mode == 3 ? first_bit : first_bit | second_bit;
    expected_count = mode == 2 || mode == 3 ? 1 : 0;
    ULONG selected = mode == 3 ? second_id : first_id;
    if (!SetProcessDefaultCpuSets(GetCurrentProcess(), expected_count ? &selected : NULL, expected_count)) return GetLastError();
    if (!SetProcessAffinityMask(GetCurrentProcess(), expected_mask)) return GetLastError();
    expected_rate = 0;
    if (mode == 4) {
        job = CreateJobObjectW(NULL, NULL);
        if (!job) return GetLastError();
        JOBOBJECT_CPU_RATE_CONTROL_INFORMATION rate = {0};
        rate.ControlFlags = JOB_OBJECT_CPU_RATE_CONTROL_ENABLE | JOB_OBJECT_CPU_RATE_CONTROL_HARD_CAP;
        rate.CpuRate = 5000;
        if (!SetInformationJobObject(job, JobObjectCpuRateControlInformation, &rate, sizeof(rate)) ||
            !AssignProcessToJobObject(job, GetCurrentProcess())) return GetLastError();
        expected_rate = 5000;
    }
    return 0;
}

__declspec(dllexport) DWORD readout_cpu_controls_verify(DWORD mode) {
    ULONG_PTR process = 0, system = 0;
    if (!GetProcessAffinityMask(GetCurrentProcess(), &process, &system) || process != expected_mask || system != system_mask) return ERROR_INVALID_DATA;
    ULONG *ids = NULL, count = 0;
    DWORD error = default_ids(&ids, &count);
    if (!error && (count != expected_count || (count && ids[0] != (mode == 3 ? second_id : first_id)))) error = ERROR_INVALID_DATA;
    if (ids) HeapFree(GetProcessHeap(), 0, ids);
    if (error) return error;
    if (job) {
        JOBOBJECT_CPU_RATE_CONTROL_INFORMATION rate = {0};
        if (!QueryInformationJobObject(job, JobObjectCpuRateControlInformation, &rate, sizeof(rate), NULL) ||
            rate.CpuRate != expected_rate || rate.ControlFlags != (JOB_OBJECT_CPU_RATE_CONTROL_ENABLE | JOB_OBJECT_CPU_RATE_CONTROL_HARD_CAP)) return ERROR_INVALID_DATA;
    }
    return 0;
}

__declspec(dllexport) DWORD readout_cpu_controls_restore(void) {
    DWORD error = 0;
    if (job) {
        JOBOBJECT_CPU_RATE_CONTROL_INFORMATION rate = {0};
        if (!SetInformationJobObject(job, JobObjectCpuRateControlInformation, &rate, sizeof(rate))) error = GetLastError();
        CloseHandle(job); job = NULL;
    }
    if (started) {
        if (!SetProcessAffinityMask(GetCurrentProcess(), original_mask) && !error) error = GetLastError();
        if (!SetProcessDefaultCpuSets(GetCurrentProcess(), original_ids, original_count) && !error) error = GetLastError();
    }
    return error;
}

__declspec(dllexport) DWORD readout_cpu_controls_finish(void) {
    DWORD error = readout_cpu_controls_restore();
    if (original_ids) HeapFree(GetProcessHeap(), 0, original_ids);
    original_ids = NULL; original_count = 0; started = FALSE;
    return error;
}
