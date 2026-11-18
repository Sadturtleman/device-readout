#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <setupapi.h>
#include <cfgmgr32.h>
#include <winioctl.h>
#include <poclass.h>
#include <stddef.h>
#include <stdint.h>
#include <wchar.h>
#define EXPORT __declspec(dllexport)
static const GUID pack_class={0x72631e54,0x78a4,0x11d0,{0xbc,0xf7,0x00,0xaa,0x00,0xb7,0xb3,0x2a}};
static const WCHAR *paths[]={L"\\\\?\\DeviceReadoutPackA",L"\\\\?\\DeviceReadoutPackB"};
static volatile LONG counters[12],tags[2]={101,202},visible=3,mode;
static PCM_NOTIFY_CALLBACK callback;
static PVOID callback_context;
static SRWLOCK callback_lock=SRWLOCK_INIT;
static HANDLE barrier;
static void record(void) {InterlockedCompareExchange(&counters[4],(LONG)GetCurrentThreadId(),0);}
EXPORT UINT32 readout_pack_counter(UINT32 index) {return index==5?GetCurrentThreadId():index<12?(UINT32)InterlockedCompareExchange(&counters[index],0,0):UINT32_MAX;}
EXPORT void readout_pack_configure(UINT32 key,UINT32 value) {
    InterlockedExchange(&counters[5],(LONG)GetCurrentThreadId());
    if(key==0) {
        if(value==50) {if(!barrier) barrier=CreateEventW(NULL,TRUE,FALSE,NULL);else ResetEvent(barrier);}
        InterlockedExchange(&mode,value);
    }
    else if(key==1 || key==2) InterlockedExchange(&tags[key-1],value);
    else if(key==3) InterlockedExchange(&visible,value);
}
EXPORT void readout_pack_release(void) {InterlockedExchange(&mode,0);if(barrier) SetEvent(barrier);}
typedef struct {UINT32 index,action;} EmitData;
static DWORD WINAPI emit_event(void *argument) {
    EmitData *emit=argument;const WCHAR *path=paths[emit->index];
    DWORD size=(DWORD)(offsetof(CM_NOTIFY_EVENT_DATA,u.DeviceInterface.SymbolicLink)+(wcslen(path)+1)*sizeof(WCHAR));
    CM_NOTIFY_EVENT_DATA *data=HeapAlloc(GetProcessHeap(),HEAP_ZERO_MEMORY,size);
    if(data) {
        data->FilterType=CM_NOTIFY_FILTER_TYPE_DEVICEINTERFACE;data->u.DeviceInterface.ClassGuid=pack_class;
        memcpy(data->u.DeviceInterface.SymbolicLink,path,(wcslen(path)+1)*sizeof(WCHAR));
        AcquireSRWLockShared(&callback_lock);
        if(callback) {callback((HCMNOTIFICATION)(uintptr_t)1,callback_context,(CM_NOTIFY_ACTION)emit->action,data,size);InterlockedIncrement(&counters[3]);}
        ReleaseSRWLockShared(&callback_lock);HeapFree(GetProcessHeap(),0,data);
    }
    HeapFree(GetProcessHeap(),0,emit);InterlockedDecrement(&counters[10]);return 0;
}
EXPORT UINT32 readout_pack_emit(UINT32 index,UINT32 action) {
    if(index>1 || action>1) return ERROR_INVALID_PARAMETER;
    EmitData *data=HeapAlloc(GetProcessHeap(),HEAP_ZERO_MEMORY,sizeof(*data));if(!data) return ERROR_NOT_ENOUGH_MEMORY;
    data->index=index;data->action=action;InterlockedIncrement(&counters[10]);
    HANDLE thread=CreateThread(NULL,0,emit_event,data,0,NULL);
    if(!thread) {DWORD error=GetLastError();InterlockedDecrement(&counters[10]);HeapFree(GetProcessHeap(),0,data);return error;}
    CloseHandle(thread);return 0;
}
EXPORT HDEVINFO WINAPI readout_pack_class_devs(const GUID *guid,PCWSTR enumerator,HWND parent,DWORD flags) {
    record();if(!callback || memcmp(guid,&pack_class,sizeof(GUID)) || enumerator || parent || flags!=0x12) {InterlockedIncrement(&counters[6]);SetLastError(ERROR_INVALID_PARAMETER);return INVALID_HANDLE_VALUE;}
    if(mode==1) {SetLastError(ERROR_ACCESS_DENIED);return INVALID_HANDLE_VALUE;}
    InterlockedIncrement(&counters[1]);return (HDEVINFO)(uintptr_t)0x55;
}
EXPORT BOOL WINAPI readout_pack_enum(HDEVINFO info,PSP_DEVINFO_DATA device,const GUID *guid,DWORD index,PSP_DEVICE_INTERFACE_DATA data) {
    record();(void)info;(void)device;(void)guid;
    UINT32 found=0;
    for(UINT32 i=0;i<2;i++) if(visible&(1u<<i)) {if(found++==index) {data->Reserved=i;return TRUE;}}
    SetLastError(ERROR_NO_MORE_ITEMS);return FALSE;
}
EXPORT BOOL WINAPI readout_pack_detail(HDEVINFO info,PSP_DEVICE_INTERFACE_DATA data,PSP_DEVICE_INTERFACE_DETAIL_DATA_W output,DWORD size,PDWORD required,PSP_DEVINFO_DATA device) {
    record();(void)info;(void)device;
    const WCHAR *path=paths[data->Reserved];*required=(DWORD)(offsetof(SP_DEVICE_INTERFACE_DETAIL_DATA_W,DevicePath)+(wcslen(path)+1)*sizeof(WCHAR));
    if(!output || size<*required) {SetLastError(ERROR_INSUFFICIENT_BUFFER);return FALSE;}
    if(output->cbSize!=sizeof(*output)) {SetLastError(ERROR_INVALID_PARAMETER);return FALSE;}
    memcpy(output->DevicePath,path,(wcslen(path)+1)*sizeof(WCHAR));return TRUE;
}
EXPORT BOOL WINAPI readout_pack_destroy(HDEVINFO info) {(void)info;record();InterlockedDecrement(&counters[1]);return TRUE;}
EXPORT HANDLE WINAPI readout_pack_open(PCWSTR path,DWORD access,DWORD sharing,LPSECURITY_ATTRIBUTES security,DWORD disposition,DWORD flags,HANDLE template_handle) {
    record();if(access!=GENERIC_READ || sharing!=3 || security || disposition!=OPEN_EXISTING || flags!=FILE_ATTRIBUTE_NORMAL || template_handle) {InterlockedIncrement(&counters[6]);SetLastError(ERROR_ACCESS_DENIED);return INVALID_HANDLE_VALUE;}
    for(UINT32 i=0;i<2;i++) if(!_wcsicmp(path,paths[i]) && (visible&(1u<<i))) {InterlockedIncrement(&counters[0]);return (HANDLE)(uintptr_t)(0x100+i);}
    SetLastError(ERROR_FILE_NOT_FOUND);return INVALID_HANDLE_VALUE;
}
EXPORT BOOL WINAPI readout_pack_close(HANDLE handle) {
    (void)handle;record();
    if(InterlockedCompareExchange(&mode,0,6)==6) {InterlockedIncrement(&counters[9]);SetLastError(ERROR_ACCESS_DENIED);return FALSE;}
    InterlockedDecrement(&counters[0]);return TRUE;
}
EXPORT BOOL WINAPI readout_pack_ioctl(HANDLE handle,DWORD control,LPVOID input,DWORD input_size,LPVOID output,DWORD output_size,LPDWORD written,LPOVERLAPPED overlapped) {
    record();UINT32 i=(UINT32)((uintptr_t)handle-0x100);*written=0;
    if(i>1 || overlapped) {SetLastError(ERROR_INVALID_PARAMETER);return FALSE;}
    if(control==IOCTL_BATTERY_QUERY_TAG && input_size==4 && output_size==4) {*(ULONG*)output=tags[i];*written=4;return TRUE;}
    if(*(ULONG*)input!=(ULONG)tags[i] || !tags[i]) {SetLastError(ERROR_NO_SUCH_DEVICE);return FALSE;}
    if(control==IOCTL_BATTERY_QUERY_STATUS && input_size==sizeof(BATTERY_WAIT_STATUS) && output_size==sizeof(BATTERY_STATUS)) {
        BATTERY_STATUS value={BATTERY_DISCHARGING,i?40:20000,10000,-5000};memcpy(output,&value,sizeof(value));*written=sizeof(value);return TRUE;
    }
    if(control==IOCTL_BATTERY_QUERY_INFORMATION && input_size==sizeof(BATTERY_QUERY_INFORMATION)) {
        BATTERY_QUERY_INFORMATION *query=input;
        if(mode==50 && query->InformationLevel==BatteryInformation) {InterlockedExchange(&counters[4],(LONG)GetCurrentThreadId());InterlockedIncrement(&counters[11]);WaitForSingleObject(barrier,6000);InterlockedDecrement(&counters[11]);}
        if(query->InformationLevel==BatteryInformation && output_size==sizeof(BATTERY_INFORMATION)) {
            BATTERY_INFORMATION value={0};value.Capabilities=i?BATTERY_CAPACITY_RELATIVE:BATTERY_SYSTEM_BATTERY;
            value.Technology=1;memcpy(value.Chemistry,"LION",4);value.DesignedCapacity=i?120:60000;value.FullChargedCapacity=i?100:50000;value.CycleCount=42;
            memcpy(output,&value,sizeof(value));*written=sizeof(value);return TRUE;
        }
        if(output_size==4 && (query->InformationLevel==BatteryTemperature || query->InformationLevel==BatteryEstimatedTime)) {
            *(ULONG*)output=query->InformationLevel==BatteryTemperature?2981:7200;*written=4;return TRUE;
        }
    }
    SetLastError(ERROR_INVALID_FUNCTION);return FALSE;
}
EXPORT CONFIGRET WINAPI readout_pack_register(PCM_NOTIFY_FILTER filter,PVOID context,PCM_NOTIFY_CALLBACK method,PHCMNOTIFICATION registration) {
    record();InterlockedIncrement(&counters[8]);
    if(filter->cbSize!=sizeof(*filter) || filter->FilterType!=CM_NOTIFY_FILTER_TYPE_DEVICEINTERFACE || memcmp(&filter->u.DeviceInterface.ClassGuid,&pack_class,sizeof(GUID))) {InterlockedIncrement(&counters[6]);return CR_INVALID_DATA;}
    AcquireSRWLockExclusive(&callback_lock);callback=method;callback_context=context;*registration=(HCMNOTIFICATION)(uintptr_t)1;InterlockedIncrement(&counters[2]);ReleaseSRWLockExclusive(&callback_lock);return CR_SUCCESS;
}
EXPORT CONFIGRET WINAPI readout_pack_unregister(HCMNOTIFICATION registration) {
    record();(void)registration;AcquireSRWLockExclusive(&callback_lock);callback=NULL;callback_context=NULL;InterlockedIncrement(&counters[7]);InterlockedDecrement(&counters[2]);ReleaseSRWLockExclusive(&callback_lock);return CR_SUCCESS;
}
