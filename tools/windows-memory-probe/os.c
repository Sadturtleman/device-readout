#include <windows.h>
#include <stdint.h>
#include <stdio.h>

typedef LONG (WINAPI *ReadVersion)(OSVERSIONINFOW*);

static int read_version(OSVERSIONINFOW* version) {
    HMODULE module = GetModuleHandleW(L"ntdll.dll");
    if (module == NULL) return 0;
    ReadVersion query = (ReadVersion)GetProcAddress(module, "RtlGetVersion");
    if (query == NULL) return 0;
    version->dwOSVersionInfoSize = sizeof(*version);
    return query(version) == 0 && version->dwPlatformId == VER_PLATFORM_WIN32_NT;
}

/* Test-only reference using the Windows SDK's native structure declaration. */
__declspec(dllexport) const char* readout_probe_os_version(void) {
    OSVERSIONINFOW version = {0};
    static char text[64];
    if (!read_version(&version)) return NULL;
    snprintf(text, sizeof(text), "%lu.%lu.%lu", version.dwMajorVersion,
        version.dwMinorVersion, version.dwBuildNumber);
    return text;
}

__declspec(dllexport) uint32_t readout_probe_os_build(void) {
    OSVERSIONINFOW version = {0};
    return read_version(&version) ? version.dwBuildNumber : UINT32_MAX;
}
