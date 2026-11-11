# Flutter viewport observer — 2026-11-11

This adds the first Flutter framework adapter on top of the [Dart observer runtime](2026-11-11-dart-observers.md). The release objective still includes all 46 entities and every specified platform/binding.

Follow-up: [Flutter screens and Windows application verification](2026-11-11-flutter-screens.md) adds Display, exact registered-view validation and a real Windows Release runner. It passes ten engine checks and five native application scenarios. The six-check evidence and pending work below describe this earlier checkpoint.

## Implementation

`flutter/device_readout_flutter` provides `FlutterViewportObserver.attach(access, view: ...)`. The app supplies its selected FlutterView and optionally its existing binding. Attachment rejects an unrelated binding or an already unregistered view before creating an SDK target. The adapter registers through WidgetsBinding's observer API and does not replace PlatformDispatcher global callbacks.

Initial attachment, metrics changes and system text-scale changes copy bounded view properties. Physical view size and viewPadding are converted to logical pixels using a positive finite device pixel ratio. System textScaleFactor is preserved; the two visual-viewport fields remain null because they are not provided by this source. ViewPadding retains safe-area meaning independent of keyboard viewInsets. The common worker performs normalization and completion timestamping. `get`, `watch` and discovery never call view getters or instantiate a native collector for this observer-only source.

Every attachment creates a fresh typed handle, and app selection determines `current`. A notification checks the registered view object before reading it. Removal or a replacement under the same view ID retires the old handle; late callbacks do not revive it. Source failures become typed observer failures and invalidate state without escaping into Flutter's UI error handler. A successful notification supplies fresh state and clears the adapter's target failure; ended streams do not restart. Disposal unregisters from WidgetsBinding and retires the target. If the SDK has already closed, a later callback safely detaches; owners should dispose the adapter before closing the SDK.

`example/lib/main.dart` demonstrates attachment in the widget dependency lifecycle, StreamBuilder consumption, explicit current selection and disposal. The example passes offline dependency resolution and Dart analysis; no platform runner/app binary is claimed yet.

## Evidence

Environment: checksum-verified Flutter **3.47.9**, Dart **3.13.7**, Windows x64 Flutter test engine. `./tools/test-flutter.ps1` passes strict analysis and **6/6** engine checks in a normal-user process. Final output is retained in `.tools/flutter-viewport-validation.log`.

| Check | Evidence and limits |
|---|---|
| Initial field mapping | Flutter TestFlutterView supplies 1200×800 pixels at DPR 2, yielding 600×400 logical size; controlled physical safe insets become 24/10/6/16 logical units; text scale 1.25 survives. Other visual fields remain null. |
| Callback-only screen access | The real WidgetsBinding metrics/text-scale notification paths deliver intermediate and duplicate snapshots despite a 60s poll setting. A view-boundary getter probe records no extra view reads from get, watch or list. Disposal prevents later notifications from reading the source. |
| Failure and recovery | An initial and subsequent view-getter failure become typed ReadFailed, end streams and require fresh state for new reads. No exception reaches Flutter's test error handler after the fix. |
| Removal and identity reuse | A controlled Flutter registry with two views verifies current-target removal, disposal, stale ID replacement and fresh attachment. This is a registry fixture, not physical window/monitor hotplug evidence. |
| Invalid source configuration | Zero density leaves size/insets null; foreign bindings and missing views fail before observer registration. Closure before a later metrics callback is contained and detaches the adapter. |
| Host responsiveness | A controlled native collector sleeps for 350ms inside an actual Flutter helper isolate. A Flutter metrics callback still copies changed state, host heartbeat continues, and 100ms active / 35ms queued read deadlines finish before the native call. The latest observed size is available after the call returns; native disposal completes afterward. |

The test engine and WidgetsBinding are real Flutter components. Dimensions, insets and text preferences are supplied through Flutter's test API; the failure/native-blocking and view-removal cases use explicit system-boundary fixtures. These results do not prove physical device behavior, actual OS window resizing, rendering performance on a real desktop application, Android/iOS/macOS lifecycle behavior or real permission dialogs.

Red evidence is retained in `.tools/flutter-viewport-red-normal-user.log`, `.tools/flutter-viewport-events-red.log`, `.tools/flutter-viewport-failure-red.log` and `.tools/flutter-viewport-removal-red.log`. It exposed absent event observation, an escaping source exception with a leaked registration after constructor failure, and stale snapshots after view removal. Each was corrected and the complete six-check suite passed.

## Tooling findings

The first sandbox test could not copy the compiled test kernel between sandbox temporary directories. Its still-live runner was explicitly interrupted and process absence checked before restarting the same test normally. No result was inferred from a timeout alone. The normal-user runner reached the intended failing SDK assertion and later passed the completed suite.

Flutter's analysis-server wrapper also attempted to write a user-global telemetry log despite the CLI suppression flag and failed under restricted filesystem access. The test script uses the same bundled Dart analyzer directly, which succeeds with the Flutter package configuration. It retains per-invocation Flutter analytics suppression and offline dependency resolution rather than modifying global preferences. The initial test dependencies were installed from pub.dev into the workspace-local pub cache; lockfiles record exact resolved versions.

## Remaining work

Next, build and run the example through a real platform runner and validate native window changes and resource teardown. Visual Studio C++ Build Tools are present on this Windows host. Flutter Display inventory, permission/platform plugins, sensor lifecycle, native collector reuse and the web bridge remain pending. Swift/Apple, React Native and the broader acceptance matrix remain part of the original goal.

Primary API references: [WidgetsBindingObserver.didChangeMetrics](https://api.flutter.dev/flutter/widgets/WidgetsBindingObserver/didChangeMetrics.html), [FlutterView.physicalSize](https://api.flutter.dev/flutter/dart-ui/FlutterView/physicalSize.html), [FlutterView.viewPadding](https://api.flutter.dev/flutter/dart-ui/FlutterView/viewPadding.html), and [PlatformDispatcher.textScaleFactor](https://api.flutter.dev/flutter/dart-ui/PlatformDispatcher/textScaleFactor.html). The corresponding sources in the pinned Flutter 3.47.9 SDK were also inspected, including the registered-view lookup and test framework notifications.
