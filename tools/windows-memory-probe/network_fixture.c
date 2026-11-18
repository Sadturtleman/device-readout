#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <iphlpapi.h>
#include <stdint.h>

/* Loaded only by explicit test bindings in an owned child process. */
static volatile LONG mode, active, held_thread, released = 1, buffers;
typedef VOID (WINAPI *TEST_CALLBACK)(PVOID, PVOID, ULONG);
typedef struct { TEST_CALLBACK callback; PVOID context; ULONG kind; BOOL live; } TEST_REGISTRATION;
static TEST_REGISTRATION registrations[128];
static SRWLOCK notification_lock = SRWLOCK_INIT;
static volatile LONG registration_count, live_registrations, unregister_count, callback_count, emit_threads;
static volatile LONG registration_thread, unregister_thread, revision;
__declspec(dllexport) void readout_network_configure(ULONG value) { InterlockedExchange(&mode, value); InterlockedExchange(&released, value >= 20 ? 0 : 1); }
__declspec(dllexport) void readout_network_release(void) { InterlockedExchange(&released, 1); }
__declspec(dllexport) ULONG readout_network_counter(ULONG field) {
    if (field == 3) return GetCurrentThreadId();
    if (field >= 4) {
        volatile LONG *value = field == 4 ? &live_registrations : field == 5 ? &registration_count :
            field == 6 ? &unregister_count : field == 7 ? &callback_count : field == 8 ? &emit_threads :
            field == 9 ? &registration_thread : &unregister_thread;
        return (ULONG)InterlockedCompareExchange(value, 0, 0);
    }
    return (ULONG)InterlockedCompareExchange(field == 0 ? &buffers : field == 1 ? &active : &held_thread, 0, 0);
}
static void hold(LONG value) {
    if (InterlockedCompareExchange(&mode, 0, 0) != value) return;
    InterlockedIncrement(&active); InterlockedExchange(&held_thread, GetCurrentThreadId());
    ULONGLONG start = GetTickCount64();
    while (!InterlockedCompareExchange(&released, 0, 0) && GetTickCount64() - start < 6000) Sleep(1);
    InterlockedDecrement(&active);
}
HANDLE WINAPI readout_network_GetProcessHeap(void) { return GetProcessHeap(); }
LPVOID WINAPI readout_network_HeapAlloc(HANDLE heap, DWORD flags, SIZE_T size) {
    LPVOID p = HeapAlloc(heap, flags, size); if (p) InterlockedIncrement(&buffers); return p;
}
BOOL WINAPI readout_network_HeapFree(HANDLE heap, DWORD flags, LPVOID p) {
    BOOL ok = HeapFree(heap, flags, p); if (ok) InterlockedDecrement(&buffers); return ok;
}
typedef struct {
    IP_ADAPTER_ADDRESSES adapter;
    IP_ADAPTER_UNICAST_ADDRESS unicast;
    IP_ADAPTER_DNS_SERVER_ADDRESS dns;
    IP_ADAPTER_GATEWAY_ADDRESS gateway;
    SOCKADDR_IN ip, dns_ip, gateway_ip;
    SOCKADDR_IN6 ipv6;
    CHAR key[40]; WCHAR name[32];
} SAMPLE;
static void ipv4(SOCKADDR_IN *value, UCHAR a, UCHAR b, UCHAR c, UCHAR d) {
    value->sin_family = AF_INET;
    UCHAR *bytes = (UCHAR *)&value->sin_addr; bytes[0] = a; bytes[1] = b; bytes[2] = c; bytes[3] = d;
}
ULONG WINAPI readout_network_GetAdaptersAddresses(ULONG family, ULONG flags, PVOID reserved,
    IP_ADAPTER_ADDRESSES *output, PULONG size) {
    (void)family; (void)flags; (void)reserved;
    hold(20);
    LONG current = InterlockedCompareExchange(&mode, 0, 0);
    if (current == 10) return ERROR_NO_DATA;
    if (current == 11) { *size = 9 * 1024 * 1024; return ERROR_BUFFER_OVERFLOW; }
    if (current == 12 && *size < 16384) { *size = 16384; return ERROR_BUFFER_OVERFLOW; }
    if (*size < sizeof(SAMPLE)) { *size = sizeof(SAMPLE); return ERROR_BUFFER_OVERFLOW; }
    SAMPLE *s = (SAMPLE *)output; ZeroMemory(s, sizeof(*s));
    strcpy_s(s->key, sizeof(s->key), "network-fixture"); wcscpy_s(s->name, 32, L"Fixture network");
    s->adapter.Length = sizeof(s->adapter); s->adapter.AdapterName = s->key;
    s->adapter.FriendlyName = s->name; s->adapter.Luid.Value = 0x1000006;
    s->adapter.Mtu = current == 14 ? UINT32_MAX : 1500 + InterlockedCompareExchange(&revision, 0, 0);
    s->adapter.IfType = current == 1 ? 0xffff : IF_TYPE_ETHERNET_CSMACD;
    s->adapter.OperStatus = current == 1 ? IfOperStatusUnknown : IfOperStatusUp;
    s->adapter.PhysicalAddressLength = 6;
    for (unsigned i = 0; i < 6; ++i) s->adapter.PhysicalAddress[i] = (BYTE)i;
    s->adapter.FirstUnicastAddress = &s->unicast;
    s->unicast.Length = sizeof(s->unicast);
    s->unicast.Address.lpSockaddr = (SOCKADDR *)&s->ip;
    s->unicast.Address.iSockaddrLength = sizeof(s->ip); s->unicast.OnLinkPrefixLength = current == 16 ? 255 : 24;
    ipv4(&s->ip, 192, 0, 2, 2);
    s->adapter.FirstDnsServerAddress = &s->dns; s->dns.Length = sizeof(s->dns);
    s->dns.Address.lpSockaddr = (SOCKADDR *)&s->dns_ip; s->dns.Address.iSockaddrLength = sizeof(s->dns_ip);
    ipv4(&s->dns_ip, 192, 0, 2, 53);
    s->adapter.FirstGatewayAddress = &s->gateway; s->gateway.Length = sizeof(s->gateway);
    s->gateway.Address.lpSockaddr = (SOCKADDR *)&s->gateway_ip; s->gateway.Address.iSockaddrLength = sizeof(s->gateway_ip);
    ipv4(&s->gateway_ip, 192, 0, 2, 1);
    if (current == 2) s->unicast.Next = &s->unicast;
    if (current == 3) s->dns.Address.lpSockaddr = (SOCKADDR *)((BYTE *)output + *size + 8);
    if (current == 4) { s->name[0] = 0xd800; s->name[1] = 0; }
    if (current == 5) s->gateway_ip.sin_family = 0xffff;
    if (current == 9) s->adapter.Next = &s->adapter;
    if (current == 13) { ++*size; return NO_ERROR; }
    if (current == 15) {
        s->ipv6.sin6_family = AF_INET6; s->ipv6.sin6_scope_id = 7;
        s->ipv6.sin6_addr.u.Byte[0] = 0xfe; s->ipv6.sin6_addr.u.Byte[1] = 0x80; s->ipv6.sin6_addr.u.Byte[15] = 1;
        s->unicast.Address.lpSockaddr = (SOCKADDR *)&s->ipv6;
        s->unicast.Address.iSockaddrLength = sizeof(s->ipv6); s->unicast.OnLinkPrefixLength = 64;
    }
    *size = sizeof(*s);
    return current == 8 ? ERROR_ACCESS_DENIED : NO_ERROR;
}
NETIO_STATUS WINAPI readout_network_GetIpForwardTable2(ADDRESS_FAMILY family, PMIB_IPFORWARD_TABLE2 *output) {
    (void)family; hold(21);
    MIB_IPFORWARD_TABLE2 *table = readout_network_HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY,
        sizeof(MIB_IPFORWARD_TABLE2) + sizeof(MIB_IPFORWARD_ROW2));
    if (!table) return ERROR_NOT_ENOUGH_MEMORY;
    *output = table; table->NumEntries = 2;
    table->Table[0].InterfaceLuid.Value = table->Table[1].InterfaceLuid.Value = 0x1000006;
    ipv4(&table->Table[0].DestinationPrefix.Prefix.Ipv4, 192, 0, 2, 0);
    table->Table[0].DestinationPrefix.PrefixLength = 24;
    ipv4(&table->Table[0].NextHop.Ipv4, 0, 0, 0, 0);
    ipv4(&table->Table[1].DestinationPrefix.Prefix.Ipv4, 0, 0, 0, 0);
    ipv4(&table->Table[1].NextHop.Ipv4, 192, 0, 2, 1);
    LONG current = InterlockedCompareExchange(&mode, 0, 0);
    if (current == 7) table->Table[0].DestinationPrefix.Prefix.si_family = 0xffff;
    return current == 6 ? ERROR_ACCESS_DENIED : NO_ERROR;
}
VOID WINAPI readout_network_FreeMibTable(PVOID memory) { readout_network_HeapFree(GetProcessHeap(), 0, memory); }

