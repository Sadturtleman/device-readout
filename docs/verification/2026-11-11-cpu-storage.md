# CPU and storage verification — 2026-11-11 (Asia/Seoul)

This checkpoint adds CpuCore and StorageVolume and extends Cpu's native model/topology fields. Android now has sixteen state collectors and thirteen sensor kinds (29 entities). The complete SDK remains in progress; this count does not mean every field is available on every device.

## Evidence

| Case | Observed result |
|---|---|
| Build | AAR and instrumentation APK assemble; Android lint reports no issues. The unchanged fourteen-test JVM suite remains passing/up to date |
| CPU discovery before implementation | API 36 public cpuCores.list() test fails with Discovery unavailable |
| CPU discovery/read/polling after implementation | API 26/36: exactly the two configured virtual CPU targets, logical indices 0/1, online state, typed reads and two polling snapshots; current() is null |
| CPU aggregate data | Both guests report two logical CPUs, two physical core groups and two processor packages. Model/vendor and API 31+ SoC fields use their native sources. These are guest OS reports, not host-hardware topology |
| App storage before implementation | API 36 public storageVolumes.current() test fails because no app-data target exists |
| App storage after implementation | API 26/36: current points to the app-data volume; total bytes match Android StatFs; free/caller-available bytes remain distinct; allocation availability is present; unknown quota/important/opportunistic fields stay null; two polling snapshots pass |
| Multiple storage views | Both guests expose private app storage and primary shared storage. After fixture cleanup both return two targets again |
| Native storage hotplug | API 26/36: real loop-backed virtual SD card, native unmount event ends the original watch with EntityRemoved while polling is 30 seconds; remount produces a usable new target and the old target still returns EntityRemoved |
| Basic Android regression | API 26/36 basic OS/memory/runtime/identity/power/battery/sensor and app-observer display checks pass. Deliberately blocking collector test still records 17 main-Looper ticks while its read deadline remains responsive |

CpuCore's current/maximum frequencies come from kernel CPUFreq files in kHz and are converted to Hz. API 26's fixture exposes neither and returns null. The API 36 virtual driver reports current frequencies exceeding its reported maximum; the SDK preserves those separate values rather than clamping them. These virtual results do not validate physical clock accuracy.

## Semantics and execution

Present CPUs define discovery, online membership defines the online field, and Runtime.availableProcessors defines process availability. Target identity uses the native index/device/inode and records observed removal. Offline alone is not removal. Topology fields with negative/unavailable values are null; aggregate counts require complete source data. No CPU control file is written.

Storage targets represent mounted app-visible views. The private-data target is selected from applicationInfo.dataDir without creating a files directory. Shared volumes use public StorageManager paths or actual mount points matched through getStorageVolume on older APIs. Shared/private views can have the same backing disk and must not be summed as distinct physical capacity. fileSystem reports the visible filesystem; both virtual-card tests report fuse, without guessing an underlying format.

statvfs provides separate filesystem total/free/caller-available byte counts and a read-only flag. getAllocatableBytes contributes only its own field and runs on the collection worker. The SDK does not call allocateBytes, create directories, start storage UI, infer encryption/case sensitivity, or substitute cache quota for total caller capacity. Storage callbacks use their own HandlerThread and enqueue deferred reads with the configured deadline. Capacity changes use polling in addition to mount-state broadcasts.

## Reproduction and fixture ownership

Run `tools/build-android.ps1 -SdkRoot <installed-sdk>`, then `tools/test-android-device.ps1` with modes `cpuContracts`, `storageContracts`, `storageHotplug` and `all`:

| AVD | Serial |
|---|---|
| DeviceReadout_API26 | emulator-5582 |
| DeviceReadout_API36 | emulator-5586 |

The storage helper independently verifies the exact project AVD name, rejects any pre-existing removable disks or enabled virtual-disk setting, enables Android's test virtual disk, and requires exactly one newly created Linux loop device (major number 7) before partitioning it as public storage. It only unmounts/remounts that new volume. Cleanup disables the test virtual disk even when assertions fail. No user/physical disk is formatted. Test output requires explicit passed status and final instrumentation code -1.

Raw output is under ignored `.tools/DeviceReadout_API<level>-cpuContracts-results.txt`, `...-storageContracts-results.txt` and `...-storageHotplug-results.txt`. Lint reports are under `kotlin/android/build/reports`; JVM XML remains under `kotlin/core/build/test-results/test`.

Cleanup was verified on both AVDs: persist.sys.virtual_disk=false and an empty sm list-disks result. Only the two exact-name project AVDs were then stopped.

## Remaining acceptance work

Physical removable/adopted storage, ARM CPU layouts, CPU offline/online/hotplug and the full supported API matrix are not established by these x86_64 virtual tests. Rapid unobserved removal/reappearance can reuse mount IDs or sysfs identities and needs additional lifecycle tracking; the current tests prove observed removal/remount handling. Namespace/permission changes, read-only volumes, quota-specific storage and sustained churn need further coverage.

Android Wi-Fi/current data RAT, eligible restricted identifiers and six sensor kinds remain. Browser/Windows completion, Swift/Apple, Flutter/RN, package consumption and the complete acceptance matrix remain required. No cross-platform completion claim is made.

Native contracts: [CPU topology](https://docs.kernel.org/admin-guide/cputopology.html), [CPUFreq attributes](https://docs.kernel.org/admin-guide/pm/cpufreq.html), [StorageManager allocation and volume APIs](https://developer.android.com/reference/android/os/storage/StorageManager), [StorageVolume metadata](https://developer.android.com/reference/android/os/storage/StorageVolume), [statvfs](https://developer.android.com/reference/android/system/StructStatVfs), [mount ID reuse](https://www.kernel.org/doc/html/latest/filesystems/proc.html), [Android virtual disk testing](https://developer.android.com/training/data-storage/app-specific).
