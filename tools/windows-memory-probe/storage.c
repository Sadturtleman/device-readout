#include <windows.h>
#include <stdint.h>

/* Test-only, read-only reference compiled against the installed Windows SDK.
   The Windows directory selects a known mounted volume for this test, not an
   application default in the product. No SDK code or declarations are linked. */
static WCHAR volume_name[MAX_PATH + 1];
static WCHAR file_system[MAX_PATH + 1];
static uint64_t values[7];

__declspec(dllexport) int readout_probe_storage_refresh(void) {
    WCHAR windows_directory[MAX_PATH + 1], root[MAX_PATH + 1];
    DISK_SPACE_INFORMATION space = {0};
    ULARGE_INTEGER available, total_for_caller, free_bytes;
    DWORD flags = 0;
    UINT length = GetWindowsDirectoryW(windows_directory, MAX_PATH + 1);
    if (!length || length > MAX_PATH) return 0;
    if (!GetVolumePathNameW(windows_directory, root, MAX_PATH + 1)) return 0;
    if (GetDiskSpaceInformationW(root, &space) != S_OK) return 0;
    if (!GetDiskFreeSpaceExW(root, &available, &total_for_caller, &free_bytes)) return 0;
    HANDLE directory = CreateFileW(root, 0,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL,
        OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, NULL);
    if (directory == INVALID_HANDLE_VALUE) return 0;
    BOOL metadata = GetVolumeInformationByHandleW(directory, volume_name,
        MAX_PATH + 1, NULL, NULL, &flags, file_system, MAX_PATH + 1);
    BOOL closed = CloseHandle(directory);
    if (!metadata || !closed) return 0;
    values[0] = space.ActualTotalAllocationUnits * space.SectorsPerAllocationUnit * space.BytesPerSector;
    values[1] = free_bytes.QuadPart;
    values[2] = total_for_caller.QuadPart;
    values[3] = available.QuadPart;
    values[4] = (flags & FILE_READ_ONLY_VOLUME) != 0;
    values[5] = GetDriveTypeW(root);
    values[6] = sizeof(DISK_SPACE_INFORMATION);
    return 1;
}

__declspec(dllexport) uint64_t readout_probe_storage_value(uint32_t field) {
    return field < 7 ? values[field] : UINT64_MAX;
}

__declspec(dllexport) const WCHAR* readout_probe_storage_text(uint32_t field) {
    return field == 0 ? volume_name : field == 1 ? file_system : NULL;
}

__declspec(dllexport) uint32_t readout_probe_storage_count(void) {
    WCHAR volume[MAX_PATH + 1];
    HANDLE search = FindFirstVolumeW(volume, MAX_PATH + 1);
    if (search == INVALID_HANDLE_VALUE)
        return GetLastError() == ERROR_NO_MORE_FILES ? 0 : UINT32_MAX;
    uint32_t count = 1;
    while (FindNextVolumeW(search, volume, MAX_PATH + 1)) ++count;
    DWORD error = GetLastError();
    BOOL closed = FindVolumeClose(search);
    return error == ERROR_NO_MORE_FILES && closed ? count : UINT32_MAX;
}
