# GitHub checkpoint: Windows power and initial storage collection — 2026-11-18

This checkpoint preserves the current implementation and design work. DeviceReadout remains in development; it is not a completed release or a claim that the full platform acceptance matrix passes. The [design](../design.ko.md) and [implementation ledger](../implementation-status.md) retain the overall scope.

## Included changes

- C# Windows power reads distinguish onboard-only battery capabilities from ambiguous DC/UPS status while preserving independent saver state and precise native source events.
- A separate native-call fixture exercises power structures, failed returns, actual system capabilities, deadlines and cancellation. The Wi-Fi regression test now waits for eventual native cleanup without requiring public disposal to block.
- Initial Dart Windows storage collection enumerates local volume GUIDs, binds context-owned handles and reads volume capacity, caller quota/free-space values, file-system metadata and removable status on the collection isolate. It uses the existing get/watch API and polling configuration. Applications select a current volume explicitly; the SDK does not infer one from the working directory.

## Verification at upload

| Area | Evidence | Scope |
|---|---|---|
| C# ordinary regression | 168/168 passed; zero build warnings/errors | Previously completed ordinary-user run; source and artifact hashes rechecked before this upload. |
| C# native power calls | 23/23 scenarios passed, including eight held-call scenarios | Same verified checkpoint; fixtures do not establish physical battery/UPS transition coverage. |
| Dart static analysis | `dart analyze dart/device_readout`: no issues | Rerun on the upload sources. |
| Dart storage standalone check | `dart run dart/device_readout/test/native_windows_storage.dart`: exit 0 | Rerun on this Windows host; checks discovery stability, readable fields, explicit current selection, foreign-context rejection, polling and capabilities. Protected volumes may return PermissionDenied. |

The C# evidence check matched all 19 recorded source-file hashes and ten artifact/log hashes before adding this upload note. Detailed results remain in the [power-source](2026-11-18-dotnet-power-source.md) and [native-power](2026-11-18-dotnet-power-native.md) records. Build artifacts and local logs under `.tools/` remain excluded from Git; source tests and reproduction commands are included.

## Work still in progress

The new Dart storage test is standalone and has not yet been added to the aggregate contract runner. Independent native-reference comparison, malformed/failing native calls, removal races, compiled-test coverage, actual Flutter application coverage and consumer/platform matrices remain pending for this collector. Earlier 69/69 Dart and 14/14 Flutter Windows results predate storage and must not be interpreted as storage verification.

Storage enumeration currently covers local Windows volumes, not mapped network shares. Encryption, current case-sensitivity and platform-specific allocation fields remain null. Native error capture and malformed optional-text handling still require review with fault coverage. Apple collectors, remaining bindings and the complete SDK acceptance matrix remain unfinished.
