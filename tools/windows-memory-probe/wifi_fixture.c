/* Included by connectivity_fixture.c to share the native source and counters. */
#include <winstring.h>
#include <wlanapi.h>
#pragma comment(lib, "runtimeobject.lib")
static volatile LONG wifi_clients,wifi_buffers,wifi_opens,wifi_queries,wifi_closes,wifi_wrong_opcode;
static ULONG wifi_counter(ULONG field) {
    volatile LONG *value=field==10?&wifi_clients:field==11?&wifi_buffers:field==12?&wifi_opens:
        field==13?&wifi_queries:field==14?&wifi_closes:&wifi_wrong_opcode;
    return InterlockedCompareExchange(value,0,0);
}
static HRESULT wifi_make(void **table,UINT64 index,void **output) {
    HRESULT hr=make(table,output);if(SUCCEEDED(hr)) ((Object *)*output)->value=index;return hr;
}
static HRESULT WINAPI wifi_level(Object *self,INT32 *output) {
    if(current_mode()<70) return level(self,output);
    apartment();LONG m=current_mode();
    *output=self->value==3 || m==75 || (m==73 && self->value==0)?0:3;return S_OK;
}
static HRESULT WINAPI wifi_wlan(Object *self,BYTE *output) { apartment();*output=self->value==2?0:1;return S_OK; }
static HRESULT WINAPI wifi_ssid(Object *self,void **output) {
    apartment();hold(92);LONG m=current_mode();
    const WCHAR *text=self->value==0?(m==71?L"":m==72?L"Changed":L"First \xD83D\xDE80"):L"Second";
    const WCHAR malformed[]={0xd800};
    HRESULT hr=m==85?WindowsCreateString(malformed,1,(HSTRING *)output):WindowsCreateString(text,(UINT32)wcslen(text),(HSTRING *)output);
    return SUCCEEDED(hr) && (m==80 || m==83)?E_ACCESSDENIED:hr;
}
static void *wifi_details_table[7]={NULL,add,release,NULL,NULL,NULL,wifi_ssid};
static HRESULT WINAPI wifi_details(Object *self,void **output) { apartment();return wifi_make(wifi_details_table,self->value,output); }
static void *wifi_extended_table[10]={NULL,add,release,NULL,NULL,NULL,NULL,wifi_wlan,NULL,wifi_details};
static HRESULT WINAPI wifi_profile_query(Object *self,REFIID iid,void **output) {
    static const IID expected={0xe2045145,0x4c9f,0x400c,{0x91,0x50,0x7e,0xc7,0xd6,0xe2,0x88,0x8a}};
    apartment();*output=NULL;if(!IsEqualIID(iid,&expected)) return E_NOINTERFACE;
    return wifi_make(wifi_extended_table,self->value,output);
}
static HRESULT WINAPI wifi_adapter_id(Object *self,GUID *output) {
    apartment();hold(91);ZeroMemory(output,sizeof(*output));output->Data1=100+(ULONG)self->value;return S_OK;
}
static HRESULT WINAPI wifi_network_id(Object *self,GUID *output) {
    apartment();ZeroMemory(output,sizeof(*output));output->Data1=(current_mode()==74 && self->value==0?300:200)+(ULONG)self->value;return S_OK;
}
static void *wifi_network_table[7]={NULL,add,release,NULL,NULL,NULL,wifi_network_id};
static HRESULT WINAPI wifi_network(Object *self,void **output) { apartment();return wifi_make(wifi_network_table,self->value,output); }
static void *wifi_adapter_table[11]={NULL,add,release,NULL,NULL,NULL,NULL,NULL,NULL,wifi_network,wifi_adapter_id};
static HRESULT WINAPI wifi_adapter(Object *self,void **output) { apartment();return wifi_make(wifi_adapter_table,self->value,output); }
static volatile LONG wifi_authentication=-1,wifi_encryption=-1;
__declspec(dllexport) void readout_wifi_auth(INT32 authentication,INT32 encryption) {
    InterlockedExchange(&wifi_authentication,authentication);InterlockedExchange(&wifi_encryption,encryption);
}
static HRESULT WINAPI wifi_auth(Object *self,INT32 *output) {
    apartment();hold(93);LONG m=current_mode(),configured=InterlockedCompareExchange(&wifi_authentication,0,0);
    *output=configured>=0?configured:m==84?99:m==71?0:m==72 && self->value==0?11:8;return S_OK;
}
static HRESULT WINAPI wifi_encryption_value(void *self,INT32 *output) {
    (void)self;apartment();LONG configured=InterlockedCompareExchange(&wifi_encryption,0,0);
    *output=configured>=0?configured:0;return S_OK;
}
static void *wifi_settings_table[8]={NULL,add,release,NULL,NULL,NULL,wifi_auth,wifi_encryption_value};
static HRESULT WINAPI wifi_settings(Object *self,void **output) {
    apartment();HRESULT hr=wifi_make(wifi_settings_table,self->value,output);
    return SUCCEEDED(hr) && (current_mode()==81 || current_mode()==83)?E_FAIL:hr;
}
static HRESULT WINAPI wifi_size(void *self,UINT32 *output) { (void)self;apartment();*output=current_mode()==78?4097:4;return S_OK; }
static HRESULT WINAPI wifi_at(void *self,UINT32 index,void **output) {
    (void)self;apartment();return wifi_make(profile_table,current_mode()==79 && index==1?0:index,output);
}
static void *wifi_vector_table[8]={NULL,add,release,NULL,NULL,NULL,wifi_at,wifi_size};
static HRESULT WINAPI wifi_profiles(void *self,void **output) {
    (void)self;apartment();hold(90);HRESULT hr=make(wifi_vector_table,output);
    return SUCCEEDED(hr) && current_mode()==77?E_ACCESSDENIED:SUCCEEDED(hr) && current_mode()==97?HRESULT_FROM_WIN32(ERROR_NOT_FOUND):hr;
}
static HRESULT wifi_preferred(void **output) { return wifi_make(profile_table,current_mode()==76?2:0,output); }
__declspec(dllexport) DWORD WINAPI readout_wifi_open(DWORD version,PVOID reserved,PDWORD negotiated,PHANDLE output) {
    (void)reserved;hold(94);InterlockedIncrement(&wifi_opens);*negotiated=2;
    if(version!=2) InterlockedIncrement(&wifi_wrong_opcode);
    *output=HeapAlloc(GetProcessHeap(),0,1);if(!*output) return ERROR_OUTOFMEMORY;
    InterlockedIncrement(&wifi_clients);return current_mode()==88?ERROR_ACCESS_DENIED:current_mode()==98?ERROR_NOT_FOUND:ERROR_SUCCESS;
}
__declspec(dllexport) DWORD WINAPI readout_wifi_query(HANDLE client,const GUID *adapter,WLAN_INTF_OPCODE opcode,PVOID reserved,PDWORD size,PVOID *data,PWLAN_OPCODE_VALUE_TYPE type) {
    (void)client;(void)reserved;(void)type;hold(95);InterlockedIncrement(&wifi_queries);
    if(opcode!=wlan_intf_opcode_rssi) {InterlockedIncrement(&wifi_wrong_opcode);return ERROR_INVALID_PARAMETER;}
    *data=HeapAlloc(GetProcessHeap(),0,sizeof(LONG));if(!*data) return ERROR_OUTOFMEMORY;
    InterlockedIncrement(&wifi_buffers);*size=sizeof(LONG);
    LONG m=current_mode();*(LONG *)*data=m==86?0:m==72?-61:adapter->Data1==100?-47:-65;
    return m==82 || m==83?ERROR_ACCESS_DENIED:m==89?ERROR_NOT_FOUND:ERROR_SUCCESS;
}
__declspec(dllexport) void WINAPI readout_wifi_free_data(PVOID data) { HeapFree(GetProcessHeap(),0,data);InterlockedDecrement(&wifi_buffers); }
__declspec(dllexport) DWORD WINAPI readout_wifi_close_client(HANDLE client,PVOID reserved) {
    (void)reserved;hold(96);InterlockedIncrement(&wifi_closes);
    if(current_mode()==87) return ERROR_ACCESS_DENIED;
    if(current_mode()==99) return ERROR_NOT_FOUND;
    HeapFree(GetProcessHeap(),0,client);InterlockedDecrement(&wifi_clients);return ERROR_SUCCESS;
}
