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
static volatile LONG counters[19],tags[2]={101,202},visible=3,mode,status_enabled;
typedef struct StatusHandle {struct StatusHandle *next;UINT32 index;OVERLAPPED *overlapped;BATTERY_STATUS *output;DWORD error,written;BOOL pending;HANDLE reader,writer;} StatusHandle;
static SRWLOCK status_lock=SRWLOCK_INIT;
static StatusHandle *status_handles;
static volatile LONG pipe_sequence;
static BOOL create_status_pipe(StatusHandle *s) {
    WCHAR name[128];wsprintfW(name,L"\\\\.\\pipe\\DeviceReadoutBatteryStatus-%lu-%ld",GetCurrentProcessId(),InterlockedIncrement(&pipe_sequence));
    s->reader=CreateNamedPipeW(name,PIPE_ACCESS_INBOUND|FILE_FLAG_OVERLAPPED|FILE_FLAG_FIRST_PIPE_INSTANCE,PIPE_TYPE_BYTE|PIPE_READMODE_BYTE|PIPE_WAIT|PIPE_REJECT_REMOTE_CLIENTS,1,4096,4096,0,NULL);
    if(s->reader==INVALID_HANDLE_VALUE) {s->reader=NULL;return FALSE;}
    OVERLAPPED connect={0};connect.hEvent=CreateEventW(NULL,TRUE,FALSE,NULL);
    if(!connect.hEvent) goto failed;
    BOOL linked=ConnectNamedPipe(s->reader,&connect);DWORD error=linked?0:GetLastError();
    if(error && error!=ERROR_IO_PENDING && error!=ERROR_PIPE_CONNECTED) goto failed;
    s->writer=CreateFileW(name,GENERIC_WRITE,0,NULL,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,NULL);
    if(s->writer==INVALID_HANDLE_VALUE) {
        s->writer=NULL;if(error==ERROR_IO_PENDING) {DWORD bytes;CancelIoEx(s->reader,&connect);GetOverlappedResult(s->reader,&connect,&bytes,TRUE);}goto failed;
    }
    if(error==ERROR_IO_PENDING) {DWORD bytes;if(!GetOverlappedResult(s->reader,&connect,&bytes,TRUE)) goto failed;}
    CloseHandle(connect.hEvent);return TRUE;
failed:
    if(connect.hEvent) CloseHandle(connect.hEvent);if(s->reader) CloseHandle(s->reader);if(s->writer) CloseHandle(s->writer);s->reader=s->writer=NULL;return FALSE;
}
static PCM_NOTIFY_CALLBACK callback;
static PVOID callback_context;
static SRWLOCK callback_lock=SRWLOCK_INIT;
static HANDLE barrier;
static void record(void) {InterlockedCompareExchange(&counters[4],(LONG)GetCurrentThreadId(),0);}
EXPORT UINT32 readout_pack_counter(UINT32 index) {return index==5?GetCurrentThreadId():index<19?(UINT32)InterlockedCompareExchange(&counters[index],0,0):UINT32_MAX;}
EXPORT void readout_pack_configure(UINT32 key,UINT32 value) {
    InterlockedExchange(&counters[5],(LONG)GetCurrentThreadId());
    if(key==0) {
        if(value==50) {if(!barrier) barrier=CreateEventW(NULL,TRUE,FALSE,NULL);else ResetEvent(barrier);}
        InterlockedExchange(&mode,value);
    }
    else if(key==1 || key==2) InterlockedExchange(&tags[key-1],value);
    else if(key==3) InterlockedExchange(&visible,value);
    else if(key==4) InterlockedExchange(&status_enabled,value);
}
EXPORT DWORD readout_pack_status_emit(UINT32 index,DWORD flags,DWORD capacity,LONG rate) {
    DWORD found=0;AcquireSRWLockExclusive(&status_lock);
    for(StatusHandle *s=status_handles;s;s=s->next) if(s->index==index && s->pending) {
        BATTERY_STATUS value={flags,capacity,10000,rate};
        if(s->writer) {DWORD bytes;if(WriteFile(s->writer,&value,sizeof(value),&bytes,NULL) && bytes==sizeof(value)) {InterlockedIncrement(&counters[18]);found++;}continue;}
        *s->output=value;s->written=sizeof(value);s->error=0;s->pending=FALSE;
        SetEvent(s->overlapped->hEvent);InterlockedDecrement(&counters[13]);InterlockedIncrement(&counters[18]);found++;
    }
    ReleaseSRWLockExclusive(&status_lock);return found?0:ERROR_NOT_FOUND;
}
EXPORT DWORD readout_pack_status_fail(UINT32 index,DWORD error) {
    DWORD found=0;AcquireSRWLockExclusive(&status_lock);
    for(StatusHandle *s=status_handles;s;s=s->next) if(s->index==index && s->pending) {
        s->written=0;s->error=error;s->pending=FALSE;SetEvent(s->overlapped->hEvent);
        InterlockedDecrement(&counters[13]);InterlockedIncrement(&counters[18]);found++;
    }
    ReleaseSRWLockExclusive(&status_lock);return found?0:ERROR_NOT_FOUND;
}
EXPORT BOOL WINAPI readout_pack_status_complete(HANDLE handle,LPOVERLAPPED overlapped,LPDWORD written,BOOL wait) {
    StatusHandle *s=(StatusHandle*)handle;
    if(s->reader) {
        BOOL ok=GetOverlappedResult(s->reader,overlapped,written,wait);DWORD error=ok?0:GetLastError();
        AcquireSRWLockExclusive(&status_lock);if(error!=ERROR_IO_INCOMPLETE) {s->pending=FALSE;s->overlapped=NULL;s->output=NULL;InterlockedDecrement(&counters[13]);InterlockedIncrement(&counters[15]);}ReleaseSRWLockExclusive(&status_lock);
        SetLastError(error);return ok;
    }
    if(wait) WaitForSingleObject(overlapped->hEvent,INFINITE);
    AcquireSRWLockExclusive(&status_lock);DWORD error=s->pending?ERROR_IO_INCOMPLETE:s->error;*written=s->written;
    if(!s->pending) {s->overlapped=NULL;s->output=NULL;InterlockedIncrement(&counters[15]);}
    ReleaseSRWLockExclusive(&status_lock);SetLastError(error);return error==0;
}
EXPORT BOOL WINAPI readout_pack_status_cancel(HANDLE handle,LPOVERLAPPED overlapped) {
    StatusHandle *s=(StatusHandle*)handle;
    if(s->reader) {InterlockedIncrement(&counters[16]);return CancelIoEx(s->reader,overlapped);}
    AcquireSRWLockExclusive(&status_lock);
    BOOL found=s->pending && s->overlapped==overlapped;
    if(found) {
        InterlockedIncrement(&counters[16]);
        if(status_enabled!=2) {s->pending=FALSE;s->error=ERROR_OPERATION_ABORTED;s->written=0;SetEvent(overlapped->hEvent);InterlockedDecrement(&counters[13]);}
    }
    ReleaseSRWLockExclusive(&status_lock);SetLastError(found?0:ERROR_NOT_FOUND);return found;
}
EXPORT void readout_pack_release(void) {
    InterlockedExchange(&mode,0);if(barrier) SetEvent(barrier);
    if(status_enabled==2) {readout_pack_status_fail(0,ERROR_OPERATION_ABORTED);readout_pack_status_fail(1,ERROR_OPERATION_ABORTED);}
}
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
    record();if(access!=GENERIC_READ || sharing!=3 || security || disposition!=OPEN_EXISTING || (flags!=FILE_ATTRIBUTE_NORMAL && flags!=(FILE_ATTRIBUTE_NORMAL|FILE_FLAG_OVERLAPPED)) || template_handle) {InterlockedIncrement(&counters[6]);SetLastError(ERROR_ACCESS_DENIED);return INVALID_HANDLE_VALUE;}
    if(flags&FILE_FLAG_OVERLAPPED) {
        if(!status_enabled) {SetLastError(ERROR_NOT_SUPPORTED);return INVALID_HANDLE_VALUE;}
        for(UINT32 i=0;i<2;i++) if(!_wcsicmp(path,paths[i]) && (visible&(1u<<i))) {
            StatusHandle *s=HeapAlloc(GetProcessHeap(),HEAP_ZERO_MEMORY,sizeof(*s));if(!s) {SetLastError(ERROR_NOT_ENOUGH_MEMORY);return INVALID_HANDLE_VALUE;}
            if(status_enabled==3 && !create_status_pipe(s)) {HeapFree(GetProcessHeap(),0,s);SetLastError(ERROR_GEN_FAILURE);return INVALID_HANDLE_VALUE;}
            s->index=i;AcquireSRWLockExclusive(&status_lock);s->next=status_handles;status_handles=s;ReleaseSRWLockExclusive(&status_lock);
            InterlockedIncrement(&counters[12]);return (HANDLE)s;
        }
        SetLastError(ERROR_FILE_NOT_FOUND);return INVALID_HANDLE_VALUE;
    }
    for(UINT32 i=0;i<2;i++) if(!_wcsicmp(path,paths[i]) && (visible&(1u<<i))) {InterlockedIncrement(&counters[0]);return (HANDLE)(uintptr_t)(0x100+i);}
    SetLastError(ERROR_FILE_NOT_FOUND);return INVALID_HANDLE_VALUE;
}
EXPORT BOOL WINAPI readout_pack_close(HANDLE handle) {
    if((uintptr_t)handle>0x1000) {
        StatusHandle *s=(StatusHandle*)handle;AcquireSRWLockExclusive(&status_lock);
        if(s->pending || s->overlapped) {InterlockedIncrement(&counters[6]);ReleaseSRWLockExclusive(&status_lock);SetLastError(ERROR_IO_PENDING);return FALSE;}
        StatusHandle **link=&status_handles;while(*link && *link!=s) link=&(*link)->next;if(*link) *link=s->next;
        ReleaseSRWLockExclusive(&status_lock);if(s->reader) CloseHandle(s->reader);if(s->writer) CloseHandle(s->writer);HeapFree(GetProcessHeap(),0,s);InterlockedDecrement(&counters[12]);return TRUE;
    }
    (void)handle;record();
    if(InterlockedCompareExchange(&mode,0,6)==6) {InterlockedIncrement(&counters[9]);SetLastError(ERROR_ACCESS_DENIED);return FALSE;}
    InterlockedDecrement(&counters[0]);return TRUE;
}
EXPORT BOOL WINAPI readout_pack_ioctl(HANDLE handle,DWORD control,LPVOID input,DWORD input_size,LPVOID output,DWORD output_size,LPDWORD written,LPOVERLAPPED overlapped) {
    if((uintptr_t)handle>0x1000) {
        StatusHandle *s=(StatusHandle*)handle;*written=0;InterlockedExchange(&counters[17],(LONG)GetCurrentThreadId());
        if(control!=IOCTL_BATTERY_QUERY_STATUS || input_size!=sizeof(BATTERY_WAIT_STATUS) || output_size!=sizeof(BATTERY_STATUS) || !overlapped || !overlapped->hEvent) {InterlockedIncrement(&counters[6]);SetLastError(ERROR_INVALID_PARAMETER);return FALSE;}
        BATTERY_WAIT_STATUS *request=input;
        if(request->BatteryTag!=(ULONG)tags[s->index]) {SetLastError(ERROR_FILE_NOT_FOUND);return FALSE;}
        InterlockedIncrement(&counters[14]);
        if(!request->Timeout) {BATTERY_STATUS value={BATTERY_DISCHARGING,s->index?40:20000,10000,-5000};memcpy(output,&value,sizeof(value));*written=sizeof(value);return TRUE;}
        if(request->Timeout!=INFINITE || request->LowCapacity!=request->HighCapacity) {InterlockedIncrement(&counters[6]);SetLastError(ERROR_INVALID_PARAMETER);return FALSE;}
        AcquireSRWLockExclusive(&status_lock);s->pending=TRUE;s->overlapped=overlapped;s->output=output;s->written=0;s->error=ERROR_IO_PENDING;
        if(s->reader) {
            BOOL ok=ReadFile(s->reader,output,output_size,written,overlapped);DWORD error=ok?0:GetLastError();
            if(error==ERROR_IO_PENDING) InterlockedIncrement(&counters[13]);
            else {s->pending=FALSE;s->overlapped=NULL;s->output=NULL;}
            ReleaseSRWLockExclusive(&status_lock);
            SetLastError(error);return ok;
        }
        InterlockedIncrement(&counters[13]);ReleaseSRWLockExclusive(&status_lock);
        SetLastError(ERROR_IO_PENDING);return FALSE;
    }
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
