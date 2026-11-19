// Test-only interposition of public Darwin reads in a separate consumer process.
#include <errno.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/sysctl.h>
#include <unistd.h>

static pthread_mutex_t trace_lock = PTHREAD_MUTEX_INITIALIZER;

static int scenario(const char *expected) {
    const char *actual = getenv("DEVICE_READOUT_CPU_CASE");
    return actual != NULL && strcmp(actual, expected) == 0;
}

static void record(const char *event) {
    const char *path = getenv("DEVICE_READOUT_CPU_TRACE");
    if (path == NULL) { abort(); }
    pthread_mutex_lock(&trace_lock);
    FILE *file = fopen(path, "a");
    if (file == NULL) { abort(); }
    fprintf(file, "%s main=%d\n", event, pthread_main_np());
    if (fclose(file) != 0) { abort(); }
    pthread_mutex_unlock(&trace_lock);
}

static int fixture_sysctl(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    const int physical = strcmp(name, "hw.physicalcpu_max") == 0;
    const int packages = strcmp(name, "hw.packages") == 0;
    if ((!physical && !packages) || newp != NULL || newlen != 0) {
        return sysctlbyname(name, oldp, oldlenp, newp, newlen);
    }
    record(physical ? "physical-read" : "package-read");
    if (physical && (scenario("held-get") || scenario("held-watch"))) {
        const char *gate = getenv("DEVICE_READOUT_CPU_GATE");
        if (gate == NULL) { abort(); }
        record("cpu-held");
        unsigned attempts = 0;
        while (access(gate, F_OK) != 0 && attempts++ < 500) { usleep(10000); }
        if (access(gate, F_OK) != 0) { record("gate-timeout"); abort(); }
        record("cpu-released");
    }
    if ((physical && scenario("physical-failure")) || (packages && scenario("package-failure"))) {
        errno = EIO;
        return -1;
    }
    if (oldlenp == NULL) { errno = EFAULT; return -1; }
    const int32_t value = scenario("zero") ? 0 : scenario("negative") ? -1 : physical ? 2 : 1;
    if (oldp == NULL) { *oldlenp = sizeof(value); return 0; }
    if (*oldlenp < sizeof(value)) { errno = ENOMEM; return -1; }
    memcpy(oldp, &value, sizeof(value));
    // Malformed reported lengths never write outside the caller's actual buffer.
    *oldlenp = scenario("short-response") ? 2 : scenario("oversized-response") ? 8 : sizeof(value);
    return 0;
}

__attribute__((used)) static const struct { const void *replacement; const void *original; }
    interpose[] __attribute__((section("__DATA,__interpose"))) = {
        { (const void *)(uintptr_t)&fixture_sysctl, (const void *)(uintptr_t)&sysctlbyname }
    };
