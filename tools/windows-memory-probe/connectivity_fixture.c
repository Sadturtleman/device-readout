#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <objbase.h>
#include <stdint.h>
#pragma comment(lib, "ole32.lib")
/* Controlled WinRT ABI boundary. No machine network settings are changed. */
typedef struct { void **table; LONG references; UINT64 value; BOOL inbound; } Object;
typedef ULONG (WINAPI *Reference)(void *);
typedef HRESULT (WINAPI *Invoke)(void *, void *);
static volatile LONG objects, registrations, removals, active, callbacks, threads, bad_apartment;
static volatile LONG mode, released = 1, held, worker;
static void *handlers[128];
static SRWLOCK lock = SRWLOCK_INIT;
static LONG current_mode(void) { return InterlockedCompareExchange(&mode, 0, 0); }
static void hold(LONG value) {
    if (current_mode() != value) return;
    InterlockedExchange(&worker, GetCurrentThreadId()); InterlockedIncrement(&held);
    ULONGLONG start = GetTickCount64();
    while (!InterlockedCompareExchange(&released,0,0) && GetTickCount64()-start < 6000) Sleep(1);
    InterlockedDecrement(&held);
}
static void apartment(void) {
    APTTYPE type; APTTYPEQUALIFIER qualifier;
    if (FAILED(CoGetApartmentType(&type, &qualifier)) || type != APTTYPE_MTA) InterlockedIncrement(&bad_apartment);
}
static ULONG WINAPI add(Object *object) { return InterlockedIncrement(&object->references); }
static ULONG WINAPI release(Object *object) {
    apartment(); LONG count = InterlockedDecrement(&object->references);
    if (!count) { HeapFree(GetProcessHeap(),0,object); InterlockedDecrement(&objects); }
    return count;
}
static HRESULT make(void **table, void **output) {
    Object *object = HeapAlloc(GetProcessHeap(),HEAP_ZERO_MEMORY,sizeof(*object));
    if (!object) return E_OUTOFMEMORY;
    object->table = table; object->references = 1; *output = object;
    InterlockedIncrement(&objects); return S_OK;
}
static HRESULT WINAPI level(void *self, INT32 *output) {
    (void)self; apartment(); LONG m=current_mode();
    *output = m==2 ? 99 : m==9 ? 2 : m==10 ? 0 : m==11 ? 1 : 3;
    return m==3 || m==5 ? E_ACCESSDENIED : S_OK;
}
static HRESULT WINAPI cost_type(void *self, INT32 *output) {
    (void)self; apartment(); LONG m=current_mode();
    *output = m==2 ? 99 : m==9 ? 2 : m==10 ? 3 : 1; return S_OK;
}
static void *cost_table[7] = {NULL,add,release,NULL,NULL,NULL,cost_type};
static HRESULT WINAPI cost(void *self, void **output) {
    (void)self; apartment(); LONG m=current_mode(); *output=NULL;
    if (m==4 || m==5) return E_FAIL;
    return m==8 ? S_OK : make(cost_table,output);
}
static HRESULT WINAPI rate_value(Object *self, UINT64 *output) {
    apartment(); if (self->inbound) hold(52);
    *output=self->value;
    return (self->inbound && current_mode()==45) || (!self->inbound && current_mode()==54) ? E_FAIL : S_OK;
}
static void *rate_table[7] = {NULL,add,release,NULL,NULL,NULL,rate_value};
extern INT32 readout_fixture_box_uint64(UINT64 value, void **output);
static HRESULT rate_reference(BOOL inbound, void **output) {
    apartment(); if (inbound) hold(51);
    LONG m=current_mode(); *output=NULL;
    if (m==56) return readout_fixture_box_uint64(inbound ? 1000000007 : UINT64_MAX,output);
    if (m==43 || (m==53 && inbound)) return S_OK;
    HRESULT hr=make(rate_table,output); if(FAILED(hr)) return hr;
    Object *value=*output; value->inbound=inbound;
    value->value=m==48 ? (inbound ? UINT64_MAX : ((UINT64)1<<63)) : m==49 ? 0 :
        m==40 ? (inbound ? 250000000 : 50000000) : (inbound ? 25000000 : 5000000);
    if (inbound && (m==44 || m==47)) return E_FAIL;
    if (!inbound && (m==46 || m==47 || m==53)) return E_ACCESSDENIED;
    return S_OK;
}
static HRESULT WINAPI inbound(void *self, void **output) { (void)self; return rate_reference(TRUE,output); }
static HRESULT WINAPI outbound(void *self, void **output) { (void)self; return rate_reference(FALSE,output); }
static void *plan_table[10] = {NULL,add,release,NULL,NULL,NULL,NULL,NULL,inbound,outbound};
static HRESULT WINAPI plan(void *self, void **output) {
    (void)self; apartment(); hold(50); *output=NULL;
    if (current_mode()==41) return S_OK;
    HRESULT hr=make(plan_table,output);
    return current_mode()==42 && SUCCEEDED(hr) ? E_FAIL : hr;
}
static void *profile_table[11] = {NULL,add,release,NULL,NULL,NULL,NULL,level,NULL,cost,plan};
static HRESULT WINAPI profile(void *self, void **output) {
    (void)self; apartment(); hold(20); *output=NULL;
    LONG m=current_mode(); if(m==7) return E_FAIL;
    return m==1 ? S_OK : make(profile_table,output);
}
static HRESULT WINAPI subscribe(void *self, void *handler, INT64 *token) {
    (void)self; apartment(); hold(21);
    LONG m=current_mode(); if(m==30) return E_NOTIMPL; if(m==31) return E_ACCESSDENIED;
    AcquireSRWLockExclusive(&lock); LONG index=registrations;
    if(index>=128) { ReleaseSRWLockExclusive(&lock); return E_OUTOFMEMORY; }
    ((Reference)(*(void ***)handler)[1])(handler); handlers[index]=handler; *token=index+1;
    InterlockedIncrement(&registrations); InterlockedIncrement(&active);
    ReleaseSRWLockExclusive(&lock); return S_OK;
}
static HRESULT WINAPI unsubscribe(void *self, INT64 token) {
    (void)self; apartment(); hold(22); InterlockedIncrement(&removals);
    if(current_mode()==32) return E_ACCESSDENIED;
    AcquireSRWLockExclusive(&lock);
    void *handler=token>0 && token<=128 ? handlers[token-1] : NULL;
    if(handler) { handlers[token-1]=NULL; InterlockedDecrement(&active); }
    ReleaseSRWLockExclusive(&lock);
    if(!handler) return E_INVALIDARG;
    ((Reference)(*(void ***)handler)[2])(handler); return S_OK;
}
static void *factory_table[14] = {NULL,add,release,NULL,NULL,NULL,NULL,profile,NULL,NULL,NULL,NULL,subscribe,unsubscribe};
__declspec(dllexport) HRESULT WINAPI readout_connectivity_activate(void **output) {
    apartment(); *output=NULL; LONG m=current_mode();
    if(m==6) return REGDB_E_CLASSNOTREG; if(m==12) return S_OK;
    HRESULT hr=make(factory_table,output); return m==13 && SUCCEEDED(hr) ? E_FAIL : hr;
}
__declspec(dllexport) void readout_connectivity_configure(LONG value) {
    InterlockedExchange(&mode,value); InterlockedExchange(&released,(value>=20 && value<=22) || (value>=50 && value<=52) ? 0 : 1);
}
__declspec(dllexport) void readout_connectivity_release(void) { InterlockedExchange(&released,1); }
__declspec(dllexport) ULONG readout_connectivity_counter(ULONG field) {
    if(field==7) return GetCurrentThreadId();
    volatile LONG *p=field==0 ? &objects : field==1 ? &registrations : field==2 ? &active : field==3 ? &removals :
        field==4 ? &callbacks : field==5 ? &threads : field==6 ? &bad_apartment : field==8 ? &held : &worker;
    return InterlockedCompareExchange(p,0,0);
}
static DWORD WINAPI emit(void *unused) {
    (void)unused; AcquireSRWLockShared(&lock);
    for(LONG i=0;i<registrations;i++) if(handlers[i]) {
        ((Invoke)(*(void ***)handlers[i])[3])(handlers[i],NULL); InterlockedIncrement(&callbacks);
    }
    ReleaseSRWLockShared(&lock); InterlockedDecrement(&threads); return 0;
}
__declspec(dllexport) DWORD readout_connectivity_emit(void) {
    InterlockedIncrement(&threads); HANDLE thread=CreateThread(NULL,0,emit,NULL,0,NULL);
    if(!thread) { InterlockedDecrement(&threads); return GetLastError(); }
    CloseHandle(thread); return 0;
}
