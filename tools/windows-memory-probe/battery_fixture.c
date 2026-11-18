#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <objbase.h>
#include <stdint.h>
#pragma comment(lib, "ole32.lib")

/* Controlled native ABI; never opens battery devices or changes machine state. */
typedef struct { void **table; LONG references; INT32 value; } BatteryObject;
typedef ULONG (WINAPI *BatteryReference)(void *);
typedef HRESULT (WINAPI *BatteryInvoke)(void *,void *,void *);
static volatile LONG objects,registrations,active,removals,callbacks,threads,bad_apartment;
static volatile LONG mode,released=1,held,worker;
static SRWLOCK handler_lock=SRWLOCK_INIT;
static void *handlers[128];
static LONG current_mode(void) {return InterlockedCompareExchange(&mode,0,0);}
static void hold(LONG expected) {
    if(current_mode()!=expected) return;
    InterlockedExchange(&worker,GetCurrentThreadId());InterlockedIncrement(&held);
    ULONGLONG start=GetTickCount64();
    while(!InterlockedCompareExchange(&released,0,0) && GetTickCount64()-start<6000) Sleep(1);
    InterlockedDecrement(&held);
}
static void apartment(void) {
    APTTYPE type;APTTYPEQUALIFIER qualifier;
    if(FAILED(CoGetApartmentType(&type,&qualifier)) || type!=APTTYPE_MTA) InterlockedIncrement(&bad_apartment);
}
static ULONG WINAPI add(BatteryObject *self) { return InterlockedIncrement(&self->references); }
static ULONG WINAPI drop(BatteryObject *self) {
    apartment();LONG count=InterlockedDecrement(&self->references);
    if(!count) {HeapFree(GetProcessHeap(),0,self);InterlockedDecrement(&objects);}return count;
}
static HRESULT make(void **table,INT32 value,void **output) {
    BatteryObject *object=HeapAlloc(GetProcessHeap(),HEAP_ZERO_MEMORY,sizeof(*object));
    if(!object) return E_OUTOFMEMORY;
    object->table=table;object->references=1;object->value=value;*output=object;InterlockedIncrement(&objects);return S_OK;
}
static HRESULT WINAPI value(BatteryObject *self,INT32 *output) {
    apartment();hold(51);*output=self->value;
    return current_mode()==6 && self->value==-5000?E_FAIL:S_OK;
}
static void *box_table[7]={NULL,add,drop,NULL,NULL,NULL,value};
static HRESULT field(unsigned index,INT32 amount,void **output) {
    apartment();LONG m=current_mode();*output=NULL;if(m==4) return S_OK;
    if(m==3 || (m==17 && index==3) || (m==20 && index==0)) amount=0;
    if(m==16 && index>0) amount=-1;
    if(m==19 && index==0) amount=5000;
    if(m==20 && index==3) amount=50000;
    HRESULT hr=make(box_table,amount,output);
    return SUCCEEDED(hr) && (m==7 || (m==5 && index==0))?E_ACCESSDENIED:hr;
}
static HRESULT WINAPI rate(void *self,void **output) {(void)self;return field(0,-5000,output);}
static HRESULT WINAPI design(void *self,void **output) {(void)self;return field(1,60000,output);}
static HRESULT WINAPI full(void *self,void **output) {(void)self;return field(2,50000,output);}
static HRESULT WINAPI remaining(void *self,void **output) {(void)self;return field(3,20000,output);}
static HRESULT WINAPI state(void *self,INT32 *output) {
    (void)self;apartment();LONG m=current_mode();*output=m==1?0:m==2?99:m==4 || m==20?2:m==19?3:1;
    return m==7?E_ACCESSDENIED:S_OK;
}
static void *report_table[11]={NULL,add,drop,NULL,NULL,NULL,rate,design,full,remaining,state};
static HRESULT WINAPI report(void *self,void **output) {
    (void)self;apartment();hold(50);*output=NULL;LONG m=current_mode();if(m==9) return S_OK;
    HRESULT hr=make(report_table,0,output);return SUCCEEDED(hr) && (m==8 || m==18)?(m==18?E_ACCESSDENIED:E_FAIL):hr;
}
static HRESULT WINAPI subscribe(void *self,void *handler,INT64 *token) {
    (void)self;apartment();hold(52);if(current_mode()==30) return E_NOTIMPL;if(current_mode()==31) return E_ACCESSDENIED;
    AcquireSRWLockExclusive(&handler_lock);LONG index=registrations;
    if(index>=128) {ReleaseSRWLockExclusive(&handler_lock);return E_OUTOFMEMORY;}
    ((BatteryReference)(*(void ***)handler)[1])(handler);handlers[index]=handler;*token=index+1;
    InterlockedIncrement(&registrations);InterlockedIncrement(&active);ReleaseSRWLockExclusive(&handler_lock);return S_OK;
}
static HRESULT WINAPI unsubscribe(void *self,INT64 token) {
    (void)self;apartment();hold(53);InterlockedIncrement(&removals);if(current_mode()==32) return E_ACCESSDENIED;
    AcquireSRWLockExclusive(&handler_lock);
    void *handler=token>0 && token<=128?handlers[token-1]:NULL;
    if(handler) {handlers[token-1]=NULL;InterlockedDecrement(&active);}
    ReleaseSRWLockExclusive(&handler_lock);if(!handler) return E_INVALIDARG;
    ((BatteryReference)(*(void ***)handler)[2])(handler);return S_OK;
}
static void *battery_table[10]={NULL,add,drop,NULL,NULL,NULL,NULL,report,subscribe,unsubscribe};
static HRESULT WINAPI aggregate(void *self,void **output) {(void)self;apartment();return make(battery_table,0,output);}
static void *factory_table[7]={NULL,add,drop,NULL,NULL,NULL,aggregate};
__declspec(dllexport) HRESULT WINAPI readout_battery_activate(void **output) {
    apartment();hold(54);HRESULT hr=make(factory_table,0,output);return SUCCEEDED(hr) && current_mode()==10?REGDB_E_CLASSNOTREG:hr;
}
__declspec(dllexport) BOOL WINAPI readout_battery_power_status(SYSTEM_POWER_STATUS *output) {
    apartment();ZeroMemory(output,sizeof(*output));LONG m=current_mode();output->BatteryFlag=1;output->BatteryLifeTime=7200;
    output->BatteryFullLifeTime=12000;
    if(m==11) {SetLastError(ERROR_ACCESS_DENIED);return FALSE;}
    if(m==12) output->ACLineStatus=1;
    if(m==13) output->BatteryFlag=128;
    if(m==14) output->BatteryLifeTime=UINT32_MAX;
    if(m==3) output->BatteryLifeTime=0;
    if(m==15) {output->BatteryFlag=255;output->ACLineStatus=255;}
    return TRUE;
}
__declspec(dllexport) void readout_battery_configure(LONG value) {
    InterlockedExchange(&mode,value);InterlockedExchange(&released,value>=50 && value<=54?0:1);
}
__declspec(dllexport) void readout_battery_release(void) {InterlockedExchange(&released,1);}
__declspec(dllexport) ULONG readout_battery_counter(ULONG field) {
    if(field==7) return GetCurrentThreadId();
    if(field==8) return InterlockedCompareExchange(&held,0,0);
    if(field==9) return InterlockedCompareExchange(&worker,0,0);
    volatile LONG *p=field==0?&objects:field==1?&registrations:field==2?&active:field==3?&removals:
        field==4?&callbacks:field==5?&threads:&bad_apartment;
    return InterlockedCompareExchange(p,0,0);
}
static DWORD WINAPI emit(void *unused) {
    (void)unused;AcquireSRWLockShared(&handler_lock);
    for(LONG i=0;i<registrations;i++) if(handlers[i]) {
        ((BatteryInvoke)(*(void ***)handlers[i])[3])(handlers[i],NULL,NULL);InterlockedIncrement(&callbacks);
    }
    ReleaseSRWLockShared(&handler_lock);InterlockedDecrement(&threads);return 0;
}
__declspec(dllexport) DWORD readout_battery_emit(void) {
    InterlockedIncrement(&threads);HANDLE worker=CreateThread(NULL,0,emit,NULL,0,NULL);
    if(!worker) {InterlockedDecrement(&threads);return GetLastError();}CloseHandle(worker);return 0;
}
