#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <roapi.h>
#include <winstring.h>
#include <stdint.h>
#pragma comment(lib, "runtimeobject.lib")

typedef HRESULT (WINAPI *BatteryActivate)(void **);
typedef HRESULT (WINAPI *BatteryGetObject)(void *, void **);
typedef HRESULT (WINAPI *BatteryGetInt32)(void *, INT32 *);
typedef ULONG (WINAPI *BatteryRelease)(void *);
typedef BOOL (WINAPI *BatteryPowerStatus)(SYSTEM_POWER_STATUS *);
static void *battery_method(void *object, unsigned index) { return (*(void ***)object)[index]; }
static void battery_drop(void *object) { if(object) ((BatteryRelease)battery_method(object,2))(object); }
static HRESULT battery_activate(void **output) {
    static const WCHAR name[]=L"Windows.Devices.Power.Battery";
    static const IID iid={0x79cd72b6,0x9e5e,0x4452,{0xbe,0xa6,0xdf,0xcd,0x54,0x1e,0x59,0x7f}};
    HSTRING text=NULL; HRESULT hr=WindowsCreateString(name,(UINT32)(sizeof(name)/sizeof(WCHAR)-1),&text);
    if(SUCCEEDED(hr)) hr=RoGetActivationFactory(text,&iid,output);
    if(text) WindowsDeleteString(text);
    return hr;
}
static HRESULT aggregate_battery(HMODULE module,void **output) {
    BatteryActivate activate=module?(BatteryActivate)GetProcAddress(module,"readout_battery_activate"):battery_activate;
    if(!activate) return E_NOINTERFACE;
    void *factory=NULL;HRESULT hr=activate(&factory);
    if(SUCCEEDED(hr)) hr=factory?((BatteryGetObject)battery_method(factory,6))(factory,output):E_FAIL;
    battery_drop(factory);
    if(SUCCEEDED(hr) && !*output) hr=E_FAIL;
    return hr;
}
__declspec(dllexport) INT32 readout_battery_available(HMODULE module) {
    HRESULT hr=RoInitialize(RO_INIT_MULTITHREADED);if(FAILED(hr)) return hr;
    void *battery=NULL;hr=aggregate_battery(module,&battery);battery_drop(battery);
    RoUninitialize();
    return hr==REGDB_E_CLASSNOTREG || hr==E_NOINTERFACE?S_FALSE:hr;
}

typedef struct {
    INT32 status;UINT32 mask;INT32 rate,design,full,remaining,state;UINT32 time_to_empty;
} ReadoutBatteryReport;

static HRESULT battery_boxed(void *report,unsigned index,INT32 *value,BOOL *present) {
    void *reference=NULL;HRESULT hr=((BatteryGetObject)battery_method(report,index))(report,&reference);
    *present=FALSE;
    if(SUCCEEDED(hr) && reference) {
        hr=((BatteryGetInt32)battery_method(reference,6))(reference,value);
        *present=SUCCEEDED(hr);
    }
    battery_drop(reference);return hr;
}
__declspec(dllexport) ReadoutBatteryReport readout_battery_aggregate(HMODULE module) {
    ReadoutBatteryReport result={0};void *battery=NULL,*report=NULL;
    HRESULT hr=RoInitialize(RO_INIT_MULTITHREADED);result.status=hr;if(FAILED(hr)) return result;
    hr=aggregate_battery(module,&battery);if(FAILED(hr)) goto done;
    hr=((BatteryGetObject)battery_method(battery,7))(battery,&report);if(FAILED(hr)) goto done;
    if(!report) {hr=E_FAIL;goto done;}
    INT32 *fields[]={&result.rate,&result.design,&result.full,&result.remaining};
    unsigned successes=0;BOOL denied=FALSE;
    for(unsigned i=0;i<4;i++) {
        BOOL present=FALSE;HRESULT status=battery_boxed(report,i+6,fields[i],&present);
        if(SUCCEEDED(status)) {successes++;if(present) result.mask|=1u<<i;}
        else if(status==E_ACCESSDENIED) denied=TRUE;
    }
    hr=((BatteryGetInt32)battery_method(report,10))(report,&result.state);
    if(SUCCEEDED(hr)) {result.mask|=16;successes++;} else if(hr==E_ACCESSDENIED) denied=TRUE;
    if(!successes) {hr=denied?E_ACCESSDENIED:E_FAIL;goto done;}
    hr=S_OK;
    BatteryPowerStatus power=module?(BatteryPowerStatus)GetProcAddress(module,"readout_battery_power_status"):GetSystemPowerStatus;
    SYSTEM_POWER_STATUS value={0};
    if(power && power(&value) && value.ACLineStatus!=1 &&
        !(value.BatteryFlag!=255 && (value.BatteryFlag&128)) && value.BatteryLifeTime!=UINT32_MAX) {
        result.mask|=32;result.time_to_empty=value.BatteryLifeTime;
    }
done:
    result.status=hr;battery_drop(report);battery_drop(battery);RoUninitialize();return result;
}

