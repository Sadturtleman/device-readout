#define _WIN32_WINNT 0x0A00
#include <windows.h>
#include <stdint.h>
#include <wchar.h>

/* Loaded only by test helpers. The override is installed only in an owned child. */
static HKEY fixture_root;
static HKEY fixture_bios;
static BOOL overridden;

/* Independent size-query evidence for boundary tests, not an SDK hook. */
__declspec(dllexport) uint64_t readout_registry_sizes(void) {
    DWORD raw = 0, requested = 0;
    if (RegQueryValueExW(fixture_bios, L"SystemManufacturer", NULL, NULL, NULL, &raw) != ERROR_SUCCESS)
        return UINT64_MAX;
    if (RegGetValueW(fixture_bios, NULL, L"SystemManufacturer", RRF_RT_REG_SZ, NULL, NULL, &requested) != ERROR_SUCCESS)
        return UINT64_MAX;
    return ((uint64_t)raw << 32) | requested;
}

static int key_name(WCHAR* output, size_t count, DWORD pid, uint64_t nonce) {
    if (pid == 0 || nonce == 0) return 0;
    return swprintf_s(output, count, L"DeviceReadoutTest_%lu_%016llx",
        pid, (unsigned long long)nonce) > 0;
}

__declspec(dllexport) LONG readout_registry_finish(void) {
    LSTATUS result = ERROR_SUCCESS;
    if (overridden) {
        result = RegOverridePredefKey(HKEY_LOCAL_MACHINE, NULL);
        overridden = FALSE;
    }
    if (fixture_bios) { RegCloseKey(fixture_bios); fixture_bios = NULL; }
    if (fixture_root) { RegCloseKey(fixture_root); fixture_root = NULL; }
    return result;
}

__declspec(dllexport) LONG readout_registry_remove(DWORD child, uint64_t nonce) {
    WCHAR name[96];
    if (!key_name(name, 96, child, nonce)) return ERROR_INVALID_PARAMETER;
    HKEY root = NULL;
    LSTATUS status = RegOpenKeyExW(HKEY_CURRENT_USER, name, 0, KEY_ALL_ACCESS | KEY_WOW64_64KEY, &root);
    if (status == ERROR_FILE_NOT_FOUND) return ERROR_SUCCESS;
    if (status != ERROR_SUCCESS) return status;
    DWORD owner = 0, bytes = sizeof(owner);
    uint64_t token = 0;
    status = RegGetValueW(root, NULL, L"OwnerProcessId", RRF_RT_REG_DWORD, NULL, &owner, &bytes);
    if (status == ERROR_SUCCESS) {
        bytes = sizeof(token);
        status = RegGetValueW(root, NULL, L"Nonce", RRF_RT_REG_QWORD, NULL, &token, &bytes);
    }
    if (status == ERROR_SUCCESS && (owner != child || token != nonce)) status = ERROR_ACCESS_DENIED;
    if (status == ERROR_SUCCESS) status = RegDeleteTreeW(root, NULL);
    RegCloseKey(root);
    if (status != ERROR_SUCCESS) return status;
    status = RegDeleteKeyW(HKEY_CURRENT_USER, name);
    if (status != ERROR_SUCCESS) return status;
    status = RegOpenKeyExW(HKEY_CURRENT_USER, name, 0, KEY_READ, &root);
    if (status == ERROR_FILE_NOT_FOUND) return ERROR_SUCCESS;
    if (status == ERROR_SUCCESS) RegCloseKey(root);
    return ERROR_DIR_NOT_EMPTY;
}

__declspec(dllexport) LONG readout_registry_start(DWORD parent, uint64_t nonce) {
    const DWORD child = GetCurrentProcessId();
    if (parent == 0 || parent == child || fixture_root) return ERROR_INVALID_PARAMETER;
    WCHAR name[96];
    if (!key_name(name, 96, child, nonce)) return ERROR_INVALID_PARAMETER;
    DWORD disposition = 0;
    LSTATUS status = RegCreateKeyExW(HKEY_CURRENT_USER, name, 0, NULL,
        REG_OPTION_VOLATILE, KEY_ALL_ACCESS | KEY_WOW64_64KEY, NULL, &fixture_root, &disposition);
    if (status != ERROR_SUCCESS) return status;
    if (disposition != REG_CREATED_NEW_KEY) {
        RegCloseKey(fixture_root); fixture_root = NULL;
        return ERROR_ALREADY_EXISTS;
    }
    status = RegSetValueExW(fixture_root, L"OwnerProcessId", 0, REG_DWORD, (const BYTE*)&child, sizeof(child));
    if (status == ERROR_SUCCESS) status = RegSetValueExW(fixture_root, L"Nonce", 0, REG_QWORD, (const BYTE*)&nonce, sizeof(nonce));
    if (status == ERROR_SUCCESS) status = RegCreateKeyExW(fixture_root,
        L"HARDWARE\\DESCRIPTION\\System\\BIOS", 0, NULL, REG_OPTION_VOLATILE,
        KEY_ALL_ACCESS | KEY_WOW64_64KEY, NULL, &fixture_bios, NULL);
    if (status == ERROR_SUCCESS) status = RegOverridePredefKey(HKEY_LOCAL_MACHINE, fixture_root);
    if (status == ERROR_SUCCESS) { overridden = TRUE; return ERROR_SUCCESS; }
    readout_registry_finish();
    /* This process just created this exact unique key; no pre-existing key is deleted. */
    RegDeleteTreeW(HKEY_CURRENT_USER, name);
    RegDeleteKeyW(HKEY_CURRENT_USER, name);
    return status;
}

