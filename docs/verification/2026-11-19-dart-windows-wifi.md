# Dart and Flutter Windows Wi-Fi verification

This record completes the corrected-source verification that was pending in the [Wi-Fi upload checkpoint](2026-11-19-upload-wifi.md). The production and test sources are unchanged from commit `40a1496`; all 555 non-Markdown inputs match the capture taken before the latest complete Dart run. The complete DeviceReadout platform, language, version and physical-device acceptance matrix remains unfinished.

## Implemented behavior

Windows `WifiConnection` uses typed discovery, current selection and target `get` / `watch`. Connected WLAN profiles are keyed by adapter and network GUIDs, and observed removal retires a handle permanently. A preferred non-WLAN connection does not select an arbitrary Wi-Fi target.

| Field | Source and failure behavior |
| --- | --- |
| `ssid` | WinRT `GetConnectedSsid`; copied UTF-16, including a valid empty string. Malformed text or an unavailable field becomes null. |
| `security` | The selected native authentication/encryption values map to the existing common enum. Unknown values become null; supported AP modes are not substituted. |
| `rssiDbm` | Signed RSSI from `WlanQueryInterface` with the RSSI opcode. Zero is retained. Missing or denied signal access becomes null when other fields remain readable. |
| `bssid`, `frequencyHz`, directional link speeds | Remain null. This collector does not scan, query current-connection details or fabricate values. |

Native status observation is shared with NetworkPath and NetworkPerformance, with independent per-watch snapshots, polling and error lifetimes. Equal polling values remain visible. A failure terminates the affected stream; recovery requires an explicit new operation.

WLAN cleanup failures retain the client for a later explicit cleanup attempt. While cleanup still fails, SSID and security remain readable, RSSI is null and another client is not opened. Actual query-level target removal remains `EntityRemoved`; inventory/open/close errors do not falsely retire a connection. These two corrections have preserved failing-test evidence followed by passing public-API tests.

## Completed checks

| Check | Result |
| --- | --- |
| Dart analysis and complete contract runner | 219/219 JIT and 219/219 compiled CLI-bundle checks; the full script exits successfully. |
| Native connectivity cases | 41 per execution mode, including 15 Wi-Fi cases per mode. |
| Wi-Fi field and target cases | 20 authentication fixtures, 10 partial-field fixtures, four invalid inventories and three retired target lifetimes per mode. |
| Wi-Fi held-call cases | Nine per mode: inventory, identity, SSID, security, WLAN open/query/close, cancellation and disposal. |
| Shared status observation | Three Wi-Fi and three path snapshots through one registration, with independent cancellation and successful final removal. |
| Retained WLAN client | Four cleanup attempts, no additional client while cleanup fails and zero remaining clients after explicit recovery. |
| App-owned permission observations | Zero implicit prompts; fresh app state permits explicit recovery. |
| Dart web boundary | Compiles and passes the unsupported-host collection check. |
| Flutter checkout Windows application | 21/21 scenarios; complete script also restores the ordinary example successfully. |
| Flutter installed Windows application | 21/21 scenarios after building and installing fresh local archives; complete script restores the ordinary example successfully. |
| Flutter framework | Analysis and 27/27 checks pass. |
| Installed-source parity | All 40 Dart runtime/build/native files and 12 Flutter package files match the verified checkout; the four relevant consumer test-support files also match. |

Held native cases verify that the collector runs on another OS thread, the caller continues making progress, a sibling context remains readable and public timeout/cancellation/disposal completes before the blocked native call returns. Native buffers and WLAN clients are released after the calls return. The actual Windows applications retain UI timer progress. These results do not establish native-crash containment or zero process overhead.

The host currently has three known profiles and no connected Wi-Fi targets. Dart agrees with an independent WinRT reference; both actual Flutter applications agree with a C++/WinRT projection. Discovery of this empty active inventory is physical-host evidence. Nonempty inventories, SSID/security/RSSI values, connection changes and failure cases use controlled native fixtures, not a physical Wi-Fi connection.

## Preserved failures and limits

The earlier complete Dart run failed when `persistent-unregister` exited with access violation `-1073741819`. Its standalone rerun and the later complete JIT/CLI-bundle run pass without source changes. The Windows error report's loaded-module list contains neither the DeviceReadout native asset nor the connectivity fixture DLL. That narrows the investigation but does not establish a root cause. The historical upload record remains accurate for its cutoff.

Additional attempts encountered a Flutter example analysis-server access violation, an installed-consumer `MSB8066` test-entrypoint build failure and a framework analysis-server crash. One analyzer's crash reporter repeatedly printed the same stack; its exact PID, executable and parent chain were verified before terminating that owned process and its output wrapper. The failed logs are preserved. The subsequent complete consumer and framework scripts passed; this does not prove that the intermittent tooling failures are fixed. No runner ignores failures or automatically retries them, and no SDK version, VM flags or global configuration was changed.

The earlier import-only compiler probe also remains evidence: it imports the tests without invoking them or any SDK collection and failed on attempt 82 while loading SDK metadata. It is not treated as proof of the cause of every later failure.

Physical Wi-Fi values and transitions, additional architectures/Windows configurations, the four unmapped fields and the full SDK acceptance matrix remain pending. App UI, permission and lifecycle state continues to come from app-owned observers.

Reproduce with `tools/test-dart.ps1`, `tools/test-flutter-windows.ps1`, `tools/build-flutter-packages.ps1 -Platform Windows`, `tools/test-flutter-windows.ps1 -ExampleRoot .tools/flutter-windows-installed` and `tools/test-flutter.ps1`. Local source hashes, native case reports, application reports, archive/source comparisons and hashes of successful and failed logs are recorded in the ignored `.tools/evidence/dart-windows-wifi-checkpoint.json`.
