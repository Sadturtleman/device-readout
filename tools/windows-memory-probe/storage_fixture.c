#include <windows.h>
#include <stdint.h>
#include <wchar.h>

/* Explicitly loaded by the storage adapter in an owned test child. These
   exports never replace system DLLs or alter any real volume or OS policy. */
static volatile LONG mode, buffers, directories, searches, removed;
static volatile LONG active, blocked, released = 1, held_thread;
static const WCHAR volume[] = L"\\\\?\\Volume{11111111-1111-1111-1111-111111111111}\\";

__declspec(dllexport) void readout_storage_configure(uint32_t value) {
    InterlockedExchange(&mode, (LONG)value);
    InterlockedExchange(&removed, 0);
    InterlockedExchange(&released, value >= 17 && value <= 20 ? 0 : 1);
}
__declspec(dllexport) void readout_storage_release(void) { InterlockedExchange(&released, 1); }
__declspec(dllexport) uint32_t readout_storage_counter(uint32_t index) {
    if (index == 6) return GetCurrentThreadId();
    volatile LONG *value = index == 0 ? &buffers : index == 1 ? &directories :
        index == 2 ? &searches : index == 3 ? &active : index == 4 ? &blocked : &held_thread;
    return (uint32_t)InterlockedCompareExchange(value, 0, 0);
}
static void hold_if(LONG expected) {
    if (InterlockedCompareExchange(&mode, 0, 0) != expected) return;
    InterlockedIncrement(&active);
    InterlockedIncrement(&blocked);
    InterlockedExchange(&held_thread, (LONG)GetCurrentThreadId());
    ULONGLONG started = GetTickCount64();
    while (!InterlockedCompareExchange(&released, 0, 0) && GetTickCount64() - started < 6000) Sleep(1);
    InterlockedDecrement(&active);
}

HANDLE WINAPI readout_storage_GetProcessHeap(void) { return GetProcessHeap(); }
LPVOID WINAPI readout_storage_HeapAlloc(HANDLE heap, DWORD flags, SIZE_T size) {
    LPVOID result = HeapAlloc(heap, flags, size);
    if (result) InterlockedIncrement(&buffers);
    return result;
}
BOOL WINAPI readout_storage_HeapFree(HANDLE heap, DWORD flags, LPVOID memory) {
    BOOL result = HeapFree(heap, flags, memory);
    if (result) InterlockedDecrement(&buffers);
    return result;
}
DWORD WINAPI readout_storage_GetLastError(void) { return GetLastError(); }

HANDLE WINAPI readout_storage_FindFirstVolumeW(LPWSTR name, DWORD capacity) {
    hold_if(18);
    LONG current = InterlockedCompareExchange(&mode, 0, 0);
    if (current == 11) { SetLastError(ERROR_ACCESS_DENIED); return INVALID_HANDLE_VALUE; }
    if (current == 15 || InterlockedCompareExchange(&removed, 0, 0)) {
        SetLastError(ERROR_NO_MORE_FILES); return INVALID_HANDLE_VALUE;
    }
    if (capacity < sizeof(volume) / sizeof(WCHAR)) {
        SetLastError(ERROR_MORE_DATA); return INVALID_HANDLE_VALUE;
    }
    wcscpy_s(name, capacity, current == 13 ? L"invalid volume" : volume);
    InterlockedIncrement(&searches);
    return (HANDLE)(uintptr_t)101;
}
BOOL WINAPI readout_storage_FindNextVolumeW(HANDLE search, LPWSTR name, DWORD capacity) {
    (void)search; (void)name; (void)capacity;
    LONG current = InterlockedCompareExchange(&mode, 0, 0);
    if (current == 12) { SetLastError(ERROR_GEN_FAILURE); return FALSE; }
    if (current == 14) { wcscpy_s(name, capacity, volume); return TRUE; }
    SetLastError(ERROR_NO_MORE_FILES);
    return FALSE;
}
BOOL WINAPI readout_storage_FindVolumeClose(HANDLE search) {
    (void)search;
    InterlockedDecrement(&searches);
    return TRUE;
}

