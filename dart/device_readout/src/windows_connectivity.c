#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <roapi.h>
#include <stdint.h>
#pragma comment(lib, "runtimeobject.lib")
#pragma comment(lib, "ole32.lib")

/* WinRT ABI calls stay inside one synchronous native invocation: Dart isolate
   work may resume on a different OS thread after an asynchronous boundary. */
typedef HRESULT (WINAPI *ReadoutActivate)(void **);
typedef HRESULT (WINAPI *GetInterface)(void *, void **);
typedef HRESULT (WINAPI *GetInteger)(void *, INT32 *);
typedef ULONG (WINAPI *ReleaseInterface)(void *);
static void *method(void *instance, unsigned slot) { return (*(void ***)instance)[slot]; }
static void release_interface(void *instance) {
    if (instance) ((ReleaseInterface)method(instance, 2))(instance);
}
static HRESULT activate_network(void **factory) {
    static const WCHAR name[] = L"Windows.Networking.Connectivity.NetworkInformation";
    static const IID iid = {0x5074f851,0x950d,0x4165,{0x9c,0x15,0x36,0x56,0x19,0x48,0x1e,0xea}};
    HSTRING text = NULL;
    HRESULT hr = WindowsCreateString(name, ARRAYSIZE(name) - 1, &text);
    if (SUCCEEDED(hr)) hr = RoGetActivationFactory(text, &iid, factory);
    WindowsDeleteString(text);
    return hr;
}

typedef struct {
    INT32 status, has_profile, level_status, level, cost_status, cost;
} ReadoutConnectivityResult;

__declspec(dllexport) ReadoutConnectivityResult readout_connectivity_read(ReadoutActivate activate) {
    ReadoutConnectivityResult result = {0,0,E_FAIL,0,E_FAIL,0};
    void *factory = NULL, *profile = NULL, *cost = NULL;
    HRESULT initialized = RoInitialize(RO_INIT_MULTITHREADED);
    result.status = initialized;
    if (FAILED(initialized)) return result;
    result.status = (activate ? activate : activate_network)(&factory);
    if (FAILED(result.status)) goto done;
    if (!factory) { result.status = E_NOINTERFACE; goto done; }
    result.status = ((GetInterface)method(factory, 7))(factory, &profile);
    if (FAILED(result.status) || !profile) goto done;
    result.has_profile = 1;
    result.level_status = ((GetInteger)method(profile, 7))(profile, &result.level);
    result.cost_status = ((GetInterface)method(profile, 9))(profile, &cost);
    if (SUCCEEDED(result.cost_status) && cost)
        result.cost_status = ((GetInteger)method(cost, 6))(cost, &result.cost);
    if (FAILED(result.level_status) && FAILED(result.cost_status))
        result.status = result.cost_status == E_ACCESSDENIED ? result.cost_status : result.level_status;
done:
    release_interface(cost); release_interface(profile); release_interface(factory);
    RoUninitialize();
    return result;
}

typedef struct {
    INT32 status, present, inbound_status, outbound_status;
    double inbound, outbound;
} ReadoutPerformanceResult;
typedef HRESULT (WINAPI *GetUInt64)(void *, UINT64 *);
static HRESULT read_rate(void *plan, unsigned slot, INT32 bit, ReadoutPerformanceResult *result, double *output) {
    void *reference = NULL; UINT64 value = 0;
    HRESULT hr = ((GetInterface)method(plan,slot))(plan,&reference);
    if (SUCCEEDED(hr) && reference) {
        hr = ((GetUInt64)method(reference,6))(reference,&value);
        if (SUCCEEDED(hr)) { *output = (double)value; result->present |= bit; }
    }
    release_interface(reference);
    return hr;
}
__declspec(dllexport) ReadoutPerformanceResult readout_connectivity_performance(ReadoutActivate activate) {
    ReadoutPerformanceResult result = {0,0,E_FAIL,E_FAIL,0,0};
    void *factory = NULL, *profile = NULL, *plan = NULL;
    HRESULT initialized = RoInitialize(RO_INIT_MULTITHREADED);
    result.status = initialized; if (FAILED(initialized)) return result;
    result.status = (activate ? activate : activate_network)(&factory);
    if (FAILED(result.status)) goto done;
    if (!factory) { result.status=E_NOINTERFACE; goto done; }
    result.status=((GetInterface)method(factory,7))(factory,&profile);
    if (FAILED(result.status) || !profile) goto done;
    result.status=((GetInterface)method(profile,10))(profile,&plan);
    if (FAILED(result.status) || !plan) goto done;
    result.inbound_status=read_rate(plan,8,1,&result,&result.inbound);
    result.outbound_status=read_rate(plan,9,2,&result,&result.outbound);
    if (FAILED(result.inbound_status) && FAILED(result.outbound_status))
        result.status=result.outbound_status==E_ACCESSDENIED ? result.outbound_status : result.inbound_status;
done:
    release_interface(plan); release_interface(profile); release_interface(factory);
    RoUninitialize(); return result;
}

