# Dart and Flutter Windows locale — 2026-11-18

Windows `DeviceAccess.native().get(Entities.locale)` and `watch(Entities.locale)` now collect the eleven Locale fields from NLS and OS ICU. The implementation was added through three public-API checks: the initial unsupported entity, missing language lists, and missing format fields each failed before its corresponding implementation. Current host values agree with independent native and .NET references.

## Field semantics

| Field | Windows native scope/source |
|---|---|
| `currentLanguageTag` | User's default formatting locale from GetUserDefaultLocaleName |
| `preferredLanguageTags` | Ordered user preferred UI language names, as validated/fallback-resolved by Windows |
| `systemLanguageTags` | Ordered system preferred UI language names, as validated/fallback-resolved by Windows |
| `appLanguageTags` | Win32 process preferred UI language list; a successful empty list means no process list is set |
| `regionCode` | LOCALE_SISO3166CTRYNAME for that locale |
| `scriptCode` | ICU language-tag parsing, likely-subtag expansion and script extraction |
| `calendar` | LOCALE_ICALENDARTYPE converted to a matching Unicode calendar identifier |
| `numberingSystem` | NLS digit-substitution preference and native digits matched to an ICU decimal numbering-system identifier |
| `hourCycle` | Unquoted `h` or `H` tokens in LOCALE_STIMEFORMAT become H12 or H23 |
| `firstWeekday` | LOCALE_IFIRSTDAYOFWEEK, with zero meaning Monday and six Sunday |
| `measurementSystem` | LOCALE_IMEASURE: metric or US, without inferring a different system from the country |

This native scope combines the user's formatting preferences with distinct user/system/process MUI lists. It does not read a Flutter widget's Localizations state or another framework's private locale override. App-local values belong to app-provided observations; a dedicated Flutter locale observer remains future integration work. The process list is not filled from the user list when empty.

[GetLocaleInfoEx](https://learn.microsoft.com/en-us/windows/win32/api/winnls/nf-winnls-getlocaleinfoex) preserves user overrides because the collector does not request LOCALE_NOUSEROVERRIDE. [User](https://learn.microsoft.com/en-us/windows/win32/api/winnls/nf-winnls-getuserpreferreduilanguages), [system](https://learn.microsoft.com/en-us/windows/win32/api/winnls/nf-winnls-getsystempreferreduilanguages) and [process](https://learn.microsoft.com/en-us/windows/win32/api/winnls/nf-winnls-getprocesspreferreduilanguages) language lists are queried separately. Their returned order is retained. The SDK validates the native count, returned length and double terminator; a failed read is re-sized from a fresh successful query instead of trusting undefined output parameters.

Calendar mapping covers Gregorian language variants as `gregory`, Japanese as `japanese`, Taiwan as `roc`, Hijri as `islamic`, Thai as `buddhist`, Hebrew as `hebrew`, Persian as `persian`, and Um Al Qura as `islamic-umalqura`. These use [Windows calendar identifiers](https://learn.microsoft.com/en-us/windows/win32/intl/calendar-identifiers) and [Unicode calendar names](https://github.com/unicode-org/cldr/blob/main/common/bcp47/calendar.xml). Other values remain null. In particular, the Korean Tangun solar era is not silently labeled as the Unicode dangi lunisolar calendar. These identifiers classify the configured calendar; the SDK does not implement date arithmetic or calendar conversion.

For [digit substitution](https://learn.microsoft.com/en-us/windows/win32/intl/locale-idigitsubstitution), no substitution selects ASCII digits; national substitution selects the native digit string. Contextual substitution with different Latin/native digits has no single identifier and yields null. Otherwise the exact ordered digits are matched against nonalgorithmic, radix-10 [ICU numbering systems](https://unicode-org.github.io/icu-docs/apidoc/dev/icu4c/unumsys_8h.html). The resulting lookup is cached only within that collection context; the current NLS preference is still read on every snapshot.

Hour extraction follows the [Windows time-format picture](https://learn.microsoft.com/en-us/windows/win32/api/datetimeapi/nf-datetimeapi-gettimeformatex), ignores quoted literals and doubled quotes, and returns null for missing, mixed or unclosed hour patterns. Unknown native enum values remain null. Optional ICU loading/conversion failures affect only script/numbering fields. If all native sources fail, the entity reports `ReadFailed`.

## Execution and verification

DLL loading, NLS calls, bounded native buffers, ICU enumeration/conversion, snapshot normalization and cleanup all run on the collection isolate. The SDK calls no locale/language setter, changes no application default, clears no global cache, and performs no UI or permission operation. State watch uses immediate first collection followed by serial polling, retaining equal values and fresh completion timestamps. Disposing a sibling context preserves the active locale and timezone collectors.

Environment: Windows x64 10.0.26300.0, Dart 3.13.7 / Flutter 3.47.9. Independent C/C++ functions use Windows SDK declarations and ICU, while a separate test-only PowerShell process compares .NET culture name, region, first weekday and calendar class. The test-only hour reference uses Windows' numeric hour-format result, independently of the SDK's format-picture parser.

| Check | Result |
|---|---|
| Dart analysis | No issues |
| Dart JIT / compiled native contracts | 66/66 in each mode |
| Current locale fields | All eleven agree with independent references |
| State watch | Three equal snapshots preserve all fields, list order and increasing completion timestamps |
| Capabilities and context lifetime | get/watch available; sibling disposal preserves live reads |
| Negative web boundary | Passed |
| Actual Flutter Windows release application | 12/12 |
| Flutter package/example analysis and framework suite | Clean analysis; 24/24 |
| Fixture inspection | No test registry keys or verification executables remain |

Observed values are `ko-KR`, user/system lists `[ko-KR, en-US]`, an empty process list, region `KR`, script `Kore`, calendar `gregory`, numbering `latn`, hour cycle H12, first weekday Sunday and metric measurement. Flutter delivers three locale snapshots while its timer advances eight times. The existing held-isolate case retains the caller deadline and native window callback, with 49 timer ticks and one callback. This does not establish zero host overhead, crash isolation, actual stalled-NLS/ICU behavior or a universal frame-time bound. The regular example was rebuilt and test DLLs are absent from its release directory.

```powershell
./tools/test-dart.ps1
./tools/test-flutter-windows.ps1
./tools/test-flutter.ps1
```

Evidence: `.tools/dart-windows-locale-red.log`, `.tools/dart-windows-locale-green.log`, `.tools/dart-windows-locale-languages-red.log`, `.tools/dart-windows-locale-languages-green.log`, `.tools/dart-windows-locale-formats-red.log`, `.tools/dart-windows-locale-formats-green.log`, `.tools/dart-windows-locale-final.log`, `.tools/flutter-windows-locale-final.log`, `.tools/flutter-windows-locale-framework.log`, `.tools/flutter-windows-viewport-544c3eedfd0341b59526e9980e83f4cb.json` and `.tools/evidence/dart-windows-locale-checkpoint.json`.

This run did not reproduce the compiler abort retained in the [preceding timezone checkpoint](2026-11-18-dart-windows-time-zone.md); its underlying cause remains unresolved. Controlled locale changes, nonempty process overrides, additional calendars/scripts/digit modes, malformed/growing native lists, native/ICU failures, ARM64/emulation, other Windows versions, framework-specific locale observations and the complete 46-entity/binding acceptance matrix remain pending. No user's settings were changed to run these tests. Android, browser application, Swift and .NET SDK suites were not rerun. These changes remain local after the latest GitHub upload.
