#define _WIN32_WINNT 0x0A00
#include <windows.h>

/* Test reference: field IDs are fixture-local and never exposed by the SDK. */
__declspec(dllexport) const WCHAR* readout_probe_device_info(int field) {
    static WCHAR buffer[32768];
    if (field == 3) {
        DWORD length = (DWORD)(sizeof(buffer) / sizeof(buffer[0]));
        return GetComputerNameW(buffer, &length) ? buffer : NULL;
    }
    const WCHAR* name = NULL;
    switch (field) {
        case 0: name = L"SystemManufacturer"; break;
        case 1: name = L"SystemProductName"; break;
        case 2: name = L"BaseBoardProduct"; break;
        default: return NULL;
    }
    DWORD bytes = sizeof(buffer);
    LSTATUS status = RegGetValueW(HKEY_LOCAL_MACHINE,
        L"HARDWARE\\DESCRIPTION\\System\\BIOS", name,
        RRF_RT_REG_SZ | RRF_SUBKEY_WOW6464KEY, NULL, buffer, &bytes);
    return status == ERROR_SUCCESS ? buffer : NULL;
}
