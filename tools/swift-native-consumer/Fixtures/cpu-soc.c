// Test-only IOKit boundary, injected only into the child consumer.
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static const io_registry_entry_t fixture_entry = 0x44520001;
static pthread_mutex_t trace_lock = PTHREAD_MUTEX_INITIALIZER;
static int scenario(const char *expected) {
    const char *actual = getenv("DEVICE_READOUT_SOC_CASE");
    return actual != NULL && strcmp(actual, expected) == 0;
}
static void record(const char *event) {
    const char *path = getenv("DEVICE_READOUT_SOC_TRACE");
    if (path == NULL) { abort(); }
    pthread_mutex_lock(&trace_lock);
    FILE *file = fopen(path, "a");
    if (file == NULL) { abort(); }
    fprintf(file, "%s main=%d\n", event, pthread_main_np());
    if (fclose(file) != 0) { abort(); }
    pthread_mutex_unlock(&trace_lock);
}
static void hold(const char *stage) {
    const char *actual = getenv("DEVICE_READOUT_SOC_CASE");
    if (actual == NULL || strncmp(actual, stage, strlen(stage)) != 0) { return; }
    const char *gate = getenv("DEVICE_READOUT_SOC_GATE");
    if (gate == NULL) { abort(); }
    record("soc-held");
    unsigned attempts = 0;
    while (access(gate, F_OK) != 0 && attempts++ < 500) { usleep(10000); }
    if (access(gate, F_OK) != 0) { record("gate-timeout"); abort(); }
    record("soc-resumed");
}
static io_registry_entry_t fixture_from_path(mach_port_t port, const io_string_t path) {
    if (strcmp(path, "IODeviceTree:/product") != 0) { return IORegistryEntryFromPath(port, path); }
    record("entry-lookup");
    hold("held-lookup");
    if (scenario("missing-entry")) { return MACH_PORT_NULL; }
    record("entry-acquired");
    return fixture_entry;
}
static CFTypeRef fixture_property(io_registry_entry_t entry, CFStringRef key, CFAllocatorRef allocator, IOOptionBits options) {
    if (entry != fixture_entry) { return IORegistryEntryCreateCFProperty(entry, key, allocator, options); }
    if (!CFEqual(key, CFSTR("product-soc-name")) || options != 0) { abort(); }
    record("property-read");
    hold("held-property");
    if (scenario("missing-property")) { return NULL; }
    if (scenario("wrong-type")) {
        const int value = 42;
        return CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &value);
    }
    if (scenario("empty-data")) { return CFDataCreate(kCFAllocatorDefault, NULL, 0); }
    if (scenario("invalid-utf8")) {
        const UInt8 bytes[] = {0xc3, 0x28, 0};
        return CFDataCreate(kCFAllocatorDefault, bytes, sizeof(bytes));
    }
    if (scenario("limit") || scenario("oversized")) {
        UInt8 bytes[4097];
        const size_t size = scenario("limit") ? 4096 : 4097;
        memset(bytes, 'S', size);
        bytes[size - 1] = 0;
        return CFDataCreate(kCFAllocatorDefault, bytes, (CFIndex)size);
    }
    const char *value = scenario("unicode") ? "SoC-Δ-가" : scenario("empty-string") ? "" : "Fixture SoC";
    const size_t count = strlen(value) + (scenario("missing-nul") ? 0 : 1);
    return CFDataCreate(kCFAllocatorDefault, (const UInt8 *)value, (CFIndex)count);
}
static kern_return_t fixture_release(io_object_t object) {
    if (object != fixture_entry) { return IOObjectRelease(object); }
    record("entry-release-start");
    hold("held-release");
    record("entry-released");
    return KERN_SUCCESS;
}
__attribute__((used)) static const struct { const void *replacement; const void *original; }
    interpose[] __attribute__((section("__DATA,__interpose"))) = {
        { (const void *)(uintptr_t)&fixture_from_path, (const void *)(uintptr_t)&IORegistryEntryFromPath },
        { (const void *)(uintptr_t)&fixture_property, (const void *)(uintptr_t)&IORegistryEntryCreateCFProperty },
        { (const void *)(uintptr_t)&fixture_release, (const void *)(uintptr_t)&IOObjectRelease }
    };
