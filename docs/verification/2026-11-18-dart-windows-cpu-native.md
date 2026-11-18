# Dart and Flutter Windows CPU native boundary — 2026-11-18

This follow-up extends the [CPU upload checkpoint](2026-11-18-upload-storage-cpu.md) with a reproduced empty-list defect, seventeen native-boundary scenarios and fresh installed-Pub application evidence. The full [implementation scope](../implementation-status.md) remains unfinished.

## Reproduced defect and correction

When the CPU-set sizing query returned ERROR_INSUFFICIENT_BUFFER with zero required bytes, the SDK reported `availableLogicalProcessorCount=null` despite having a valid process affinity and no default CPU-set selection. The public get test reproduced this before the change; `.tools/cpu-empty-sets-red.log` records the unexpected null.

[GetSystemCpuSetInformation](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-getsystemcpusetinformation) documents zero returned length when no CPU sets exist and insufficient-buffer status for null-buffer sizing. The bounded query helper now accepts this empty sizing response only where empty data is allowed. An empty topology is still rejected, and an actual access-denied response with zero length still yields an unavailable field. This permits the existing affinity-only path without treating arbitrary native failures as empty success.

The change does not alter the public API, timeout settings, polling behavior or native process policy. A later ordinary response recovers in the same context. Topology and other independently readable fields remain available when CPU-set data fails.

## Native-call scenarios

The C fixture uses installed Windows SDK declarations and the production FFI/error-capture path. The existing internal CPU library binding selects it inside a retained child process; public `DeviceAccess.native()` continues using system APIs. No registry value, real CPU policy or process-wide library binding is changed by this fixture.

| Cases | Count | Public behavior checked |
|---|---:|---|
| Empty CPU-set sizing result, failed empty CPU-set query, invalid empty topology | 3 | Valid emptiness preserves affinity; failed data stays null; mandatory topology data is not fabricated. |
| Unsigned affinity/topology including logical bit 63 | 1 | Four logical processors, two cores, one package and three process-available processors survive the native-to-Dart boundary. |
| Duplicate core membership, truncated topology, excessive required size, failed topology with populated output | 4 | Invalid topology is rejected; independent active-count/availability fields survive; excessive sizing is rejected before its allocation. |
| Unknown CPU-set flag bits | 1 | Availability becomes null while independent topology remains readable. |
| Held topology, affinity, default CPU sets and system CPU sets | 4 | Host timer progress and read timeout precede native return; an open context recovers afterward. |
| Cancellation, context disposal, initial watch and subsequent polled watch during a held native call | 4 | Cancellation stays distinct from timeout; public completion does not join native work; released native buffers are reclaimed. |

These seventeen scenarios run in both JIT and CLI-bundle execution, producing 34 verified child reports. Every held case records a different native worker thread, host timer progress, public completion before native return and zero buffers after collection or completed disposal. The C hold has a six-second fail-safe; the parent retains and validates each child's process handle and terminal exit, with its own eight-second bound.

A preliminary disposal report observed zero buffers between native operations and later saw two buffers as the read continued. The fixture now forwards the real collector's `dispose()` through the existing public collector seam and reports when that cleanup has finished. It waits for that signal before asserting disposal resource counts. SDK disposal remains nonblocking; this correction changes the verifier, not the SDK lifetime contract. A separate fixture declaration-order compile error was corrected before final verification and is not counted as a reproduced SDK defect.

These controlled calls establish the tested boundaries only. They do not prove physical driver fault isolation, crash containment or a universal UI latency bound.

## Current verification

| Command | Result |
|---|---|
| `./tools/test-dart.ps1` | Clean analysis; **121/121 JIT** and **121/121 CLI-bundle** checks; negative browser boundary passed. |
| `./tools/build-flutter-packages.ps1 -Platform Windows` | Real Pub archive download into the hosted cache; separate consumer analyzed and built with the production Windows asset. |
| `./tools/test-flutter-windows.ps1 -ExampleRoot .tools/flutter-windows-installed` | **16/16 actual installed-consumer scenarios**; ordinary entrypoint rebuilt after the fixture. |
| `./tools/test-flutter-windows.ps1` | **16/16 actual checkout application scenarios**; ordinary entrypoint rebuilt. |
| `./tools/test-flutter.ps1` | **27/27 framework checks**, with clean package analysis. |

Both application consumers compare all six readable CPU fields against the independent native reference and exercise equal-value polling with fresh timestamps. CPU SoC fields remain null. Storage, screen observations and the existing held-isolate deadline/window-callback checks remain included. The standalone aggregate also retains the four real child-process CPU-policy scenarios from the preceding checkpoint, independently of the new synthetic native-response fixture.

The local package fixture rebuilds development version 0.1.0 archives for a fresh loopback Pub origin. Pub's changed-content warning for the prior lock is preserved in the package build log; the newly downloaded archive hashes and installed runtime sources are checked against the current build. No public registry release occurs. Production application directories include the Windows helper and exclude the native test/reference/control DLLs.

Local records remain under ignored `.tools/`: `cpu-empty-sets-red.log`, `cpu-empty-sets-green.log`, `cpu-native-boundaries-final.log`, `dart-cpu-native-final.log`, `flutter-cpu-native-packages.log`, `flutter-cpu-native-installed.log`, `flutter-cpu-native-checkout.log` and `flutter-cpu-native-framework.log`. Actual app reports are `flutter-windows-viewport-ac66446bdf544ae8a693182edcb3b473.json` (installed) and `flutter-windows-viewport-b7c4c45de8e64c3fa45fca53a32a2fcf.json` (checkout). Source tests and reproduction scripts are kept in Git.

## Remaining scope

This closes the preceding checkpoint's installed Windows CPU-consumer gap for these artifacts and adds specific native-failure/stall coverage. Further native growth/race combinations, multiple processor groups/packages, actual reservations, WOW64/ARM64, physical hot-plug and the complete version/platform matrix remain pending. Android/browser application runtimes, .NET, Kotlin and Swift were not rerun for this Windows Dart change. Apple collectors and other incomplete SDK bindings/fields remain required by the full design.