typedef void (WINAPI *ReadoutDispatch)(void *, void *, ULONG);
typedef struct { void **table; LONG references; ReadoutDispatch dispatch; uint64_t token; } Handler;
static ULONG WINAPI handler_add(Handler *self) { return InterlockedIncrement(&self->references); }
static ULONG WINAPI handler_release(Handler *self) {
    LONG count = InterlockedDecrement(&self->references);
    if (!count) HeapFree(GetProcessHeap(),0,self);
    return count;
}
static HRESULT WINAPI handler_query(Handler *self, REFIID iid, void **output) {
    static const IID handler = {0x71ba143f,0x598e,0x49d0,{0x84,0xeb,0x8f,0xeb,0xae,0xdc,0xc1,0x95}};
    static const IID unknown = {0,0,0,{0xc0,0,0,0,0,0,0,0x46}};
    static const IID agile = {0x94ea2b94,0xe9cc,0x49e0,{0xc0,0xff,0xee,0x64,0xca,0x8f,0x5b,0x90}};
    if (!output) return E_POINTER;
    *output = NULL;
    if (memcmp(iid,&handler,sizeof(IID)) && memcmp(iid,&unknown,sizeof(IID)) && memcmp(iid,&agile,sizeof(IID))) return E_NOINTERFACE;
    handler_add(self); *output=self; return S_OK;
}
static HRESULT WINAPI handler_invoke(Handler *self, void *sender) {
    (void)sender;
    /* Only an invalidation token crosses the async boundary, never sender.
       The shared bridge owns callback admission and bounded pending messages. */
    self->dispatch((void *)(uintptr_t)self->token,(void *)1,0);
    return S_OK;
}
static void *handler_table[] = {handler_query,handler_add,handler_release,handler_invoke};
typedef struct {
    void *factory; Handler *handler; INT64 event_token; CO_MTA_USAGE_COOKIE mta;
} Observation;
typedef struct { INT32 status; Observation *owner; } ReadoutConnectivitySubscription;
typedef struct { INT32 status; CO_MTA_USAGE_COOKIE cookie; } ReadoutConnectivityContext;
typedef HRESULT (WINAPI *AddEvent)(void *, void *, INT64 *);
typedef HRESULT (WINAPI *RemoveEvent)(void *, INT64);

__declspec(dllexport) ReadoutConnectivityContext readout_connectivity_context_create(void) {
    ReadoutConnectivityContext result = {E_FAIL,NULL};
    result.status=CoIncrementMTAUsage(&result.cookie);
    return result;
}
__declspec(dllexport) INT32 readout_connectivity_context_close(CO_MTA_USAGE_COOKIE cookie) {
    return CoDecrementMTAUsage(cookie);
}

__declspec(dllexport) ReadoutConnectivitySubscription readout_connectivity_subscribe(
    ReadoutActivate activate, ReadoutDispatch dispatch, uint64_t token) {
    ReadoutConnectivitySubscription result = {E_INVALIDARG,NULL};
    if (!dispatch || !token || token > UINTPTR_MAX) return result;
    HRESULT initialized = RoInitialize(RO_INIT_MULTITHREADED);
    result.status=initialized; if (FAILED(initialized)) return result;
    Observation *owner=HeapAlloc(GetProcessHeap(),HEAP_ZERO_MEMORY,sizeof(*owner));
    if (!owner) { result.status=E_OUTOFMEMORY; goto done; }
    /* Retain the MTA independently of Dart's migrating worker thread. Every
       COM call still has balanced same-thread RoInitialize/RoUninitialize. */
    result.status=CoIncrementMTAUsage(&owner->mta);
    if (FAILED(result.status)) goto failed;
    result.status=(activate ? activate : activate_network)(&owner->factory);
    if (FAILED(result.status)) goto failed;
    if (!owner->factory) { result.status=E_NOINTERFACE; goto failed; }
    owner->handler=HeapAlloc(GetProcessHeap(),HEAP_ZERO_MEMORY,sizeof(Handler));
    if (!owner->handler) { result.status=E_OUTOFMEMORY; goto failed; }
    owner->handler->table=handler_table; owner->handler->references=1;
    owner->handler->dispatch=dispatch; owner->handler->token=token;
    result.status=((AddEvent)method(owner->factory,12))(owner->factory,owner->handler,&owner->event_token);
    if (FAILED(result.status)) goto failed;
    result.owner=owner; goto done;
failed:
    if (owner->handler) handler_release(owner->handler);
    release_interface(owner->factory);
    if (owner->mta) CoDecrementMTAUsage(owner->mta);
    HeapFree(GetProcessHeap(),0,owner);
done:
    RoUninitialize(); return result;
}

__declspec(dllexport) INT32 readout_connectivity_unsubscribe(Observation *owner) {
    if (!owner) return E_INVALIDARG;
    HRESULT initialized=RoInitialize(RO_INIT_MULTITHREADED);
    if (FAILED(initialized)) return initialized;
    HRESULT result=((RemoveEvent)method(owner->factory,13))(owner->factory,owner->event_token);
    /* A failed removal retains every native owner for a later explicit retry.
       The Dart-side token is already detached, so late callbacks are harmless. */
    if (SUCCEEDED(result)) {
        handler_release(owner->handler); release_interface(owner->factory);
        CoDecrementMTAUsage(owner->mta); HeapFree(GetProcessHeap(),0,owner);
    }
    RoUninitialize(); return result;
}
