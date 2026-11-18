#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <iphlpapi.h>
#include <stdint.h>

/* Test-only transparent native adapter. Every query/registration delegates to
   the real Windows API; no network settings or devices are changed. */
typedef VOID (WINAPI *CALLBACK_FN)(PVOID, PVOID, ULONG);
typedef struct { CALLBACK_FN callback; PVOID context; HANDLE handle; ULONG kind; } LIVE_REGISTRATION;
static volatile LONG live, registered, cancelled, callbacks, acknowledgements, buffers;
static volatile LONG kind_acknowledgements[3];
__declspec(dllexport) ULONG readout_network_live_counter(ULONG field) {
    if(field >= 6 && field <= 8) return (ULONG)InterlockedCompareExchange(&kind_acknowledgements[field-6],0,0);
    volatile LONG *value = field == 0 ? &buffers : field == 1 ? &live : field == 2 ? &registered :
        field == 3 ? &cancelled : field == 4 ? &callbacks : &acknowledgements;
    return (ULONG)InterlockedCompareExchange(value, 0, 0);
}
HANDLE WINAPI readout_live_GetProcessHeap(void) { return GetProcessHeap(); }
LPVOID WINAPI readout_live_HeapAlloc(HANDLE heap, DWORD flags, SIZE_T size) {
    LPVOID p=HeapAlloc(heap,flags,size); if(p) InterlockedIncrement(&buffers); return p;
}
BOOL WINAPI readout_live_HeapFree(HANDLE heap, DWORD flags, LPVOID memory) {
    BOOL ok=HeapFree(heap,flags,memory); if(ok) InterlockedDecrement(&buffers); return ok;
}
ULONG WINAPI readout_live_GetAdaptersAddresses(ULONG family, ULONG flags, PVOID reserved, PIP_ADAPTER_ADDRESSES values, PULONG size) {
    return GetAdaptersAddresses(family,flags,reserved,values,size);
}
NETIO_STATUS WINAPI readout_live_GetIpForwardTable2(ADDRESS_FAMILY family, PMIB_IPFORWARD_TABLE2 *table) { return GetIpForwardTable2(family,table); }
VOID WINAPI readout_live_FreeMibTable(PVOID memory) { FreeMibTable(memory); }
static VOID WINAPI changed(PVOID context, PVOID row, ULONG type) {
    LIVE_REGISTRATION *record=context;
    InterlockedIncrement(&callbacks);
    if(type==MibInitialNotification) { InterlockedIncrement(&acknowledgements); InterlockedIncrement(&kind_acknowledgements[record->kind]); }
    record->callback(record->context,row,type);
}
static DWORD subscribe(ULONG kind, CALLBACK_FN callback, PVOID context, BOOLEAN initial, HANDLE *handle) {
    LIVE_REGISTRATION *record=HeapAlloc(GetProcessHeap(),HEAP_ZERO_MEMORY,sizeof(*record));
    if(!record) return ERROR_NOT_ENOUGH_MEMORY;
    record->callback=callback; record->context=context; record->kind=kind;
    DWORD result = kind == 0 ? NotifyIpInterfaceChange(AF_UNSPEC,(PIPINTERFACE_CHANGE_CALLBACK)changed,record,initial,&record->handle) :
        kind == 1 ? NotifyUnicastIpAddressChange(AF_UNSPEC,(PUNICAST_IPADDRESS_CHANGE_CALLBACK)changed,record,initial,&record->handle) :
        NotifyRouteChange2(AF_UNSPEC,(PIPFORWARD_CHANGE_CALLBACK)changed,record,initial,&record->handle);
    if(result) { HeapFree(GetProcessHeap(),0,record); return result; }
    *handle=record; InterlockedIncrement(&live); InterlockedIncrement(&registered); return NO_ERROR;
}
NETIO_STATUS WINAPI readout_live_NotifyIpInterfaceChange(ADDRESS_FAMILY family, PIPINTERFACE_CHANGE_CALLBACK callback, PVOID context, BOOLEAN initial, HANDLE *handle) {
    (void)family; return subscribe(0,(CALLBACK_FN)callback,context,initial,handle);
}
NETIO_STATUS WINAPI readout_live_NotifyUnicastIpAddressChange(ADDRESS_FAMILY family, PUNICAST_IPADDRESS_CHANGE_CALLBACK callback, PVOID context, BOOLEAN initial, HANDLE *handle) {
    (void)family; return subscribe(1,(CALLBACK_FN)callback,context,initial,handle);
}
NETIO_STATUS WINAPI readout_live_NotifyRouteChange2(ADDRESS_FAMILY family, PIPFORWARD_CHANGE_CALLBACK callback, PVOID context, BOOLEAN initial, HANDLE *handle) {
    (void)family; return subscribe(2,(CALLBACK_FN)callback,context,initial,handle);
}
NETIO_STATUS WINAPI readout_live_CancelMibChangeNotify2(HANDLE handle) {
    LIVE_REGISTRATION *record=handle;
    DWORD error=CancelMibChangeNotify2(record->handle);
    if(!error) { HeapFree(GetProcessHeap(),0,record); InterlockedDecrement(&live); InterlockedIncrement(&cancelled); }
    return error;
}
