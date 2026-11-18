#include <windows.h>
#include <stdint.h>
#include <stddef.h>

/* Loaded only through the CPU adapter in an owned test child. No process CPU
   policy, registry value or system DLL binding is changed. */
static volatile LONG mode, buffers, active, released = 1, worker_thread, maximum_buffer;
__declspec(dllexport) void readout_cpu_configure(uint32_t value) {
    InterlockedExchange(&mode, (LONG)value);
    InterlockedExchange(&released, (value >= 20 && value <= 23) || value == 106 ? 0 : 1);
}
__declspec(dllexport) uint32_t readout_cpu_buffers(void) {
    return (uint32_t)InterlockedCompareExchange(&buffers, 0, 0);
}
__declspec(dllexport) void readout_cpu_release(void) { InterlockedExchange(&released, 1); }
__declspec(dllexport) uint32_t readout_cpu_counter(uint32_t index) {
    if (index == 2) return GetCurrentThreadId();
    return (uint32_t)InterlockedCompareExchange(index == 0 ? &active : index == 3 ? &maximum_buffer : &worker_thread, 0, 0);
}
static void hold_if(LONG expected) {
    if (InterlockedCompareExchange(&mode, 0, 0) != expected) return;
    InterlockedIncrement(&active);
    InterlockedExchange(&worker_thread, (LONG)GetCurrentThreadId());
    ULONGLONG started = GetTickCount64();
    while (!InterlockedCompareExchange(&released, 0, 0) && GetTickCount64() - started < 6000) Sleep(1);
    InterlockedDecrement(&active);
}
HANDLE WINAPI readout_cpu_GetProcessHeap(void) { return GetProcessHeap(); }
LPVOID WINAPI readout_cpu_HeapAlloc(HANDLE heap, DWORD flags, SIZE_T size) {
    if (size > (SIZE_T)InterlockedCompareExchange(&maximum_buffer, 0, 0))
        InterlockedExchange(&maximum_buffer, (LONG)size);
    LPVOID value = HeapAlloc(heap, flags, size);
    if (value) InterlockedIncrement(&buffers);
    return value;
}
BOOL WINAPI readout_cpu_HeapFree(HANDLE heap, DWORD flags, LPVOID memory) {
    BOOL success = HeapFree(heap, flags, memory);
    if (success) InterlockedDecrement(&buffers);
    return success;
}
DWORD WINAPI readout_cpu_GetActiveProcessorCount(WORD group) {
    if (InterlockedCompareExchange(&mode, 0, 0) == 5)
        return group == ALL_PROCESSOR_GROUPS ? 4 : group < 2 ? 2 : 0;
    if (InterlockedCompareExchange(&mode, 0, 0) == 30)
        return group == ALL_PROCESSOR_GROUPS || group == 0 ? 3 : 0;
    return group == 0 || group == ALL_PROCESSOR_GROUPS ? 4 : 0;
}
WORD WINAPI readout_cpu_GetActiveProcessorGroupCount(void) {
    return InterlockedCompareExchange(&mode, 0, 0) == 5 ? 2 : 1;
}
BOOL WINAPI readout_cpu_GetProcessAffinityMask(HANDLE process, PDWORD_PTR current, PDWORD_PTR system) {
    hold_if(21);
    if (process != GetCurrentProcess()) { SetLastError(ERROR_INVALID_PARAMETER); return FALSE; }
    if (InterlockedCompareExchange(&mode, 0, 0) == 4) {
        *current = ((DWORD_PTR)1 << 63) | 3;
        *system = *current | ((DWORD_PTR)1 << 62);
    } else { *current = 0xb; *system = 0xf; }
    return TRUE;
}
BOOL WINAPI readout_cpu_GetLogicalProcessorInformationEx(LOGICAL_PROCESSOR_RELATIONSHIP kind,
    PSYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX data, PDWORD length) {
    hold_if(20);
    LONG current = InterlockedCompareExchange(&mode, 0, 0);
    if (current == 32) { SetLastError(ERROR_ACCESS_DENIED); return FALSE; }
    if (current == 3) {
        *length = 0; SetLastError(ERROR_INSUFFICIENT_BUFFER); return FALSE;
    }
    if (current == 8) {
        *length = 9 * 1024 * 1024; SetLastError(ERROR_INSUFFICIENT_BUFFER); return FALSE;
    }
    const DWORD record_size = (DWORD)(offsetof(SYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX, Processor.GroupMask) + sizeof(GROUP_AFFINITY));
    const DWORD required = 3 * record_size + (current == 5 ? (DWORD)sizeof(GROUP_AFFINITY) : 0);
    if (kind != RelationAll) { SetLastError(ERROR_INVALID_PARAMETER); return FALSE; }
    DWORD capacity = *length;
    *length = required;
    if (!data || capacity < required) { SetLastError(ERROR_INSUFFICIENT_BUFFER); return FALSE; }
    memset(data, 0, required);
    for (DWORD i = 0; i < 3; i++) {
        PSYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX item = (void *)((BYTE *)data + i * record_size);
        item->Size = record_size;
        item->Relationship = i < 2 ? RelationProcessorCore : RelationProcessorPackage;
        item->Processor.GroupCount = 1;
        item->Processor.Flags = i < 2 ? LTP_PC_SMT : 0;
        item->Processor.GroupMask[0].Mask = i == 0 ? 3 : i == 1 ? 12 : 15;
        if (current == 4) {
            KAFFINITY first = ((KAFFINITY)1 << 63) | 1;
            KAFFINITY second = ((KAFFINITY)1 << 62) | 2;
            item->Processor.GroupMask[0].Mask = i == 0 ? first : i == 1 ? second : first | second;
        }
        if (current == 6 && i == 1) item->Processor.GroupMask[0].Mask = 3;
        if (current == 30) item->Processor.GroupMask[0].Mask = i == 0 ? 3 : i == 1 ? 4 : 7;
        if (current == 5) {
            item->Processor.GroupMask[0].Mask = 3;
            item->Processor.GroupMask[0].Group = i == 1 ? 1 : 0;
            if (i == 2) {
                item->Size += sizeof(GROUP_AFFINITY);
                item->Processor.GroupCount = 2;
                item->Processor.GroupMask[1].Group = 1;
                item->Processor.GroupMask[1].Mask = 3;
            }
        }
    }
    if (current == 7) *length = required - 1;
    if (current == 10) { SetLastError(ERROR_GEN_FAILURE); return FALSE; }
    return TRUE;
}
BOOL WINAPI readout_cpu_GetProcessDefaultCpuSets(HANDLE process, PULONG ids, ULONG count, PULONG required) {
    hold_if(22);
    (void)ids; (void)count;
    if (process != GetCurrentProcess()) { SetLastError(ERROR_INVALID_PARAMETER); return FALSE; }
    *required = 0;
    return TRUE;
}
BOOL WINAPI readout_cpu_GetSystemCpuSetInformation(PSYSTEM_CPU_SET_INFORMATION data,
    ULONG capacity, PULONG length, HANDLE process, ULONG flags) {
    hold_if(23);
    if (process != GetCurrentProcess() || flags != 0) { SetLastError(ERROR_INVALID_PARAMETER); return FALSE; }
    LONG current = InterlockedCompareExchange(&mode, 0, 0);
    if (current == 1 || current == 2) {
        *length = 0;
        SetLastError(current == 1 ? ERROR_INSUFFICIENT_BUFFER : ERROR_ACCESS_DENIED);
        return FALSE;
    }
    *length = 4 * sizeof(SYSTEM_CPU_SET_INFORMATION);
    if (!data || capacity < *length) { SetLastError(ERROR_INSUFFICIENT_BUFFER); return FALSE; }
    memset(data, 0, *length);
    for (ULONG i = 0; i < 4; i++) {
        data[i].Size = sizeof(SYSTEM_CPU_SET_INFORMATION);
        data[i].Type = CpuSetInformation;
        data[i].CpuSet.Id = 10 + i;
        data[i].CpuSet.LogicalProcessorIndex = (BYTE)i;
        if (current == 4) data[i].CpuSet.LogicalProcessorIndex = (BYTE)(i == 0 ? 0 : i == 1 ? 63 : i == 2 ? 1 : 62);
        if (current == 9 && i == 0) data[i].CpuSet.AllFlags = 0x80;
        data[i].CpuSet.CoreIndex = (BYTE)(i / 2);
    }
    return TRUE;
}

