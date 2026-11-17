#include <windows.h>
#include <stdint.h>

/* Independent same-process OS reference; no SDK code is linked here. */
__declspec(dllexport) uint64_t readout_probe_available_commit(void) {
    MEMORYSTATUSEX status = {0};
    status.dwLength = sizeof(status);
    if (!GlobalMemoryStatusEx(&status)) return UINT64_MAX;
    return status.ullAvailPageFile;
}

__declspec(dllexport) uint32_t readout_probe_process_id(void) {
    return GetCurrentProcessId();
}
