# Dart sensor sources and Flutter lifecycle — 2026-11-11

This extends the [Dart observer foundation](2026-11-11-dart-observers.md) and [Flutter screen checkpoint](2026-11-11-flutter-screens.md). It implements source contracts and an explicit framework lifecycle adapter. Native sensor plugin connections, physical hardware evidence and the full 46-entity/platform acceptance matrix remain required.

Follow-up: the [Flutter Android bridge checkpoint](2026-11-11-flutter-android-sensors.md) connects the existing Kotlin sensor collectors and adds native API 26/36 evidence. Its source sessions also receive captured readTimeout. The foundation results and pending work below describe this earlier checkpoint.

## Implemented contracts

`observers.sensorSource(target, SensorObserverSource<S>)` registers an application-owned source for a typed sensor target. Registration and watch construction perform no subscription. Each get or subscribed watch owns a fresh session with typed publication, failure, cancellation and a captured sampling request. Continuous watches receive their immutable configured frequency; get and event sensors receive PlatformDefault. The SDK never fabricates, resamples, deduplicates or automatically retries sensor events.

Source setup and cleanup may complete asynchronously. These callbacks are an explicit app-side boundary and must be nonblocking; an application-provided synchronous blocking callback is not magically isolated. Native device work belongs in a worker. Returned cleanup runs once even when registration completes after cancellation. Source/observer failures end the operation; late samples, late registration failures and cleanup exceptions cannot escape the closed session. Removing a source permanently retires its target.

Sensor get waits for a fresh actual sample, including a next occurrence for event sensors. Continuous watch has a first-active-sample deadline. Event watch has no initial/idle occurrence timeout, but actual normalization still has readTimeout. StepDetected and SignificantMotion require an actual `value: true` occurrence; false/null source events fail ReadFailed. Successful snapshots have direct nullable fields and one isolate-assigned UTC completion timestamp.

Sensor activity is an explicit app input. Inactivity cancels source sessions, invalidates queued/in-flight samples and suspends active watches. Resumption starts fresh sessions with their prior settings. A get's overall deadline continues during inactivity. Watch does not spend its first-sample deadline while inactive. Reentrant activity updates retain the latest state across all listeners.

Each watch retains at most 2048 pending samples plus one in-flight/normalized delivery. Pause preserves order and duplicates; overload fails ReadFailed. A normalized value waiting for a paused consumer remains in SDK-owned storage so an intervening lifecycle transition can invalidate it before delivery. No implicit replay supplies a new get or session.

`describe(sensor)` normalizes the registered source's optional SensorDescription in the worker without starting collection, even while inactive. The typed target determines its sensor kind. It retains cancellation, deadlines, removal and blocking observer failures. This implements app-supplied metadata; native sensor metadata discovery is still pending. Generated mapping covers the shared schema's 19 sensor kinds.

The Dart web branch rejects sensor get/watch/describe without invoking the host source because the Web Worker bridge is not implemented. Existing screen normalization follows the same rule.

## Flutter adapter

`FlutterSensorActivityObserver.attach(access)` explicitly attaches to an existing WidgetsBinding. It copies initial lifecycle state once and consumes subsequent callbacks. Queries do not read framework state, create a binding, open permission UI or register native sensors.