__declspec(dllexport) LONG readout_registry_prepare(int scenario) {
    if (!fixture_bios || !overridden) return ERROR_INVALID_PARAMETER;
    if (scenario == 5) scenario = 0;
    if (scenario == 4) {
        WCHAR* text = HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, 65538);
        if (!text) return ERROR_NOT_ENOUGH_MEMORY;
        for (int i = 0; i < 32767; ++i) text[i] = L'A';
        LSTATUS status = RegSetValueExW(fixture_bios, L"SystemManufacturer", 0,
            REG_SZ, (const BYTE*)text, 65536);
        text[32767] = L'A';
        if (status == ERROR_SUCCESS) status = RegSetValueExW(fixture_bios, L"SystemProductName", 0,
            REG_SZ, (const BYTE*)text, 65538);
        if (status == ERROR_SUCCESS) status = RegSetValueExW(fixture_bios, L"BaseBoardProduct", 0,
            REG_SZ, (const BYTE*)text, 65536);
        HeapFree(GetProcessHeap(), 0, text);
        return status;
    }
    if (scenario == 3) {
        const WCHAR unterminated[] = { 0xac00, L'B' };
        const BYTE odd[] = { 'X', 0, 0 };
        LSTATUS status = RegSetValueExW(fixture_bios, L"SystemManufacturer", 0,
            REG_SZ, (const BYTE*)unterminated, sizeof(unterminated));
        if (status == ERROR_SUCCESS) status = RegSetValueExW(fixture_bios, L"SystemProductName", 0,
            REG_SZ, NULL, 0);
        if (status == ERROR_SUCCESS) status = RegSetValueExW(fixture_bios, L"BaseBoardProduct", 0,
            REG_SZ, odd, sizeof(odd));
        return status;
    }
    if (scenario == 2) {
        const WCHAR high[] = { 0xd800, 0 };
        const WCHAR low[] = { 0xdc00, 0 };
        const WCHAR board[] = L"Fixture board";
        LSTATUS status = RegSetValueExW(fixture_bios, L"SystemManufacturer", 0,
            REG_SZ, (const BYTE*)high, sizeof(high));
        if (status == ERROR_SUCCESS) status = RegSetValueExW(fixture_bios, L"SystemProductName", 0,
            REG_SZ, (const BYTE*)low, sizeof(low));
        if (status == ERROR_SUCCESS) status = RegSetValueExW(fixture_bios, L"BaseBoardProduct", 0,
            REG_SZ, (const BYTE*)board, sizeof(board));
        return status;
    }
    if (scenario == 1) {
        const WCHAR manufacturer[] = { 0xac00, 0xd83d, 0xde80, 0x00e9, 0 };
        const WCHAR model[] = L"";
        const WCHAR board[] = L"Fixture board";
        LSTATUS status = RegSetValueExW(fixture_bios, L"SystemManufacturer", 0,
            REG_SZ, (const BYTE*)manufacturer, sizeof(manufacturer));
        if (status == ERROR_SUCCESS) status = RegSetValueExW(fixture_bios, L"SystemProductName", 0,
            REG_SZ, (const BYTE*)model, sizeof(model));
        if (status == ERROR_SUCCESS) status = RegSetValueExW(fixture_bios, L"BaseBoardProduct", 0,
            REG_SZ, (const BYTE*)board, sizeof(board));
        return status;
    }
    if (scenario != 0) return ERROR_INVALID_PARAMETER;
    DWORD wrong_type = 42;
    LSTATUS status = RegSetValueExW(fixture_bios, L"SystemManufacturer", 0,
        REG_DWORD, (const BYTE*)&wrong_type, sizeof(wrong_type));
    const WCHAR model[] = L"Fixture model";
    if (status == ERROR_SUCCESS) status = RegSetValueExW(fixture_bios, L"SystemProductName", 0,
        REG_SZ, (const BYTE*)model, sizeof(model));
    return status;
}
