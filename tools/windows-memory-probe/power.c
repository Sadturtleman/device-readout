#include <windows.h>
#include <stdint.h>
#include <stddef.h>
#include <powrprof.h>

/* Read-only test reference using the Windows SDK declaration and native ABI. */
__declspec(dllexport) uint32_t readout_probe_power_status(void) {
    SYSTEM_POWER_STATUS status = {0};
    if (!GetSystemPowerStatus(&status)) return UINT32_MAX;
    return (uint32_t)status.ACLineStatus | ((uint32_t)status.SystemStatusFlag << 8);
}

__declspec(dllexport) uint32_t readout_probe_power_status_size(void) {
    return (uint32_t)sizeof(SYSTEM_POWER_STATUS);
}

__declspec(dllexport) uint32_t readout_probe_battery_class(void) {
    SYSTEM_POWER_CAPABILITIES capabilities = {0};
    if (!GetPwrCapabilities(&capabilities)) return UINT32_MAX;
    return (uint32_t)capabilities.SystemBatteriesPresent |
        ((uint32_t)capabilities.UpsPresent << 8) |
        ((uint32_t)capabilities.BatteriesAreShortTerm << 16);
}

__declspec(dllexport) uint32_t readout_probe_power_capabilities_layout(void) {
    return (uint32_t)sizeof(SYSTEM_POWER_CAPABILITIES) |
        ((uint32_t)offsetof(SYSTEM_POWER_CAPABILITIES, UpsPresent) << 8) |
        ((uint32_t)offsetof(SYSTEM_POWER_CAPABILITIES, SystemBatteriesPresent) << 16) |
        ((uint32_t)offsetof(SYSTEM_POWER_CAPABILITIES, BatteriesAreShortTerm) << 24);
}
