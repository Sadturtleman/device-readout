# Dart and Flutter Windows CPU cores — 2026-11-18

The eleventh standalone Windows collector kind, `CpuCore`, now provides typed discovery, get/watch, native core/package membership and available clock fields. It uses the existing DeviceAccess API and collection isolate. This extends the [CPU native-boundary checkpoint](2026-11-18-dart-windows-cpu-native.md); the full [implementation scope](../implementation-status.md) remains unfinished.

## Public use and fields

```dart
final access = DeviceAccess.native();
final cores = await access.cpuCores.list();
final snapshot = await access.get(cores.first);
final samples = access
    .withPollInterval(const Duration(milliseconds: 500))
    .watch(cores.first);
```

The caller handles an empty or failed discovery before selecting a target. Handles belong to their DeviceAccess context and keep the same lifetime across immutable configuration views. `cpuCores.current()` has no inferred native default: the collector's executing thread does not identify an application's preferred CPU. Applications can explicitly select a returned handle through `access.observers.current(Entities.cpuCore, target)`.

| Field | Windows mapping |
|---|---|
| `logicalIndex` | Processor group number × 64 + the bit index in its native affinity mask. |
| `coreIndex` | Physical-core relationships ordered by their smallest logical index. |
| `packageIndex` | Processor-package relationships ordered by their smallest logical index; null if that relation is unavailable. |
| `online` | True for processors in the current native topology. Observed disappearance retires the target rather than returning an invented offline snapshot. |
| `currentClockHz` | `PROCESSOR_POWER_INFORMATION.CurrentMhz` × 1,000,000. |
| `maximumClockHz` | `PROCESSOR_POWER_INFORMATION.MaxMhz` × 1,000,000. |

[GetLogicalProcessorInformationEx](https://learn.microsoft.com/en-us/windows/win32/api/sysinfoapi/nf-sysinfoapi-getlogicalprocessorinformationex) supplies processor relationships. The existing CPU-count parser now retains the validated membership graph for per-target reads; `Cpu` counts and `CpuCore` mappings share the same interpretation. Indices describe the current topology and are not permanent hardware identifiers.

Clocks use read-only [CallNtPowerInformation](https://learn.microsoft.com/en-us/windows/win32/api/powerbase/nf-powerbase-callntpowerinformation) with ProcessorInformation. [PROCESSOR_POWER_INFORMATION](https://learn.microsoft.com/en-us/windows/win32/power/processor-power-information-str) defines the system processor number, specified maximum frequency and throttle-derived current frequency. The SDK uses the returned Number field instead of array position and does not substitute MhzLimit for either clock field.

Power records expose no processor group. Clock mapping therefore requires a single processor group and a contiguous zero-based topology of at most 64 logical processors. Sparse or multi-group topology remains readable with clock fields null. A failed or malformed power response also leaves only the clock fields null; zero and full-width unsigned MHz values remain valid numeric data. The tested process is Windows x64; WOW64 topology is unsupported and ARM64 execution remains unverified.

## Reproduction and native boundary

Three red cases were recorded before their corrections:

- `cpuCores.list()` returned UnsupportedEntity before this collector was implemented (`.tools/cpu-cores-red.log`).
- Core topology was initially readable while both clock fields remained null; known native clock records exposed the missing mapping (`.tools/cpu-core-clock-red.log`).
- Native topology access denial was reported as generic ReadFailed. The query helper now preserves PermissionDenied for whole inventory/target failure (`.tools/cpu-core-denial-red.log`); unrelated malformed data remains ReadFailed.

The C fixture is selected only through the existing internal native-adapter binding in an owned child. It supplies Windows SDK ABI responses through production FFI calls without changing actual CPU policy or replacing system libraries.

| Native scenarios | Count | Behavior |
|---|---:|---|
| Reordered clock records, failed calls with populated output, duplicate/out-of-range Number, zero and unsigned maximum MHz | 6 | Exact field mapping and units; failures stay nullable without corrupting topology. |
| Sparse indices including bit 63, synthetic two-group topology | 2 | Logical identity and membership remain correct; ambiguous clock mappings stay null. |
| Observed CPU removal/reappearance | 1 | Existing watch fails with EntityRemoved; current selection clears; the replacement gets a new handle generation and the old handle never revives. |
| Malformed and permission-denied inventory | 2 | Typed list/read failures preserve known handles; ordinary reads recover after the source recovers. |
| Held native clock query during get and initial watch | 2 | Public timeout finishes before native return, host timers progress on a separate thread, subsequent reads recover and buffers are released. |

Each of these thirteen cases runs in JIT and CLI-bundle mode. The four held-clock reports show public completion before native return and zero native buffers after recovery. Existing CPU, storage, registry, observer and sensor gates remain in the aggregate. The fixtures do not establish physical CPU hot-plug, native crash containment or universal UI timing guarantees.

## Independent native and application verification

An independent C probe queries core and package relationships separately through Windows SDK structures and compares their membership graph with every SDK target. It also reads native processor power records. On this host all 32 logical processors map to 24 physical cores and one package. Native maximum clock values agree for all targets. Live current clocks are sampled at different instants and are checked for valid native units; controlled fixtures separately verify their exact mapping.

Both actual Flutter Windows consumers perform full membership comparisons, typed target/current/capability checks and three polling snapshots while a host timer progresses. Existing screen and held-isolate checks remain included. These reference probes run only in verification applications and are not part of SDK get/watch.

| Command | Result |
|---|---|
| `./tools/test-dart.ps1` | Clean analysis; **135/135 JIT** and **135/135 CLI-bundle** checks; negative browser boundary passed. |
| `./tools/test-flutter-windows.ps1` | **17/17 checkout Windows application scenarios**; ordinary entrypoint rebuilt afterward. |
| `./tools/build-flutter-packages.ps1 -Platform Windows` | Separate hosted-Pub consumer analyzed and built from newly prepared archives. |
| `./tools/test-flutter-windows.ps1 -ExampleRoot .tools/flutter-windows-installed` | **17/17 installed-consumer scenarios**; ordinary entrypoint rebuilt. |
| `./tools/test-flutter.ps1` | Clean analysis and **27/27 framework checks**. |

Local logs are `.tools/dart-cpu-cores-final.log`, `flutter-cpu-cores-checkout.log`, `flutter-cpu-cores-packages.log`, `flutter-cpu-cores-installed.log` and `flutter-cpu-cores-framework.log`. Actual application reports are `flutter-windows-viewport-8b276a042cf642848884045c33403a1d.json` (checkout) and `flutter-windows-viewport-a9ec47c5c19844cdaff9a8ab05c66584.json` (installed). Build artifacts and raw logs stay excluded from Git. No public package release is performed.

Physical topology changes, actual multi-group/package machines, more native growth/race combinations, ARM64, and the full OS/framework version matrix remain pending. Android/browser applications, .NET, Kotlin and Swift were not rerun for this Windows Dart collector. Remaining platform collectors and bindings continue to be required by the full design.
