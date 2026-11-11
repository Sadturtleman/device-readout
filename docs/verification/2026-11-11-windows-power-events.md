# Windows power events and deferred state reads — 2026-11-11

Windows Power and individual Battery watches now combine native power-setting notifications with serial polling. The common .NET runtime executes deferred state-event reads on its background collection lane and preserves cleanup after a read deadline. The overall SDK implementation remains incomplete; the Windows collector count stays at twelve.

## Behavior

`Watch(Entities.Power)` registers for power-source and battery-saver changes. The native callback copies its DWORD value and queues a deferred read. The worker reads the remaining power state, applies the captured event field, normalizes the snapshot and assigns its completion timestamp. Source values 0/1/2 map to External/Battery/Ups; saver values 0/1 map to false/true. Unrecognized values become null. Equal notifications are retained. An event field is not replaced by a later OS query, which could otherwise erase a short-lived transition.

`Watch(battery)` registers for power-source and aggregate battery-percentage notifications. These are signals to read the selected device/tag on the collection worker. The system-wide percentage is never copied into an individual pack's level. An observed changed/removed tag still retires the target permanently and terminates its stream. No battery file is opened inside the callback.

Both watches keep the configured polling interval because these notifications do not cover every snapshot field. Unsupported notification registration (Win32 50/120) falls back to polling; other registration failures produce a typed error. Partial registration and stream failure release all registrations already owned by the subscription. Construction, ordinary get and list do not subscribe to power events.

The native implementation uses [PowerSettingRegisterNotification](https://learn.microsoft.com/en-us/windows/win32/api/powersetting/nf-powersetting-powersettingregisternotification) with callback delivery. It does not create a window, install a UI message loop, change power settings or request permissions. Microsoft documents an initial current-value callback for each registration. Native source/saver/percentage meanings follow [Power Setting GUIDs](https://learn.microsoft.com/en-us/windows/win32/power/power-setting-guids).

The callback validates the expected GUID and four-byte [POWERBROADCAST_SETTING payload](https://learn.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-powerbroadcast_setting). A single rooted callback and never-reused numeric registration contexts avoid dangling managed delegate/GCHandle pointers. Removing a context makes late notifications inert; exceptions do not unwind into the native callback. Unregistration uses [PowerSettingUnregisterNotification](https://learn.microsoft.com/en-us/windows/win32/api/powersetting/nf-powersetting-powersettingunregisternotification) on the worker.

## Common .NET collection contract

`IDeviceCollector.ObserveChanges` is an optional state-observation hook. Its callback submits `Func<CancellationToken, DeviceSnapshot>` instead of performing a native query inline. Existing snapshot-producing observations and sensor subscriptions remain available. Initial reads, polls and deferred state reads share a serial input path. Each read has the configured deadline; snapshots are emitted directly, including equal values. App-owned failure/removal gates are checked before and after a deferred read.

A public-API regression reproduced this leak: a state-event read exceeded its deadline, then the queued subscription disposal expired behind the still-running native call. After the native call returned, the old implementation skipped the canceled disposal and left the subscription registered until context closure.

Cleanup now has its own non-cancelable work item. The caller's bounded wait may end, but the disposal remains queued. Ordinary queued collection requests are still limited to 128; cleanup for already-owned subscriptions is admitted even when that queue is full. Context closure retains final worker-owned cleanup. This does not forcibly abort native calls: a permanently stuck call can still prevent its lane from releasing native resources. Caller deadlines remain independent, and disposal does not join that thread on the UI path.

Screen and permission state continue to come from app-owned observers. This change adds no screen getter or permission-prompt path.

## Evidence

The final .NET build has zero warnings/errors. All 32 checks pass in the sandbox and in a normal-user Windows process. The seven checks added since the battery checkpoint cover:

* Deferred state reads on the collection lane, duplicate delivery, cancellation and rejection of late callbacks.
* Event-read deadlines followed by eventual subscription release after an uncooperative native call returns.
* Subscription release with a saturated ordinary-read queue, while admitted reads recover and excess reads fail explicitly.
* Captured power-source/saver values, UPS mapping, unknown values, equal events and worker-owned registration/read/disposal.
* Individual-pack refresh from aggregate power notifications, unchanged values, removal and permanent retirement.
* Real native current-setting callbacks for both source and saver, followed by successful unregistration of both handles without a window. An hour-long polling interval prevents the poller from satisfying this check; a probe wraps only the actual OS boundary to distinguish the two callback GUIDs and record unregistration failures.
* Polling fallback, hybrid polling, partial registration cleanup, native callback failure and independent reads after a failed subscription.

Logs: `.tools/state-change-cleanup-red.log`, `.tools/state-change-pressure.log`, `.tools/windows-power-event-red.log`, `.tools/windows-power-native-red.log`, `.tools/windows-battery-events-red.log`, `.tools/windows-power-final.log` and `.tools/windows-power-normal-user.log`. Red runs failed on the intended missing observation/cleanup behavior; final runs pass. TypeScript, browser and Kotlin/Android suites were not rerun for changes confined to .NET/Windows.

## Remaining work

This host has no physical battery. Battery transitions and field values use controlled driver/notification inputs; real source/saver registration evidence does not prove laptop charging transitions or physical replacement. Subsequent checkpoints add [context-owned battery hotplug observation](2026-11-11-windows-battery-hotplug.md) and [OS aggregate battery selection and report callbacks](2026-11-11-windows-aggregate-battery.md). The subsequent [individual status checkpoint](2026-11-11-windows-battery-status.md) adds per-device driver waits. Physical pack/UPS/multiple-pack tests, actual driver-wait behavior, other Windows architectures/versions and the remaining Windows entities are still pending. Changes without a delivered native observation can remain undetected. The SDK does not promise zero resource cost or process-crash isolation.