typedef void (WINAPI *BatteryDispatch)(void *,void *,ULONG);
typedef struct {void **table;LONG references;BatteryDispatch dispatch;UINT64 token;} BatteryHandler;
static ULONG WINAPI battery_handler_add(BatteryHandler *self) {return InterlockedIncrement(&self->references);}
static ULONG WINAPI battery_handler_drop(BatteryHandler *self) {
    LONG count=InterlockedDecrement(&self->references);if(!count) HeapFree(GetProcessHeap(),0,self);return count;
}
static HRESULT WINAPI battery_handler_query(BatteryHandler *self,REFIID iid,void **output) {
    static const IID handler={0x4d4aa646,0x767f,0x5645,{0xaf,0x5c,0x54,0x64,0x64,0xd3,0xec,0x09}};
    static const IID unknown={0,0,0,{0xc0,0,0,0,0,0,0,0x46}};
    static const IID agile={0x94ea2b94,0xe9cc,0x49e0,{0xc0,0xff,0xee,0x64,0xca,0x8f,0x5b,0x90}};
    if(!output) return E_POINTER;*output=NULL;
    if(memcmp(iid,&handler,sizeof(IID)) && memcmp(iid,&unknown,sizeof(IID)) && memcmp(iid,&agile,sizeof(IID))) return E_NOINTERFACE;
    battery_handler_add(self);*output=self;return S_OK;
}
static HRESULT WINAPI battery_handler_invoke(BatteryHandler *self,void *sender,void *args) {
    (void)sender;(void)args;
    /* Only a bounded invalidation token crosses to Dart; native event arguments
       are never retained by the asynchronous listener. */
    self->dispatch((void *)(uintptr_t)self->token,(void *)1,0);return S_OK;
}
static void *battery_handler_table[]={battery_handler_query,battery_handler_add,battery_handler_drop,battery_handler_invoke};
typedef struct {void *battery;BatteryHandler *handler;INT64 event_token;CO_MTA_USAGE_COOKIE mta;} BatteryObservation;
typedef struct {INT32 status;BatteryObservation *owner;} ReadoutBatteryObservation;
typedef HRESULT (WINAPI *BatteryAddEvent)(void *,void *,INT64 *);
typedef HRESULT (WINAPI *BatteryRemoveEvent)(void *,INT64);
__declspec(dllexport) ReadoutBatteryObservation readout_battery_subscribe(HMODULE module,BatteryDispatch dispatch,UINT64 token) {
    ReadoutBatteryObservation result={E_INVALIDARG,NULL};
    if(!dispatch || !token || token>UINTPTR_MAX) return result;
    HRESULT initialized=RoInitialize(RO_INIT_MULTITHREADED);result.status=initialized;if(FAILED(initialized)) return result;
    BatteryObservation *owner=HeapAlloc(GetProcessHeap(),HEAP_ZERO_MEMORY,sizeof(*owner));
    if(!owner) {result.status=E_OUTOFMEMORY;goto done;}
    result.status=CoIncrementMTAUsage(&owner->mta);if(FAILED(result.status)) goto failed;
    result.status=aggregate_battery(module,&owner->battery);if(FAILED(result.status)) goto failed;
    owner->handler=HeapAlloc(GetProcessHeap(),HEAP_ZERO_MEMORY,sizeof(*owner->handler));
    if(!owner->handler) {result.status=E_OUTOFMEMORY;goto failed;}
    owner->handler->table=battery_handler_table;owner->handler->references=1;
    owner->handler->dispatch=dispatch;owner->handler->token=token;
    result.status=((BatteryAddEvent)battery_method(owner->battery,8))(owner->battery,owner->handler,&owner->event_token);
    if(FAILED(result.status)) goto failed;
    result.owner=owner;goto done;
failed:
    if(owner->handler) battery_handler_drop(owner->handler);battery_drop(owner->battery);
    if(owner->mta) CoDecrementMTAUsage(owner->mta);HeapFree(GetProcessHeap(),0,owner);
done:
    RoUninitialize();return result;
}
__declspec(dllexport) INT32 readout_battery_unsubscribe(BatteryObservation *owner) {
    if(!owner) return E_INVALIDARG;
    HRESULT initialized=RoInitialize(RO_INIT_MULTITHREADED);if(FAILED(initialized)) return initialized;
    HRESULT hr=((BatteryRemoveEvent)battery_method(owner->battery,9))(owner->battery,owner->event_token);
    /* Failed removal retains the battery, handler and MTA for an explicit retry.
       The caller has already detached its token, so late native calls are inert. */
    if(SUCCEEDED(hr)) {
        battery_handler_drop(owner->handler);battery_drop(owner->battery);
        CoDecrementMTAUsage(owner->mta);HeapFree(GetProcessHeap(),0,owner);
    }
    RoUninitialize();return hr;
}
