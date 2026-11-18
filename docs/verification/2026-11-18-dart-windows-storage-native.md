# Dart Windows storage native failures and packaging — 2026-11-18

This follow-up fixes malformed optional text and preserves Win32 errors across the Dart FFI boundary. Twenty-nine native-fixture scenarios now run through public list/get/watch in both JIT and a separately built CLI bundle. Final Dart regression passes 99/99 in each mode. Both the checkout Flutter Windows application and a separate consumer installed from Pub archives pass 15/15; framework tests pass 27/27 and Chrome/Edge each pass sixteen Dart browser scenarios.

## Reproduced failures and corrections

1. A successful metadata call returning a volume name without a terminator caused the entire snapshot to fail. `.tools/storage-text-red.log` records the ReadFailed error. The decoder now returns null for the affected optional field, retaining independent fields; the follow-up test passes.
2. An unpaired UTF-16 surrogate was returned as a name instead of null. `.tools/storage-unicode-red.log` records the failed field assertion. The bounded decoder now validates surrogate pairs. Valid Unicode and empty strings remain intact, and independently malformed file-system names receive the same treatment.
3. During the expanded fixture run, enumeration reported `FindNextVolumeW failed (Win32 0)` although the native end-of-inventory response sets ERROR_NO_MORE_FILES. `.tools/storage-fields.log` preserves this intermittent failure. Resolving GetLastError early was insufficient to preserve its thread-local value across separate FFI calls. The collector now uses a small C function to call the selected Win32 entry point and store both its result and error before returning to Dart. It does not reinterpret error zero as a successful enumeration.

