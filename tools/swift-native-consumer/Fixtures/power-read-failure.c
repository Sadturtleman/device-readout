// Test-only failure at the public IOKit boundary; no SDK test hook is involved.
#include <IOKit/ps/IOPowerSources.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static pthread_mutex_t trace_lock = PTHREAD_MUTEX_INITIALIZER;

static void record(const char *event) {
    const char *path = getenv("DEVICE_READOUT_POWER_READ_TRACE");
    if (path == NULL) { fputs("Missing power read trace path\n", stderr); abort(); }
    pthread_mutex_lock(&trace_lock);
    FILE *file = fopen(path, "a");
    if (file == NULL) { fputs("Cannot open power read trace\n", stderr); abort(); }
    fprintf(file, "%s main=%d\n", event, pthread_main_np());
    if (fclose(file) != 0) { fputs("Cannot close power read trace\n", stderr); abort(); }
    pthread_mutex_unlock(&trace_lock);
}

__attribute__((constructor)) static void loaded(void) { record("fixture-loaded"); }

static CFTypeRef fixture_copy_info(void) {
    record("source-info-unavailable");
    return NULL;
}

__attribute__((used)) static const struct { const void *replacement; const void *original; }
    interpose_copy_info __attribute__((section("__DATA,__interpose"))) = {
        (const void *)(uintptr_t)&fixture_copy_info,
        (const void *)(uintptr_t)&IOPSCopyPowerSourcesInfo
    };
