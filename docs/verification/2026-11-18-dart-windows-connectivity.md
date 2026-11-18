# Dart and Flutter Windows network path — 2026-11-18

The native Windows adapter now implements `get(Entities.networkPath)` and `watch(Entities.networkPath)` with preferred-profile connectivity, internet-validation and metering fields. Watches share a native status subscription within their collection context and supplement it with serial polling. The [complete SDK scope](../implementation-status.md) remains all 46 entities, all bindings and the full acceptance matrix.

## Field meanings and API

| Field | Windows source and mapping |
|---|---|
| `connectionState` | Preferred profile `GetNetworkConnectivityLevel`: None is Disconnected; LocalAccess, ConstrainedInternetAccess and InternetAccess are Connected. No preferred profile returns Disconnected. |
| `internetValidated` | InternetAccess is true; the other known connectivity levels and no preferred profile are false. Unknown levels are null. |
| `metered` | `GetConnectionCost().NetworkCostType`: Unrestricted is false; Fixed and Variable are true. Unknown, missing or failed cost is null. |
| Remaining eight fields | `transports`, `expensive`, `constrained`, `saveData`, `supportsIpv4`, `supportsIpv6`, `supportsDns` and `captivePortal` remain null. |

These values describe the OS-selected internet profile. They do not establish an application's explicitly bound socket route, a complete VPN/underlying-transport set, or reachability of a particular server. Limited internet connectivity does not establish a captive portal or the user's low-data mode. The SDK performs no active HTTP request, speed test or network-configuration change. See [GetInternetConnectionProfile](https://learn.microsoft.com/en-us/uwp/api/windows.networking.connectivity.networkinformation.getinternetconnectionprofile), [NetworkConnectivityLevel](https://learn.microsoft.com/en-us/uwp/api/windows.networking.connectivity.networkconnectivitylevel) and [NetworkCostType](https://learn.microsoft.com/en-us/uwp/api/windows.networking.connectivity.networkcosttype).

Snapshot fields retain the agreed nullable values and one completion timestamp. Unknown enum values remain null. A failed connectivity getter does not discard readable cost, and a failed cost getter does not discard readable connectivity. Whole-query failures retain common typed errors. No UI getter, permission prompt or application observer policy is changed.

Capability queries and unconsumed streams do not start native collection. Watch first registers observation and reads a fresh snapshot. Native `NetworkStatusChanged` invalidations request another read; per-watch polling retains the existing default/configurable interval and equal-value delivery. Event registration returning E_NOTIMPL falls back to polling; denied registration fails the stream. Each returned snapshot is complete for these available fields, without an event wrapper or changed-field list.

## Worker and native lifetime

The bundled Windows C asset owns the WinRT ABI boundary. Each synchronous read, registration and removal balances `RoInitialize` and `RoUninitialize` on one OS thread. Profiles, cost objects and per-read factories are released before returning to Dart. Values, normalization, timestamps, polling and cleanup remain on the collection isolate. No COM pointer or borrowed event sender is sent to the application isolate.

An actual Windows run reproduced HRESULT **0x80080008 (CO_E_SERVER_STOPPING)** when the last MTA lifetime ended between successive calls. The collector now retains its own MTA usage cookie from its first native operation until context cleanup. Every observation also owns a cookie so a failed unregister can retain a valid native owner after public context closure. This accommodates Dart work resuming on different OS threads without changing their preexisting COM initialization balance. Microsoft documents cross-thread release of an MTA usage cookie in [CoDecrementMTAUsage](https://learn.microsoft.com/en-us/windows/win32/api/combaseapi/nf-combaseapi-codecrementmtausage).

The native delegate posts only an invalidation token through the existing bounded callback registry. Last unsubscribe retires the token before closing the Dart callback or calling WinRT removal. Old invocations cannot call a closed Dart trampoline. Unregister failure retains the factory, delegate, event token and observation cookie. An explicit later subscription retries retained cleanup before registering another source; context disposal makes its final attempt. Persistent native refusal is reported in verification as a remaining owner, not a successful release. There is no infinite retry loop.

Public deadlines, cancellation, unsubscribe and context disposal do not join a blocked native operation. The worker finishes and cleans up after the native call returns. This is scheduling and lifetime isolation, not protection from native crashes or a promise of zero process overhead.

## Verification

| Gate | Result |
|---|---:|
| `./tools/test-dart.ps1`, JIT | 190/190 |
| Same contracts, separately compiled CLI bundle including native assets | 190/190 |
| Dart analyzer and negative browser boundary | Pass |
| `./tools/test-flutter-windows.ps1`, checkout Windows Release app | 19/19 |
| `./tools/build-flutter-packages.ps1 -Platform Windows`, separate installed consumer build | Pass |
| `./tools/test-flutter-windows.ps1 -ExampleRoot .tools/flutter-windows-installed` | 19/19 |
| `./tools/test-flutter.ps1`, framework/observer contracts | 27/27 |

The actual Dart path agrees with an independent Windows PowerShell WinRT projection. Both Flutter consumers agree with a separate Windows SDK C++/WinRT projection; that reference also successfully registers and removes a real OS status handler. Polling produces three equal snapshots with fresh timestamps while caller timers progress. The ordinary example entrypoint is rebuilt after each hidden verification app exits.

Fourteen owned native-child scenarios run in each Dart mode:

| Native boundary coverage | Cases |
|---|---:|
| C-thread status callbacks, duplicate snapshots, and shared observation with independent stream lifetimes | 2 |
| Thirteen literal field/error fixtures, including unknown enums, no profile/cost and failed output cleanup | 1 |
| Unavailable-event polling, denied registration, terminal update failure and explicit recovery | 3 |
| Held read, held watch read, held registration, held removal, cancellation and context disposal | 6 |
| Failed unregister followed by explicit recovery; persistent unregister refusal and late callbacks | 2 |

The six held cases per mode record concurrent caller/worker thread IDs, at least three advancing caller timer ticks, and public completion while the native call is still held. Native holds have six-second failsafes; the parent owns each child handle and a nine-second deadline. After release, ordinary cases report zero remaining fixture objects and registrations. Persistent-refusal cases deliberately report one remaining native object and registration after two removal attempts; late callbacks stay detached. No test changes the host network configuration.

All fixture COM getter/release/registration/removal calls record an MTA apartment. Field fixtures enter through a native factory seam into the production C helper and Dart public API; they do not replace the public SDK or normalization. Actual Windows projection checks separately corroborate the ABI and available fields. Controlled callbacks do not prove physical link or profile transition delivery.

Initial failing evidence is `.tools/dart-connectivity-red.log` (unsupported collector) and `dart-connectivity-events-red.log` (missing native observation). The actual MTA failure is preserved in `dart-connectivity-mta-red.log`. A test timing assumption was also corrected: progress is observed until three ticks occur under a retained native hold, rather than assuming Windows delivers three 5 ms ticks within 30 ms. The old unsupported-entity sentinel now targets the still-unimplemented native NetworkPerformance collector.

Final logs are `.tools/dart-connectivity-final.log`, `flutter-connectivity-checkout.log`, `flutter-connectivity-packages.log`, `flutter-connectivity-installed.log` and `flutter-connectivity-framework.log`. The audit `.tools/evidence/dart-windows-connectivity-checkpoint.json` records **545 unchanged code/build/schema inputs**, native reports, actual app reports and artifact hashes. It verifies archive download evidence and byte equality for **38 Dart runtime/build/native-source files** and **12 Flutter runtime files** in the separately installed packages. These local artifacts are excluded from Git; this checkpoint does not publish packages or upload new commits.

## Remaining work

The other NetworkPath fields, explicitly bound routes, physical connection/profile/cost changes, rapid cross-context reopen and more callback/teardown races, ARM64/other supported Windows configurations, and sustained overload still require evidence. C# production sources are unchanged and its suite was not rerun for this Dart change. Android and browser application builds were not rerun; the Dart browser boundary and Flutter framework regressions passed. Apple collectors, remaining bindings/entities, physical devices, minimum-version consumers and the complete acceptance matrix remain required.
