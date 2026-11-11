# Flutter Display and Windows application verification — 2026-11-11

This extends the [first Viewport adapter](2026-11-11-flutter-viewport.md) with Display inventory and a real Windows runner. The full 46-entity/multiplatform release objective remains active.

## Changes

`FlutterDisplayObserver` explicitly attaches to an existing WidgetsBinding. It supplies typed Display targets from Flutter's reported inventory, preserves handles across replacement of immutable Display objects and retires them after observed absence. Reappearance gets a new identity. `selectView` follows the display for an app-selected, currently registered view; selection is never inferred from focus or primary-monitor status. Both screen adapters now reject stale view objects before registration/selection, even when the view ID exists again.

Display maps valid pixel size and scale factor independently. On Windows it also maps currentMode using the pinned engine's current-settings refresh rate; 0/1, nonfinite or unreadable rate leaves currentMode null. Unknown dimensions and independent field failures remain null without discarding readable fields. DensityDpi, logical/work-area bounds, maximum rate, supported modes, primary/internal status and other absent properties stay null. Non-Windows currentMode mapping remains pending: a framework render cadence must not be substituted for a physical mode.

Native fields are copied only at explicit attachment/selection and framework metrics callbacks. SDK reads use the common worker normalization path and do not query UI objects. Inventory failure invalidates state and terminates streams with ReadFailed; successful fresh observation supports new subscriptions. Disposing unregisters the framework observer and retires its targets. The app owns one Display inventory adapter per DeviceAccess context and its selection/failure slot. Permission dialogs and other UI actions still belong to the app coordinator.

The existing example now has a generated Windows C++ runner. A separate test entrypoint and compile-time native channel operate only on that runner's retained HWND. The test window remains hidden. After verification, the script rebuilds the ordinary example without the test code. Its final generated VCXPROJ contains neither the test definition nor test source. No other windows, display settings or global Flutter configuration are changed.

## Evidence

Environment: Flutter **3.47.9**, Dart **3.13.7**, Windows x64. Flutter selected the installed Visual Studio 2022 Community C++ toolchain for this build. Strict analysis passes. The final source passes:

* `./tools/test-flutter.ps1`: **10/10** engine checks (six Viewport, four Display).
* `./tools/test-flutter-windows.ps1`: **5/5** scenarios in an actual AOT Release application, followed by a successful ordinary example Release build.

Final logs: `.tools/flutter-screen-final.log`, `.tools/flutter-windows-screen-final.log`. Native report: `.tools/flutter-windows-viewport-4567df227c244a9eaeeb484a76caf8e5.json`.

| Scenario | Evidence |
|---|---|
| Display field/event contracts | Real Flutter test notifications retain equal updates with a one-minute polling interval; controlled Windows rates 120→144→144 survive, unspecified rate becomes null, and non-Windows mode fields remain null. Independent source failures preserve readable properties. |
| Display inventory lifetime | Controlled two-display inventory preserves live IDs across object replacement, clears selected missing views, rejects stale/foreign views, retires removed IDs and issues new handles on return. Empty inventory remains empty; malformed/failed inventory becomes ReadFailed without pretending removal. SDK reads add no source getter calls. |
| Real window dimensions | An actual hidden HWND at 144 DPI reports a 1898×1024 client area; the SDK returns 1265.333…×682.666… logical units. Native resizes to 901×607 and 1133×733 yield the expected logical snapshots before the one-minute polling interval. |
| Native monitor inventory | Flutter and independent `EnumDisplayMonitors` report two monitors. After a post-parenting native metrics notification, the selected monitor's 5120×2160 pixels, scale 1.5 and 144Hz match `GetMonitorInfo`, `GetDpiForWindow` and `EnumDisplaySettings`. A test-injected WM_DISPLAYCHANGE causes real native re-enumeration, retains handles and delivers another snapshot. This is not a physical hotplug event. |
| Detach and reattach | Old watches end with EntityRemoved, discovery/current are cleared, later native resizes do not revive the old stream, and fresh attachment gets a new handle with current native dimensions. |
| Host responsiveness | A controlled collector sleeps 500ms in the actual application's helper isolate. During that call a real Windows resize reaches the Flutter callback, a 200ms host deadline completes and the main-isolate heartbeat continues. Final run records 49 heartbeat ticks over the test; latest observed size and worker disposal are verified after the call returns. |

The native table has five application scenarios; the two engine-only rows expand the four new Display contract cases. Earlier Dart 18/18 and .NET/Android/browser results were not rerun for these Flutter-only changes.

## Findings and corrections

The missing Display API first failed strict analysis (`.tools/flutter-display-red.log`). The initial fixture cleanup incorrectly restored a Flutter debug platform override after the framework's invariant check; it now restores the override in the test's finally block. Stale-view selection and Viewport reattachment were separately reproduced in `.tools/flutter-display-stale-view-red.log` and `.tools/flutter-viewport-stale-attach-red.log`. Both now require the exact current registered view object. Getter probes register their wrapper as the canonical fixture view while continuing to receive real WidgetsBinding notifications.

The first real display comparison failed: the newly started hidden view initially associated with the other monitor (1440×2560 at 165Hz), while its final parent window was on the 5120×2160 monitor. The pinned engine sends initial view metrics before the generated runner finishes parenting its child. Waiting for an actual post-parenting native resize notification corrected the association, with no SDK field substitution. Diagnostic output remains in `.tools/flutter-windows-screen-diagnostic.log`. This startup limitation is documented: the adapter reports Flutter's observed association, not an independently polled OS window-to-monitor relationship.

## Limits and next work

The Release application exercises real Win32 resizing, two actual monitor inventory values, Flutter notification delivery, AOT isolates and app teardown. Physical monitor unplug/replug, movement between different-DPI monitors, system text-scale changes, keyboard/pinch behavior, signed/package deployment and other Flutter platforms/versions remain unverified. Inventory replacement/removal, optional getter failures and stale-object races use controlled platform fixtures. The source inventory may be a subset of OS displays on other platforms.

Continue Flutter native collector/plugin reuse, explicit permission-plugin observations, sensor lifecycle, Dart sensor sources and the web worker bridge. Swift/Apple and React Native integrations and the remaining platform/entity acceptance matrix are still required. No claim of zero host overhead or native-crash isolation is made.

Primary references: [Flutter Windows runner documentation](https://docs.flutter.dev/platform-integration/windows/building), [Display API](https://api.flutter.dev/flutter/dart-ui/Display-class.html), [Flutter display inventory](https://api.flutter.dev/flutter/dart-ui/PlatformDispatcher/displays.html), [GetDpiForWindow](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getdpiforwindow), and [AdjustWindowRectExForDpi](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-adjustwindowrectexfordpi). The pinned SDK's `engine/src/flutter/shell/platform/windows/display_manager.cc`, `flutter_window.cc` and `flutter_windows_view.cc` provide the verified Windows mapping and view-metrics source; its `dart:ui` sources confirm Display object replacement and metrics notification behavior.
