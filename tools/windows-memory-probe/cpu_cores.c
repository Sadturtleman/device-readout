#include <windows.h>
#include <stdint.h>
#include <stddef.h>
#include <powrprof.h>

/* Independent Windows SDK topology reads for the current verification host.
   Each relationship is queried separately and compared as a membership graph. */
#define CORE_LIMIT 4096
static uint32_t core_min[CORE_LIMIT], package_min[CORE_LIMIT], logical_ids[CORE_LIMIT], logical_count;
typedef struct ReadoutCorePower {
    ULONG Number, MaxMhz, CurrentMhz, MhzLimit, MaxIdleState, CurrentIdleState;
} ReadoutCorePower;
static ULONG current_mhz[64], maximum_mhz[64];
static BOOL clocks_valid;
static void read_clocks(void) {
    clocks_valid = FALSE;
    if (!logical_count || logical_count > 64 || GetActiveProcessorGroupCount() != 1) return;
    for (uint32_t i = 0; i < logical_count; i++) if (logical_ids[i] != i) return;
    SYSTEM_INFO info; GetSystemInfo(&info);
    if (info.dwNumberOfProcessors != logical_count) return;
    ReadoutCorePower values[64] = {0};
    if (CallNtPowerInformation(ProcessorInformation, NULL, 0, values, logical_count * sizeof(ReadoutCorePower)) != 0) return;
    BOOL seen[64] = {0};
    for (uint32_t i = 0; i < logical_count; i++) {
        ULONG number = values[i].Number;
        if (number >= logical_count || seen[number]) return;
        seen[number] = TRUE;
        current_mhz[number] = values[i].CurrentMhz;
        maximum_mhz[number] = values[i].MaxMhz;
    }
    clocks_valid = TRUE;
}
static BOOL read_members(LOGICAL_PROCESSOR_RELATIONSHIP kind, uint32_t *membership) {
    DWORD bytes = 0;
    if (GetLogicalProcessorInformationEx(kind, NULL, &bytes) || GetLastError() != ERROR_INSUFFICIENT_BUFFER ||
        !bytes || bytes > 8 * 1024 * 1024) return FALSE;
    BYTE *data = HeapAlloc(GetProcessHeap(), 0, bytes);
    if (!data) return FALSE;
    DWORD capacity = bytes;
    BOOL valid = FALSE;
    if (!GetLogicalProcessorInformationEx(kind, (void *)data, &bytes) || bytes > capacity) goto done;
    for (DWORD offset = 0; offset < bytes;) {
        if (bytes - offset < 8) goto done;
        PSYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX item = (void *)(data + offset);
        if (item->Size < offsetof(SYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX, Processor.GroupMask) ||
            item->Size > bytes - offset || item->Relationship != kind) goto done;
        WORD groups = item->Processor.GroupCount;
        if (!groups || (kind == RelationProcessorCore && groups != 1) ||
            offsetof(SYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX, Processor.GroupMask) + groups * sizeof(GROUP_AFFINITY) > item->Size) goto done;
        uint32_t smallest = UINT32_MAX;
        for (WORD g = 0; g < groups; g++) {
            GROUP_AFFINITY group = item->Processor.GroupMask[g];
            for (DWORD bit = 0; bit < 64; bit++) if (group.Mask & ((KAFFINITY)1 << bit)) {
                uint32_t index = group.Group * 64 + bit;
                if (index >= CORE_LIMIT) goto done;
                if (index < smallest) smallest = index;
            }
        }
        if (smallest == UINT32_MAX) goto done;
        for (WORD g = 0; g < groups; g++) {
            GROUP_AFFINITY group = item->Processor.GroupMask[g];
            for (DWORD bit = 0; bit < 64; bit++) if (group.Mask & ((KAFFINITY)1 << bit)) {
                uint32_t index = group.Group * 64 + bit;
                if (membership[index] != UINT32_MAX) goto done;
                membership[index] = smallest;
            }
        }
        offset += item->Size;
    }
    valid = TRUE;
done:
    HeapFree(GetProcessHeap(), 0, data);
    return valid;
}
__declspec(dllexport) uint32_t readout_probe_cpu_cores_refresh(void) {
    logical_count = 0;
    clocks_valid = FALSE;
    for (uint32_t i = 0; i < CORE_LIMIT; i++) core_min[i] = package_min[i] = UINT32_MAX;
    if (!read_members(RelationProcessorCore, core_min) || !read_members(RelationProcessorPackage, package_min)) return UINT32_MAX;
    for (uint32_t i = 0; i < CORE_LIMIT; i++) if (core_min[i] != UINT32_MAX) {
        if (package_min[i] == UINT32_MAX) return UINT32_MAX;
        logical_ids[logical_count++] = i;
    }
    read_clocks();
    return logical_count;
}
__declspec(dllexport) uint32_t readout_probe_cpu_core_clocks_valid(void) { return clocks_valid ? 1 : 0; }
__declspec(dllexport) uint32_t readout_probe_cpu_core_value(uint32_t position, uint32_t field) {
    if (position >= logical_count) return UINT32_MAX;
    uint32_t index = logical_ids[position];
    return field == 0 ? index : field == 1 ? core_min[index] : field == 2 ? package_min[index] :
        field == 3 && clocks_valid ? maximum_mhz[index] : field == 4 && clocks_valid ? current_mhz[index] : UINT32_MAX;
}
