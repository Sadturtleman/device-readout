#define _WIN32_WINNT 0x0A00
#include <windows.h>
#include <icu.h>
#include <stdint.h>

static DYNAMIC_TIME_ZONE_INFORMATION zone;
static DWORD zone_state = TIME_ZONE_ID_INVALID;
static int32_t offset_seconds;
static UChar iana[256];

extern "C" __declspec(dllexport) int readout_probe_time_zone_refresh(void) {
    ZeroMemory(&zone, sizeof(zone));
    ZeroMemory(iana, sizeof(iana));
    zone_state = GetDynamicTimeZoneInformation(&zone);
    if (zone_state == TIME_ZONE_ID_INVALID) return 0;
    SYSTEMTIME utc, local;
    FILETIME utc_file, local_file;
    GetSystemTime(&utc);
    if (!SystemTimeToTzSpecificLocalTimeEx(&zone, &utc, &local) ||
        !SystemTimeToFileTime(&utc, &utc_file) || !SystemTimeToFileTime(&local, &local_file)) return 0;
    ULARGE_INTEGER u, l;
    u.LowPart = utc_file.dwLowDateTime; u.HighPart = utc_file.dwHighDateTime;
    l.LowPart = local_file.dwLowDateTime; l.HighPart = local_file.dwHighDateTime;
    offset_seconds = (int32_t)(((LONGLONG)l.QuadPart - (LONGLONG)u.QuadPart) / 10000000);
    UErrorCode status = U_ZERO_ERROR;
    const int32_t count = ucal_getTimeZoneIDForWindowsID(
        reinterpret_cast<const UChar*>(zone.TimeZoneKeyName), -1, nullptr, iana, 256, &status);
    if (U_FAILURE(status) || count <= 0 || count >= 256) iana[0] = 0;
    return 1;
}

extern "C" __declspec(dllexport) const WCHAR* readout_probe_time_zone_windows(void) {
    return zone.TimeZoneKeyName;
}
extern "C" __declspec(dllexport) const UChar* readout_probe_time_zone_iana(void) {
    return iana;
}
extern "C" __declspec(dllexport) int32_t readout_probe_time_zone_offset(void) {
    return offset_seconds;
}
extern "C" __declspec(dllexport) int readout_probe_time_zone_daylight(void) {
    return zone_state == TIME_ZONE_ID_DAYLIGHT;
}
