#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdint.h>

typedef void (*ReadoutNetworkListener)(uint64_t token, int32_t has_row, uint32_t type);
typedef struct ReadoutNetworkSlot {
    struct ReadoutNetworkSlot *next;
    uint64_t token;
    ReadoutNetworkListener listener;
    uint32_t pending;
    BOOL overflow;
} ReadoutNetworkSlot;
static SRWLOCK slots_lock = SRWLOCK_INIT;
static ReadoutNetworkSlot *slots;
static LONG64 sequence;
static uint32_t slot_count;

/* The context is a non-reused numeric token, never a dereferenced allocation.
   OS-owned row memory does not cross the asynchronous Dart callback boundary. */
static VOID WINAPI readout_network_dispatch(PVOID context, PVOID row, ULONG type) {
    uint64_t token = (uintptr_t)context;
    AcquireSRWLockExclusive(&slots_lock);
    for (ReadoutNetworkSlot *slot = slots; slot; slot = slot->next) {
        if (slot->token != token || slot->overflow) continue;
        if (slot->pending >= 2048) {
            slot->overflow = TRUE;
            slot->listener(token, 0, UINT32_MAX);
        } else {
            ++slot->pending;
            /* NativeCallable.listener only posts a message; it never waits for
               Dart collection. Detach cannot race the native invocation. */
            slot->listener(token, row != NULL, type);
        }
        break;
    }
    ReleaseSRWLockExclusive(&slots_lock);
}

__declspec(dllexport) uint64_t readout_network_callback_create(ReadoutNetworkListener listener) {
    HMODULE module;
    /* A failed OS unregister may leave a late call to the static trampoline.
       Keep that tiny native module resident; retired tokens are safe no-ops. */
    if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_PIN,
        (LPCWSTR)(uintptr_t)&readout_network_dispatch, &module)) return 0;
    ReadoutNetworkSlot *slot = HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, sizeof(*slot));
    if (!slot) return 0;
    LONG64 token = InterlockedIncrement64(&sequence);
    AcquireSRWLockExclusive(&slots_lock);
    if (token <= 0 || slot_count >= 4096) {
        ReleaseSRWLockExclusive(&slots_lock); HeapFree(GetProcessHeap(), 0, slot); return 0;
    }
    slot->token = (uint64_t)token; slot->listener = listener;
    slot->next = slots; slots = slot; ++slot_count;
    ReleaseSRWLockExclusive(&slots_lock);
    return slot->token;
}
__declspec(dllexport) PVOID readout_network_callback_function(void) { return (PVOID)&readout_network_dispatch; }
__declspec(dllexport) void readout_network_callback_ack(uint64_t token) {
    AcquireSRWLockExclusive(&slots_lock);
    for (ReadoutNetworkSlot *slot = slots; slot; slot = slot->next) {
        if (slot->token == token) { if (slot->pending) --slot->pending; break; }
    }
    ReleaseSRWLockExclusive(&slots_lock);
}
__declspec(dllexport) void readout_network_callback_remove(uint64_t token) {
    AcquireSRWLockExclusive(&slots_lock);
    ReadoutNetworkSlot **link = &slots;
    while (*link) {
        ReadoutNetworkSlot *slot = *link;
        if (slot->token == token) {
            *link = slot->next; --slot_count; HeapFree(GetProcessHeap(), 0, slot); break;
        }
        link = &slot->next;
    }
    ReleaseSRWLockExclusive(&slots_lock);
}