typedef struct ReadoutCpuPower {
    ULONG Number, MaxMhz, CurrentMhz, MhzLimit, MaxIdleState, CurrentIdleState;
} ReadoutCpuPower;
LONG WINAPI readout_cpu_CallNtPowerInformation(POWER_INFORMATION_LEVEL level,
    PVOID input, ULONG input_bytes, PVOID output, ULONG output_bytes) {
    hold_if(106);
    if (level != ProcessorInformation || input || input_bytes || output_bytes != 4 * sizeof(ReadoutCpuPower))
        return (LONG)0xC000000DL;
    ReadoutCpuPower *values = output;
    for (ULONG i = 0; i < 4; i++) {
        ULONG number = 3 - i;
        values[i] = (ReadoutCpuPower){number, 3200 + number * 100, 2200 + number * 100, 999, 7, 2};
    }
    LONG current = InterlockedCompareExchange(&mode, 0, 0);
    if (current == 101) return (LONG)0xC0000001L;
    if (current == 102) values[3].Number = values[0].Number;
    if (current == 103) values[0].Number = 4;
    if (current == 104 || current == 105) for (ULONG i = 0; i < 4; i++)
        values[i].CurrentMhz = values[i].MaxMhz = current == 104 ? 0 : UINT32_MAX;
    return 0;
}
