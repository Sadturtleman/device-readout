// Test-only interposition at public Darwin APIs, loaded into a separate consumer.
#include <errno.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/sysctl.h>
#include <sys/utsname.h>
#include <unistd.h>

static pthread_mutex_t trace_lock = PTHREAD_MUTEX_INITIALIZER;

static void record(const char *event) {
    const char *path = getenv("DEVICE_READOUT_OS_TRACE");
    if (path == NULL) { abort(); }
    pthread_mutex_lock(&trace_lock);
    FILE *file = fopen(path, "a");
    if (file == NULL) { abort(); }
    fprintf(file, "%s main=%d\n", event, pthread_main_np());
    if (fclose(file) != 0) { abort(); }
    pthread_mutex_unlock(&trace_lock);
}

static int unavailable(void) {
    const char *mode = getenv("DEVICE_READOUT_OS_MODE");
    return mode != NULL && strcmp(mode, "unavailable") == 0;
}

static int fixture_sysctl(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (strcmp(name, "kern.osversion") == 0 && newp == NULL && newlen == 0) {
        if (unavailable()) {
            record("sysctl-unavailable");
            errno = EPERM;
            return -1;
        }
        const char *gate = getenv("DEVICE_READOUT_OS_GATE");
        if (gate != NULL && oldp == NULL) {
            record("sysctl-held");
            unsigned attempts = 0;
            while (access(gate, F_OK) != 0 && attempts++ < 500) { usleep(10000); }
            if (access(gate, F_OK) != 0) { record("gate-timeout"); abort(); }
            record("sysctl-released");
        }
    }
    return sysctlbyname(name, oldp, oldlenp, newp, newlen);
}

static int fixture_uname(struct utsname *value) {
    if (unavailable()) { record("uname-unavailable"); errno = EIO; return -1; }
    return uname(value);
}

__attribute__((used)) static const struct { const void *replacement; const void *original; }
    interpose[] __attribute__((section("__DATA,__interpose"))) = {
        { (const void *)(uintptr_t)&fixture_sysctl, (const void *)(uintptr_t)&sysctlbyname },
        { (const void *)(uintptr_t)&fixture_uname, (const void *)(uintptr_t)&uname }
    };
