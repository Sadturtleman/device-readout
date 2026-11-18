#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <roapi.h>
#include <winstring.h>
#include <wlanapi.h>
#include <stdint.h>
#pragma comment(lib, "runtimeobject.lib")
#pragma comment(lib, "wlanapi.lib")

typedef HRESULT (WINAPI *Activate)(void **);
typedef HRESULT (WINAPI *WifiGetObject)(void *, void **);
typedef HRESULT (WINAPI *GetInt)(void *, INT32 *);
typedef HRESULT (WINAPI *GetAt)(void *, UINT32, void **);
typedef HRESULT (WINAPI *GetGuid)(void *, GUID *);
typedef HRESULT (WINAPI *GetBool)(void *, BYTE *);
typedef HRESULT (WINAPI *Query)(void *, REFIID, void **);
static void *slot(void *value, unsigned n) { return (*(void ***)value)[n]; }
static void drop(void *value) { if(value) ((ULONG (WINAPI *)(void *))slot(value,2))(value); }
static const IID profile2 = {0xe2045145,0x4c9f,0x400c,{0x91,0x50,0x7e,0xc7,0xd6,0xe2,0x88,0x8a}};
static HRESULT factory(void **output) {
    static const WCHAR name[]=L"Windows.Networking.Connectivity.NetworkInformation";
    static const IID iid={0x5074f851,0x950d,0x4165,{0x9c,0x15,0x36,0x56,0x19,0x48,0x1e,0xea}};
    HSTRING text=NULL; HRESULT hr=WindowsCreateString(name,ARRAYSIZE(name)-1,&text);
    if(SUCCEEDED(hr)) hr=RoGetActivationFactory(text,&iid,output);
    WindowsDeleteString(text); return hr;
}

