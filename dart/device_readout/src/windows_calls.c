#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdint.h>

typedef struct ReadoutWin32Result {
    intptr_t value;
    uint32_t error;
} ReadoutWin32Result;

/* Capture the error before returning through the VM. No application, process,
   thread policy or device state is modified. Called only on the collector isolate. */
__declspec(dllexport) void readout_win32_call(int32_t kind, void *function,
    const uintptr_t *a, ReadoutWin32Result *result) {
    intptr_t value;
    switch (kind) {
        case 0:
            value = (intptr_t)((HANDLE (WINAPI *)(LPWSTR, DWORD))function)((LPWSTR)a[0], (DWORD)a[1]);
            break;
        case 1:
            value = ((BOOL (WINAPI *)(HANDLE, LPWSTR, DWORD))function)((HANDLE)a[0], (LPWSTR)a[1], (DWORD)a[2]);
            break;
        case 2:
            value = ((BOOL (WINAPI *)(LPCWSTR, PULARGE_INTEGER, PULARGE_INTEGER, PULARGE_INTEGER))function)(
                (LPCWSTR)a[0], (PULARGE_INTEGER)a[1], (PULARGE_INTEGER)a[2], (PULARGE_INTEGER)a[3]);
            break;
        case 3:
            value = (intptr_t)((HANDLE (WINAPI *)(LPCWSTR, DWORD, DWORD, LPSECURITY_ATTRIBUTES, DWORD, DWORD, HANDLE))function)(
                (LPCWSTR)a[0], (DWORD)a[1], (DWORD)a[2], (LPSECURITY_ATTRIBUTES)a[3], (DWORD)a[4], (DWORD)a[5], (HANDLE)a[6]);
            break;
        case 4:
            value = ((BOOL (WINAPI *)(HANDLE, LPWSTR, DWORD, LPDWORD, LPDWORD, LPDWORD, LPWSTR, DWORD))function)(
                (HANDLE)a[0], (LPWSTR)a[1], (DWORD)a[2], (LPDWORD)a[3], (LPDWORD)a[4], (LPDWORD)a[5], (LPWSTR)a[6], (DWORD)a[7]);
            break;
        case 5:
            value = ((BOOL (WINAPI *)(LOGICAL_PROCESSOR_RELATIONSHIP, PSYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX, PDWORD))function)(
                (LOGICAL_PROCESSOR_RELATIONSHIP)a[0], (PSYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX)a[1], (PDWORD)a[2]);
            break;
        case 6:
            value = ((BOOL (WINAPI *)(HANDLE, PDWORD_PTR, PDWORD_PTR))function)(
                (HANDLE)a[0], (PDWORD_PTR)a[1], (PDWORD_PTR)a[2]);
            break;
        case 7:
            value = ((BOOL (WINAPI *)(HANDLE, PULONG, ULONG, PULONG))function)(
                (HANDLE)a[0], (PULONG)a[1], (ULONG)a[2], (PULONG)a[3]);
            break;
        case 8:
            value = ((BOOL (WINAPI *)(PSYSTEM_CPU_SET_INFORMATION, ULONG, PULONG, HANDLE, ULONG))function)(
                (PSYSTEM_CPU_SET_INFORMATION)a[0], (ULONG)a[1], (PULONG)a[2], (HANDLE)a[3], (ULONG)a[4]);
            break;
        default:
            result->value = 0; result->error = ERROR_INVALID_PARAMETER; return;
    }
    DWORD error = GetLastError();
    result->value = value;
    result->error = error;
}
