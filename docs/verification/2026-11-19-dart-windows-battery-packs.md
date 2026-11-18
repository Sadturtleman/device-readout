# Dart and Flutter Windows individual battery checkpoint

This development checkpoint extends the [aggregate battery collector](2026-11-19-dart-windows-aggregate-battery.md) with individual battery discovery and typed get/watch. It also includes the separately verified [C# capacity correction](2026-11-19-dotnet-aggregate-capacity.md). The complete 46-entity, language, platform, version and physical-device acceptance matrix remains unfinished.

## Behavior and ownership

`list(Entities.battery)` returns tagged individual packs and the OS aggregate endpoint when available. `current(Entities.battery)` continues to select the OS aggregate, without choosing an arbitrary individual pack. Handles belong to their access context and remain stable while their native target generation is live.

SetupAPI inventories and read-only battery IOCTLs run on the collection isolate. Configuration Manager interface observation begins before enumeration and remains owned until context disposal, including between get-only calls. Native removal callbacks record retirement before posting a bounded invalidation token. Changed tags, observed absence and removal permanently retire the old handle; path/tag reuse creates a new handle. A result spanning removal is rejected. Native callbacks do not perform device reads.

Individual watches perform an initial read, respond to interface notifications and use serial polling at the configured interval. Equal snapshots remain deliverable. Individual driver status-wait IOCTL observation is not implemented in Dart yet; the C# status observer is separate. Aggregate watches retain WinRT ReportUpdated observation and polling.

| Individual field | Mapping |
| --- | --- |
| Presence and level | A valid tagged report establishes presence. Remaining/full capacity produces level when full capacity is positive, including relative-capacity devices. |
| State and charging | Known, consistent native power flags; unknown or conflicting flags become null. |
| Energy and charge rate | Native absolute capacities in mWh and signed rate in mW. Relative-capacity devices expose neither physical energy nor power. Native unknown sentinels become null. |
| Voltage and current | Native millivolts; current uses the same report's absolute rate and positive voltage, converted to microamps. |
| Temperature and lifetime | Native tenths-kelvin converted to Celsius, and known estimated seconds to time-to-empty. |
| Chemistry and cycles | Valid printable chemistry text and known nonzero cycle count. |
| Remaining fields | Average current, charge counter, time-to-full and health remain null. |

A reproduced lifetime defect allowed an old handle to recover when a confirmed replacement was followed by a CloseHandle failure and later tag reuse. Retirement is now recorded before cleanup; cleanup failure cannot erase the replacement evidence. Failed handle/inventory cleanup retains ownership for later cleanup. Failed notification unregistration does not falsely release its native context.

## Verification and its limits

| Check | Result |
| --- | --- |
| Dart JIT | 240/240 contracts pass. The unified script subsequently failed during native compilation. |
| Dart compiled CLI bundle | A separate unchanged-source build and run passes 240/240 contracts and the web boundary check. A clean unified Dart script run is not claimed. |
| Native pack cases | Five scenarios per mode, ten passing child reports: discovery/fields, retirement across failed cleanup, interface lifetime, held read, and removal during a held read. Ordinary cases finish with zero native handles, inventories and registrations. |
| Held native read | Public timeout completes before native return, the caller continues progressing, and a sibling native RAM context remains readable. Concurrent caller/worker thread IDs differ. |
| Checkout Windows app | 22/22 application checks pass. The wrapper fails during ordinary-example restoration; a separate unchanged-source restoration succeeds. |
| Installed Windows app | 22/22 application checks pass. The wrapper fails during ordinary-example restoration; a separate unchanged-source restoration succeeds. |
| Flutter framework | 27/27 checks pass after the test-reference helper correction. |
| Installed package parity | All 44 Dart runtime/build/native files and twelve Flutter package files match the locally served Pub archives. Five consumer reference/support files also match. These packages are not published to pub.dev. |

The physical host has zero individual packs and one logical aggregate endpoint, independently confirmed by a C++ SetupAPI/QueryTag reference. Both actual apps check this inventory, three aggregate snapshots and UI timer progress. Positive individual fields, replacement and removal currently have controlled native-fixture evidence, not physical battery evidence.

The Flutter reference test initially failed because an inline Isolate.run closure captured a typed SDK handle and its ReceivePort through a shared closure context. Top-level reference helpers now capture only the library path; both actual consumers pass with that correction. Production SDK sources were unchanged by this test-helper fix.

The final audit matches 569 non-Markdown source inputs. Only the Flutter reference helper changed after the Dart source capture; the later framework and consumer runs use that corrected helper. The local evidence manifest is `.tools/evidence/dart-windows-battery-packs-checkpoint.json`; ignored logs, native binaries, Pub archives and source hashes remain local.

## Unresolved evidence

Earlier CL, Dart VM/compiler, Flutter analyzer and build failures are preserved in the local evidence manifest. A corrected archive of the preceding `df96162` sources builds successfully with the same Dart SDK; current sources later compile and pass unchanged. These results do not establish a tooling root cause or fix. No automatic failure suppression, test-runner retry, SDK upgrade or global compiler setting was introduced. Passing application checks and separately successful restoration do not make their failed wrapper runs successful.

Individual status observation, further native error/cleanup cases, physical pack values/hotplug, architecture coverage, Apple collectors and the full SDK acceptance matrix remain required. Worker execution preserves caller deadlines and progress; it does not provide native-crash containment or zero process overhead.