Mobile/web collect in Resumed. Native desktop also collects in Inactive, preserving collection when visible windows lose focus. Hidden, Paused, Detached and unknown initial state suspend sources. These mappings use [Flutter's lifecycle meanings](https://api.flutter.dev/flutter/dart-ui/AppLifecycleState.html); notifications arrive through [WidgetsBindingObserver](https://api.flutter.dev/flutter/widgets/WidgetsBindingObserver/didChangeAppLifecycleState.html). The pinned Flutter 3.47.9 framework/engine sources were inspected as well. Mapping Linux/macOS/web states does not establish full SDK platform support.

Use one lifecycle owner per shared DeviceAccess context, attached before opening sensors. Dispose unregisters the observer and suspends sources; watches remain pending until cancelled or the context closes. A callback after context closure detaches safely. App-side source callbacks remain nonblocking; this is scheduling isolation, not a promise of zero main-isolate work or native crash isolation.

## Verification

Environment: Windows x64, Flutter 3.47.9 / Dart 3.13.7. `tools/test-dart.ps1` generates all 46 entity models and metadata, resolves offline, analyzes, runs JIT contracts, compiles/runs the native executable and compiles/runs the JavaScript negative boundary. All **28/28** Dart contracts pass in both native modes; analysis and the web negative check pass.

Ten sensor checks extend the previous eighteen state/permission/foundation checks:

| Check | Evidence |
|---|---|
| Demand and settings | Inert registration/construction, separate get/watch sessions, 60Hz watch versus default get, fresh sample and cleanup |
| Activity | Inactive waiting, immediate source cancellation, no late callbacks, fresh resumption with retained settings |
| Event sensors | Idle watch survives its readTimeout; get times out; fabricated false occurrence fails |
| Late registration/cleanup | Async setup returns cleanup after cancellation; thrown cleanup and late rejection are contained; context closure does not wait |
| Failure while inactive | PermissionDenied remains terminal after immediate clearing and later resume |
| Metadata | No sampling, authoritative typed kind, field normalization, UTC timestamp, non-sensor and removed-target errors |
| Reentrant activity | Synchronous cleanup-triggered resume cannot be overwritten by the older suspension dispatch |
| Ordering/overload | Equal samples retained, invalid vector null, paused source overflow explicit and bounded |
| Busy worker | Actual 500ms fixture in the collection isolate; 100ms get/event-normalization/metadata deadlines, heartbeat and nonjoining context closure |
| Paused delivery plus lifecycle | In-flight sample finishes while consumer is paused; inactivity discards it; resumed session delivers only fresh values |

`tools/test-flutter.ps1` passes **13/13** engine checks: the previous ten screen checks and three lifecycle checks. They cover actual WidgetsBinding callback dispatch under mobile/desktop platform policies, source release/resume, desktop focus retention, hidden suspension, unknown initial state, no query-time lifecycle getters, metadata without sampling, no implicit permission coordinator, disposal and callbacks after SDK closure. These are Windows Flutter-engine tests with controlled source inputs, not actual Android/iOS hardware lifecycle tests.

`tools/test-flutter-windows.ps1` also passes **5/5** existing screen/worker scenarios in an owned hidden Windows Release application. It corroborates screen state against independent Win32 queries, performs real client resizes, verifies removal/reattachment and preserves host responsiveness during a blocked helper-isolate read. The script rebuilds the normal example without its test channel. These cases are screen regressions, not native sensor evidence.

Logs:

- `.tools/dart-sensor-validation.log`: strict analysis, JIT 28/28, AOT 28/28 and web negative boundary.
- `.tools/flutter-sensor-validation.log`: strict analysis and 13/13 engine checks.
- `.tools/flutter-windows-sensor-regression.log`: 5/5 native screen scenarios and ordinary example rebuild.

Red cases are retained in `.tools/dart-sensor-source-red.log`, `.tools/dart-sensor-activity-red.log`, `.tools/dart-sensor-events-red.log`, `.tools/dart-sensor-description-red.log`, `.tools/dart-sensor-reentrant-red.log`, `.tools/dart-sensor-paused-lifecycle-red.log` and `.tools/flutter-sensor-activity-red.log`. Behavioral failures reproduced and corrected include fabricated event acceptance, stale reentrant suspension and stale paused delivery after inactivity. The Flutter fixture was also corrected to await asynchronous source cleanup rather than require synchronous teardown.

## Remaining scope

- Connect Dart/Flutter to native Android/Windows/Apple sensor collectors and their actual worker-owned registration/cleanup. Source contract tests are not physical sensor support.
- Implement native discovery/metadata/capabilities and remaining entity collectors; the direct Dart native collector still supplies only Runtime process architecture and process bitness.
- Verify actual mobile background/foreground, desktop visibility, physical sensor units/coordinates/frequency, plugin permission changes and native removal/reappearance across supported versions.
- Implement the Dart web worker bridge, Swift/Apple and React Native bindings and complete the minimum-version/architecture/package-consumption matrix.

Unchanged TypeScript, .NET and Android suites were not rerun for this Dart/Flutter checkpoint. Their preceding evidence remains separate.
