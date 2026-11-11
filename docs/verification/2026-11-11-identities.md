# Android restricted identifiers checkpoint — 2026-11-11

## Scope

Added HardwareSerial and TelephonyIdentity collectors, bringing Android to 37 mapped entities: twenty state entities and seventeen sensor kinds. Collector presence is not complete field, device or binding coverage. The full SDK objective remains active.

HardwareSerial reads the public `Build.getSerial()` API. It preserves an available value, turns native UNKNOWN/blank into null, and propagates native permission denial as PermissionDenied. It does not use the deprecated Build.SERIAL field or substitute an ANDROID_ID/UUID.

TelephonyIdentity discovers logical modem slots using activeModemCount on API 30+ and phoneCount earlier. Targets are ordered by logical slot index and do not require an active SIM subscription. current() is null. Slot-specific IMEI/MEID reads preserve strings, including leading zeros and case. These handles identify logical slots in the SDK context, not permanent physical-device identities.

Each identifier field is read independently. An available value survives the other field's failure. When no identifier value is readable and Android reports a permission failure, the whole read fails with PermissionDenied. If both native calls are unsupported, it fails with UnsupportedEntity; other whole-read failures use ReadFailed. Successful native nulls remain null. Cancellation is not converted into a missing field. Target validity is checked again after native field collection so a removed slot cannot return a successful completed snapshot.

Serial watches use serial polling. Telephony watches add API 30+ protected multi-SIM configuration broadcasts, with polling for incomplete notifications. The callback retains the supplied removed-slot count before deferring a read, so a rapid return of the slot cannot erase an observed removal. Old handles remain removed. Without an attached watch, transitions entirely between observations remain unverified.

## Execution and permissions

All native identifier queries and discovery run on the collection worker. Multi-SIM callbacks use a dedicated HandlerThread and do not perform identifier queries in the callback. The receiver accepts the protected system action from the privileged telephony sender. Construction is inert. Collection never invokes a permission coordinator or changes modem/SIM state.

The SDK delegates identifier eligibility to Android rather than trying to reconstruct every privileged/owner/carrier/role condition with an ordinary permission precheck. Runtime permission grants alone do not establish modern identifier access. The observed legacy-target UNKNOWN/null response is retained, not converted into a fabricated ID.

The native test oracles compare values in memory. Reports contain policy outcomes and booleans, never the actual hardware serial, IMEI or MEID.

## Contract tests

Five new public-interface tests passed using Robolectric 4.16 / API 36 native service fixtures, alongside the previous eight sensor tests:

1. Serial polling preserves equal native values and timestamps; UNKNOWN/empty has no fallback value.
2. Two logical slots return their own IMEI/MEID even without subscription discovery; current() remains null.
3. A readable field survives the other field's denial; wholly denied/unsupported reads have typed errors. Identifier getters execute off the main Looper, with no permission prompt.
4. A removal broadcast ends the watched old slot with EntityRemoved even if the native modem count has already recovered; a newly discovered slot works and the old handle remains invalid.
5. Removal during the native field read produces EntityRemoved rather than a successful stale snapshot; re-discovery does not revive the old handle.

The tests initially reproduced missing collectors, loss of a readable IMEI when MEID failed, an ignored slot-removal event, and a successful snapshot for a slot removed during its read. The implementation corrected each failing behavior. Fixtures replace Android service behavior only; no SDK implementation objects or private methods are mocked.

The final `tools/build-android.ps1 -SdkRoot <sdk>` passed thirteen Android service tests, retained the fourteen passing common JVM contracts, assembled the AAR/test APK and passed Android lint. The separate `-TestTargetSdk 26` build also passed. Default targetSdk 35 was restored afterward. Logs are `.tools/identity-adapter-final-build.log` and `.tools/identity-adapter-legacy-build.log`.

## Native permission matrix

These are ordinary test-APK results on project-owned x86_64 AVDs, not privileged-device claims.

| OS API | App target SDK | READ_PHONE_STATE fixture | Observed SDK outcome |
|---|---|---|---|
| 26 | 35 | Granted | Native serial/IMEI values match; equal IMEI snapshots are retained by watch |
| 26 | 35 | Denied | get and watch terminate with PermissionDenied |
| 36 | 35 | Granted | Stronger native identifier restrictions still produce PermissionDenied |
| 36 | 35 | Denied | PermissionDenied |
| 36 | 26 | Granted | Native serial UNKNOWN and absent identifiers remain null |
| 36 | 26 | Denied | PermissionDenied |

All six cases passed without automatic permission requests. Native capability/discovery checks remain independent of read authorization. The assertions inspect actual Android return values/errors and do not print identifiers.

Six additional scenario/environment combinations passed: cellular authorized/denied reads and basic SDK integration on both API 26 and 36. These exercise the shared permission-fixture changes and existing collectors. During the basic integration's cancellation-insensitive 500 ms collector and 100 ms read deadline, the UI heartbeat ran 17 ticks on API 26 and 18 ticks on API 36; the caller returned before 450 ms.

Every native pass includes `deviceReadoutStatus=passed` and `INSTRUMENTATION_CODE: -1`. Target-specific evidence is preserved at:

- `.tools/DeviceReadout_API26-identityContracts-target35-results.txt`
- `.tools/DeviceReadout_API26-identityDenied-target35-results.txt`
- `.tools/DeviceReadout_API36-identityContracts-target35-results.txt`
- `.tools/DeviceReadout_API36-identityDenied-target35-results.txt`
- `.tools/DeviceReadout_API36-identityContracts-target26-results.txt`
- `.tools/DeviceReadout_API36-identityDenied-target26-results.txt`

Cellular/basic reports use the same `-target35-results.txt` suffix. The helper preserves and restores the test APK's runtime permission and package/UID app-op modes. The final API 36 test APK was restored to target SDK 35, and its three tracked runtime permissions were confirmed false in `.tools/DeviceReadout_API36-identity-final-permission-state.txt`. Both owned AVDs were stopped after testing.

## Remaining verification

Physical multi-modem hardware, actual modem-removal broadcasts, privileged/owner/carrier/default-role access and the full Android API/consumer-target matrix remain unverified. The controlled slot-removal tests do not prove physical hotplug. No Windows, browser, Apple, Flutter or React Native tests were rerun for these Android-only changes. Main-thread dispatch separation does not imply process crash isolation or zero resource usage.

## Primary references

- [Build.getSerial access rules and legacy UNKNOWN behavior](https://developer.android.com/reference/android/os/Build#getSerial())
- [TelephonyManager slot identity, modem count and multi-SIM notification APIs](https://developer.android.com/reference/android/telephony/TelephonyManager)
- [Android 10 restrictions on non-resettable identifiers](https://developer.android.com/about/versions/10/privacy/changes#non-resettable-device-ids)
- [AOSP protected multi-SIM broadcast declaration](https://android.googlesource.com/platform/frameworks/base/+/android-15.0.0_r1/core/res/AndroidManifest.xml)