static DWORD register_notification(ULONG kind, TEST_CALLBACK callback, PVOID context, BOOLEAN initial, HANDLE *handle) {
    InterlockedExchange(&registration_thread, GetCurrentThreadId());
    hold(30);
    LONG current = InterlockedCompareExchange(&mode, 0, 0);
    if (current == 40 || (current == 41 && kind == 1)) return ERROR_NOT_SUPPORTED;
    if (current == 42 && kind == 1) return ERROR_ACCESS_DENIED;
    if (current == 44 && kind == 2) { *handle = NULL; return NO_ERROR; }
    AcquireSRWLockExclusive(&notification_lock);
    LONG index = registration_count;
    if (index >= 128) { ReleaseSRWLockExclusive(&notification_lock); return ERROR_NOT_ENOUGH_MEMORY; }
    TEST_REGISTRATION *entry = &registrations[index];
    entry->callback = callback; entry->context = context; entry->kind = kind; entry->live = TRUE;
    InterlockedIncrement(&registration_count); InterlockedIncrement(&live_registrations);
    *handle = entry;
    ReleaseSRWLockExclusive(&notification_lock);
    if (initial) callback(context, NULL, MibInitialNotification);
    return current == 43 && kind == 2 ? ERROR_GEN_FAILURE : NO_ERROR;
}
NETIO_STATUS WINAPI readout_network_NotifyIpInterfaceChange(ADDRESS_FAMILY family, PIPINTERFACE_CHANGE_CALLBACK callback, PVOID context, BOOLEAN initial, HANDLE *handle) {
    (void)family; return register_notification(0, (TEST_CALLBACK)callback, context, initial, handle);
}
NETIO_STATUS WINAPI readout_network_NotifyUnicastIpAddressChange(ADDRESS_FAMILY family, PUNICAST_IPADDRESS_CHANGE_CALLBACK callback, PVOID context, BOOLEAN initial, HANDLE *handle) {
    (void)family; return register_notification(1, (TEST_CALLBACK)callback, context, initial, handle);
}
NETIO_STATUS WINAPI readout_network_NotifyRouteChange2(ADDRESS_FAMILY family, PIPFORWARD_CHANGE_CALLBACK callback, PVOID context, BOOLEAN initial, HANDLE *handle) {
    (void)family; return register_notification(2, (TEST_CALLBACK)callback, context, initial, handle);
}
NETIO_STATUS WINAPI readout_network_CancelMibChangeNotify2(HANDLE handle) {
    InterlockedExchange(&unregister_thread, GetCurrentThreadId());
    hold(31);
    AcquireSRWLockExclusive(&notification_lock);
    TEST_REGISTRATION *entry = handle;
    if (entry < registrations || entry >= registrations + registration_count || !entry->live) {
        ReleaseSRWLockExclusive(&notification_lock); return ERROR_INVALID_PARAMETER;
    }
    InterlockedIncrement(&unregister_count);
    if (InterlockedCompareExchange(&mode, 0, 0) == 32) {
        ReleaseSRWLockExclusive(&notification_lock); return ERROR_ACCESS_DENIED;
    }
    entry->live = FALSE; InterlockedDecrement(&live_registrations);
    ReleaseSRWLockExclusive(&notification_lock);
    return NO_ERROR;
}
typedef struct { ULONG kind, type, valid, late, burst; } TEST_EMIT;
static DWORD WINAPI emit_notifications(PVOID data) {
    TEST_EMIT request = *(TEST_EMIT *)data; HeapFree(GetProcessHeap(), 0, data);
    for (ULONG n = 0; n < request.burst; ++n) {
        AcquireSRWLockShared(&notification_lock);
        for (LONG i = 0; i < registration_count; ++i) {
            TEST_REGISTRATION *entry = &registrations[i];
            if (entry->kind != request.kind || (request.late ? entry->live : !entry->live)) continue;
            BYTE row[256]; memset(row, 0xAB, sizeof(row));
            entry->callback(entry->context, request.valid ? row : NULL, request.type);
            memset(row, 0xDE, sizeof(row)); InterlockedIncrement(&callback_count);
        }
        ReleaseSRWLockShared(&notification_lock);
    }
    InterlockedDecrement(&emit_threads); return 0;
}
__declspec(dllexport) DWORD readout_network_emit(ULONG kind, ULONG type, ULONG valid, ULONG late, ULONG burst, ULONG value) {
    TEST_EMIT *request = HeapAlloc(GetProcessHeap(), 0, sizeof(TEST_EMIT));
    if (!request) return ERROR_NOT_ENOUGH_MEMORY;
    *request = (TEST_EMIT){kind, type, valid, late, burst}; InterlockedExchange(&revision, value);
    InterlockedIncrement(&emit_threads);
    HANDLE thread = CreateThread(NULL, 0, emit_notifications, request, 0, NULL);
    if (!thread) { DWORD error = GetLastError(); HeapFree(GetProcessHeap(), 0, request); InterlockedDecrement(&emit_threads); return error; }
    CloseHandle(thread); return NO_ERROR;
}
