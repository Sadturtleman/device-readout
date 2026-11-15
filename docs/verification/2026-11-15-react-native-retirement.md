# React Native API 26/36 and target retirement — 2026-11-15

The actual RN 0.88.0/Hermes/JSI verification APK now passes on both API 26 and API 36 x86_64 emulators. A separate native binding regression reproduces and fixes a live-stream retirement defect. This checkpoint preserves the full SDK scope and does not establish complete platform support.

The subsequent [native inventory observation checkpoint](2026-11-15-react-native-inventory.md) connects collector change callbacks, adds five contracts and reruns both emulator APIs. The results below retain this earlier explicit-list scope.

## Discovered-target removal

Before the fix, a successful native `list` response could retire a missing target's handle while an existing `watch` for that target continued running. Subsequent `get` rejected the handle, but the old subscription did not emit `EntityRemoved` or release its listener. The new public binding contract test timed out waiting for that terminal response on the original implementation.

The endpoint now associates selected native requests with their context-local target token. Target selection, successful inventory retirement and response delivery use the same identity gate. Discovering absence cancels affected work with a removal cause; the protocol delivers `EntityRemoved`, and ordinary caller cancellation stays silent. Late successful responses are suppressed after retirement. Cleanup retains the existing collection worker and does not wait for native listener disposal on the caller path.

The regression verifies:

- a running state watch fails with `EntityRemoved` when a successful list excludes its target;
- the removed native listener is released;
- a late callback cannot restore the old stream;
- a sibling target's stream continues receiving values;
- reappearance creates a new token while the old handle remains invalid.

This evidence uses a controlled `CpuCore` collector through `NativeBindingEndpoint.send/next`. It does not prove physical hotplug or automatic inventory observation. Removal discovered by successful list queries is covered; native inventory notifications, paused sensor removal, broader in-flight operations and all-kind hardware cases still need verification.

## Actual application results

The existing [application harness](2026-11-11-react-native-app.md) was run first on API 26 and then rebuilt with the endpoint fix and rerun on both APIs.

| Verification | API 26 | API 36 |
| --- | --- | --- |
| Eight baseline Hermes/native/observer scenarios | Passed | Passed |
| RAM value agrees with independent `/proc/meminfo` | Passed | Passed |
| App-owned window observation after actual resize | Passed | Passed |
| Actual background callback and native sensor release | Passed | Passed |
| Native sensor registration and fresh sample after resume | Passed | Passed |

These application scenarios exercise the real native module, generated autolinking and Hermes/JSI path. The app owns its window and lifecycle observers. Permission coordination uses controlled app state without an OS permission dialog. The ordinary-workload heartbeat remains weaker evidence than a deliberately blocked native-collection test; no stronger responsiveness claim is made.

The previously failed API 26 emulator launch succeeded on this run. Two initial verification attempts stopped before application launch because API 26 logd rejected `logcat -c` immediately after package installation. The harness now retries that command at most five times with 250 ms spacing and still requires a successful clear before launching. This prevents old logs from satisfying assertions. Both API 26 runs after the harness change passed. Neither the earlier process failure nor transient logd failure is reported as an SDK behavior failure.

## Commands and evidence

Kotlin `:core:test` passes **31/31**: DeviceAccess 12, native binding 9, observers 7 and snapshots 3. The RN example TypeScript checks and APK build pass with the existing pinned application toolchain. The same rebuilt APK passes on both APIs.

Commands from the repository root, with the project-local Gradle home configured for the Kotlin command:

```powershell
./kotlin/gradlew.bat -p kotlin :core:test --no-daemon --console=plain
./tools/build-react-native-app.ps1 -GradleHome 'C:/short/gradle-cache'
# Run once against each project-owned API 26/36 AVD after it has booted:
./tools/test-react-native-android.ps1 -SdkRoot 'C:/path/to/Android/Sdk' -Serial emulator-5584
```

Ignored local evidence:

- `.tools/rn-target-retirement-red.log`: pre-fix failing behavioral test.
- `.tools/rn-target-retirement-green.log`: passing regression.
- `.tools/rn-retirement-kotlin-full.log` and `kotlin/core/build/test-results/test`: all 31 contracts.
- `.tools/rn-retirement-app-build.log`: rebuilt actual APK.
- `.tools/rn-api26-retirement-validation.log` and `.tools/rn-api36-retirement-validation.log`: final application runs.
- `.tools/rn-android-DeviceReadout_API26.json` and `.tools/rn-android-DeviceReadout_API36.json`: scenario reports, accompanied by app logs, kernel memory and foreground/background/resumed sensor dumps.

The harness restored its window-size overrides and stopped the verification app. The project-owned emulators were shut down after verification. Other SDK tests retain their preceding checkpoint evidence and were not rerun solely for this endpoint change.

## Remaining scope

Automatic native inventory subscriptions, app sensor-source sessions, reusable RN framework adapters, OS permission integration, full malformed-input/overload/detachment coverage, blocked-native Hermes/UI responsiveness, external package distribution, physical-device coverage, other RN platforms and the complete entity/field/version matrix remain required. The other binding and platform work in the implementation ledger also remains required.
