# Flutter web application checkpoint — 2026-11-17

The actual Flutter example and a public-API consumer now run against the served DeviceReadout module worker. This checkpoint covers representative Chrome/Edge applications, not the full 46-entity, binding, physical-device or platform acceptance matrix.

The subsequent [Dart watch-delivery checkpoint](2026-11-17-dart-watch-delivery.md) rebuilds these same applications after adding polling handoff and completed-read deadline handling; all application scenarios remain passing.

## Changes and reproduced defects

The example previously constructed native access in the browser and rendered an UnsupportedEntity read error. It now selects `DeviceAccess.web(workerUri: ...)` on web and native access elsewhere. The build helper bundles Flutter's web resources locally and copies the built SDK worker beside the app. The contract consumer is also served under `/contracts/`, exercising a relative worker URL and a non-root base path.

Flutter's pinned 3.47.9 web engine constructs Display.size from Screen.width/height in CSS pixels. Its device ratio also incorporates visual viewport scale, so multiplying those dimensions cannot establish a physical monitor mode. The SDK previously returned those CSS dimensions as pixelSize; the corrected-null contract failed in both browsers before the adapter fix. Web pixelSize is now null, scaleFactor retains the engine ratio, and currentMode remains null. Native display mapping is unchanged. This leaves physical browser display resolution unavailable rather than inventing it.

The source evidence is the locally validated SDK's `engine/display.dart` under its cached web engine. The [CSSOM View specification](https://drafts.csswg.org/cssom-view/#the-screen-interface) defines screen dimensions in CSS pixels; Flutter's general [Display.size documentation](https://api.flutter.dev/flutter/dart-ui/Display/size.html) describes physical pixels and does not resolve this engine-specific mismatch.

## Verification

Run `./tools/test-flutter-web.ps1` from the repository root. It builds the normal example and the contract app, then drives installed Chrome and Edge with isolated headless contexts and an ephemeral localhost server. Flutter 3.47.9 / Dart 3.13.7, Chrome 158.0.8127.37 and Edge 157.0.4341.60 were used. Both application builds and Dart analysis pass. Builds still print the existing missing CupertinoIcons font-family warning and a newer dependency-version notice.

Each browser passes the normal rendered-example case and six grouped application scenarios:

1. Typed CPU/locale reads agree with browser values; viewport/display discovery and current selection use app-owned framework observations. Attaching observers does not create the SDK worker.
2. Actual browser resizing updates the viewport stream. Cancellation stops delivery, disposal retires the old handle, and replacement observes the settled new dimensions.
3. Native tab activation generates a trusted blur event while the original page remains visible. Flutter enters inactive, releases the controlled sensor session and times out an inactive get. Returning focus resumes a fresh session and normalizes its quaternion.
4. App-published denied permission and a separate owned PermissionDenied failure stop reads/streams without requesting UI. Explicit coordination waits for the app response beyond readTimeout; clearing the owned failure and granting permission allows a fresh read.
5. A separate controlled worker holds collection for 800 ms. Its read times out at approximately 161 ms while ten rendered Flutter frames and sixteen host timer ticks progress in the recorded run.
6. Widget unmount disposes the shared context, cancels old reads and releases the remaining worker. Both SDK workers created by the scenario are terminated.

The driver passes 4/4 Node parent tests: two normal examples and two six-scenario consumers. It writes local JSON evidence under `.tools/evidence/flutter-browser-*`; generated builds, browser profiles and evidence files are excluded from version control. The separate framework suite is run with `./tools/test-flutter.ps1`.

## Test-harness corrections and boundaries

The installed Playwright polling helper treated an async predicate's Promise as truthy before its state settled. Async conditions now use an explicitly awaited Node polling loop. Playwright's always-focused emulation also hid real tab focus changes; disabling that emulation after navigation allows actual browser blur/focus events. These were test-harness corrections, not SDK failures. The fixture publishes both permission state and its separately owned read failure, following the existing contract rather than making permission status implicitly control collection.

CPU/locale reads, browser layout, Flutter framework callbacks and worker lifetimes are real browser integration. Sensor samples, permission coordination and the held worker are controlled application fixtures. This does not verify physical sensors, native permission dialogs, hidden-page/background suspension, multiple monitors, zoom transitions, Firefox, Safari, Flutter Wasm, external package distribution or the complete support matrix. Progress during one held worker does not promise zero host overhead, process isolation or a maximum frame time.
