# Dart and Flutter Windows storage — 2026-11-18

The initial storage collector preserved in the [upload checkpoint](2026-11-18-upload-power-storage.md) is now covered by the aggregate Dart runner, an independent native reference and the actual Flutter Windows release application. Dart passes 70/70 checks in both JIT and compiled execution; the Windows app passes 15/15 scenarios; Flutter framework tests pass 27/27. This checkpoint adds verification and formats the existing collector; it does not claim a newly reproduced SDK defect.

## Public contract and field mapping

```dart
final access = DeviceAccess.native();
final volumes = await access.storageVolumes.list();
final selected = volumes.first; // The application chooses an appropriate handle.
final snapshot = await access.get(selected);

access.observers.current(Entities.storageVolume, selected);
final updates = access
    .withPollInterval(const Duration(seconds: 2))
    .watch(selected);
// Subscribe to updates; cancel the subscription and dispose access when finished.
```

Local volume GUIDs are internal identities; callers receive typed, context-owned handles. Repeated successful discovery preserves unchanged handles. Collection checks presence before and after reading. No application storage location is guessed: native `current()` is null until the app supplies its selection. A handle from another context is rejected.

| Snapshot field | Native source and meaning |
|---|---|
| `name`, `fileSystem`, `readOnly` | Metadata from a read-only root handle and `GetVolumeInformationByHandleW`; `FILE_READ_ONLY_VOLUME` determines read-only state. |
| `totalBytes` | `DISK_SPACE_INFORMATION.ActualTotalAllocationUnits` multiplied by its sector/allocation-unit sizes, with unsigned overflow bounds. This is the capacity before caller quota limits. |
| `freeBytes` | `GetDiskFreeSpaceExW` total free bytes for the volume. |
| `totalBytesForCaller`, `availableToCallerBytes` | The same API's separate caller-limited capacity and available bytes. |
| `removable` | `GetDriveTypeW`: removable is true, fixed is false, other kinds are null. |
| `encrypted`, `caseSensitive`, `availableForImportantUsageBytes`, `availableForOpportunisticUsageBytes`, `allocatableBytes` | Null in this collector. File-system feature support is not substituted for current encryption or per-directory case behavior. |

The capacity distinction follows the documented [disk-space structure](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/ns-fileapi-disk_space_information) and [free-space outputs](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-getdiskfreespaceexw). Metadata uses the [handle-based query](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-getvolumeinformationbyhandlew). Local volume enumeration is not a claim of mapped network-share discovery.

Binding, native calls, allocation, decoding and cleanup stay on the collection isolate. Reads change no OS storage setting or global error policy. Serial polling retains equal values and completion timestamps. The reference DLL is test-only; the normal application and SDK do not depend on it.

## Independent reference and observed results

`tools/windows-memory-probe/storage.c` is compiled against Windows SDK 10.0.26100.0 declarations and links no SDK code. It selects the Windows directory's volume for verification only, obtains native counts/metadata and separately enumerates the volume inventory. A shared test helper loads the probe in Dart and the Flutter fixture.

The host reported three local volumes. The independently queried system volume reported an empty label, NTFS, 999115714560 total bytes, the same current caller capacity, and false read-only/removable flags. The SDK matched those stable fields. The native disk-space structure was 96 bytes. Live free/available values were collected independently and recorded; tests check their presence and capacity bounds rather than require equality across separate reads. These runs had no configured caller quota difference, so they do not prove quota-limited behavior on hardware.

The public tests also check stable handles, explicit current selection, foreign-context rejection, advertised capabilities, and initial plus two polled snapshots with fresh timestamps. Enumerated protected volumes can return PermissionDenied; at least one snapshot matching the independently queried system volume is required. Denial is not silently treated as a successful snapshot.

| Command | Result |
|---|---|
| `./tools/test-dart.ps1` | No analysis issues; 70/70 JIT and 70/70 compiled checks; web boundary check passed. |
| `./tools/test-flutter-windows.ps1` | No analysis issues; 15/15 actual release-app scenarios; ordinary example rebuilt after the test host exited. |
| `./tools/test-flutter.ps1` | No analysis issues; 27/27 framework checks. |

The Windows report is `.tools/flutter-windows-viewport-0a63e0e6ff414e01a6b75b26981a15d1.json`. Logs are `.tools/dart-storage-full.log`, `.tools/flutter-windows-storage.log`, and `.tools/flutter-storage-framework.log`. The source/artifact audit is `.tools/evidence/dart-windows-storage-checkpoint.json`. Local evidence/build artifacts remain ignored by Git; source tests and reproduction commands are tracked.

The first reference rebuild in the restricted environment failed with LNK1114/error 5 while overwriting its existing import library. The unchanged build and test passed in the ordinary-user environment. This was a build-environment failure, not a reproduced SDK defect. The earlier registry-child Dart compiler abort remains recorded in the [time-zone checkpoint](2026-11-18-dart-windows-time-zone.md); it did not recur here and its cause is not established.

## Remaining scope

Actual Flutter polling retained host timer progress. The existing controlled held-isolate scenario also retained 50 timer ticks, one native window callback and an independent host deadline. These checks do not establish a bound for real stalled storage drivers, zero host overhead or process crash isolation.

Native failures, malformed/unterminated optional metadata, immediate native error capture, removal/reappearance races, sparse/quota/removable/media configurations, network-share discovery, ARM64 and installed consumer coverage remain pending. The prior storage review items are not claimed fixed by successful host reads. Apple collectors, the other remaining platform collectors and the complete SDK acceptance matrix remain unfinished.
