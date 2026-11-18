# C# Windows network notification cleanup — 2026-11-18

Windows network notification registrations now retain cleanup ownership across failed registration and failed unregister calls. The original registration error remains visible, and final context cleanup retries only handles that were not released. The [previous field checkpoint](2026-11-18-dotnet-windows-network.md), public APIs and context-owned observation lifetime remain intact. The full [SDK objective](../implementation-status.md) is still incomplete.

## Reproduced failures

A public List test reproduced a non-null registration output being forgotten when the registration call returned failure. The two earlier registrations were released, but the unexpected third handle was omitted from rollback. Windows documents null output on registration failure, so this case is a defensive malformed-output test, not a claim that ordinary Windows returns this combination. The native fixture also exercises it through the production P/Invoke declaration. See [NotifyRouteChange2](https://learn.microsoft.com/en-us/windows/win32/api/netioapi/nf-netioapi-notifyroutechange2) for the API's output contract.

A second public test reproduced the cleanup error replacing the registration error: a registration failure of 31 (ReadFailed) became unregister error 5 (PermissionDenied). Failed handles also lost their cleanup owner when Subscribe threw. The source now owns each registration before invoking the OS, preserves the original error, and retains failed cleanup entries for context closure.

## Ownership and execution

The native platform owns its registration group even if subscription initialization never returns a usable observation. Group cleanup first retires every callback token and clears captured handlers, then attempts native unregister for every owned handle. Successful entries are removed; failed entries retain their handle. Final collector cleanup retries those remaining entries. It does not cancel successfully released siblings twice.

Registration failure remains terminal for that source: another List does not start registrations or an automatic cleanup loop. During ordinary context closure, failed observation cleanup gets one final owner-cleanup attempt. If native unregister continues to refuse, the SDK cannot claim that the OS resource was released. There is no infinite retry worker. Retired callback tokens ignore subsequent native invocations while the native registration is still present.

All registration and cleanup operations stay on the collection worker. No callback row is retained or decoded: native events enqueue a fresh snapshot read. Unregister runs outside callback locks and outside the callback thread, following the [CancelMibChangeNotify2 requirements](https://learn.microsoft.com/en-us/windows/win32/api/netioapi/nf-netioapi-cancelmibchangenotify2). Public read deadlines, cancellation and context/iterator disposal do not join a blocked native operation.

This change preserves the existing C# context lifetime: List/read starts observation, watches share it, and ending the last watch does not itself release the context's registrations. Unsupported native sources retain serial polling. Equal event and polling values remain visible. It does not introduce a new retry or error API.

## Verification

`./tools/test-dotnet.ps1` passes **215/215** checks in the ordinary-user Windows x64 environment, with zero build warnings or errors. The final log is `.tools/dotnet-network-notifications-final.log`.

| Additional native-child coverage | Cases |
|---|---:|
| C-thread events shared by two watches; late callbacks after closure | 2 |
| Unsupported and partially available native sources retain polling | 2 |
| Denied registration, failed return with output, successful return with null handle | 3 |
| Failed rollback recovers at closure; persistent rollback cleanup refusal remains bounded | 2 |
| Invalid callback terminates the stream with the common error | 1 |
| Held registration and held unregister preserve caller progress and public completion | 2 |
| Normal closure retries only a failed handle; persistent unregister refusal remains bounded | 2 |

These **14/14** cases use the existing C fixture through the SDK's production P/Invoke functions in owned child processes. The parent owns each child process handle and imposes a 20-second deadline; native holds have six-second failsafes. The fixture changes no real network configuration. Its callback rows are invalidated immediately after the C callback returns.

The two held-call cases observe progressing caller timers, distinct concurrent native/caller threads and public completion before native return. Late registration results are then released on the worker. The single-failed-handle case registers three handles and makes four unregister attempts in total. Persistent-failure cases make six attempts and deliberately report **three remaining fixture registrations**, rather than reporting zero. Their detached callbacks cannot revive the closed SDK context.

The aggregate also retains two public failure reproductions, all **28** native network-property cases, the actual **84-interface/nine-field/61-route** comparison, and actual Windows registration/acknowledgement/cancellation checks. The fixture's import override is confined to child processes; it does not replace the actual native checks in the parent.

Red evidence is `.tools/dotnet-network-registration-output-red.log` and `.tools/dotnet-network-rollback-red.log`. Focused green evidence is `dotnet-network-registration-output-green.log`, `dotnet-network-rollback-green.log`, `dotnet-network-notifications-native.log` and `dotnet-network-unregister-native.log`, all under `.tools/`.

The audit `.tools/evidence/dotnet-windows-network-notifications-checkpoint.json` verifies **108 unchanged code/build/schema inputs** through the final gate and records assembly, native fixture and log hashes. These local artifacts are excluded from Git. No public package release or new GitHub upload is performed by this checkpoint.

Physical link/address/route transitions, more concurrent callback/teardown races, permanent OS cleanup refusal, other architectures and separately installed .NET consumers remain pending. Dart/Flutter and the separate C# power-native gate were not rerun: this follow-up changes C# notification ownership and tests, while their production sources and the shared C fixture remain unchanged from the previous checkpoint. The complete 46-entity, all-binding, version/physical/consumer acceptance matrix is still required.
