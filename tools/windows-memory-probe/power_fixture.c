#include <windows.h>
#include <stdint.h>
#include <string.h>

/* Test-child-only Win32 responses. No OS power policy, registry or device is changed. */
enum { STATUS_FAIL = 1, CAPABILITIES_FAIL = 2, HOLD_STATUS = 4, HOLD_CAPABILITIES = 8 };
static volatile LONG status_value, capability_value, behavior, released = 1;
static volatile LONG status_calls, capability_calls, active_calls, blocked_calls;
static volatile LONG worker_thread, different_thread, registration_calls;

__declspec(dllexport) void readout_power_fixture_configure(uint32_t status, uint32_t capabilities, uint32_t flags) {
    InterlockedExchange(&status_value, (LONG)status);
    InterlockedExchange(&capability_value, (LONG)capabilities);
    InterlockedExchange(&behavior, (LONG)flags);
    InterlockedExchange(&released, (flags & (HOLD_STATUS | HOLD_CAPABILITIES)) ? 0 : 1);
}

__declspec(dllexport) void readout_power_fixture_release(void) { InterlockedExchange(&released, 1); }

__declspec(dllexport) uint32_t readout_power_fixture_counter(uint32_t which) {
    volatile LONG *value;
    switch (which) {
        case 0: value = &status_calls; break;
        case 1: value = &capability_calls; break;
        case 2: value = &active_calls; break;
        case 3: value = &blocked_calls; break;
        case 4: value = &worker_thread; break;
        case 5: value = &different_thread; break;
        case 6: value = &registration_calls; break;
        default: return UINT32_MAX;
    }
    return (uint32_t)InterlockedCompareExchange(value, 0, 0);
}

static void record_thread(void) {
    LONG current = (LONG)GetCurrentThreadId();
    LONG first = InterlockedCompareExchange(&worker_thread, current, 0);
    if (first && first != current) InterlockedExchange(&different_thread, 1);
}

static void enter_call(uint32_t hold_flag) {
    InterlockedIncrement(&active_calls);
    record_thread();
    if ((uint32_t)InterlockedCompareExchange(&behavior, 0, 0) & hold_flag) {
        ULONGLONG start = GetTickCount64();
        InterlockedIncrement(&blocked_calls);
        /* The parent owns the child handle; this bound is a second fixture fail-safe. */
        while (!InterlockedCompareExchange(&released, 0, 0) && GetTickCount64() - start < 15000) Sleep(1);
        InterlockedDecrement(&blocked_calls);
    }
}

BOOL WINAPI readout_fixture_GetSystemPowerStatus(LPSYSTEM_POWER_STATUS status) {
    InterlockedIncrement(&status_calls);
    enter_call(HOLD_STATUS);
    uint32_t value = (uint32_t)InterlockedCompareExchange(&status_value, 0, 0);
    memset(status, 0, sizeof(*status));
    status->ACLineStatus = (BYTE)value;
    status->SystemStatusFlag = (BYTE)(value >> 8);
    status->BatteryFlag = 8;
    status->BatteryLifePercent = 75;
    status->BatteryLifeTime = 600;
    status->BatteryFullLifeTime = 3600;
    BOOL success = !(InterlockedCompareExchange(&behavior, 0, 0) & STATUS_FAIL);
    InterlockedDecrement(&active_calls);
    if (!success) SetLastError(ERROR_GEN_FAILURE);
    return success;
}

BOOLEAN WINAPI readout_fixture_GetPwrCapabilities(PSYSTEM_POWER_CAPABILITIES capabilities) {
    InterlockedIncrement(&capability_calls);
    enter_call(HOLD_CAPABILITIES);
    uint32_t value = (uint32_t)InterlockedCompareExchange(&capability_value, 0, 0);
    /* Unrelated bytes are deliberately nonzero so wrong field offsets cannot look absent. */
    memset(capabilities, 0xA5, sizeof(*capabilities));
    capabilities->SystemBatteriesPresent = (BYTE)value;
    capabilities->UpsPresent = (BYTE)(value >> 8);
    capabilities->BatteriesAreShortTerm = (BYTE)(value >> 16);
    BOOLEAN success = (InterlockedCompareExchange(&behavior, 0, 0) & CAPABILITIES_FAIL) ? FALSE : TRUE;
    InterlockedDecrement(&active_calls);
    if (!success) SetLastError(ERROR_GEN_FAILURE);
    return success;
}

DWORD WINAPI readout_fixture_PowerSettingRegisterNotification(LPCGUID setting, DWORD flags, void *recipient, void **handle) {
    (void)setting; (void)flags; (void)recipient;
    record_thread();
    InterlockedIncrement(&registration_calls);
    *handle = NULL;
    return ERROR_NOT_SUPPORTED;
}

DWORD WINAPI readout_fixture_PowerSettingUnregisterNotification(void *handle) {
    (void)handle;
    return ERROR_INVALID_HANDLE;
}
