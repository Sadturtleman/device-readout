# Dart and Flutter Windows time zone — 2026-11-18

Windows `DeviceAccess.native().get(Entities.timeZone)` and `watch(Entities.timeZone)` now return typed TimeZone snapshots. The initial public test failed with `UnsupportedEntity`; after implementation, all four fields agree with independently compiled Windows/ICU queries on the current host. Flutter Windows uses the same Dart collector without another platform plugin.

## Field mapping

| Field | Native source and meaning |
|---|---|
| `windowsId` | `DYNAMIC_TIME_ZONE_INFORMATION.TimeZoneKeyName`; empty or malformed text is null |
| `ianaId` | OS ICU `ucal_getTimeZoneIDForWindowsID` using that Windows key and no regional preference; unavailable/unmapped results are null |
| `utcOffsetSeconds` | Negative current Windows bias in minutes, multiplied by 60; includes the standard or daylight adjustment selected by the query result |
| `daylightSavingTime` | True for native daylight state, false for standard time or no DST transitions; an unrecognized native state is null |

[GetDynamicTimeZoneInformation](https://learn.microsoft.com/en-us/windows/win32/api/timezoneapi/nf-timezoneapi-getdynamictimezoneinformation) returns the key, bias data and current DST state together. Its `TIME_ZONE_ID_UNKNOWN` value specifically means no DST transitions, so it produces false, not an unknown SDK value. The [native structure](https://learn.microsoft.com/en-us/windows/win32/api/timezoneapi/ns-timezoneapi-dynamic_time_zone_information) defines bias as UTC minus local time; the SDK exposes the opposite direction as its UTC offset.

The [ICU conversion](https://unicode-org.github.io/icu-docs/apidoc/dev/icu4c/ucal_8h.html) supplies a default equivalent IANA identifier. An app locale is not used to guess a regional variant. Conversion failure does not discard readable Windows fields. The collector resolves `icu.dll` through `GetSystemDirectoryW`, uses the combined [Windows ICU library](https://learn.microsoft.com/en-us/windows/win32/intl/international-components-for-unicode--icu-) and does not initialize COM or alter ICU's default locale/time zone.

Native query failure or inability to allocate its structure produces `ReadFailed`. Unknown result codes retain independently readable IDs while leaving offset/DST null. These failure branches are implemented but have not been exercised through controlled native failures.

## Execution and lifecycle

The collection isolate owns native library loading, the timezone structure, bounded UTF-16 buffers, ICU conversion and cleanup. Capability queries report get/watch support without loading those bindings. Ordinary state watch performs the first read immediately and then serial polling, honoring the immutable configured interval and delivering unchanged values with fresh completion timestamps.

The implementation neither changes system time-zone settings nor clears application caches. The Windows query is performed on each read; no ICU default-time-zone cache is substituted for current OS state. Closing a sibling context preserves subsequent time-zone and DeviceInfo reads in the active context. DLL reference release and native buffer disposal remain worker-owned.

## Verification

Windows x64 build 10.0.26300.0, Dart 3.13.7 / Flutter 3.47.9. The native C++ reference computes offset independently by converting the current UTC SYSTEMTIME to local time and subtracting their FILETIME values. It calls ICU through Windows SDK declarations. A separate test-only PowerShell process compares the Windows key, offset and DST state with .NET TimeZoneInfo. Production code launches no subprocess.

| Check | Result |
|---|---|
| Dart analysis | No issues |
| Final Dart JIT / compiled native suites | 65/65 in each mode |
| Current native/.NET values | `Korea Standard Time`, `Asia/Seoul`, 32,400 seconds, DST=false |
| get/watch/capabilities | Three equal readings with fresh timestamps; readable/watchable true |
| Sibling context lifetime | Live time-zone and DeviceInfo reads retained |
| Negative web boundary | Passed |
| Actual Flutter Windows release application | 11/11 |
| Flutter package/example analysis and framework suite | Clean analysis; 24/24 |
| Fixture cleanup | No test registry keys or verification executables remain |

The actual Flutter time-zone watch delivered three snapshots while its timer advanced eight times. The existing held-isolate scenario preserved the host deadline and native window callback, with 49 timer ticks and one native metrics callback. These checks do not establish zero overhead, native crash isolation, physical frame-time bounds or behavior during an artificially stalled timezone/ICU native call. The regular example was rebuilt after verification; test DLLs are not copied into its release directory.

One initial full JIT attempt aborted in the existing registry scenario 4 child, reporting `runtime_entry.cc:3477: unreachable code` in the VM's kernel-service compiler while reading SDK metadata. The parent retained the failure and removed the owned key. The same registry case passed alone, then the unchanged full sources passed JIT/native suites and Flutter checks. No retry or suppression was added to the runner. The cause of this isolated compiler abort is not established; successful reruns do not prove it resolved.

```powershell
./tools/test-dart.ps1
./tools/test-flutter-windows.ps1
./tools/test-flutter.ps1
```

Evidence: `.tools/dart-windows-time-zone-red.log`, `.tools/dart-windows-time-zone-green.log`, the preserved abort in `.tools/dart-windows-time-zone-final.log`, `.tools/time-zone-registry-jit-repro.log`, `.tools/dart-windows-time-zone-final-2.log`, `.tools/flutter-windows-time-zone-final.log`, `.tools/flutter-windows-time-zone-framework.log`, `.tools/flutter-windows-viewport-ccf334767fac46f1a562bdd5ade39f7d.json`, and `.tools/evidence/dart-windows-time-zone-checkpoint.json`.

Actual DST transitions, other timezone configurations, controlled native/ICU failures, ARM64/emulation, further hardware/OS versions, external distribution and the complete 46-entity/binding acceptance matrix remain pending. No host timezone was changed for testing. Android, browser application, Swift and .NET SDK suites were not rerun. This checkpoint remains local after the latest GitHub upload.