BOOL WINAPI readout_storage_GetDiskFreeSpaceExW(LPCWSTR root,
    PULARGE_INTEGER available, PULARGE_INTEGER total, PULARGE_INTEGER free_bytes) {
    (void)root;
    hold_if(17);
    available->QuadPart = 2048000;
    total->QuadPart = 6144000;
    free_bytes->QuadPart = 4096000;
    LONG current = InterlockedCompareExchange(&mode, 0, 0);
    if (current == 16) InterlockedExchange(&removed, 1);
    if (current == 7 || current == 9) { SetLastError(ERROR_ACCESS_DENIED); return FALSE; }
    if (current == 24) available->QuadPart = total->QuadPart = free_bytes->QuadPart = 0;
    if (current == 25) available->QuadPart = total->QuadPart = free_bytes->QuadPart = UINT64_MAX;
    return TRUE;
}
HRESULT WINAPI readout_storage_GetDiskSpaceInformationW(LPCWSTR root, DISK_SPACE_INFORMATION *space) {
    (void)root;
    memset(space, 0xA5, sizeof(*space));
    space->ActualTotalAllocationUnits = 2000;
    space->SectorsPerAllocationUnit = 8;
    space->BytesPerSector = 512;
    LONG current = InterlockedCompareExchange(&mode, 0, 0);
    if (current == 8 || current == 9) return E_ACCESSDENIED;
    if (current == 21) space->SectorsPerAllocationUnit = 0;
    if (current == 22) space->ActualTotalAllocationUnits = UINT64_MAX;
    return S_OK;
}
UINT WINAPI readout_storage_GetDriveTypeW(LPCWSTR root) {
    (void)root;
    LONG current = InterlockedCompareExchange(&mode, 0, 0);
    return current == 9 || current == 23 ? DRIVE_UNKNOWN : DRIVE_FIXED;
}
HANDLE WINAPI readout_storage_CreateFileW(LPCWSTR name, DWORD access, DWORD sharing,
    LPSECURITY_ATTRIBUTES attributes, DWORD creation, DWORD flags, HANDLE template_file) {
    (void)name; (void)attributes; (void)template_file;
    if (InterlockedCompareExchange(&mode, 0, 0) == 10) {
        SetLastError(ERROR_ACCESS_DENIED); return INVALID_HANDLE_VALUE;
    }
    if (access != 0 || sharing != 7 || creation != OPEN_EXISTING || flags != FILE_FLAG_BACKUP_SEMANTICS) {
        SetLastError(ERROR_INVALID_PARAMETER); return INVALID_HANDLE_VALUE;
    }
    InterlockedIncrement(&directories);
    return (HANDLE)(uintptr_t)102;
}
BOOL WINAPI readout_storage_GetVolumeInformationByHandleW(HANDLE file,
    LPWSTR name, DWORD name_capacity, LPDWORD serial, LPDWORD component_size,
    LPDWORD flags, LPWSTR file_system, DWORD fs_capacity) {
    (void)file; (void)serial; (void)component_size;
    hold_if(19);
    if (InterlockedCompareExchange(&mode, 0, 0) == 1) {
        for (DWORD i = 0; i < name_capacity; ++i) name[i] = L'A';
    } else if (InterlockedCompareExchange(&mode, 0, 0) == 2) {
        name[0] = 0xD800; name[1] = 0;
    } else {
        wcscpy_s(name, name_capacity, L"Fixture volume");
    }
    wcscpy_s(file_system, fs_capacity, L"NTFS");
    *flags = FILE_READ_ONLY_VOLUME;
    LONG current = InterlockedCompareExchange(&mode, 0, 0);
    if (current == 3) for (DWORD i = 0; i < fs_capacity; ++i) file_system[i] = L'F';
    if (current == 4) { file_system[0] = 0xDC00; file_system[1] = 0; }
    if (current == 5) {
        const WCHAR unicode[] = {0xAC00, 0xD83D, 0xDE80, 0xE9, 0};
        wcscpy_s(name, name_capacity, unicode); file_system[0] = 0;
    }
    if (current == 6 || current == 9) { SetLastError(ERROR_ACCESS_DENIED); return FALSE; }
    return TRUE;
}
BOOL WINAPI readout_storage_CloseHandle(HANDLE file) {
    (void)file;
    hold_if(20);
    InterlockedDecrement(&directories);
    return TRUE;
}
