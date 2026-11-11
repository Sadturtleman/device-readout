# Windows individual battery status observation — 2026-11-11

Individual Battery watches now observe driver status changes in addition to the existing polling, power-setting callbacks and interface-removal observation. The public get/watch API and snapshot fields are unchanged. All 49 .NET checks pass in sandbox and normal-user Windows runs. The full SDK goal remains incomplete.

## Native observation

Each individual watch opens a separate, read-only device handle with FILE_FLAG_OVERLAPPED. It uses [IOCTL_BATTERY_QUERY_STATUS](https://learn.microsoft.com/en-us/windows/win32/power/ioctl-battery-query-status) with the selected target's battery tag. No set-information request, device reconfiguration or permission prompt is used.

The first status request has a zero timeout. Subsequent requests use [BATTERY_WAIT_STATUS](https://learn.microsoft.com/en-us/windows/win32/power/battery-wait-status-str) to wait for a power-state difference or capacity outside the last reported value. Known capacity becomes both thresholds; unknown capacity disables the capacity condition with the full unsigned range. The wait has no idle deadline. It is independent of get's read timeout and the subscription's polling interval.

Returned state/capacity/voltage/rate values are copied before rearming. A deferred collection-worker read validates the target generation and reads the other available fields, while retaining those captured status values. Later device state therefore cannot replace a queued charging/discharging transition. Equal native reports and equal poll results remain visible. CollectedAt remains the snapshot completion time, not a claim that every native field was measured simultaneously.

Native status waits cover power state and capacity. They do not promise notifications for every voltage/rate/temperature change, so serial polling remains active at the configured interval. ERROR_INVALID_FUNCTION and ERROR_NOT_SUPPORTED stop the optional native status observer while polling continues. Other native errors keep the common error contract: access denial becomes PermissionDenied; invalid input/other read failures become ReadFailed.

## Lifetimes and isolation

The driver wait uses its own background thread, separate from the shared collection worker. Opening the observation handle, issuing I/O, waiting, requesting cancellation, retrieving completion and closing the handle all stay on that lane. Ordinary reads, snapshot normalization and timestamping retain the common collection worker. Construction is inert; native observation begins when watch is consumed.

Each request owns unmanaged input/output storage, a zeroed [OVERLAPPED](https://learn.microsoft.com/en-us/windows/win32/api/minwinbase/ns-minwinbase-overlapped) structure and a manual-reset completion event. Managed arrays are not exposed to a driver after a P/Invoke returns. Cancellation signals the observation lane; it calls [CancelIoEx](https://learn.microsoft.com/en-us/windows/win32/api/ioapiset/nf-ioapiset-cancelioex) for that exact request and then retrieves completion before releasing the buffers. Cancellation alone does not return buffer ownership. [GetOverlappedResult](https://learn.microsoft.com/en-us/windows/win32/api/ioapiset/nf-ioapiset-getoverlappedresult) completion runs on the observation lane even after the consumer has stopped waiting.

Closing one watch cancels only its device wait. Context closure cancels all watches. Neither operation joins an outstanding status thread on the caller or shared collection worker. A non-cooperative driver can retain its dedicated thread, native storage and device handle until completion; the SDK cannot safely free an in-flight native buffer. This is execution isolation, not a promise of zero resource use or protection against native process crashes. Screen, permission and lifecycle UI remain app-owned observer inputs.

A native removed-device/tag error permanently invalidates the observed generation and ends its matching watchers. Rediscovery can create a new handle even if the same path/tag reappears. Device paths compare without case sensitivity, including subscriptions created before and after a path's casing changes. This notification does not invent an interface disappearance: a replacement pack in a persistent interface remains discoverable.

## Verification

The final build has zero warnings/errors. Seven checks were added to the previous 42-check suite, through public DeviceAccess APIs with OS seams controlled where needed:

| Check | Evidence |
|---|---|
| Status delivery and responsiveness | A pending native wait leaves get responsive; captured discharge, charge and duplicate reports arrive in order even though subsequent direct reads return a different native state. |
| Error and generation semantics | File-not-found, no-such-device and device-not-connected statuses yield EntityRemoved and cannot revive old handles; access denial/other errors remain typed and do not fabricate removal. |
| Overlapped buffer lifetime | Controlled kernel calls receive the production unmanaged layouts. Cancellation completion is deliberately held back; watch disposal and other reads finish while the device and its pending storage remain owned. Cleanup follows actual completion. |
| Unknown capacity and fallback | An unknown capacity disables thresholds but preserves independently available state/zero rate. Unsupported native waits close and unchanged polling snapshots continue. |
| Actual Windows kernel completion/cancellation | A private, process-owned named pipe supplies controlled status bytes to the production overlapped transport. Actual completion events, CancelIoEx and GetOverlappedResult run, with ERROR_OPERATION_ABORTED on cancellation. No UI message loop is involved. |
| Independent subscription lifetimes | Closing one of two watches leaves the other receiving native status; context closure cancels the remaining wait. |
| Removal across path casing changes | Re-discovery preserves the typed handle when only casing changes. A status removal ends both old and new observers. This caught and fixed case-sensitive listener matching. |

The kernel test substitutes only the data-producing ReadFile operation for the battery DeviceIoControl submission. It exercises real Windows event/OVERLAPPED completion and the production cancellation/completion P/Invokes. It is **not** evidence of a real battery driver's status-wait behavior. Battery protocol inputs and transitions remain controlled fixtures on this batteryless host. Existing native aggregate, power-setting, interface-registration and ordinary Windows queries also pass in the full suite.

Commands: `tools/test-dotnet.ps1`, then the built .NET verification executable in a normal-user process. Final logs: `.tools/windows-battery-status-final.log` and `.tools/windows-battery-status-normal-user.log`, both 49/49. Development evidence also includes `.tools/windows-battery-status-red.log`, `.tools/windows-battery-status-errors-red.log`, `.tools/windows-battery-overlapped-red.log` and `.tools/windows-battery-status-peers-red.log`. Other language/browser suites were not rerun for these Windows-only changes.

## Remaining work

Actual battery-driver waiting, physical charge/discharge and capacity transitions, cancellation on laptop/UPS drivers, pack replacement within a persistent interface, multiple packs and the Windows version/architecture matrix still need direct evidence. The host still has no individual battery devices. Volume/network generation notifications and remaining Windows collectors/fields, Apple/Swift, Flutter/RN and the complete cross-platform verification matrix remain in scope.
