#include <windows.h>
#include <stdint.h>

static uint32_t counts[4];
static WCHAR model[32768], vendor[32768];
static BOOL model_valid, vendor_valid;
static uint32_t bit_count(ULONG_PTR value) {
    uint32_t count = 0;
    while (value) { value &= value - 1; ++count; }
    return count;
}
static uint32_t relationship_count(LOGICAL_PROCESSOR_RELATIONSHIP kind) {
    DWORD length = 0;
    if (GetLogicalProcessorInformationEx(kind, NULL, &length) ||
        GetLastError() != ERROR_INSUFFICIENT_BUFFER || !length || length > 8 * 1024 * 1024) return UINT32_MAX;
    BYTE *data = HeapAlloc(GetProcessHeap(), 0, length);
    if (!data) return UINT32_MAX;
    DWORD capacity = length;
    uint32_t count = 0;
    if (!GetLogicalProcessorInformationEx(kind, (PSYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX)data, &length) || length > capacity) count = UINT32_MAX;
    else for (DWORD offset = 0; offset < length;) {
        if (length - offset < 8) { count = UINT32_MAX; break; }
        PSYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX item = (void *)(data + offset);
        if (item->Size < 8 || item->Size > length - offset || item->Relationship != kind) { count = UINT32_MAX; break; }
        ++count; offset += item->Size;
    }
    HeapFree(GetProcessHeap(), 0, data);
    return count;
}
static uint32_t available_count(void) {
    if (GetActiveProcessorGroupCount() != 1) return UINT32_MAX;
    ULONG_PTR process = 0, system = 0;
    if (!GetProcessAffinityMask(GetCurrentProcess(), &process, &system) || !process) return UINT32_MAX;
    ULONG required = 0;
    BOOL empty = GetProcessDefaultCpuSets(GetCurrentProcess(), NULL, 0, &required);
    if ((!empty && GetLastError() != ERROR_INSUFFICIENT_BUFFER) || required > 65536) return UINT32_MAX;
    ULONG *selected = required ? HeapAlloc(GetProcessHeap(), 0, required * sizeof(ULONG)) : NULL;
    ULONG capacity = required;
    if (required && (!selected || !GetProcessDefaultCpuSets(GetCurrentProcess(), selected, capacity, &required) || required > capacity)) {
        if (selected) HeapFree(GetProcessHeap(), 0, selected);
        return UINT32_MAX;
    }
    ULONG length = 0;
    BOOL sized = GetSystemCpuSetInformation(NULL, 0, &length, GetCurrentProcess(), 0);
    if ((!sized && GetLastError() != ERROR_INSUFFICIENT_BUFFER) || length > 8 * 1024 * 1024) {
        if (selected) HeapFree(GetProcessHeap(), 0, selected);
        return UINT32_MAX;
    }
    BYTE *data = length ? HeapAlloc(GetProcessHeap(), 0, length) : NULL;
    ULONG byte_capacity = length;
    uint32_t result = UINT32_MAX;
    if (length && (!data || !GetSystemCpuSetInformation((PSYSTEM_CPU_SET_INFORMATION)data, length, &length, GetCurrentProcess(), 0) || length > byte_capacity)) goto cleanup;
    ULONG_PTR known = 0, eligible = 0, preferred = 0;
    for (ULONG offset = 0; offset < length;) {
        if (length - offset < 8) goto cleanup;
        PSYSTEM_CPU_SET_INFORMATION item = (void *)(data + offset);
        if (item->Size < sizeof(SYSTEM_CPU_SET_INFORMATION) || item->Size > length - offset || item->Type != CpuSetInformation) goto cleanup;
        if (item->CpuSet.Group != 0 || item->CpuSet.LogicalProcessorIndex >= sizeof(ULONG_PTR) * 8) goto cleanup;
        ULONG_PTR bit = (ULONG_PTR)1 << item->CpuSet.LogicalProcessorIndex;
        known |= bit;
        if (!item->CpuSet.Allocated || item->CpuSet.AllocatedToTargetProcess) {
            eligible |= bit;
            for (ULONG i = 0; i < required; ++i) if (selected[i] == item->CpuSet.Id) preferred |= bit;
        }
        offset += item->Size;
    }
    if (!length && !required) result = bit_count(process);
    else if ((system & ~known) == 0) {
        eligible &= process; preferred &= eligible;
        ULONG_PTR available = required && preferred ? preferred : eligible;
        if (available) result = bit_count(available);
    }
cleanup:
    if (data) HeapFree(GetProcessHeap(), 0, data);
    if (selected) HeapFree(GetProcessHeap(), 0, selected);
    return result;
}
__declspec(dllexport) void readout_probe_cpu_refresh(void) {
    counts[0] = GetActiveProcessorCount(ALL_PROCESSOR_GROUPS);
    counts[1] = relationship_count(RelationProcessorCore);
    counts[2] = relationship_count(RelationProcessorPackage);
    counts[3] = available_count();
    DWORD bytes = sizeof(model);
    model_valid = RegGetValueW(HKEY_LOCAL_MACHINE, L"HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0",
        L"ProcessorNameString", RRF_RT_REG_SZ | RRF_SUBKEY_WOW6464KEY | RRF_ZEROONFAILURE,
        NULL, model, &bytes) == ERROR_SUCCESS;
    bytes = sizeof(vendor);
    vendor_valid = RegGetValueW(HKEY_LOCAL_MACHINE, L"HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0",
        L"VendorIdentifier", RRF_RT_REG_SZ | RRF_SUBKEY_WOW6464KEY | RRF_ZEROONFAILURE,
        NULL, vendor, &bytes) == ERROR_SUCCESS;
}
__declspec(dllexport) uint32_t readout_probe_cpu_count(uint32_t field) {
    return field < 4 ? counts[field] : UINT32_MAX;
}
__declspec(dllexport) const WCHAR* readout_probe_cpu_text(uint32_t field) {
    return field == 0 && model_valid ? model : field == 1 && vendor_valid ? vendor : NULL;
}