/* Only copied values cross back to Dart. No COM object escapes this call. */
typedef struct {
    GUID adapter, network;
    INT32 ssid_status, security_status, rssi_status;
    UINT32 ssid_length;
    WCHAR *ssid;
    INT32 authentication, encryption, rssi, removed;
    HANDLE retained_client;
} WifiRecord;
typedef struct { INT32 status; UINT32 count; WifiRecord *records; INT32 current; } WifiInventory;
static BOOL same(const WifiRecord *a,const WifiRecord *b) {
    return IsEqualGUID(&a->adapter,&b->adapter) && IsEqualGUID(&a->network,&b->network);
}
static HRESULT key(void *profile, WifiRecord *value, BOOL *active) {
    void *extended=NULL,*adapter=NULL,*network=NULL; BYTE wlan=0; INT32 level=0;
    static const GUID zero={0}; *active=FALSE;
    HRESULT hr=((Query)slot(profile,0))(profile,&profile2,&extended);
    if(FAILED(hr)) goto done;
    if(!extended) {hr=E_FAIL;goto done;}
    hr=((GetBool)slot(extended,7))(extended,&wlan);
    if(FAILED(hr) || wlan==0) goto done;
    if(wlan!=1) {hr=E_FAIL;goto done;}
    hr=((GetInt)slot(profile,7))(profile,&level);
    if(FAILED(hr) || level==0) goto done;
    if(level<1 || level>3) {hr=E_FAIL;goto done;}
    hr=((WifiGetObject)slot(profile,11))(profile,&adapter);
    if(FAILED(hr)) goto done;
    if(!adapter) {hr=E_FAIL;goto done;}
    hr=((GetGuid)slot(adapter,10))(adapter,&value->adapter); if(FAILED(hr)) goto done;
    hr=((WifiGetObject)slot(adapter,9))(adapter,&network); if(FAILED(hr)) goto done;
    if(!network) {hr=E_FAIL;goto done;}
    hr=((GetGuid)slot(network,6))(network,&value->network); if(FAILED(hr)) goto done;
    if(IsEqualGUID(&value->adapter,&zero) || IsEqualGUID(&value->network,&zero)) {hr=E_FAIL;goto done;}
    *active=TRUE;
done:
    drop(network);drop(adapter);drop(extended);return hr;
}
static HRESULT inventory(void *source,void **vector,UINT32 *count) {
    HRESULT hr=((WifiGetObject)slot(source,6))(source,vector);
    if(FAILED(hr)) return hr;
    if(!*vector) return E_FAIL;
    hr=((GetInt)slot(*vector,7))(*vector,(INT32 *)count);
    return SUCCEEDED(hr) && *count>4096 ? E_FAIL : hr;
}
__declspec(dllexport) void readout_wifi_free(WifiRecord *records,UINT32 count) {
    if(!records) return;
    for(UINT32 i=0;i<count;i++) if(records[i].ssid) HeapFree(GetProcessHeap(),0,records[i].ssid);
    HeapFree(GetProcessHeap(),0,records);
}
__declspec(dllexport) WifiInventory readout_wifi_inventory(Activate activate,INT32 want_current) {
    WifiInventory result={0,0,NULL,-1};void *source=NULL,*vector=NULL,*profile=NULL;UINT32 count=0;
    result.status=RoInitialize(RO_INIT_MULTITHREADED);if(FAILED(result.status)) return result;
    result.status=(activate?activate:factory)(&source);if(FAILED(result.status)) goto done;
    if(!source) {result.status=E_FAIL;goto done;}
    result.status=inventory(source,&vector,&count);if(FAILED(result.status)) goto done;
    if(count) {
        result.records=HeapAlloc(GetProcessHeap(),HEAP_ZERO_MEMORY,count*sizeof(WifiRecord));
        if(!result.records) {result.status=E_OUTOFMEMORY;goto done;}
    }
    for(UINT32 i=0;i<count;i++) {
        WifiRecord record={0};BOOL active=FALSE;
        result.status=((GetAt)slot(vector,6))(vector,i,&profile);if(FAILED(result.status)) goto done;
        if(!profile) {result.status=E_FAIL;goto done;}
        result.status=key(profile,&record,&active);drop(profile);profile=NULL;
        if(FAILED(result.status)) goto done;
        if(!active) continue;
        for(UINT32 j=0;j<result.count;j++) if(same(&record,&result.records[j])) {result.status=E_FAIL;goto done;}
        result.records[result.count++]=record;
    }
    if(want_current) {
        result.status=((WifiGetObject)slot(source,7))(source,&profile);if(FAILED(result.status)) goto done;
        if(profile) {
            WifiRecord preferred={0};BOOL active=FALSE;result.status=key(profile,&preferred,&active);
            if(FAILED(result.status)) goto done;
            if(active) for(UINT32 i=0;i<result.count;i++) if(same(&preferred,&result.records[i])) result.current=(INT32)i;
        }
    }
done:
    drop(profile);drop(vector);drop(source);RoUninitialize();
    if(FAILED(result.status)) {readout_wifi_free(result.records,result.count);result.records=NULL;result.count=0;result.current=-1;}
    return result;
}
static HRESULT ssid(void *profile,WifiRecord *record) {
    void *extended=NULL,*details=NULL;HSTRING text=NULL;HRESULT hr=((Query)slot(profile,0))(profile,&profile2,&extended);
    if(FAILED(hr)) goto done;
    if(!extended) {hr=E_FAIL;goto done;}
    hr=((WifiGetObject)slot(extended,9))(extended,&details);if(FAILED(hr) || !details) goto done;
    hr=((WifiGetObject)slot(details,6))(details,(void **)&text);if(FAILED(hr)) goto done;
    UINT32 length=0;const WCHAR *buffer=WindowsGetStringRawBuffer(text,&length);
    if(length>65536 || (length && !buffer)) {hr=E_FAIL;goto done;}
    for(UINT32 i=0;i<length;i++) {
        if(buffer[i]>=0xd800 && buffer[i]<=0xdbff) {
            if(++i>=length || buffer[i]<0xdc00 || buffer[i]>0xdfff) {hr=E_FAIL;goto done;}
        } else if(buffer[i]>=0xdc00 && buffer[i]<=0xdfff) {hr=E_FAIL;goto done;}
    }
    record->ssid=HeapAlloc(GetProcessHeap(),HEAP_ZERO_MEMORY,((SIZE_T)length+1)*sizeof(WCHAR));
    if(!record->ssid) {hr=E_OUTOFMEMORY;goto done;}
    if(length) CopyMemory(record->ssid,buffer,length*sizeof(WCHAR));record->ssid_length=length;
done:
    WindowsDeleteString(text);drop(details);drop(extended);return hr;
}
static HRESULT security(void *profile,WifiRecord *record) {
    void *settings=NULL;record->authentication=-1;record->encryption=-1;
    HRESULT hr=((WifiGetObject)slot(profile,14))(profile,&settings);
    if(SUCCEEDED(hr) && settings) {
        hr=((GetInt)slot(settings,6))(settings,&record->authentication);
        if(SUCCEEDED(hr) && (record->authentication==0 || record->authentication==2))
            hr=((GetInt)slot(settings,7))(settings,&record->encryption);
    }
    drop(settings);return hr;
}
typedef DWORD (WINAPI *WlanOpen)(DWORD,PVOID,PDWORD,PHANDLE);
typedef DWORD (WINAPI *WlanQuery)(HANDLE,const GUID *,WLAN_INTF_OPCODE,PVOID,PDWORD,PVOID *,PWLAN_OPCODE_VALUE_TYPE);
typedef void (WINAPI *WlanFree)(PVOID);
typedef DWORD (WINAPI *WlanClose)(HANDLE,PVOID);
__declspec(dllexport) INT32 readout_wifi_close(HMODULE module,HANDLE client) {
    WlanClose close=module?(WlanClose)GetProcAddress(module,"readout_wifi_close_client"):WlanCloseHandle;
    return close?HRESULT_FROM_WIN32(close(client,NULL)):E_NOTIMPL;
}
static HRESULT rssi(HMODULE module,WifiRecord *record,BOOL *removed) {
    *removed=FALSE;
    WlanOpen open=module?(WlanOpen)GetProcAddress(module,"readout_wifi_open"):WlanOpenHandle;
    WlanQuery query=module?(WlanQuery)GetProcAddress(module,"readout_wifi_query"):WlanQueryInterface;
    WlanFree free=module?(WlanFree)GetProcAddress(module,"readout_wifi_free_data"):WlanFreeMemory;
    WlanClose close=module?(WlanClose)GetProcAddress(module,"readout_wifi_close_client"):WlanCloseHandle;
    if(!open || !query || !free || !close) return E_NOTIMPL;
    DWORD version=0,size=0;HANDLE client=NULL;void *data=NULL;
    HRESULT hr=HRESULT_FROM_WIN32(open(2,NULL,&version,&client));if(FAILED(hr)) goto done;
    if(!client) {hr=E_FAIL;goto done;}if(version<2) {hr=E_NOTIMPL;goto done;}
    hr=HRESULT_FROM_WIN32(query(client,&record->adapter,wlan_intf_opcode_rssi,NULL,&size,&data,NULL));
    if(hr==HRESULT_FROM_WIN32(ERROR_NOT_FOUND) || hr==HRESULT_FROM_WIN32(ERROR_INVALID_STATE)) *removed=TRUE;
    if(FAILED(hr)) goto done;
    if(size!=sizeof(LONG) || !data) {hr=E_FAIL;goto done;}record->rssi=*(LONG *)data;
done:
    if(data) free(data);
    if(client) {
        HRESULT cleanup=HRESULT_FROM_WIN32(close(client,NULL));
        if(FAILED(cleanup)) {record->retained_client=client;if(SUCCEEDED(hr)) hr=cleanup;}
    }
    return hr;
}
__declspec(dllexport) INT32 readout_wifi_fields(Activate activate,HMODULE module,WifiRecord *record,INT32 wlan_status) {
    if(!record) return E_INVALIDARG;
    record->removed=FALSE;
    void *source=NULL,*vector=NULL,*profile=NULL;UINT32 count=0,found=0;
    HRESULT hr=RoInitialize(RO_INIT_MULTITHREADED);if(FAILED(hr)) return hr;
    hr=(activate?activate:factory)(&source);if(FAILED(hr)) goto done;
    if(!source) {hr=E_FAIL;goto done;}hr=inventory(source,&vector,&count);if(FAILED(hr)) goto done;
    for(UINT32 i=0;i<count;i++) {
        WifiRecord identity={0};BOOL active=FALSE;
        hr=((GetAt)slot(vector,6))(vector,i,&profile);if(FAILED(hr)) goto done;
        if(!profile) {hr=E_FAIL;goto done;}hr=key(profile,&identity,&active);if(FAILED(hr)) goto done;
        if(active && same(record,&identity)) {
            if(found++) {hr=E_FAIL;goto done;}
            BOOL removed=FALSE;
            record->ssid_status=ssid(profile,record);record->security_status=security(profile,record);
            record->rssi_status=FAILED(wlan_status)?wlan_status:rssi(module,record,&removed);
            if(removed) {record->removed=TRUE;hr=record->rssi_status;goto done;}
            if(FAILED(record->ssid_status) && FAILED(record->security_status) && FAILED(record->rssi_status)) {
                hr=record->ssid_status==E_ACCESSDENIED || record->security_status==E_ACCESSDENIED || record->rssi_status==E_ACCESSDENIED?E_ACCESSDENIED:E_FAIL;
                goto done;
            }
        }
        drop(profile);profile=NULL;
    }
    if(!found) {record->removed=TRUE;hr=HRESULT_FROM_WIN32(ERROR_NOT_FOUND);}
done:
    drop(profile);drop(vector);drop(source);RoUninitialize();return hr;
}
