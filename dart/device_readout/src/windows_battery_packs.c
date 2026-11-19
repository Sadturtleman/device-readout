#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <setupapi.h>
#include <cfgmgr32.h>
#include <winioctl.h>
#include <poclass.h>
#include <stdint.h>
#include <stddef.h>
#include <wchar.h>
#pragma comment(lib,"setupapi.lib")
#pragma comment(lib,"cfgmgr32.lib")
#define EXPORT __declspec(dllexport)
static const GUID pack_class={0x72631e54,0x78a4,0x11d0,{0xbc,0xf7,0x00,0xaa,0x00,0xb7,0xb3,0x2a}};
typedef HDEVINFO (WINAPI *PackClassDevs)(const GUID*,PCWSTR,HWND,DWORD);
typedef BOOL (WINAPI *PackEnum)(HDEVINFO,PSP_DEVINFO_DATA,const GUID*,DWORD,PSP_DEVICE_INTERFACE_DATA);
typedef BOOL (WINAPI *PackDetail)(HDEVINFO,PSP_DEVICE_INTERFACE_DATA,PSP_DEVICE_INTERFACE_DETAIL_DATA_W,DWORD,PDWORD,PSP_DEVINFO_DATA);
typedef BOOL (WINAPI *PackDestroy)(HDEVINFO);
typedef HANDLE (WINAPI *PackOpen)(PCWSTR,DWORD,DWORD,LPSECURITY_ATTRIBUTES,DWORD,DWORD,HANDLE);
typedef BOOL (WINAPI *PackIoctl)(HANDLE,DWORD,LPVOID,DWORD,LPVOID,DWORD,LPDWORD,LPOVERLAPPED);
typedef BOOL (WINAPI *PackClose)(HANDLE);
typedef CONFIGRET (WINAPI *PackRegister)(PCM_NOTIFY_FILTER,PVOID,PCM_NOTIFY_CALLBACK,PHCMNOTIFICATION);
typedef CONFIGRET (WINAPI *PackUnregister)(HCMNOTIFICATION);
typedef void (WINAPI *PackDispatch)(void*,void*,ULONG);
typedef struct PackPath {struct PackPath *next;WCHAR *text;UINT64 version;BOOL absent;} PackPath;
typedef struct PackTarget {struct PackTarget *next;PackPath *path;UINT64 id,version;ULONG tag;volatile LONG retired,references;} PackTarget;
typedef struct PackResource {struct PackResource *next;HANDLE handle;BOOL inventory;} PackResource;
typedef struct {
    SRWLOCK lock;PackPath *paths;PackTarget *targets;PackResource *resources;UINT64 sequence,token;
    HCMNOTIFICATION registration;PackDispatch dispatch;DWORD failure;BOOL closed;HMODULE module;
    PackClassDevs class_devs;PackEnum enumerate;PackDetail detail;PackDestroy destroy;
    PackOpen open;PackIoctl ioctl;PackClose close;PackRegister subscribe;PackUnregister unsubscribe;
} PackContext;
typedef struct {DWORD error;PackContext *owner;} PackContextResult;
typedef struct {DWORD error,count;UINT64 *ids;} PackInventory;
typedef struct {
    DWORD error,mask,capabilities,design,full,cycles,flags,remaining,voltage;
    LONG rate;DWORD temperature,seconds;UCHAR chemistry[4];
} PackReport;
typedef struct PackFound {struct PackFound *next;WCHAR *text;PackTarget *target;} PackFound;
static void *pack_alloc(SIZE_T bytes) {return HeapAlloc(GetProcessHeap(),HEAP_ZERO_MEMORY,bytes);}
static void pack_free(void *value) {if(value) HeapFree(GetProcessHeap(),0,value);}
static void pack_target_release(PackTarget *target) {if(target && !InterlockedDecrement(&target->references)) pack_free(target);}
EXPORT void readout_pack_free(void *value) {pack_free(value);}
static DWORD pack_last_error(void) {DWORD value=GetLastError();return value?value:ERROR_GEN_FAILURE;}
static BOOL pack_removed(DWORD error) {return error==ERROR_FILE_NOT_FOUND || error==ERROR_NO_SUCH_DEVICE || error==ERROR_DEVICE_NOT_CONNECTED;}
static BOOL pack_equal(const WCHAR *left,const WCHAR *right) {return CompareStringOrdinal(left,-1,right,-1,TRUE)==CSTR_EQUAL;}
static int pack_text_length(const WCHAR *text,DWORD units) {
    BOOL high=FALSE;
    for(DWORD i=0;i<units;i++) {
        WCHAR value=text[i];if(!value) return high || !i?-1:(int)i;
        if(value>=0xd800 && value<=0xdbff) {if(high) return -1;high=TRUE;}
        else if(value>=0xdc00 && value<=0xdfff) {if(!high) return -1;high=FALSE;}
        else if(high) return -1;
    }
    return -1;
}
static PackPath *pack_path(PackContext *owner,const WCHAR *text) {
    for(PackPath *p=owner->paths;p;p=p->next) if(pack_equal(p->text,text)) return p;
    SIZE_T bytes=(wcslen(text)+1)*sizeof(WCHAR);PackPath *p=pack_alloc(sizeof(*p));
    if(!p) return NULL;p->text=pack_alloc(bytes);if(!p->text) {pack_free(p);return NULL;}
    memcpy(p->text,text,bytes);p->next=owner->paths;owner->paths=p;return p;
}
static void pack_retire(PackContext *owner,PackPath *path,ULONG except_tag) {
    for(PackTarget *t=owner->targets;t;t=t->next) if(t->path==path && (!except_tag || t->tag!=except_tag)) InterlockedExchange(&t->retired,TRUE);
}
static DWORD pack_health(PackContext *owner) {return owner->closed?ERROR_DEVICE_NOT_CONNECTED:owner->failure;}
static DWORD CALLBACK pack_notification(HCMNOTIFICATION registration,PVOID context,CM_NOTIFY_ACTION action,PCM_NOTIFY_EVENT_DATA data,DWORD size) {
    (void)registration;PackContext *owner=context;
    if(action!=CM_NOTIFY_ACTION_DEVICEINTERFACEARRIVAL && action!=CM_NOTIFY_ACTION_DEVICEINTERFACEREMOVAL) return ERROR_SUCCESS;
    AcquireSRWLockExclusive(&owner->lock);
    if(owner->closed) {ReleaseSRWLockExclusive(&owner->lock);return ERROR_SUCCESS;}
    DWORD offset=(DWORD)offsetof(CM_NOTIFY_EVENT_DATA,u.DeviceInterface.SymbolicLink);
    if(!data || size<offset+4 || size>offset+65536 || (size&1) || data->FilterType!=CM_NOTIFY_FILTER_TYPE_DEVICEINTERFACE || data->Reserved) owner->failure=ERROR_INVALID_DATA;
    else if(!memcmp(&data->u.DeviceInterface.ClassGuid,&pack_class,sizeof(GUID))) {
        const WCHAR *text=data->u.DeviceInterface.SymbolicLink;
        if(pack_text_length(text,(size-offset)/2)<0) owner->failure=ERROR_INVALID_DATA;
        else {
            PackPath *path=pack_path(owner,text);
            if(!path) owner->failure=ERROR_NOT_ENOUGH_MEMORY;
            else if(action==CM_NOTIFY_ACTION_DEVICEINTERFACEREMOVAL) {
                if(path->version==UINT64_MAX) owner->failure=ERROR_ARITHMETIC_OVERFLOW;
                else ++path->version;
                path->absent=TRUE;pack_retire(owner,path,0);
            } else path->absent=FALSE;
        }
    }
    /* Record the removal synchronously before posting an invalidation. This
       remains effective while the Dart collection isolate is in native I/O. */
    if(owner->dispatch) owner->dispatch((void*)(uintptr_t)owner->token,(void*)1,0);
    ReleaseSRWLockExclusive(&owner->lock);return ERROR_SUCCESS;
}
static DWORD pack_release_resource(PackContext *owner,PackResource *resource) {
    BOOL done=resource->inventory?owner->destroy((HDEVINFO)resource->handle):owner->close(resource->handle);
    if(!done) return pack_last_error();
    PackResource **link=&owner->resources;while(*link && *link!=resource) link=&(*link)->next;
    if(*link) *link=resource->next;pack_free(resource);return 0;
}
static DWORD pack_cleanup(PackContext *owner) {
    DWORD error=0;PackResource *r=owner->resources;
    while(r) {PackResource *next=r->next;DWORD status=pack_release_resource(owner,r);if(!error) error=status;r=next;}
    return error;
}
static void pack_destroy_context(PackContext *owner) {
    while(owner->targets) {PackTarget *t=owner->targets;owner->targets=t->next;pack_target_release(t);}
    while(owner->paths) {PackPath *p=owner->paths;owner->paths=p->next;pack_free(p->text);pack_free(p);}
    pack_free(owner);
}
EXPORT DWORD readout_pack_context_close(PackContext *owner) {
    if(!owner) return ERROR_INVALID_PARAMETER;
    AcquireSRWLockExclusive(&owner->lock);owner->closed=TRUE;owner->dispatch=NULL;ReleaseSRWLockExclusive(&owner->lock);
    if(owner->registration) {
        CONFIGRET status=owner->unsubscribe(owner->registration);
        if(status!=CR_SUCCESS) return CM_MapCrToWin32Err(status,ERROR_GEN_FAILURE);
        owner->registration=NULL;
    }
    DWORD error=pack_cleanup(owner);if(error) return error;
    pack_destroy_context(owner);return 0;
}
EXPORT PackContextResult readout_pack_context_create(HMODULE module,PackDispatch dispatch,UINT64 token) {
    PackContextResult result={ERROR_NOT_ENOUGH_MEMORY,NULL};PackContext *owner=pack_alloc(sizeof(*owner));if(!owner) return result;
    owner->dispatch=dispatch;owner->token=token;owner->module=module;result.error=ERROR_PROC_NOT_FOUND;
#define LOAD(field,type,name,native) owner->field=module?(type)GetProcAddress(module,name):native;if(!owner->field) goto failed
    LOAD(class_devs,PackClassDevs,"readout_pack_class_devs",SetupDiGetClassDevsW);
    LOAD(enumerate,PackEnum,"readout_pack_enum",SetupDiEnumDeviceInterfaces);
    LOAD(detail,PackDetail,"readout_pack_detail",SetupDiGetDeviceInterfaceDetailW);
    LOAD(destroy,PackDestroy,"readout_pack_destroy",SetupDiDestroyDeviceInfoList);
    LOAD(open,PackOpen,"readout_pack_open",CreateFileW);LOAD(ioctl,PackIoctl,"readout_pack_ioctl",DeviceIoControl);
    LOAD(close,PackClose,"readout_pack_close",CloseHandle);LOAD(subscribe,PackRegister,"readout_pack_register",CM_Register_Notification);
    LOAD(unsubscribe,PackUnregister,"readout_pack_unregister",CM_Unregister_Notification);
#undef LOAD
    if(!dispatch || !token || token>UINTPTR_MAX) {result.error=ERROR_INVALID_PARAMETER;goto failed;}
    CM_NOTIFY_FILTER filter={0};filter.cbSize=sizeof(filter);filter.FilterType=CM_NOTIFY_FILTER_TYPE_DEVICEINTERFACE;filter.u.DeviceInterface.ClassGuid=pack_class;
    CONFIGRET status=owner->subscribe(&filter,owner,pack_notification,&owner->registration);
    result.error=status==CR_SUCCESS?0:CM_MapCrToWin32Err(status,ERROR_GEN_FAILURE);
    if(!result.error && !owner->registration) result.error=ERROR_INVALID_DATA;
    if(!result.error) {result.owner=owner;return result;}
failed:
    if(owner->registration) {
        if(readout_pack_context_close(owner)) result.owner=owner;
    } else pack_destroy_context(owner);
    return result;
}
static PackResource *pack_resource(PackContext *owner,BOOL inventory) {
    PackResource *resource=pack_alloc(sizeof(*resource));if(!resource) return NULL;
    resource->inventory=inventory;resource->next=owner->resources;owner->resources=resource;return resource;
}
static DWORD pack_open(PackContext *owner,const WCHAR *path,PackResource **output) {
    PackResource *r=pack_resource(owner,FALSE);if(!r) return ERROR_NOT_ENOUGH_MEMORY;
    r->handle=owner->open(path,GENERIC_READ,FILE_SHARE_READ|FILE_SHARE_WRITE,NULL,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,NULL);
    if(r->handle==INVALID_HANDLE_VALUE || !r->handle) {DWORD error=pack_last_error();owner->resources=r->next;pack_free(r);return error;}
    *output=r;return 0;
}
static DWORD pack_query(PackContext *owner,PackResource *resource,DWORD code,void *input,DWORD input_size,void *output,DWORD output_size) {
    DWORD written=0;if(!owner->ioctl(resource->handle,code,input,input_size,output,output_size,&written,NULL)) return pack_last_error();
    return written==output_size?0:ERROR_INVALID_DATA;
}
static DWORD pack_tag(PackContext *owner,PackResource *resource,ULONG *tag) {
    ULONG wait=0;return pack_query(owner,resource,IOCTL_BATTERY_QUERY_TAG,&wait,sizeof(wait),tag,sizeof(*tag));
}
static DWORD pack_enumerate(PackContext *owner,PackFound **found) {
    PackResource *resource=pack_resource(owner,TRUE);if(!resource) return ERROR_NOT_ENOUGH_MEMORY;
    resource->handle=owner->class_devs(&pack_class,NULL,NULL,DIGCF_PRESENT|DIGCF_DEVICEINTERFACE);
    if(resource->handle==INVALID_HANDLE_VALUE || !resource->handle) {DWORD error=pack_last_error();owner->resources=resource->next;pack_free(resource);return error;}
    DWORD error=0;PackFound **tail=found;
    for(DWORD i=0;;i++) {
        SP_DEVICE_INTERFACE_DATA data={0};data.cbSize=sizeof(data);
        if(!owner->enumerate(resource->handle,NULL,&pack_class,i,&data)) {error=pack_last_error();if(error==ERROR_NO_MORE_ITEMS) error=0;break;}
        if(i>=4096) {error=ERROR_NOT_ENOUGH_MEMORY;break;}
        DWORD required=0;
        BOOL sized=owner->detail(resource->handle,&data,NULL,0,&required,NULL);error=sized?ERROR_INVALID_DATA:pack_last_error();
        if(error!=ERROR_INSUFFICIENT_BUFFER) break;
        if(required<6 || required>65536 || (required&1)) {error=ERROR_INVALID_DATA;break;}
        SP_DEVICE_INTERFACE_DETAIL_DATA_W *detail=pack_alloc(required);
        if(!detail) {error=ERROR_NOT_ENOUGH_MEMORY;break;}detail->cbSize=sizeof(*detail);
        DWORD actual=0;
        if(!owner->detail(resource->handle,&data,detail,required,&actual,NULL)) {error=pack_last_error();pack_free(detail);break;}
        int length=actual>=6 && actual<=required?pack_text_length(detail->DevicePath,(actual-4)/2):-1;
        if(length<0) {error=ERROR_INVALID_DATA;pack_free(detail);break;}
        BOOL duplicate=FALSE;for(PackFound *p=*found;p;p=p->next) if(pack_equal(p->text,detail->DevicePath)) duplicate=TRUE;
        if(!duplicate) {
            PackFound *entry=pack_alloc(sizeof(*entry));
            if(entry) entry->text=pack_alloc(((SIZE_T)length+1)*sizeof(WCHAR));
            if(!entry || !entry->text) {pack_free(entry);pack_free(detail);error=ERROR_NOT_ENOUGH_MEMORY;break;}
            memcpy(entry->text,detail->DevicePath,((SIZE_T)length+1)*sizeof(WCHAR));*tail=entry;tail=&entry->next;
        }
        pack_free(detail);error=0;
    }
    DWORD cleanup=pack_release_resource(owner,resource);return error?error:cleanup;
}
EXPORT PackInventory readout_pack_inventory(PackContext *owner) {
    PackInventory result={0};PackFound *found=NULL;
    AcquireSRWLockShared(&owner->lock);result.error=pack_health(owner);ReleaseSRWLockShared(&owner->lock);
    if(result.error) return result;
    result.error=pack_cleanup(owner);if(result.error) return result;
    result.error=pack_enumerate(owner,&found);if(result.error) goto done;
    AcquireSRWLockExclusive(&owner->lock);
    /* Only a completed enumeration proves absent paths. Later query failures
       cannot revive these retired targets or earlier removal notifications. */
    for(PackPath *p=owner->paths;p;p=p->next) {
        BOOL present=FALSE;for(PackFound *f=found;f;f=f->next) if(pack_equal(p->text,f->text)) present=TRUE;
        if(!present) pack_retire(owner,p,0);
    }
    ReleaseSRWLockExclusive(&owner->lock);
    for(PackFound *f=found;f;f=f->next) {
        AcquireSRWLockExclusive(&owner->lock);
        PackPath *path=pack_path(owner,f->text);UINT64 version=path?path->version:0;BOOL absent=path?path->absent:TRUE;
        ReleaseSRWLockExclusive(&owner->lock);
        if(!path) {result.error=ERROR_NOT_ENOUGH_MEMORY;goto done;}if(absent) continue;
        PackResource *resource=NULL;ULONG tag=0;DWORD error=pack_open(owner,f->text,&resource);
        if(!error) {
            error=pack_tag(owner,resource,&tag);
            if(!error) {
                /* A known tag change remains authoritative even if closing
                   this read-only handle subsequently fails. */
                AcquireSRWLockExclusive(&owner->lock);pack_retire(owner,path,tag);ReleaseSRWLockExclusive(&owner->lock);
            }
            DWORD cleanup=pack_release_resource(owner,resource);if(!error) error=cleanup;
        }
        AcquireSRWLockExclusive(&owner->lock);
        if(pack_removed(error)) {pack_retire(owner,path,0);error=0;tag=0;}
        if(!error) {
            if(tag && path->version==version && !path->absent) {
                PackTarget *target=NULL;
                for(PackTarget *t=owner->targets;t;t=t->next) if(t->path==path && t->tag==tag && t->version==version && !t->retired) {target=t;break;}
                if(!target) {
                    target=pack_alloc(sizeof(*target));
                    if(!target || owner->sequence==UINT64_MAX) {pack_free(target);target=NULL;error=ERROR_NOT_ENOUGH_MEMORY;}
                    else {target->references=1;target->id=++owner->sequence;target->tag=tag;target->version=version;target->path=path;target->next=owner->targets;owner->targets=target;}
                }
                f->target=target;
            }
        }
        ReleaseSRWLockExclusive(&owner->lock);
        if(error) {result.error=error;goto done;}
    }
    AcquireSRWLockShared(&owner->lock);result.error=pack_health(owner);
    if(!result.error) {
        for(PackFound *f=found;f;f=f->next) if(f->target && !f->target->retired) result.count++;
        if(result.count) result.ids=pack_alloc(result.count*sizeof(UINT64));
        if(result.count && !result.ids) {result.error=ERROR_NOT_ENOUGH_MEMORY;result.count=0;}
        else {DWORD index=0;for(PackFound *f=found;f;f=f->next) if(f->target && !f->target->retired) result.ids[index++]=f->target->id;}
    }
    ReleaseSRWLockShared(&owner->lock);
done:
    while(found) {PackFound *next=found->next;pack_free(found->text);pack_free(found);found=next;}
    return result;
}
static DWORD pack_check(PackContext *owner,PackTarget *target) {
    DWORD error=pack_health(owner);if(error) return error;
    return !target || target->retired || target->path->absent || target->version!=target->path->version?ERROR_DEVICE_NOT_CONNECTED:0;
}
static PackReport pack_report(PackContext *owner,UINT64 id,const BATTERY_STATUS *captured) {
    PackReport result={0};PackTarget *target=NULL;PackResource *resource=NULL;
    AcquireSRWLockShared(&owner->lock);
    for(PackTarget *t=owner->targets;t;t=t->next) if(t->id==id) {target=t;break;}
    result.error=pack_check(owner,target);ReleaseSRWLockShared(&owner->lock);if(result.error) return result;
    result.error=pack_cleanup(owner);if(result.error) return result;
    result.error=pack_open(owner,target->path->text,&resource);if(result.error) goto done;
    ULONG tag=0;result.error=pack_tag(owner,resource,&tag);if(result.error) goto done;
    if(tag!=target->tag) {result.error=ERROR_DEVICE_NOT_CONNECTED;goto done;}
    BATTERY_QUERY_INFORMATION request={0};request.BatteryTag=tag;
    BATTERY_INFORMATION information={0};BATTERY_STATUS status={0};BATTERY_WAIT_STATUS wait={0};wait.BatteryTag=tag;
    DWORD errors[4];errors[0]=pack_query(owner,resource,IOCTL_BATTERY_QUERY_INFORMATION,&request,sizeof(request),&information,sizeof(information));
    if(!errors[0]) {result.mask|=1;result.capabilities=information.Capabilities;result.design=information.DesignedCapacity;result.full=information.FullChargedCapacity;result.cycles=information.CycleCount;memcpy(result.chemistry,information.Chemistry,4);}
    if(captured) {status=*captured;errors[1]=0;}
    else errors[1]=pack_query(owner,resource,IOCTL_BATTERY_QUERY_STATUS,&wait,sizeof(wait),&status,sizeof(status));
    if(!errors[1]) {result.mask|=2;result.flags=status.PowerState;result.remaining=status.Capacity;result.voltage=status.Voltage;result.rate=status.Rate;}
    request.InformationLevel=BatteryTemperature;errors[2]=pack_query(owner,resource,IOCTL_BATTERY_QUERY_INFORMATION,&request,sizeof(request),&result.temperature,sizeof(result.temperature));
    if(!errors[2]) result.mask|=4;
    request.InformationLevel=BatteryEstimatedTime;errors[3]=pack_query(owner,resource,IOCTL_BATTERY_QUERY_INFORMATION,&request,sizeof(request),&result.seconds,sizeof(result.seconds));
    if(!errors[3]) result.mask|=8;
    for(unsigned i=0;i<4;i++) if(pack_removed(errors[i])) {result.error=errors[i];goto done;}
    if(!result.mask) {result.error=ERROR_GEN_FAILURE;for(unsigned i=0;i<4;i++) if(errors[i]==ERROR_ACCESS_DENIED) result.error=ERROR_ACCESS_DENIED;goto done;}
    result.error=pack_tag(owner,resource,&tag);if(!result.error && tag!=target->tag) result.error=ERROR_DEVICE_NOT_CONNECTED;
done:
    if(resource) {DWORD cleanup=pack_release_resource(owner,resource);if(!result.error) result.error=cleanup;}
    AcquireSRWLockExclusive(&owner->lock);
    if(pack_removed(result.error)) InterlockedExchange(&target->retired,TRUE);
    if(!result.error) result.error=pack_check(owner,target);
    ReleaseSRWLockExclusive(&owner->lock);return result;
}
EXPORT PackReport readout_pack_report(PackContext *owner,UINT64 id) {return pack_report(owner,id,NULL);}
EXPORT PackReport readout_pack_report_status(PackContext *owner,UINT64 id,DWORD flags,DWORD capacity,DWORD voltage,LONG rate) {
    BATTERY_STATUS status={flags,capacity,voltage,rate};return pack_report(owner,id,&status);
}

