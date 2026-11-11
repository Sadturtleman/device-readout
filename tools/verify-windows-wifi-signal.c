/* Independent read-only Native Wi-Fi probe. No scans, BSSID queries or permission requests. */
#define _WIN32_WINNT 0x0600
#include <windows.h>
#include <wlanapi.h>
#include <stdio.h>

int main(void) {
    HANDLE client = NULL;
    DWORD version = 0;
    DWORD opened = WlanOpenHandle(2, NULL, &version, &client);
    printf("{\"longSize\":%zu,\"rssiOpcode\":%u,\"openResult\":%lu,\"version\":%lu",
        sizeof(LONG), (unsigned)wlan_intf_opcode_rssi, opened, version);
    if (opened != ERROR_SUCCESS || client == NULL) {
        if (client != NULL) WlanCloseHandle(client, NULL);
        puts("}");return 0;
    }
    PWLAN_INTERFACE_INFO_LIST interfaces = NULL;
    DWORD enumerated = WlanEnumInterfaces(client, NULL, &interfaces);
    printf(",\"enumResult\":%lu,\"interfaceCount\":%lu,\"connectedSignals\":[", enumerated,
        enumerated == ERROR_SUCCESS && interfaces != NULL ? interfaces->dwNumberOfItems : 0);
    unsigned emitted = 0;
    if (enumerated == ERROR_SUCCESS && interfaces != NULL) {
        for (DWORD index = 0; index < interfaces->dwNumberOfItems; ++index) {
            PWLAN_INTERFACE_INFO item = &interfaces->InterfaceInfo[index];
            if (item->isState != wlan_interface_state_connected && item->isState != wlan_interface_state_ad_hoc_network_formed) continue;
            void *data = NULL;DWORD size = 0;
            DWORD result = WlanQueryInterface(client, &item->InterfaceGuid, wlan_intf_opcode_rssi, NULL, &size, &data, NULL);
            if (emitted++) putchar(',');
            printf("{\"result\":%lu,\"size\":%lu,\"rssiDbm\":", result, size);
            if (result == ERROR_SUCCESS && data != NULL && size == sizeof(LONG)) printf("%ld", *(LONG *)data);
            else printf("null");
            putchar('}');if (data != NULL) WlanFreeMemory(data);
        }
    }
    if (interfaces != NULL) WlanFreeMemory(interfaces);
    /* A synthetic, absent interface exercises the native failure ABI without changing hardware. */
    const GUID absent = {0x11111111, 0x2222, 0x3333, {0x44, 0x44, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55}};
    void *missingData = NULL;DWORD missingSize = 0;
    DWORD missing = WlanQueryInterface(client, &absent, wlan_intf_opcode_rssi, NULL, &missingSize, &missingData, NULL);
    printf("],\"absentQueryResult\":%lu,\"absentDataSize\":%lu}\n", missing, missingSize);
    if (missingData != NULL) WlanFreeMemory(missingData);
    DWORD closed = WlanCloseHandle(client, NULL);
    if (closed != ERROR_SUCCESS) {fprintf(stderr, "WlanCloseHandle failed: %lu\n", closed);return 1;}
    return 0;
}
