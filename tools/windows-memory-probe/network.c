#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <iphlpapi.h>
#include <stdint.h>
#include <stdio.h>

/* Independent test reference uses Windows SDK structures, not Dart offsets. */
static IP_ADAPTER_ADDRESSES *storage;
static IP_ADAPTER_ADDRESSES *items[65536];
static ULONG count;
static MIB_IPFORWARD_TABLE2 *routes;
static WCHAR text[1024];

__declspec(dllexport) void readout_probe_network_free(void) {
    if (storage) HeapFree(GetProcessHeap(), 0, storage);
    if (routes) FreeMibTable(routes);
    storage = NULL; routes = NULL; count = 0;
}
__declspec(dllexport) DWORD readout_probe_network_refresh(void) {
    readout_probe_network_free();
    ULONG size = 15000;
    for (unsigned attempt = 0; attempt < 3; ++attempt) {
        if (size > 8 * 1024 * 1024) return ERROR_INVALID_DATA;
        storage = HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, size);
        if (!storage) return ERROR_NOT_ENOUGH_MEMORY;
        ULONG error = GetAdaptersAddresses(AF_UNSPEC, GAA_FLAG_SKIP_ANYCAST |
            GAA_FLAG_SKIP_MULTICAST | GAA_FLAG_INCLUDE_GATEWAYS |
            GAA_FLAG_INCLUDE_ALL_INTERFACES, NULL, storage, &size);
        if (error == ERROR_BUFFER_OVERFLOW) { HeapFree(GetProcessHeap(), 0, storage); storage = NULL; continue; }
        if (error == ERROR_NO_DATA) { readout_probe_network_free(); return 0; }
        if (error) { readout_probe_network_free(); return error; }
        for (IP_ADAPTER_ADDRESSES *item = storage; item; item = item->Next) {
            if (count == 65536) { readout_probe_network_free(); return ERROR_INVALID_DATA; }
            items[count++] = item;
        }
        error = GetIpForwardTable2(AF_UNSPEC, &routes);
        if (error != NO_ERROR && error != ERROR_NOT_FOUND) { readout_probe_network_free(); return error; }
        return 0;
    }
    return ERROR_BUFFER_OVERFLOW;
}
__declspec(dllexport) ULONG readout_probe_network_count(void) { return count; }
static MIB_IPFORWARD_ROW2 *route(ULONG item, ULONG index) {
    if (!routes || item >= count) return NULL;
    for (ULONG n = 0; n < routes->NumEntries; ++n) {
        if (routes->Table[n].InterfaceLuid.Value != items[item]->Luid.Value) continue;
        if (!index--) return &routes->Table[n];
    }
    return NULL;
}
__declspec(dllexport) uint64_t readout_probe_network_number(ULONG item, ULONG field, ULONG index) {
    if (item >= count) return UINT64_MAX;
    IP_ADAPTER_ADDRESSES *adapter = items[item];
    ULONG total = 0;
    switch (field) {
        case 0: return adapter->IfType;
        case 1: return adapter->OperStatus;
        case 2: return adapter->Mtu;
        case 3: for (IP_ADAPTER_UNICAST_ADDRESS *p = adapter->FirstUnicastAddress; p; p = p->Next) ++total; return total;
        case 4: for (IP_ADAPTER_DNS_SERVER_ADDRESS *p = adapter->FirstDnsServerAddress; p; p = p->Next) ++total; return total;
        case 5: for (IP_ADAPTER_GATEWAY_ADDRESS *p = adapter->FirstGatewayAddress; p; p = p->Next) ++total; return total;
        case 6: while (route(item, total)) ++total; return total;
        case 7: for (IP_ADAPTER_UNICAST_ADDRESS *p = adapter->FirstUnicastAddress; p; p = p->Next) if (!index--) return p->OnLinkPrefixLength; break;
        case 8: { MIB_IPFORWARD_ROW2 *p = route(item, index); if (p) return p->DestinationPrefix.PrefixLength; break; }
    }
    return UINT64_MAX;
}
static const WCHAR *address(const SOCKADDR *value) {
    if (!value) return NULL;
    if (value->sa_family == AF_INET) {
        return InetNtopW(AF_INET, &((const SOCKADDR_IN *)value)->sin_addr, text, 1024);
    }
    if (value->sa_family == AF_INET6) {
        const SOCKADDR_IN6 *ip = (const SOCKADDR_IN6 *)value;
        if (!InetNtopW(AF_INET6, &ip->sin6_addr, text, 1024)) return NULL;
        if (ip->sin6_scope_id) {
            size_t used = wcslen(text);
            _snwprintf_s(text + used, 1024 - used, _TRUNCATE, L"%%%lu", ip->sin6_scope_id);
        }
        return text;
    }
    return NULL;
}
__declspec(dllexport) const WCHAR *readout_probe_network_text(ULONG item, ULONG field, ULONG index) {
    if (item >= count) return NULL;
    IP_ADAPTER_ADDRESSES *adapter = items[item];
    switch (field) {
        case 0: return adapter->FriendlyName;
        case 1:
            if (!adapter->PhysicalAddressLength) return NULL;
            text[0] = 0;
            for (ULONG n = 0; n < adapter->PhysicalAddressLength; ++n) {
                size_t used = wcslen(text);
                _snwprintf_s(text + used, 1024 - used, _TRUNCATE, n ? L":%02X" : L"%02X", adapter->PhysicalAddress[n]);
            }
            return text;
        case 2: for (IP_ADAPTER_UNICAST_ADDRESS *p = adapter->FirstUnicastAddress; p; p = p->Next) if (!index--) return address(p->Address.lpSockaddr); break;
        case 3: for (IP_ADAPTER_DNS_SERVER_ADDRESS *p = adapter->FirstDnsServerAddress; p; p = p->Next) if (!index--) return address(p->Address.lpSockaddr); break;
        case 4: for (IP_ADAPTER_GATEWAY_ADDRESS *p = adapter->FirstGatewayAddress; p; p = p->Next) if (!index--) return address(p->Address.lpSockaddr); break;
        case 5: { MIB_IPFORWARD_ROW2 *p = route(item, index); if (p) return address((const SOCKADDR *)&p->DestinationPrefix.Prefix); break; }
        case 6: { MIB_IPFORWARD_ROW2 *p = route(item, index); if (p) return address((const SOCKADDR *)&p->NextHop); break; }
    }
    return NULL;
}