Microsoft documents that the [last-error value must be read immediately](https://learn.microsoft.com/en-us/windows/win32/api/errhandlingapi/nf-errhandlingapi-getlasterror). The capture helper covers FindFirstVolumeW, FindNextVolumeW, GetDiskFreeSpaceExW, CreateFileW and GetVolumeInformationByHandleW. GetDiskSpaceInformationW continues to use its directly returned HRESULT. There is no process-wide DLL replacement, error-policy change or UI callback in production collection.

## Native fixture boundary

The C fixture is compiled against installed Windows SDK declarations. An internal adapter binding, supplied through the existing isolated collector factory, selects its library only for the storage adapter in a retained child process. Public `DeviceAccess.native()` still supplies the ordinary system binding. The internal binding is not exported from the SDK entrypoint and adds no environment-variable switch or global override.

Tests observe typed snapshots, errors, target lifetimes and streams through the public SDK. Native counters corroborate buffer, enumeration-search and directory-handle release. Each scenario runs in a separate owned child, whose PID and terminal exit are verified. A timed-out fixture child can be terminated only through that retained process handle. Real volumes, mount points, registry entries and system policy are unchanged.

| Cases | Count | Evidence |
|---|---:|---|
| Unterminated name/file system, malformed surrogates, valid Unicode/empty string | 5 | Only the invalid field becomes null; independent metadata and volume/caller capacities survive; a later valid read recovers. |
| Metadata, free-space, capacity, root-open failures and all-denied reads | 5 | Failed calls' apparently valid output buffers are ignored; partial fields remain usable; complete denial produces PermissionDenied. |
| First/partial enumeration failure, malformed and duplicate inventories | 4 | Failed inventories preserve known handles; successful subsequent collection recovers on the same generation. |
| Removal before or during collection | 2 | EntityRemoved terminates access to the old generation; reappearance of the same GUID creates a new readable handle. |
| Invalid geometry, capacity overflow, unknown drive kind, zero/maximum unsigned counts | 5 | Invalid/unrecognized values become null; valid zeros and full-width byte counts are preserved. |
| Held get, discovery, metadata, cleanup, cancellation, context disposal, initial/polled watch | 8 | Public deadlines/cancellation/disposal finish before the blocked native call returns; host timers progress; released operations free their resources; open contexts recover. |

The fixture supplies distinct unquotaed and caller capacities (8192000 and 6144000 bytes), and distinct volume/caller free counts (4096000 and 2048000). Those are controlled ABI responses, not evidence of a configured quota on the physical host. The [preceding host checkpoint](2026-11-18-dart-windows-storage.md) separately compares real current values with an independent native reference.

The held cases use native Sleep loops in the storage-call fixture. Host operations complete while the native active-call counter remains one, and the executing native thread differs from the caller thread. Each released case ends with zero tracked buffers, directory/search handles and active held calls. This proves the controlled boundary, not a universal UI latency bound or process crash isolation.

## Native asset and consumer distribution

The production helper is `dart/device_readout/src/windows_calls.c`; `hook/build.dart` builds it only for Windows using [Dart build hooks](https://dart.dev/tools/hooks). `@Native` resolves the bundled code asset. C compilation and dependency resolution happen during application builds; SDK reads do not run compilers, download libraries or launch helper processes.

Windows Dart consumers now need a supported C compiler/Windows SDK for the source build hook. The dependency constraints include code_assets and hooks, with native_toolchain_c pinned to 0.19.3 for compatibility with the selected toolchain family. Flutter Windows already requires its native desktop build tools. CLI consumers use [`dart build cli`](https://dart.dev/tools/dart-build), which bundles the executable and native library together; a lone `dart compile exe` output is no longer the supported packaging path for this SDK's Windows native asset.

`tools/test-dart.ps1` prepares a separate build-only consumer and runs `.tools/dart-checks/bundle/bin/contracts.exe` with its adjacent bundle library directory. The native fixture DLL remains outside that production bundle. Package preparation now includes `hook/` and `src/`, and the portable Windows reference helper stays inside the copied example sources.

The Windows distribution check downloads both SDK packages from a local Pub server into the hosted cache, builds the consumer from those installed packages and runs the same fifteen actual app scenarios. Its ordinary application directory contains the production `device_readout_win32.dll`, with no reference/fixture DLL. No package was published to the public Pub registry.

`dumpbin /dependents` reports only KERNEL32.dll for the validated x64 CLI helper. This inspection is recorded in `.tools/storage-native-dependencies.log`; it applies to this built artifact, not every future toolchain/architecture combination.

Android's installed-package consumer also builds successfully; its APK contains no DeviceReadout Windows DLL. This is build/package evidence only: the Android application was not rerun on an emulator or physical device in this follow-up. The existing Kotlin 2.2.20 future-support warning remains visible; dependency validation was not bypassed.

## Reproduction and records

| Command | Final result |
|---|---|
| `./tools/test-dart.ps1` | No analysis issues; 99/99 JIT and 99/99 bundled native checks; negative web boundary passed. |
| `./tools/test-flutter-windows.ps1` | 15/15 actual checkout release-app scenarios; ordinary example rebuilt. |
| `./tools/build-flutter-packages.ps1 -Platform Windows` | Separate hosted-Pub consumer analyzed and built with the production DLL. |
| `./tools/test-flutter-windows.ps1 -ExampleRoot .tools/flutter-windows-installed` | 15/15 installed-consumer release-app scenarios; ordinary consumer rebuilt. |
| `./tools/test-flutter.ps1` | 27/27 framework checks. |
| `./tools/test-dart-browser.ps1` | Sixteen scenarios per Chrome and Edge. |
| `./tools/build-flutter-packages.ps1 -Platform Android` | Separate hosted-Pub consumer APK built; Windows DLL absent. |

The final Dart log is `.tools/dart-storage-native-final.log`; it contains 58 successful child reports, including sixteen held-case reports, across the two execution modes. Windows logs are `.tools/flutter-storage-native-windows.log` and `.tools/flutter-storage-installed-windows.log`; their reports end in `e87b1446d4224a87a650a055c15f296b` and `f4c53eed2a4a4ec6b2245183f7439dae` respectively. Framework, browser and Android build logs use the `storage-native` prefix. The source/artifact audit is `.tools/evidence/dart-windows-storage-native-checkpoint.json`.

The earlier source-only helper and compiler-abort records remain historical evidence. This change resolves the three storage failures described above; it does not establish the cause of the older registry-child Dart compiler abort.

Physical storage hot-plug/reformat behavior, unobserved rapid removal/reuse, real stalled drivers, failed native cleanup, removable/media/quota combinations, mapped network-share discovery, ARM64 and Apple/mobile runtime coverage remain unfinished. Other collectors and the complete SDK acceptance matrix are still required.
