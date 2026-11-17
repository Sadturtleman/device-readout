# Dart Windows registry boundaries — 2026-11-18

The public Windows DeviceInfo test exposed a real boundary defect: a terminated REG_SZ occupying 65,536 bytes was returned as null because the native size-only query reported 65,538 bytes. The collector now allows the extra UTF-16 sizing allowance, attempts a read with its unchanged 64 KiB allocation limit, and validates the actual returned byte count. A value that requires more than the bounded buffer remains null; a failed read at the maximum capacity is not retried with a larger allocation.

## Evidence and behavior

The independent test DLL writes a volatile HKCU subtree and installs a process-local HKLM override only in an owned child. Tests call public `DeviceAccess.native().get(Entities.deviceInfo)` and `watch(Entities.deviceInfo)` against actual Win32 registry APIs; they do not invoke or replace private SDK methods. Parent DeviceInfo readings are compared before and after, and fixture keys are deleted only after PID/nonce ownership checks and child termination.

| Case | Verified behavior |
|---|---|
| Wrong type and missing value | Unreadable manufacturer/board stay null; readable model survives |
| Unicode and empty strings | Korean, an emoji surrogate pair, accented text and an empty string retain their values |
| Malformed UTF-16 | Unpaired high and low surrogates become null without losing the independent board field |
| Termination and odd length | OS-repaired terminator and zero-length stored value become valid strings; odd byte length is null |
| Size boundary | A terminated 64 KiB value is accepted; a 65,538-byte value and an unterminated 64 KiB value are null |
| Existing watch recovery | The same stream recovers from unreadable to Unicode/empty fields, retains equal-value deliveries and increasing timestamps, and leaves old snapshots unchanged |

The size test failed before the production fix. Its independent `RegQueryValueExW`/`RegGetValueW` measurements reported 65,536 stored bytes and a 65,538-byte sizing result in both final execution modes. Microsoft documents that [RegGetValueW checks and can supply string termination](https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-reggetvaluew); the exact extra size-query allowance above is observed evidence from this host, not a guarantee for every Windows build. The other new behavior checks passed without requiring production changes. A diagnostic typo in the termination test initially prevented compilation; correcting that fixture was not an SDK defect.

## Verification

Windows x64 build 10.0.26300.0, Dart 3.13.7 and Flutter 3.47.9. The local date is November 18; report timestamps remain UTC on November 17.

| Check | Result |
|---|---|
| Dart analysis | No issues |
| Dart JIT / compiled native contracts | 64/64 in each mode |
| Registry scenarios | Six per mode; twelve child terminations, unchanged-parent checks and verified key removals |
| Negative web boundary | Passed |
| Actual Flutter Windows release application | 10/10 |
| Flutter package/example analysis and framework tests | Clean analysis; 24/24 |
| Final fixture inspection | No DeviceReadoutTest registry keys or verification executables remain |

The Flutter DeviceInfo watch delivered three snapshots while its host timer advanced eight times. The existing controlled held-collector scenario retained the caller deadline and native window callback, with 50 host timer ticks and one native metrics callback in that scenario. Collection, decoding and native resource cleanup still belong to the SDK isolate. This does not establish zero host overhead, process crash isolation, actual stalled-registry-call behavior or a universal frame-time bound. The regular example was rebuilt after testing and contains neither test probe DLL.

```powershell
./tools/test-dart.ps1
./tools/test-flutter-windows.ps1
./tools/test-flutter.ps1
```

Evidence: `.tools/registry-size-red.log`, `.tools/registry-size-green.log`, `.tools/dart-windows-registry-final.log`, `.tools/flutter-windows-registry-final.log`, `.tools/flutter-windows-registry-framework.log`, `.tools/flutter-windows-viewport-a3d94b39330e4723af95bbc98370f77e.json` and `.tools/evidence/dart-windows-registry-checkpoint.json`.

Concurrent size-growth races, all-source failure, access-denial/allocator failures, remaining DeviceInfo fields, ARM64/emulation, further hardware and Windows versions, external consumers, Apple collectors and the complete 46-entity/binding acceptance matrix remain pending. Android, browser application, Swift and .NET suites were not rerun. This checkpoint is local work after the latest GitHub upload.
