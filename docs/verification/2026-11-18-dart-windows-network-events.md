# Dart and Flutter Windows network notifications — 2026-11-18

Windows NetworkInterface watch now combines native change notifications with serial polling. This extends the [initial network-field checkpoint](2026-11-18-dart-windows-network.md), without changing the public Entity/Snapshot API. The full [implementation objective](../implementation-status.md) remains incomplete.

The subsequent [C# network-field checkpoint](2026-11-18-dotnet-windows-network.md) verifies the same 84-interface NDIS inventory on .NET 10 and corrects its MTU/DNS/type differences. Fresh Dart native-boundary and actual-reference checks pass with the shared fixture extension. The broader architecture/configuration and physical-transition gaps below remain open.

## Observation behavior

The first active network watch registers [interface](https://learn.microsoft.com/en-us/windows/win32/api/netioapi/nf-netioapi-notifyipinterfacechange), [unicast-address](https://learn.microsoft.com/en-us/windows/win32/api/netioapi/nf-netioapi-notifyunicastipaddresschange) and [route](https://learn.microsoft.com/en-us/windows/win32/api/netioapi/nf-netioapi-notifyroutechange2) notifications for both address families. Watches in one DeviceAccess context share this registration group. Plain list/get and creation of an uncollected stream do not register observers. The last unsubscribe releases the group; a later subscription explicitly starts a new group.

The initial snapshot follows registration. OS registration acknowledgements are ignored as data events. Each valid change requests a fresh full snapshot, including equal-value updates. A protocol row deletion is not adapter removal: the current inventory must independently confirm that the target disappeared. Target generation and nullable field rules remain those of the initial collector.

Polling continues for fields not fully covered by those notifications and for additional NDIS entries. Each watch captures its own immutable interval, initially one second. A single poll timer is armed after collection completes, and at most one polling read waits in that watch's queue. Native events use the existing bounded state-stream queues. An unsupported registration (ERROR_NOT_SUPPORTED), or absent registration entrypoint, leaves the other available notifications and polling active; access denial or malformed registration output fails the stream with the common typed error.

## Callback ownership and execution

[NativeCallable.listener](https://api.dart.dev/dart-ffi/NativeCallable/NativeCallable.listener.html) dispatches asynchronously, so an OS callback's temporary row cannot be passed to Dart for later decoding. The new bundled C bridge sends only a registration token, row-presence flag and notification kind. SDK reads never retain or dereference callback row memory. Collection and normalization remain on the collection isolate.

The C bridge keeps a synchronized token registry. It bounds pending native messages to 2,048 per registration, followed by one terminal overflow signal, and limits active registry entries to 4,096 across the process. Retired tokens are not reused. A callback flood fails with ReadFailed instead of creating an unbounded native-to-Dart queue.

Tokens are removed before closing the Dart callable and before native unregister. This closes the race between a native callback invocation and callable destruction. The native module is pinned for the process lifetime so a late call can still enter the static dispatcher and safely find no live token. This deliberately retains the small native module; it is not a claim of zero process-wide resource use.

[CancelMibChangeNotify2](https://learn.microsoft.com/en-us/windows/win32/api/netioapi/nf-netioapi-cancelmibchangenotify2) runs on the collection worker, outside native callback dispatch and registry locks. Cancellation listeners only schedule teardown. Public cancellation/disposal do not join a blocked native unregister, and initial watch deadlines include blocked registration. Caller timers continue during the controlled held-call tests.

If unregister fails, its native handle is retained for a later explicit subscription or context cleanup attempt. New registration is rejected while cleanup still fails, preventing repeated subscriptions from accumulating another group of OS handles in that context. Retired callbacks cannot enter Dart during the failure. A permanently failing OS unregister cannot be claimed to have freed the OS registration; physical driver failures and permanent shutdown failures remain outside the completed evidence. No background infinite retry is added.

## Reproductions and native verification

The first public test failed because none of the three native sources was registered (`.tools/network-events-red.log`). After implementation it receives interface/address/route changes before a configured ten-second poll, then observes zero registrations after the last unsubscribe.

A second test reproduced loss of failed-unregister handles: a later subscription accumulated new native registrations while the old registrations remained (`.tools/network-unregister-red.log`). Retaining the failed handles and cleaning them before an explicit new subscription fixes that case. A persistent-failure variant confirms that another attempt returns PermissionDenied without adding registrations, and succeeds after the native source recovers.

The tests avoid comparing OS thread IDs sampled at different times because Dart can reuse idle OS threads. Thread separation is checked while a native call is actually held. The real OS test also avoids assuming one initial acknowledgement per subscription: this host sends separate IPv4/IPv6 acknowledgements, two for each of the three source kinds.

| Additional public/native-boundary coverage | Cases per mode |
|---|---:|
| Immediate native updates, equal values, shared subscriptions and full/partial polling fallback | 4 |
| Denied/failed/null-handle registrations and invalid/missing-row callbacks | 5 |
| Protocol deletion, confirmed adapter removal and late callback after unsubscribe | 3 |
| Held registration and held unregister, with public completion before native return | 2 |
| Failed unregister recovery and rejection while cleanup continues to fail | 2 |
| 4,096-callback flood with bounded failure | 1 |
| Actual Windows registration, acknowledgements, sharing and unregister | 1 |

These **18 cases run in both JIT and CLI-bundle modes**. Seventeen use native adapter fixtures in retained child processes. The eighteenth uses a separate transparent C adapter that forwards queries and registrations to the real Windows APIs; it performs no network configuration changes. Each real-OS run reports three registrations, acknowledgements from all three source kinds, three successful unregisters and zero active registrations. This proves actual registration/callback setup and teardown, not a physical link transition.

The existing 21 network query/failure cases remain in each aggregate. Their eight held-read reports and the four new held-registration/unregister reports all finish public operations before native return while caller timers progress. Test children have retained process handles and eight-second deadlines; controlled native holds have six-second failsafes.

## Completed gates

| Command | Result |
|---|---|
| `./tools/test-dart.ps1` | Clean analysis; **175/175 JIT** and **175/175 CLI-bundle** checks; negative browser boundary passed. |
| `./tools/test-flutter-windows.ps1` | **18/18 checkout Windows app scenarios** with the new callback bridge; ordinary entrypoint rebuilt. |
| `./tools/build-flutter-packages.ps1 -Platform Windows` | Separate hosted-Pub consumer downloaded the rebuilt packages, analyzed and built. |
| `./tools/test-flutter-windows.ps1 -ExampleRoot .tools/flutter-windows-installed` | **18/18 installed Windows app scenarios**; ordinary entrypoint rebuilt. |
| `./tools/test-flutter.ps1` | Clean analysis and **27/27 framework checks**. |

The Windows C asset now includes `src/windows_network_events.c` through the existing build hook. Runtime queries do not build, download or spawn helper processes. Both actual Flutter Windows consumers retain independent field comparisons for 84 interfaces and 61 routes, polling snapshots and UI timer progress. The native fixtures, transparent test adapter and reference DLL are not bundled into the ordinary examples.

The local audit confirms that all 533 captured code/input files stayed unchanged during these gates. It matches 36 core-package runtime files and 12 Flutter runtime files against the installed packages, verifies archive hashes and copied consumer test entrypoints, and checks 374 local documentation links. The combined source/artifact record is `.tools/evidence/dart-windows-network-events-checkpoint.json`.

Final local logs are `.tools/dart-network-events-final.log`, `flutter-network-events-checkout.log`, `flutter-network-events-packages.log`, `flutter-network-events-installed.log` and `flutter-network-events-framework.log`. Application reports are `flutter-windows-viewport-85b39cf785aa4ad79e557892f62f34cd.json` and `flutter-windows-viewport-a8d730cabe984fb0a1f5d8a5f10e0310.json`. These artifacts are local and excluded from Git; no public package release or new GitHub upload is performed by this checkpoint.

Physical link/address/route transitions, more concurrent callback/teardown races, sustained load, permanent OS cleanup failure, ARM64, additional routing compartments/VPN configurations and cross-binding inventory parity remain pending. Android/browser apps, C#, Kotlin and Swift were not rerun for this Windows Dart change. All remaining entities, bindings and the complete version/physical/consumer matrix remain required by the original objective.
