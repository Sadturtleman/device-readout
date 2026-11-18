# C# Windows power native calls and lifetime — 2026-11-18

The [source-semantics change](2026-11-18-dotnet-power-source.md) now has a separate native-call verification command. Public `WindowsDeviceAccess.Create()`, Get and Watch execute the production P/Invoke declarations against Windows SDK structures supplied by an owned child-process fixture. Twenty-three scenarios pass. The final ordinary-user .NET regression suite also passes 168/168 with zero build warnings/errors.

The power implementation required no further change in this checkpoint. These checks corroborate the existing fix rather than establish another power defect. The full regression run exposed an unrelated Wi-Fi test's incorrect assumption about synchronous native cleanup; that test was corrected as described below.

## Native-call verification

The C fixture includes the installed Windows SDK headers and exports the native status, capability and notification-registration entry points. It fills actual SYSTEM_POWER_STATUS and SYSTEM_POWER_CAPABILITIES structures, including deliberately nonzero unrelated capability bytes, so the production field offsets and native signatures are exercised. Both required and optional failures can leave apparently valid output bytes behind; the SDK must honor the failed return value.

Each scenario runs in its own test child. [NativeLibrary.SetDllImportResolver](https://learn.microsoft.com/en-us/dotnet/api/system.runtime.interopservices.nativelibrary.setdllimportresolver?view=net-10.0) redirects only imports from the SDK's Windows assembly in that child. The runtime, parent and other processes retain their ordinary system imports. There is no system DLL replacement, registry write, power-setting change or application-global hook. The fixture library stays loaded until child exit because imported function pointers may remain cached. The parent retains the process handle, waits for terminal exit and can terminate only that owned process if the fixture deadline expires.

| Coverage | Scenarios | Verified behavior |
|---|---:|---|
| Source/saver fields through get and initial/polled watch | 12 | Onboard-only, UPS, mixed, short-term, absent and unknown capability flags; external/unknown line status; unknown saver flag; optional query failure. Equal values receive fresh timestamps. |
| Required status failure | 1 | [GetSystemPowerStatus](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-getsystempowerstatus) failure produces ReadFailed with Win32 error 31, does not query capabilities, and permits a fresh read after recovery. |
| Optional capability failure and recovery | 1 | Source changes Battery -> null -> Battery within the same watch; saver state remains available. |
| Actual system capabilities with controlled offline status | 1 | The production capability call uses the real system PowrProf DLL and agrees with a separate C Windows SDK reference. |
| Held native status/capability calls | 8 | Get deadlines/cancellation, context closure, initial/polled watch deadlines, watch cancellation and iterator disposal finish before native return. |

External and unknown line status never query capabilities: the fixture would hold that call if it were made. Native status/capability work and registration attempts stay on one collection thread distinct from the caller. Fixture registration reports unsupported, so these scenarios exercise polling fallback; the ordinary suite retains separate evidence for real source/saver notifications and unregistration.

In the actual-system-capability scenario, only the coarse AC-line status is replaced with offline status. The real [GetPwrCapabilities](https://learn.microsoft.com/en-us/windows/win32/api/powerbase/nf-powerbase-getpwrcapabilities) result is compared with the independent C reference before and after the read. The current desktop reports all three battery/UPS capability flags as zero; the SDK returns a null source while preserving the controlled saver flag. This executes the previously untested capability binding without disconnecting physical power. It is not a physical battery or UPS transition test.

Each held-call scenario observes a C function still blocked, then verifies host timer progress and public completion before releasing it. Final runs record three or four host timer ticks during the observation window. After release, active native calls reach zero; still-open contexts support a fresh successful read, while the deliberately closed context remains closed. No release depends on joining that native call from the caller. These are controlled C ABI holds, not faults injected into an actual Windows driver and not a universal UI-frame or zero-overhead bound.

The parent reads External and saver=false after all 23 children exit. The fixture affects only test code and is not a dependency or asset of the SDK packages.

## Wi-Fi cleanup test correction

An intermediate complete run passed 167/168. The failed assertion expected a disconnected Wi-Fi watch's native event handler to have been removed immediately after stream termination. The SDK contract already lets stream termination finish before worker-owned native cleanup.

A controlled hold in the WinRT test adapter reproduced the same failure deterministically (0/1). The corrected test proves that EntityRemoved and iterator disposal are delivered while native removal is still held. It then releases removal and waits, with a bound, for registration/removal counts to balance and the handler count to reach zero. Retired-handle behavior, reappearance, mid-read replacement and resource-balance assertions remain. The isolated test passes 1/1, and the final complete suite passes 168/168. No SDK cleanup behavior, error handling or assertion about eventual resource release was removed or relaxed.

## Reproduction and evidence

On Windows x64, the native command requires Visual Studio 2022 C++ tools and a Windows SDK in addition to .NET 10. The ordinary .NET command keeps its existing tool requirements.

```powershell
./tools/test-dotnet-power-native.ps1
./tools/test-dotnet.ps1
```

Local evidence includes `.tools/dotnet-power-native-first.log` (1 scenario), `dotnet-power-native-fields.log` (14), `dotnet-power-native-held.log` (22), `dotnet-power-native-final.log` (23), the intermediate failing `dotnet-power-native-regression-final.log`, and the Wi-Fi `dotnet-wifi-removal-timing-red.log` / `dotnet-wifi-removal-timing-green.log`. Final results are `.tools/dotnet-power-native-final-2.log` (23/23) and `.tools/dotnet-power-native-regression-final-2.log` (168/168), with source, binary, log and fixture hashes in `.tools/evidence/dotnet-power-native-checkpoint.json`.

Physical battery/UPS and saver transitions, real driver failures, ARM64, installed consumer packages, the other bindings and the full 46-entity/version/platform/physical-device acceptance matrix remain unfinished. No Dart or Flutter application tests were rerun for this verification-only extension. Changes remain local after GitHub commit 056ee70.
