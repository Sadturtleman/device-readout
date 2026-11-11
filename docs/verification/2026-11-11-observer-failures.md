# Kotlin and .NET observer failure verification — 2026-11-11

The application's screen/permission observer can now report a typed failure through Kotlin `access.observers.failure(entity, error)` or .NET `access.Observers.Failure(entity, error)`. Passing null clears that failure. The SDK still performs no implicit UI lookup or permission request.

## Contract and implementation

- A targeted entity gates only that target. An entity-kind input gates the whole collection, including list/current/describe and its targets. Permission status and capability queries remain separate from the collection failure input.
- A failure invalidates observed snapshots, fails pending observed first-state reads and ends registered streams. Poll-only native state streams also subscribe to failure notifications, so a long polling interval does not delay the error. Native sensor subscriptions are released on the collection worker.
- Clearing a failure does not restore a cached snapshot or restart an ended stream. The application can publish refreshed state while the failure remains active, then clear the failure. A new query reads that refreshed state.
- Completed first-value promises are replaced during invalidation. Otherwise, a cleared failure could accidentally return the first pre-failure snapshot through the old promise.
- Native read/list/current/describe calls capture the failure revision before entering the source. They reject results that crossed a matching failure, even when the application cleared it before the source returned. A subsequent fresh request can succeed. This does not forcibly stop an uncooperative native call; the existing worker/read deadline still bounds the caller's wait.
- Removal has priority over later failure or publication. A removed handle cannot be revived. An explicitly observed empty current selection makes an otherwise empty collection discoverable as an empty list rather than falling back to native discovery.

The new failure callbacks update synchronized state and notify asynchronous consumers. They do not dispose native subscriptions, collect platform state or normalize snapshots on the app's callback thread.

## Verification

The public seams are get/watch/list/current/describe, observer inputs and permission state. Test collectors replace the external OS/service boundary; tests do not call SDK internals.

| Scenario | Kotlin | .NET |
|---|---|---|
| Target failure, unrelated target, collection failure, independent permission state | Passed | Passed |
| Clear without fresh state times out instead of returning an old cached value | Passed | Passed |
| Fresh recovery and late publication after target removal | Passed | Passed |
| Observed empty discovery and failure before the first observed value | Passed | Passed |
| Fresh state published while failed becomes readable only after clearing | Passed | Passed |
| Native polling stream with a 30-second interval receives an app failure | Passed | Passed |
| Native event watch fails before its first event; cleanup runs on its registration worker | Passed | Passed |
| Native event get fails before its first event | Existing shared Kotlin sensor path; not a separate new case | Passed explicitly |
| Native read crossing failure and immediate recovery discards the old result | Passed | Passed |
| Native list/current/describe crossing failure and immediate recovery discard old results | Passed | Passed |

The polling-wait defect and native in-flight result defects were reproduced before correction. The application-observer API tests initially failed to compile because the new input did not yet exist. Recovery, empty-discovery and worker-release cases were then retained as regression coverage.

Final commands and results:

```powershell
./tools/build-android.ps1 -SdkRoot 'C:/Users/rugsn/AppData/Local/Android/Sdk'
./tools/test-dotnet.ps1
```

- Kotlin common suite: **20 tests passed** (12 DeviceAccess, 5 observer, 3 snapshot cases).
- Android service contract suite: **13 tests passed** (5 identity, 5 sensor, 3 trigger cases).
- Android AAR and instrumentation APK assembly and lint: **passed**, 85 Gradle tasks. Existing deprecation warnings remain for the legacy cellular APIs.
- .NET: **18/18 checks passed**, including real Windows memory, OS, runtime, CPU, storage and network queries. Build reported zero warnings and errors. Firmware physical-memory lookup remained null in this sandbox; the partial-result contract preserves that null.

Final logs: `.tools/observer-android-final.log` and `.tools/observer-dotnet-final.log`. Gradle XML results are under `kotlin/core/build/test-results/test` and `kotlin/android/build/test-results/testDebugUnitTest`. Red-stage evidence includes `.tools/observer-kotlin-poll-red.log`, `.tools/observer-dotnet-poll-red.log`, `.tools/observer-kotlin-race-red.log` and the two `observer-*-discovery-red.log` files. Logs and build output remain local ignored artifacts.

The first Gradle attempt could not connect to its local daemon under the network restriction. After permission for build communication was granted, compilation and tests ran normally. This environment failure was separate from the reproduced SDK failures.

## Remaining scope

No new emulator/device instrumentation or browser suite was run in this checkpoint. Android service fixtures and JVM tests do not establish actual screen/permission UI behavior, physical sensor revocation or all lifecycle/error interleavings. In particular, failure handling while a sensor is paused and simultaneous error/cancel/overload races need additional cross-language coverage. Existing native instrumentation evidence remains in the earlier reports.

Swift/Apple, Flutter and React Native implementations, remaining browser/Windows collectors, minimum-version consumption and the full platform matrix remain pending. The all-46-entity release objective is still active.
