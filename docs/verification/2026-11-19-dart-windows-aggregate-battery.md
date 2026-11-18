# Dart and Flutter Windows aggregate battery verification

The subsequent [individual battery checkpoint](2026-11-19-dart-windows-battery-packs.md) adds pack discovery/get/watch and interface lifetime handling. Results and unsupported operations below describe this earlier aggregate-only snapshot.

This record completes the installed-consumer checks left pending in the [aggregate battery upload checkpoint](2026-11-19-upload-aggregate-battery.md). It verifies the Dart/Flutter source snapshot uploaded as `df96162`. Before the separate [C# capacity correction](2026-11-19-dotnet-aggregate-capacity.md), all 564 non-Markdown inputs matched the capture taken before the final Dart run. The complete DeviceReadout acceptance matrix remains unfinished.

## Implemented behavior

`current(Entities.battery)` resolves the operating system's logical aggregate endpoint for typed `get(target)` and `watch(target)`. The handle survives an absent battery. This collector does not yet provide individual battery discovery, individual-pack reads or device-interface hotplug; `list(Entities.battery)` remains unsupported.

WinRT reports supply nullable status, signed charge rate and distinct design/full/remaining capacities. Negative capacities become null; valid zero and negative discharge power remain available. Level uses remaining capacity over positive full-charge capacity. A NotPresent status returns `present=false` and clears stale numeric values. Unknown status remains null. Optional known system lifetime becomes time-to-empty only when AC is not explicitly online and the battery is not explicitly absent. Other aggregate fields remain null.

The mapping follows the native API's documented mWh capacity contract. Microsoft also documents devices that misreport mAh in the full-capacity property. The SDK does not apply a magnitude heuristic or infer a conversion; driver-unit correctness on such hardware remains unverified. See [remaining capacity](https://learn.microsoft.com/en-us/uwp/api/windows.devices.power.batteryreport.remainingcapacityinmilliwatthours?view=winrt-26100) and [full-charge capacity](https://learn.microsoft.com/en-us/uwp/api/windows.devices.power.batteryreport.fullchargecapacityinmilliwatthours?view=winrt-26100).

Native `ReportUpdated` events invalidate the current report, with one shared registration and independent watch lifetimes. Serial polling supplements events and retains equal snapshots. Unsupported registration falls back to polling; other failures remain typed and terminal. Permanently failed unregister retains native ownership for explicit cleanup rather than claiming the resource was freed. Retired tokens reject late callbacks.

## Completed checks

| Check | Result |
| --- | --- |
| Dart analysis and contracts | 235/235 JIT and 235/235 CLI-bundle checks; the complete script passes. |
| Native battery cases | Fifteen per mode, including sixteen field fixtures and five whole-read failure cases. All thirty reports pass. |
| Held native cases | Eight per mode cover activation, nullable value, read, watch, registration, unregister, cancellation and disposal. |
| Shared observation | Two consumers retain independent deliveries and cancellation through one registration and one final removal. |
| Reference ownership | Ordinary cases finish with zero retained objects; the persistent-unregister case explicitly retains one native owner. Apartment errors remain zero. |
| Dart web boundary | Unsupported-host negative collection check passes. |
| Checkout Windows application | Complete script passes 22/22 and restores the ordinary example. |
| Installed Windows application | Fresh local archives install through Pub; complete script passes 22/22 and restores the ordinary example. |
| Flutter framework | Analysis and 27/27 checks pass. |
| Installed-source parity | All 42 Dart runtime/build/native files, twelve Flutter package files and five relevant consumer support files match the verified sources. Archive hashes and actual download requests are checked. |

Both Windows applications compare the aggregate with an independent C++/WinRT projection, receive three snapshots with fresh completion times and retain UI timer progress. On this host, the projection reports no battery and eight stable fields agree. This proves physical absence behavior; positive battery values and native event/failure paths currently rely on controlled fixtures.

Held-call scenarios verify a distinct collection thread, caller progress, a readable sibling context and public completion before native return. Native read and cleanup work remains on the isolate. Screen, permission and lifecycle inputs remain app-owned observations. These checks do not establish native-crash containment or zero shared-resource overhead.

## Preserved failures and remaining coverage

Earlier runs include a network `unknown-prefix` child access violation, a Dart compiler `BinaryBuilder.readStringTable` failure and a Microsoft C++ compiler `c2.dll` access violation. A focused unchanged network child and the final complete gates pass, but the root causes remain unestablished. Failed logs, crash records and the earlier assertion that reproduced negative energy remain preserved; no test runner suppresses failures or retries automatically.

Individual battery list/get, interface hotplug, physical charge/discharge transitions, drivers with incorrect unit reporting, ARM64 and other Windows configurations remain unverified or unimplemented. Apple collectors and the full language/framework/platform matrix remain required. Local Pub archives are verification artifacts, not published packages.

Reproduce with `tools/test-dart.ps1`, `tools/test-flutter.ps1`, `tools/test-flutter-windows.ps1`, `tools/build-flutter-packages.ps1 -Platform Windows` and `tools/test-flutter-windows.ps1 -ExampleRoot .tools/flutter-windows-installed`. Source captures, native reports, consumer reports, archive comparisons and successful/failed log hashes are preserved in the ignored `.tools/evidence/dart-windows-aggregate-battery-checkpoint.json`.
