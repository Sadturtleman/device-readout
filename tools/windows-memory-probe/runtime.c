#define _WIN32_WINNT 0x0A00
#include <windows.h>

/* The compiler's Windows declarations provide the independent native ABI. */
__declspec(dllexport) const char* readout_probe_host_architecture(void) {
    USHORT process = IMAGE_FILE_MACHINE_UNKNOWN;
    USHORT native = IMAGE_FILE_MACHINE_UNKNOWN;
    if (!IsWow64Process2(GetCurrentProcess(), &process, &native)) return NULL;
    switch (native) {
        case IMAGE_FILE_MACHINE_I386: return "X86";
        case IMAGE_FILE_MACHINE_AMD64: return "X64";
        case IMAGE_FILE_MACHINE_ARMNT: return "Arm32";
        case IMAGE_FILE_MACHINE_ARM64: return "Arm64";
        default: return NULL;
    }
}
