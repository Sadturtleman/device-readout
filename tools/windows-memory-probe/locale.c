#define _WIN32_WINNT 0x0A00
#include <windows.h>
#include <wchar.h>

static WCHAR locale_name[LOCALE_NAME_MAX_LENGTH];
static WCHAR region[16];
static DWORD weekday, measurement, calendar;
static WCHAR languages[32768];
static ULONG language_count;

__declspec(dllexport) int readout_probe_locale_languages(int kind) {
    ULONG capacity = 32768;
    language_count = 0;
    ZeroMemory(languages, sizeof(languages));
    BOOL success = FALSE;
    if (kind == 0) success = GetUserPreferredUILanguages(MUI_LANGUAGE_NAME, &language_count, languages, &capacity);
    if (kind == 1) success = GetSystemPreferredUILanguages(MUI_LANGUAGE_NAME, &language_count, languages, &capacity);
    if (kind == 2) success = GetProcessPreferredUILanguages(MUI_LANGUAGE_NAME, &language_count, languages, &capacity);
    return success ? (int)language_count : -1;
}
__declspec(dllexport) const WCHAR* readout_probe_locale_language(int index) {
    if (index < 0 || (ULONG)index >= language_count) return NULL;
    const WCHAR* current = languages;
    for (int i = 0; i < index; ++i) current += wcslen(current) + 1;
    return current;
}

__declspec(dllexport) int readout_probe_locale_refresh(void) {
    ZeroMemory(locale_name, sizeof(locale_name));
    ZeroMemory(region, sizeof(region));
    weekday = measurement = calendar = MAXDWORD;
    if (!GetUserDefaultLocaleName(locale_name, LOCALE_NAME_MAX_LENGTH)) return 0;
    GetLocaleInfoEx(locale_name, LOCALE_SISO3166CTRYNAME, region, 16);
    GetLocaleInfoEx(locale_name, LOCALE_IFIRSTDAYOFWEEK | LOCALE_RETURN_NUMBER,
        (LPWSTR)&weekday, sizeof(weekday) / sizeof(WCHAR));
    GetLocaleInfoEx(locale_name, LOCALE_IMEASURE | LOCALE_RETURN_NUMBER,
        (LPWSTR)&measurement, sizeof(measurement) / sizeof(WCHAR));
    GetLocaleInfoEx(locale_name, LOCALE_ICALENDARTYPE | LOCALE_RETURN_NUMBER,
        (LPWSTR)&calendar, sizeof(calendar) / sizeof(WCHAR));
    return 1;
}
__declspec(dllexport) const WCHAR* readout_probe_locale_name(void) { return locale_name; }
__declspec(dllexport) const WCHAR* readout_probe_locale_region(void) { return region; }
__declspec(dllexport) DWORD readout_probe_locale_weekday(void) { return weekday; }
__declspec(dllexport) DWORD readout_probe_locale_measurement(void) { return measurement; }
__declspec(dllexport) DWORD readout_probe_locale_calendar(void) { return calendar; }
