// Public Mach boundary fixture, loaded only into the standalone consumer.
#include <mach/mach.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static pthread_mutex_t trace_lock = PTHREAD_MUTEX_INITIALIZER;

static int scenario(const char *expected) {
    const char *actual = getenv("DEVICE_READOUT_RAM_CASE");
    return actual != NULL && strcmp(actual, expected) == 0;
}

static void record(const char *event) {
    const char *path = getenv("DEVICE_READOUT_RAM_TRACE");
    if (path == NULL) { abort(); }
    pthread_mutex_lock(&trace_lock);
    FILE *file = fopen(path, "a");
    if (file == NULL) { abort(); }
    fprintf(file, "%s main=%d\n", event, pthread_main_np());
    if (fclose(file) != 0) { abort(); }
    pthread_mutex_unlock(&trace_lock);
}

static kern_return_t fixture_page_size(host_t host, vm_size_t *page_size) {
    (void)host;
    record("page-size");
    if (scenario("page-failure")) { return KERN_FAILURE; }
    *page_size = scenario("invalid-page") ? 0 : scenario("overflow") ? (vm_size_t)UINT64_MAX :
                 scenario("large-page") ? 16384 : 4096;
    return KERN_SUCCESS;
}

static kern_return_t fixture_statistics(host_t host, host_flavor_t flavor, host_info64_t info,
                                        mach_msg_type_number_t *count) {
    if (flavor != HOST_VM_INFO64) { return host_statistics64(host, flavor, info, count); }
    record("vm-statistics");
    if (scenario("statistics-failure")) { return KERN_FAILURE; }
    if (info == NULL || count == NULL || *count < HOST_VM_INFO64_COUNT) { return KERN_INVALID_ARGUMENT; }
    vm_statistics64_t value = (vm_statistics64_t)info;
    memset(value, 0, sizeof(*value));
    value->free_count = scenario("zero") ? 0 : scenario("overflow") ? 2 : 512;
    value->speculative_count = scenario("zero") ? 0 : 123; // Already included in free_count.
    *count = scenario("short-response") ? 0 : HOST_VM_INFO64_COUNT;
    return KERN_SUCCESS;
}

__attribute__((used)) static const struct { const void *replacement; const void *original; }
    interpose[] __attribute__((section("__DATA,__interpose"))) = {
        { (const void *)(uintptr_t)&fixture_page_size, (const void *)(uintptr_t)&host_page_size },
        { (const void *)(uintptr_t)&fixture_statistics, (const void *)(uintptr_t)&host_statistics64 }
    };
