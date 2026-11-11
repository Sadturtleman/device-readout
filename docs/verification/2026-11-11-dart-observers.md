# Dart screen and permission observer inputs — 2026-11-11

This extends the [Dart isolate foundation](2026-11-11-dart-foundation.md). The full release scope is unchanged. Framework-owned Flutter observers and platform plugins are still separate pending work.

Follow-up: the [Flutter viewport checkpoint](2026-11-11-flutter-viewport.md) implements the first explicit framework adapter and verifies six Windows-engine cases. The Dart-only evidence and remaining scope below describe this earlier checkpoint.

The subsequent [Flutter screen checkpoint](2026-11-11-flutter-screens.md) adds Display inventory and actual Windows application evidence, while retaining the Dart-only results below as historical evidence.

The [sensor/lifecycle checkpoint](2026-11-11-dart-sensors.md) subsequently implements Dart sensor sources, activity, app-supplied metadata and a Flutter lifecycle adapter. Its 28 Dart and 13 Flutter checks supersede the counts below; the earlier checkpoint's scope remains recorded here.

## Implemented behavior

`DeviceAccess.observers` now accepts typed target registration, state publication, current-target selection, removal, whole-operation failures and permission status. State publications replace the complete observed snapshot. Handles are scoped to their access context and shared by its immutable configuration views. `list(kind)` / `current(kind)` and typed collection helpers expose app-observed inventories. An unspecified current target remains null; a known empty inventory returns an empty list. Native inventory queries are not implemented in Dart yet.

App callbacks store immutable state and schedule delivery. Reads send the captured snapshot to the collection isolate for normalization and UTC completion stamping. The native collector factory is now lazy inside the worker: observer-only reads never instantiate a native collector. No query, inventory, permission check or stream invokes a UI getter or permission coordinator implicitly. Observer callbacks still perform small local state/queue operations; this is not a zero-overhead claim.

State watches use observer notifications when available. They preserve intermediate publications, order and equal values, independently of `pollInterval`. Native state reads without an observation source retain serial polling. A paused observer stream retains at most 2048 pending updates plus an already-running read; overflow terminates it with `ReadFailed` rather than dropping or conflating values. The initial observed-state wait and normalization share the read deadline. Once a first snapshot is delivered, idle event waiting has no read timeout.

`observers.failure(entity, error)` blocks the target or complete kind, clears matching cached state and terminates matching streams immediately. In-flight reads retain the failure even if it is cleared before the native operation returns. A fresh publication plus cleared failure permits new reads; failed streams do not restart. Removing a target permanently retires its handle, invalidates current selection and ignores late publications. Re-registering the same identity does not revive that handle; a new source lifetime needs a new identity.

`permissions.check` reads independently observed status. A target inherits kind-level status unless it has an explicit override, including null. Status by itself does not declare the whole entity unreadable: an adapter uses `observers.failure(...PermissionDenied...)` when the entire operation is blocked, and null fields when only particular fields are unavailable.

Only `permissions.request` invokes the registered application coordinator. It returns an already observed Granted status directly; otherwise it registers for the matching permission observation before scheduling the app callback. Successful callback completion alone does not complete the request. Unrelated screen publications and overridden kind-level permission updates do not complete it. There is no read timeout on the user's permission response wait. Caller cancellation, context closure or observed response ends the coordinator's cancellation lifetime. Asynchronous coordinator errors become `ReadFailed`; late errors after a completed response are observed without becoming unhandled errors. Each coordinator registration owns its own unregister function, including when the same callback is registered again.

The app coordinator owns actual platform UI and must keep its entry callback nonblocking. These tests do not open real permission dialogs or establish web user-activation behavior.

## Verification

`./tools/test-dart.ps1` passes strict analysis and **18/18** contracts in both JIT and a compiled Windows x64 executable, using Dart 3.13.7 from Flutter 3.47.9. JavaScript compilation and the negative web boundary test also pass.

The nine added contract checks cover:

1. Typed app-observed screen reads with a native factory that fails if invoked, whole-state replacement, cross-context rejection and worker normalization.
2. Four ordered screen snapshots including rapid intermediate and duplicate updates, despite a ten-second polling interval; cancellation prevents later delivery.
3. First observed-state waiting, read timeout, caller cancellation and context closure.
4. Kind-level observer failure, immediate termination of a long-interval watch, invalidated cached state, explicit recovery, and a failure/recovery race during a controlled 350ms native call.
5. Typed discovery, explicit current selection, permanent removal, late-callback rejection and a known empty inventory.
6. No implicit permission coordinator invocation from get/watch/list/check; a permission response wait longer than readTimeout; inherited permission response and Granted fast path.
7. Explicit null target overrides, ignored kind-level updates, permission reads during a blocking failure, caller/context cancellation and contained late coordinator failures.
8. Explicit overflow failure for a paused observer consumer while fresh gets retain the latest published state.
9. Exclusive coordinator registration, stale teardown after re-registration, missing coordinator errors and asynchronous coordinator failure.

The prior nine foundation checks still pass, including actual Windows x64 Runtime fields, exact nullable snapshots, blocked-collector host heartbeat, independent deadlines, cancellation and late worker cleanup. The JavaScript negative check now includes an app-observed screen: absent a Web Worker bridge, normalization also returns UnsupportedEntity rather than running on the host.

Evidence is in `.tools/dart-observer-validation.log`. Red cases preceding implementation are retained in `.tools/dart-observed-read-red.log`, `.tools/dart-observer-events-red.log`, `.tools/dart-observer-first-red.log`, `.tools/dart-observer-failures-red.log`, `.tools/dart-observer-discovery-red.log` and `.tools/dart-permission-observer-red.log`.

## Remaining scope

This is Dart SDK contract evidence using app-input and OS-boundary fixtures. It is not evidence of actual Flutter screen changes, device hotplug or permission dialogs. Flutter bindings still need explicit framework observer adapters and plugin connections to the existing native/web collectors. Dart sensor sources, sensor lifecycle activity, native state notifications, native discovery, describe/capabilities and remaining native entity collectors are pending. Apple, React Native, broader platform/architecture versions and the full acceptance matrix remain in scope.
