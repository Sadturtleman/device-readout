# Windows aggregate battery upload checkpoint

This development snapshot includes the design, implementation and verification records available on 2026-11-19. The full 46-entity, language, framework and platform acceptance matrix remains unfinished. No packages are published by this upload.

Subsequent verification completes the previously pending installed-package gate; see the [aggregate battery follow-up](2026-11-19-dart-windows-aggregate-battery.md). The separate [C# capacity correction](2026-11-19-dotnet-aggregate-capacity.md) also reproduces and fixes negative aggregate energy. The evidence below preserves the original upload cutoff.

## Implementation included

Dart and Flutter Windows add the operating system's logical aggregate battery through `current(Entities.battery)`, followed by typed `get(target)` and `watch(target)`. The aggregate handle remains stable when no battery is present. Individual battery enumeration, individual-pack reads and interface hotplug are not implemented in this Dart collector; `list(Entities.battery)` remains unsupported.

| Field | Aggregate mapping |
| --- | --- |
| `present`, `state`, `charging` | WinRT BatteryReport status. NotPresent returns `present=false` and clears stale battery values; an unrecognized status remains null. |
| `level` | Remaining capacity divided by positive full-charge capacity, with common ratio validation. |
| `chargeRateMilliwatts` | Nullable signed native rate; discharge can remain negative. |
| `remainingEnergyMilliwattHours`, `fullChargeEnergyMilliwattHours`, `designEnergyMilliwattHours` | Nullable native capacities; negative capacities become null and valid zero is preserved. |
| `timeToEmpty` | Optional known GetSystemPowerStatus battery lifetime, excluding explicitly online AC and explicitly absent battery. |
| Other aggregate fields | Null; no substitute voltage, current, temperature, chemistry, health, cycles or time-to-full is manufactured. |

The native bridge collects and releases references on the collection isolate. Watch performs an initial read, shares `ReportUpdated` observation and retains serial polling with equal-value delivery and fresh snapshot completion times. Unsupported native registration falls back to polling; other failures remain typed and terminal. Failed native unregister retains the resources needed for explicit recovery, with detached callback tokens preventing late delivery.

Screen, permission and lifecycle inputs remain application-owned observations. The collector does not request permission or change device settings. Held native work does not make public timeout, cancellation or disposal wait for native return; this is not a claim of native-crash containment or zero shared-resource overhead.

## Verification available at upload

The 564 non-Markdown source inputs match the capture taken before the final Dart and Flutter verification runs. No production or test source changed while preparing this upload.

| Scope | Result |
| --- | --- |
| Dart analysis and contracts | 235/235 in both JIT and CLI-bundle modes; negative web-boundary check passes. |
| Native battery scenarios | Fifteen child-process scenarios per mode, including sixteen field fixtures and five whole-read failure cases. All thirty reports pass. |
| Held calls and cancellation | Eight scenarios per mode verify caller progress, independent-context RAM reads and public completion before native return. |
| Shared observation and cleanup | One registration serves two consumers with independent lifetimes. Persistent unregister failure deliberately retains native ownership rather than reporting it freed. |
| Flutter framework | 27/27 checks pass. |
| Checkout Windows application | The complete script passes 22/22 scenarios and restores the ordinary example. Battery checks agree with eight stable independent C++/WinRT reference fields, receive three snapshots and record UI timer progress. |
| Installed-package consumer | **Pending for this battery addition.** Fresh archives, installed-source parity and the installed Windows application have not been rerun. Earlier Wi-Fi package results do not validate the new battery files. |

The physical host reports no battery. The real application therefore verifies absence and null-field behavior, not physical charge/discharge values or transitions. Positive values, malformed responses, errors, native events and stalls are covered by controlled native fixtures.

The completed [Wi-Fi follow-up](2026-11-19-dart-windows-wifi.md) is also included: that earlier source snapshot passed 219/219 Dart checks per mode, both complete Windows consumers at 21/21 and Flutter framework checks at 27/27, with installed-source parity.

## Preserved failures and remaining work

Earlier runs failed in an existing network `unknown-prefix` native child, a Dart compiler `BinaryBuilder.readStringTable` path and the Microsoft C++ compiler's `c2.dll`. The network child subsequently passed unchanged in isolation; the final full Dart gate and checkout Windows script also passed. These later successes do not establish a root cause or a tooling fix. Failure logs and Windows crash records remain locally preserved under `.tools/`.

The negative-capacity fixture reproduced a Dart aggregate-field bug and now passes after filtering invalid energy values. The corresponding C# aggregate path still needs a dedicated reproduction and parity check. Individual Dart battery inventory, hotplug, physical battery transitions, additional architectures, Apple collectors and the complete cross-platform acceptance matrix remain outstanding.

For the pending installed-consumer checks, run `tools/build-flutter-packages.ps1 -Platform Windows`, then `tools/test-flutter-windows.ps1 -ExampleRoot .tools/flutter-windows-installed`. The existing source checks are `tools/test-dart.ps1`, `tools/test-flutter.ps1` and `tools/test-flutter-windows.ps1`.

The repository includes source, fixtures, test runners and this status record. Downloaded tools, local caches, raw logs, credentials and generated binaries are excluded from this upload.
