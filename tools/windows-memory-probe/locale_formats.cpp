#define _WIN32_WINNT 0x0A00
#include <windows.h>
#include <icu.h>
#include <cstring>
#include <cwchar>

static char script[16], numbering[64];
static DWORD hour_cycle;

extern "C" __declspec(dllexport) int readout_probe_locale_formats(void) {
    WCHAR name[LOCALE_NAME_MAX_LENGTH], digits[32];
    char tag[256], locale[256], likely[256];
    script[0] = numbering[0] = 0;
    hour_cycle = MAXDWORD;
    if (!GetUserDefaultLocaleName(name, LOCALE_NAME_MAX_LENGTH)) return 0;
    GetLocaleInfoEx(name, LOCALE_ITIME | LOCALE_RETURN_NUMBER,
        reinterpret_cast<LPWSTR>(&hour_cycle), 2);
    if (WideCharToMultiByte(CP_UTF8, 0, name, -1, tag, 256, nullptr, nullptr)) {
        UErrorCode status = U_ZERO_ERROR;
        int32_t parsed = 0;
        uloc_forLanguageTag(tag, locale, 256, &parsed, &status);
        if (U_SUCCESS(status) && parsed == (int32_t)strlen(tag)) {
            uloc_addLikelySubtags(locale, likely, 256, &status);
            if (U_SUCCESS(status)) uloc_getScript(likely, script, 16, &status);
        }
        if (U_FAILURE(status)) script[0] = 0;
    }
    DWORD substitution = MAXDWORD;
    if (GetLocaleInfoEx(name, LOCALE_IDIGITSUBSTITUTION | LOCALE_RETURN_NUMBER,
        reinterpret_cast<LPWSTR>(&substitution), 2) != 2) return 1;
    if (!GetLocaleInfoEx(name, LOCALE_SNATIVEDIGITS, digits, 32)) return 1;
    if (substitution == 1) wcscpy_s(digits, L"0123456789");
    else if (substitution != 2 && (substitution != 0 || wcscmp(digits, L"0123456789"))) return 1;
    UErrorCode status = U_ZERO_ERROR;
    UEnumeration* names = unumsys_openAvailableNames(&status);
    if (!names || U_FAILURE(status)) { if (names) uenum_close(names); return 1; }
    const char* key;
    while ((key = uenum_next(names, nullptr, &status)) != nullptr && U_SUCCESS(status)) {
        UErrorCode item_status = U_ZERO_ERROR;
        UNumberingSystem* system = unumsys_openByName(key, &item_status);
        if (!system) continue;
        UChar description[64];
        if (U_SUCCESS(item_status) && !unumsys_isAlgorithmic(system) && unumsys_getRadix(system) == 10) {
            const int32_t count = unumsys_getDescription(system, description, 64, &item_status);
            if (U_SUCCESS(item_status) && count > 0 && count < 64 &&
                !wcscmp(reinterpret_cast<const WCHAR*>(description), digits)) {
                strcpy_s(numbering, key);
                unumsys_close(system);
                break;
            }
        }
        unumsys_close(system);
    }
    uenum_close(names);
    return 1;
}
extern "C" __declspec(dllexport) const char* readout_probe_locale_script(void) { return script; }
extern "C" __declspec(dllexport) const char* readout_probe_locale_numbering(void) { return numbering; }
extern "C" __declspec(dllexport) DWORD readout_probe_locale_hour_cycle(void) { return hour_cycle; }