/* Status waits own a separate lane and a copy of the path. Context disposal
   does not join driver completion or leave a thread pointing into freed paths. */
typedef BOOL (WINAPI *PackComplete)(HANDLE,LPOVERLAPPED,LPDWORD,BOOL);
typedef BOOL (WINAPI *PackCancel)(HANDLE,LPOVERLAPPED);
typedef struct {DWORD kind,error,flags,remaining,voltage;LONG rate;} PackStatusValue;
typedef struct {
    SRWLOCK lock;volatile LONG references;HANDLE stop,completed,device;HMODULE module;
    PackTarget *target;WCHAR *path;ULONG tag;PackOpen open;PackClose close;PackIoctl ioctl;
    PackComplete complete;PackCancel cancel;PackDispatch dispatch;UINT64 token;
    PackStatusValue queue[128];DWORD first,count,failure;
} PackStatusWatch;
typedef struct {DWORD error;PackStatusWatch *owner;} PackStatusResult;
static void pack_status_release(PackStatusWatch *watch) {
    if(InterlockedDecrement(&watch->references)) return;
    /* A failed close retains the allocation and module rather than unloading
       code or pretending that the native resource was released. */
    if(watch->device) return;
    if(watch->completed) CloseHandle(watch->completed);
    if(watch->stop) CloseHandle(watch->stop);
    if(watch->module) FreeLibrary(watch->module);
    pack_target_release(watch->target);pack_free(watch->path);pack_free(watch);
}
static void pack_status_publish(PackStatusWatch *watch,DWORD error,const BATTERY_STATUS *status) {
    if(pack_removed(error)) InterlockedExchange(&watch->target->retired,TRUE);
    AcquireSRWLockExclusive(&watch->lock);
    if(WaitForSingleObject(watch->stop,0)!=WAIT_OBJECT_0) {
        if(watch->count==128) {watch->failure=ERROR_NOT_ENOUGH_MEMORY;SetEvent(watch->stop);}
        else {
            PackStatusValue *value=&watch->queue[(watch->first+watch->count++)%128];
            value->kind=error?2:1;value->error=error;
            if(status) {value->flags=status->PowerState;value->remaining=status->Capacity;value->voltage=status->Voltage;value->rate=status->Rate;}
        }
        watch->dispatch((void*)(uintptr_t)watch->token,(void*)1,0);
    }
    ReleaseSRWLockExclusive(&watch->lock);
}
static DWORD WINAPI pack_status_thread(void *argument) {
    PackStatusWatch *watch=argument;DWORD error=0;
    if(WaitForSingleObject(watch->stop,0)==WAIT_OBJECT_0) goto done;
    watch->device=watch->open(watch->path,GENERIC_READ,FILE_SHARE_READ|FILE_SHARE_WRITE,NULL,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL|FILE_FLAG_OVERLAPPED,NULL);
    if(!watch->device || watch->device==INVALID_HANDLE_VALUE) {error=pack_last_error();watch->device=NULL;goto done;}
    BATTERY_WAIT_STATUS request={0};request.BatteryTag=watch->tag;
    while(WaitForSingleObject(watch->stop,0)!=WAIT_OBJECT_0) {
        if(watch->target->retired) {error=ERROR_DEVICE_NOT_CONNECTED;break;}
        OVERLAPPED overlapped={0};overlapped.hEvent=watch->completed;ResetEvent(watch->completed);
        BATTERY_STATUS status={0};DWORD written=0;
        BOOL success=watch->ioctl(watch->device,IOCTL_BATTERY_QUERY_STATUS,&request,sizeof(request),&status,sizeof(status),&written,&overlapped);
        error=success?0:pack_last_error();
        if(error==ERROR_IO_PENDING) {
            HANDLE waits[]={watch->stop,watch->completed};DWORD waited=WaitForMultipleObjects(2,waits,FALSE,INFINITE);
            if(waited!=WAIT_OBJECT_0+1) watch->cancel(watch->device,&overlapped);
            /* Even after cancellation the driver owns both buffers until
               completion. Only this dedicated thread may wait for that. */
            success=watch->complete(watch->device,&overlapped,&written,TRUE);
            error=success?0:pack_last_error();
        }
        if(WaitForSingleObject(watch->stop,0)==WAIT_OBJECT_0) break;
        if(error) break;
        if(written!=sizeof(status)) {error=ERROR_INVALID_DATA;break;}
        pack_status_publish(watch,0,&status);
        request.Timeout=INFINITE;request.PowerState=status.PowerState;
        request.LowCapacity=status.Capacity==BATTERY_UNKNOWN_CAPACITY?0:status.Capacity;request.HighCapacity=status.Capacity;
    }
done:
    if(error && error!=ERROR_INVALID_FUNCTION && error!=ERROR_NOT_SUPPORTED) pack_status_publish(watch,error,NULL);
    if(watch->device) {
        if(watch->close(watch->device)) watch->device=NULL;
        else pack_status_publish(watch,pack_last_error(),NULL);
    }
    pack_status_release(watch);return 0;
}
EXPORT PackStatusResult readout_pack_status_create(PackContext *owner,UINT64 id,PackDispatch dispatch,UINT64 token) {
    PackStatusResult result={ERROR_NOT_ENOUGH_MEMORY,NULL};PackStatusWatch *watch=pack_alloc(sizeof(*watch));if(!watch) return result;
    watch->references=1;watch->dispatch=dispatch;watch->token=token;watch->open=owner->open;watch->close=owner->close;watch->ioctl=owner->ioctl;
    AcquireSRWLockShared(&owner->lock);PackTarget *target=NULL;
    for(PackTarget *t=owner->targets;t;t=t->next) if(t->id==id) {target=t;break;}
    result.error=pack_check(owner,target);
    if(!result.error) {
        SIZE_T bytes=(wcslen(target->path->text)+1)*sizeof(WCHAR);watch->path=pack_alloc(bytes);
        if(!watch->path) result.error=ERROR_NOT_ENOUGH_MEMORY;
        else {memcpy(watch->path,target->path->text,bytes);watch->tag=target->tag;watch->target=target;InterlockedIncrement(&target->references);}
    }
    ReleaseSRWLockShared(&owner->lock);if(result.error) goto failed;
    if(!dispatch || !token || token>UINTPTR_MAX) {result.error=ERROR_INVALID_PARAMETER;goto failed;}
    watch->complete=owner->module?(PackComplete)GetProcAddress(owner->module,"readout_pack_status_complete"):GetOverlappedResult;
    watch->cancel=owner->module?(PackCancel)GetProcAddress(owner->module,"readout_pack_status_cancel"):CancelIoEx;
    if(!watch->complete || !watch->cancel) {result.error=ERROR_PROC_NOT_FOUND;goto failed;}
    if(!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS,(LPCWSTR)(uintptr_t)watch->open,&watch->module)) {result.error=pack_last_error();goto failed;}
    watch->stop=CreateEventW(NULL,TRUE,FALSE,NULL);if(!watch->stop) {result.error=pack_last_error();goto failed;}
    watch->completed=CreateEventW(NULL,TRUE,FALSE,NULL);if(!watch->completed) {result.error=pack_last_error();goto failed;}
    InterlockedIncrement(&watch->references);HANDLE thread=CreateThread(NULL,0,pack_status_thread,watch,0,NULL);
    if(!thread) {result.error=pack_last_error();InterlockedDecrement(&watch->references);goto failed;}
    CloseHandle(thread);result.error=0;result.owner=watch;return result;
failed:
    pack_status_release(watch);return result;
}
EXPORT PackStatusValue readout_pack_status_take(PackStatusWatch *watch) {
    PackStatusValue result={0};AcquireSRWLockExclusive(&watch->lock);
    if(watch->failure) {result.kind=2;result.error=watch->failure;watch->failure=0;}
    else if(watch->count) {result=watch->queue[watch->first];watch->first=(watch->first+1)%128;--watch->count;}
    ReleaseSRWLockExclusive(&watch->lock);return result;
}
EXPORT void readout_pack_status_close(PackStatusWatch *watch) {if(watch) {SetEvent(watch->stop);pack_status_release(watch);}}
