// Test-only dynamic interposition at the public Darwin notification boundary.
// The SDK receives one real token; its first cancellation is deliberately refused.
#include <notify.h>
#include <IOKit/ps/IOPowerSources.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static atomic_int watched_token = -1;
static atomic_int cancellation_attempts = 0;
static pthread_mutex_t trace_lock = PTHREAD_MUTEX_INITIALIZER;

static void record(const char *event) {
    const char *path = getenv("DEVICE_READOUT_POWER_TRACE");
    if (path == NULL) { fputs("Missing power fixture trace path\n", stderr); abort(); }
    pthread_mutex_lock(&trace_lock);
    FILE *file = fopen(path, "a");
    if (file == NULL) { fputs("Cannot open power fixture trace\n", stderr); abort(); }
    fprintf(file, "%s main=%d\n", event, pthread_main_np());
    if (fclose(file) != 0) { fputs("Cannot close power fixture trace\n", stderr); abort(); }
    pthread_mutex_unlock(&trace_lock);
}

__attribute__((constructor)) static void loaded(void) { record("fixture-loaded"); }

static uint32_t fixture_register(const char *name, int *token, dispatch_queue_t queue, notify_handler_t handler) {
    // dyld preserves original bindings inside the interposing image. Dynamic
    // dlsym call-through crashed both the native-only and Swift consumer probes.
    uint32_t status = notify_register_dispatch(name, token, queue, handler);
    if (name != NULL && strcmp(name, kIOPSNotifyPowerSource) == 0 && status == NOTIFY_STATUS_OK) {
        atomic_store(&watched_token, *token);
        record("registered");
    }
    return status;
}

static uint32_t fixture_cancel(int token) {
    if (token == atomic_load(&watched_token)) {
        if (atomic_fetch_add(&cancellation_attempts, 1) == 0) {
            record("cancel-refused");
            return NOTIFY_STATUS_FAILED;
        }
        const char *gate = getenv("DEVICE_READOUT_POWER_RETRY_GATE");
        if (gate != NULL) {
            record("retry-entered");
            const struct timespec delay = { .tv_sec = 0, .tv_nsec = 10000000 };
            int remaining = 500;
            while (access(gate, F_OK) != 0 && remaining-- > 0) { nanosleep(&delay, NULL); }
            if (access(gate, F_OK) != 0) {
                record("retry-wait-expired");
                return NOTIFY_STATUS_FAILED;
            }
            record("retry-released");
        }
        uint32_t status = notify_cancel(token);
        record(status == NOTIFY_STATUS_OK || status == NOTIFY_STATUS_INVALID_TOKEN ? "cancelled" : "cancel-retry-refused");
        return status;
    }
    return notify_cancel(token);
}

#define INTERPOSE(replacement, original) \
    __attribute__((used)) static const struct { const void *replacement; const void *original; } \
    interpose_##original __attribute__((section("__DATA,__interpose"))) = { \
        (const void *)(uintptr_t)&replacement, (const void *)(uintptr_t)&original \
    }
INTERPOSE(fixture_register, notify_register_dispatch);
INTERPOSE(fixture_cancel, notify_cancel);
