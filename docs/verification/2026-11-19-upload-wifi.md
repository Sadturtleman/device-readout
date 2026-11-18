# Windows Wi-Fi upload checkpoint

This development checkpoint includes the current design, implementation, tests and verification records on 2026-11-19. DeviceReadout's complete 46-entity, language, framework and platform acceptance matrix remains unfinished. The current Wi-Fi sources have not passed the complete regression and installed-consumer gates.

Subsequent unchanged-source verification completed the corrected-source Dart, both Windows consumer and Flutter framework gates. See the [Wi-Fi verification follow-up](2026-11-19-dart-windows-wifi.md). The results below preserve the evidence available at upload time, including the earlier failures.

## Implementation included

Dart and Flutter Windows add `WifiConnection`, bringing the native Windows implementation to fifteen entity kinds. Use `access.list(Entities.wifiConnection)`, `current(Entities.wifiConnection)` and typed target handles with `get(target)` / `watch(target)`. Connected WLAN profiles are identified by adapter and network GUIDs; observed removal retires the target. The preferred connection is current only when it is Wi-Fi.

| Field | Mapping |
| --- | --- |
| `ssid` | WinRT `GetConnectedSsid`, with copied and validated UTF-16 text |
| `security` | Selected native authentication/encryption mapped to the common enum; unrecognized values become null |
| `rssiDbm` | Signed signal strength from `WlanQueryInterface` using the RSSI opcode |
| `bssid`, `frequencyHz`, `receiveLinkSpeedBps`, `transmitLinkSpeedBps` | Null; no substitute values or scans |

Collection, reference cleanup and WLAN client ownership stay on the collection isolate. Watch shares native status observation with the existing connectivity collectors and retains independent polling, equal-value delivery and cancellation. The app supplies permission, screen and lifecycle observations. These collectors do not request permissions or change connection settings.

Two reproduced error cases are corrected in this upload. Failed cleanup of a retained WLAN client now leaves readable SSID/security available and RSSI null without opening another client. General inventory/open/close errors no longer masquerade as removal of a selected connection; actual query-level removal remains `EntityRemoved`.

## Verification at this upload

| Scope | Result and limitation |
| --- | --- |
| Current source identity | All 555 non-Markdown inputs match the capture taken before the latest full Dart run. |
| Current Dart analysis | No issues found. |
| Current Wi-Fi native cases | All 15 JIT child scenarios passed, including 20 authentication fixtures, 10 partial-field fixtures, four invalid inventories and shared observation. |
| Current held-call cases | Nine Wi-Fi scenarios cover held inventory, identity, SSID, security, WLAN open/query/close, cancellation and disposal. They verify caller progress, independent-context reads and public completion before native return. |
| Current cleanup/permission cases | Retained-client recovery completes with four close attempts and zero remaining clients. App-observer checks report zero implicit permission prompts. |
| Latest complete Dart gate | **Failed.** After 40 passing connectivity child reports, `persistent-unregister` exited with `-1073741819` without diagnostic output. The JIT suite did not finish and the compiled stage was not reached. The cause is unestablished; this is not classified as a compiler-only failure. |
| Earlier compiled Wi-Fi build | 219/219 contracts passed before the two corrections above. The surrounding script then failed its web-compilation step; a separate web-boundary run passed. These results do not validate the corrected sources. |
| Earlier Flutter applications | Checkout and installed Windows apps each reported 21 passing scenarios before the corrections. Both complete scripts failed while restoring the ordinary example. Separate restoration builds later succeeded. |
| Earlier Flutter framework | 27/27 passed before the corrections. Current corrected sources still require rebuilt checkout, installed-consumer and framework gates. |

The current physical host has three known profiles and zero connected Wi-Fi targets. Dart discovery agrees with an independent WinRT reference; the earlier Flutter applications agree with an independent C++/WinRT projection. This verifies empty discovery on this host, not physical SSID/security/signal values or real connection transitions. Those field paths have controlled native-fixture evidence.

## Unresolved failures and remaining verification

Separate earlier runs encountered Dart compiler failures while loading SDK metadata and Flutter `gen_snapshot` / `MSB8066` failures. An import-only probe that never invokes the SDK or its tests reproduced a compiler failure on attempt 82 after 81 successful runs. This is evidence for an independent tooling problem, not proof of the cause of the latest `persistent-unregister` crash. No failure suppression or automatic retry was added to the test runners.

The preceding [network-performance checkpoint](2026-11-19-dart-windows-network-performance.md) records its completed unchanged-source gates: 203/203 Dart contracts in each mode, 20/20 in each complete Windows consumer script and 27/27 Flutter framework checks. Those are historical results for that checkpoint.

Continue with `tools/test-dart.ps1`, `tools/test-flutter-windows.ps1`, `tools/build-flutter-packages.ps1 -Platform Windows`, the installed-consumer Windows script and `tools/test-flutter.ps1`. Investigate the latest crash and rerun the corrected-source gates before claiming complete verification. Physical connections, additional architectures, remaining fields and the full SDK matrix remain pending.

Production code, native fixtures, test runners and this status record are committed. Raw logs, compiler probes, downloaded SDKs, generated binaries and local evidence remain excluded under `.tools/`. This upload is a development snapshot, not a package release or a claim of native-crash containment.
