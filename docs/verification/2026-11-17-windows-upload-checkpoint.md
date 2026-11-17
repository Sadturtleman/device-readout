# Windows collector upload checkpoint — 2026-11-17

This checkpoint includes the Dart and Flutter Windows Runtime, Os and DeviceInfo additions, their native reference probes and application tests, and a new partial-field registry test. It preserves the full design and the remaining implementation matrix; it is a development checkpoint, not a completed SDK release.

## Upload-time verification

`./tools/test-dart.ps1` completed successfully against the uploaded source, with Dart 3.13.7 from Flutter 3.47.9 on Windows x64:

| Check | Result |
|---|---|
| Dart analysis | No issues |
| JIT contracts | 59/59 |
| Compiled native contracts | 59/59 |
| Negative web boundary | Passed |
| Child registry fixture | Parent readings unchanged; owned key removed and absence verified in both modes |

The preceding [DeviceInfo checkpoint](2026-11-17-dart-windows-device-info.md) records 10/10 actual Flutter Windows release-app scenarios and 24/24 framework checks for these collectors. Those Flutter checks were not rerun for the subsequent test-only registry fixture. Android, browser application, Swift and .NET suites were not rerun for this upload. Local upload-time evidence is in `.tools/github-upload-dart-check.log`; generated artifacts and logs are excluded from Git.

## Partial-field registry coverage

The separate test DLL creates a uniquely named volatile HKCU subtree. Only an owned child process calls `RegOverridePredefKey` to map its own HKLM reads to that subtree. The test exercises the public SDK against a wrong-type manufacturer, a readable model and a missing board, requiring null for the unreadable fields while retaining the model. The parent compares its real DeviceInfo before and after the child, waits for child termination, and removes only the exact fixture key after checking its PID and nonce ownership markers. The fixture then verifies that key is absent. Production SDK code neither overrides registry mappings nor writes registry values.

The initial JIT fixture exposed a launcher PID mismatch: `dart.exe` delegated execution to another process. SDK assertions had passed, but fixture ownership validation failed. The test now retains `dartvm.exe` directly for JIT and its own executable for compiled runs. The earlier test-owned key was removed using the same exact-marker cleanup. The final complete suites pass with matching child PIDs and verified cleanup.

Native encoding, size/growth races, all-source failure, other DeviceInfo field mappings, ARM64/emulation, further hardware/OS versions, Apple collectors, remaining framework platforms and the full acceptance matrix remain pending. No new production behavior was added solely for the registry fixture.
