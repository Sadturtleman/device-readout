// Temporary minimization of the test interposer crash; no SDK or Swift runtime.
#include <dispatch/dispatch.h>
#include <notify.h>
#include <IOKit/ps/IOPowerSources.h>
#include <stdio.h>

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    puts("[DEBUG-power-probe] before registration");
    int token = 0;
    uint32_t status = notify_register_dispatch(kIOPSNotifyPowerSource, &token,
        dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^(int received) { (void)received; });
    printf("[DEBUG-power-probe] registered status=%u token=%d\n", status, token);
    if (status != NOTIFY_STATUS_OK) return 1;
    uint32_t first = notify_cancel(token);
    printf("[DEBUG-power-probe] first cancellation=%u\n", first);
    uint32_t second = notify_cancel(token);
    printf("[DEBUG-power-probe] second cancellation=%u\n", second);
    return second == NOTIFY_STATUS_OK || second == NOTIFY_STATUS_INVALID_TOKEN ? 0 : 1;
}
