// Test-only public sysctl boundary, injected only into the child consumer.
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
    const char *actual = getenv("DEVICE_READOUT_IDENTITY_CASE");
    return actual != NULL && strcmp(actual, expected) == 0;
}
static void record(const char *event) {
    const char *path = getenv("DEVICE_READOUT_IDENTITY_TRACE");
    if (path == NULL) { abort(); }
    pthread_mutex_lock(&trace_lock);
    FILE *file = fopen(path, "a");
    if (file == NULL) { abort(); }
    fprintf(file, "%s main=%d\n", event, pthread_main_np());
    if (fclose(file) != 0) { abort(); }
    pthread_mutex_unlock(&trace_lock);
}
static int fixture_sysctl(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    const int model = strcmp(name, "machdep.cpu.brand_string") == 0;
    const int vendor = strcmp(name, "machdep.cpu.vendor") == 0;
    if ((!model && !vendor) || newp != NULL || newlen != 0) {
        return sysctlbyname(name, oldp, oldlenp, newp, newlen);
    }
    record(oldp == NULL ? (model ? "model-size" : "vendor-size") : (model ? "model-read" : "vendor-read"));
    if (oldlenp == NULL) { errno = EFAULT; return -1; }
    if ((model && scenario("model-failure")) || (vendor && scenario("vendor-failure"))) {
        errno = ENOENT; return -1;
    }
    const char *value = model ? "Fixture CPU" : "Fixture Vendor";
    if (scenario("unicode")) { value = model ? "CPU-Δ-가" : "Vendor-회사"; }
    if (scenario("shrink")) { value = model ? "CPU" : "Vendor"; }
    const size_t length = strlen(value) + 1;
    if (oldp == NULL) {
        *oldlenp = scenario("size-zero") ? 0 : scenario("size-one") ? 1 :
                   scenario("size-too-large") ? 4097 : scenario("size-overflow") ? SIZE_MAX :
                   scenario("limit") ? 4096 : 64;
        return 0;
    }
    if (model && (scenario("held-get") || scenario("held-watch"))) {
        const char *gate = getenv("DEVICE_READOUT_IDENTITY_GATE");
        if (gate == NULL) { abort(); }
        record("identity-held");
        unsigned attempts = 0;
        while (access(gate, F_OK) != 0 && attempts++ < 500) { usleep(10000); }
        if (access(gate, F_OK) != 0) { record("gate-timeout"); abort(); }
        record("identity-released");
    }
    if (scenario("read-failure")) { errno = EIO; return -1; }
    const size_t capacity = *oldlenp;
    if (capacity < length) { errno = ENOMEM; return -1; }
    if (scenario("limit")) {
        if (capacity != 4096) { abort(); }
        memset(oldp, model ? 'M' : 'V', capacity);
        ((unsigned char *)oldp)[capacity - 1] = 0;
    } else if (scenario("empty")) {
        ((unsigned char *)oldp)[0] = 0;
        *oldlenp = 1;
    } else if (scenario("missing-nul")) {
        memset(oldp, 'X', capacity);
    } else if (scenario("short-write")) {
        memcpy(oldp, "CPU", 3); // No NUL; unwritten bytes must not become a terminator.
    } else if (scenario("invalid-utf8")) {
        const unsigned char bytes[] = { 0xc3, 0x28, 0 };
        memcpy(oldp, bytes, sizeof(bytes));
        *oldlenp = sizeof(bytes);
    } else {
        memcpy(oldp, value, length);
        // A larger reported length never causes a write outside the actual buffer.
        *oldlenp = scenario("reported-growth") ? capacity + 1 : length;
    }
    return 0;
}
__attribute__((used)) static const struct { const void *replacement; const void *original; }
    interpose[] __attribute__((section("__DATA,__interpose"))) = {
        { (const void *)(uintptr_t)&fixture_sysctl, (const void *)(uintptr_t)&sysctlbyname }
    };
