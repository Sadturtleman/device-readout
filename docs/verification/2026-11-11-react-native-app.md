# React Native Android application checkpoint — 2026-11-11

This record captures the completed API 36 run before development was paused. It does not mark the SDK or the React Native support matrix complete. Repository publication did not rerun the application tests.

## Application and toolchain

The verification application in `packages/react-native/example` runs React Native 0.88.0, React 19.3.0, Hermes and the new architecture. Generated RN autolinking registers the Java package and C++ module provider. Actual native RAM, CPU and accelerometer calls exercise the JSI/TurboModule path. Monorepo package resolution and shared Kotlin sources are used; standalone package installation is not yet verified.

The application uses the official RN 0.88.0 template toolchain: Gradle 9.4.1, AGP 9.2.1, Kotlin 2.2.0, compile SDK 37, build tools 37.0.0, NDK 27.1.12297006 and CMake 3.22.1. Its target SDK is 36, minimum SDK is 26, and the verified ABI is x86_64. The bundled debug APK runs without a Metro development server. A short Gradle cache and CMake staging path avoid Windows Ninja path-length failures. The example debug keystore is the unchanged public RN template fixture, not a release signing key.

## Recorded results

`tools/build-react-native-app.ps1` completed successfully. `tools/test-react-native-android.ps1` passed on the project-owned `DeviceReadout_API36` emulator.

| Check | Result |
| --- | --- |
| Hermes runtime and exact integer support | Passed |
| Native RAM read and immutable collection timestamp | Passed |
| Immutable settings and native watch | Passed; two snapshots with an 80 ms configured interval |
| Native CPU discovery and context ownership | Passed; two cores, foreign-context target rejected |
| App-observed viewport | Passed; initial 320 × 640 state matched the app hook |
| Exact integer round trip and context closure | Passed; `9007199254740993`, zero and false preserved |
| App-owned permission coordination | Passed with controlled observer state; no OS permission dialog |
| Native accelerometer observation | Passed |
| Independent kernel-memory comparison | Passed; `kernelAccessibleBytes = 2067738624` matched `/proc/meminfo` |
| Actual window resize | Passed; observer and SDK both reported 640 × 320 |
| Actual Activity background/resume | Passed; native sensor registration disappeared in background and returned on resume |
| Fresh sensor sample after resume | Passed; collection timestamp was later than the recorded resume time |

The eight baseline scenarios are followed by the external kernel, resize and lifecycle checks. The app owns `useWindowDimensions` and `AppState` subscriptions and feeds SDK observer inputs. The harness checks native SensorManager registrations using the app UID and collector listener name. It restores its display-size override and stops the verification app when finished.

Local evidence is retained in ignored `.tools` files: `rn-app-build-lifecycle.log`, `rn-api36-app-validation-final.log`, `rn-android-DeviceReadout_API36.json`, the application log, independent meminfo and foreground/background/resumed sensor dumps. These build and emulator artifacts are not included in Git.

## Limits and remaining work

- API 26 execution was not completed. The emulator launch command ended with Windows process error `-1073741502`; no passing RN API 26 result is claimed.
- Permission coordination uses controlled app state. Actual OS permission interactions remain unverified.
- The app records an ordinary-workload heartbeat. Deliberately blocked native collection and full overload/engine-detachment behavior remain unverified for RN.
- Reusable framework observer adapters, app sensor-source sessions, dynamic-inventory stream retirement and complete malformed-input handling remain required.
- Physical devices, external package distribution, other RN platforms and the complete entity/field/version matrix remain required.

## Reproduction entrypoints

From the repository root, install the root dependencies and the locked RN runtime, then build with the toolchain above:

```powershell
npm ci --workspaces=false --ignore-scripts
./tools/prepare-react-native.ps1
./tools/build-react-native-app.ps1 -SdkRoot 'C:/path/to/Android/Sdk' -GradleHome 'C:/short/gradle-cache'
# Start a project-owned DeviceReadout AVD first. The SDK below needs platform-tools.
./tools/test-react-native-android.ps1 -SdkRoot 'C:/path/to/Android/Sdk' -Serial emulator-5584
```

The preceding [observer checkpoint](2026-11-11-react-native-observers.md) and [foundation checkpoint](2026-11-11-react-native-foundation.md) retain their original test counts and limitations.
