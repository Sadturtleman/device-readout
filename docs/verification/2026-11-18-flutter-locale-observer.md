# Flutter app locale observation — 2026-11-18

`FlutterLocaleObserver.attach(access, state: valueListenable)` now accepts app-captured `FlutterLocaleState`. It supplies `Entities.locale` through the Dart observation runtime. The application chooses the Localizations scope, owns its lifecycle and publishes changes; SDK get/watch never read BuildContext, Localizations, PlatformDispatcher or the supplied listenable.

## Fields and application integration

| Locale field | App observation mapping |
|---|---|
| currentLanguageTag | currentLocale.toLanguageTag(), or null |
| preferredLanguageTags | Explicit preferredLocales in supplied order |
| systemLanguageTags | Explicit systemLocales in supplied order |
| appLanguageTags | Explicit appLocales in supplied order |
| regionCode | Current Locale countryCode; absent/empty becomes null |
| scriptCode | Current Locale scriptCode; absent/empty becomes null |
| calendar | App-supplied calendar identifier |
| numberingSystem | App-supplied numbering-system identifier |
| hourCycle | App-supplied typed hour cycle |
| firstWeekday | App-supplied typed weekday |
| measurementSystem | App-supplied typed measurement system |

Every input is a complete state. Lists are immutable copies; null remains unavailable and an explicitly empty list remains empty. A later observation does not inherit fields from an earlier one or from a native locale with different semantics. Repeated equal observations are delivered. Region/script and formatting values are not guessed from another source.

[Localizations.maybeLocaleOf](https://api.flutter.dev/flutter/widgets/Localizations/maybeLocaleOf.html) reports the selected widget scope and establishes a dependency. Applications can use it in didChangeDependencies to publish the effective locale, including Localizations.override. [didChangeLocales](https://api.flutter.dev/flutter/widgets/WidgetsBindingObserver/didChangeLocales.html) reports a system locale notification; it does not establish a widget's resolved locale or an explicit application override list. The adapter therefore does not substitute these scopes. Language tags use Flutter's [toLanguageTag](https://api.flutter.dev/flutter/dart-ui/Locale/toLanguageTag.html).

```dart
// Create once from the application's lifecycle, before starting locale watches.
final localeState = ValueNotifier(
  FlutterLocaleState(currentLocale: null),
);
final localeObserver = FlutterLocaleObserver.attach(access, state: localeState);

// In the selected app State's didChangeDependencies (after super):
localeState.value = FlutterLocaleState(
  currentLocale: Localizations.maybeLocaleOf(context),
  // Supply other lists/preferences only when the application knows their scope.
);

final snapshot = await access.get(Entities.locale);
final stream = access.watch(Entities.locale);

// In the owning app State's dispose:
localeObserver.dispose();
localeState.dispose();
```

This is explicit application wiring, not an automatically installed widget observer. One DeviceAccess context has one effective singleton locale source; configured access views share that owner. Apps with different locale scopes can use separate contexts. The SDK does not own or dispose the supplied ValueListenable.

## Source ownership and failures

The shared Dart API adds `access.observers.stateSource(entity) -> ObserverStateSource<S>` for singleton state entities. Registration reserves the source, `publish(snapshot)` supplies its complete value and `dispose()` releases only that owner. A registered source with no value waits for its first publication under the existing read deadline. An existing direct observation, a second state source or direct publish into an owned source is rejected with InvalidConfiguration. Target collections and sensors continue using their existing APIs.

Attaching or detaching a source invalidates current reads/watches with ReadFailed. The caller may start a new operation. Detachment does not permanently retire the singleton; new operations use native collection, which may itself be unsupported on a given platform. Old owners cannot overwrite or erase a replacement, and late publication is rejected after source/context disposal. Source changes do not clear application permission/failure policy.

The Flutter adapter owns a separate failure slot. A failed app getter invalidates the cached state and terminates watches. Fresh observations recover only that slot; app-owned policy remains intact. If app listener removal throws, SDK ownership is still released and retained callbacks become inert. The SDK cannot force an app listenable to release a callback after its own cleanup failed.

## Execution and evidence

The app callback captures locales and converts their small tag/list payloads. Snapshot normalization and completion timestamps use the existing collection worker. get/watch invoke no UI getter or permission operation; native NLS/ICU work remains isolate-owned. Application-supplied listenable getters and listener registration/removal must be nonblocking. No native locale setting, global cache or application locale policy is changed by the SDK.

Environment: Windows x64 10.0.26300.0, Flutter 3.47.9 / Dart 3.13.7.

| Verification | Result |
|---|---|
| Dart analysis | Clean |
| Dart JIT and compiled contracts | 68/68 each |
| Flutter package/example analysis | Clean |
| Flutter framework tests | 27/27 |
| Actual Windows release application | 13/13 |
| Negative Dart web boundary | Passed |

The release application changes actual Localizations from zh-Hant-TW to fr-FR, observes both through get/watch, verifies terminal ReadFailed on detach and compares all native locale fields before/after restoration. Existing held-collector coverage still delivers a native window callback and the caller deadline before the worker returns (49 host timer ticks, one callback). This establishes those controlled cases, not zero host overhead, crash isolation, forced native interruption or a general frame-time guarantee. The ordinary example executable was rebuilt after the test.

Red evidence: `.tools/dart-state-source-red.log` and `.tools/flutter-locale-observer-red.log` record the missing public APIs. `.tools/flutter-locale-failure-red.log` reproduces an app cleanup exception escaping disposal; the implementation now contains it while releasing source ownership. Ownership/deadline and actual widget integration tests passed on their first implemented runs; they are corroborating checks, not additional reproduced defects. One attempt used an incorrect fixture working-directory path and was corrected before running. A later sandbox-only Flutter temp-file copy error prevented test execution; its session was stopped, no matching child remained and the same test passed under normal user permissions. Neither is counted as an SDK regression.

Final logs: `.tools/dart-locale-observer-final.log`, `.tools/flutter-locale-observer-framework.log`, `.tools/flutter-locale-observer-windows.log`. Release report: `.tools/flutter-windows-viewport-dd46a0d94c63455b93ee7dcbe131b5b9.json`. Source/artifact hashes and link checks: `.tools/evidence/flutter-locale-observer-checkpoint.json`.

```powershell
./tools/test-dart.ps1
./tools/test-flutter.ps1
./tools/test-flutter-windows.ps1
```

Android/browser applications, Apple builds, Swift/.NET SDK suites and installed external consumers were not rerun for this addition. Cross-platform app locale integration, platform-specific language/preference feeds, more native locale configurations and the complete 46-entity/binding/device/version acceptance matrix remain required. The prior unreproduced JIT compiler abort did not recur in this run; its underlying cause remains unresolved. This checkpoint is local work after commit 0efdcde and is not a package release.
