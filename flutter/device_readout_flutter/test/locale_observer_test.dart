import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' as widgets;
import 'package:flutter_test/flutter_test.dart';
import 'package:device_readout_flutter/device_readout_flutter.dart' as readout;

readout.DeviceCollector forbiddenFactory(Object? _) => throw StateError(
  'An observed locale must not initialize native collection.',
);

final class LocaleInput extends ValueNotifier<readout.FlutterLocaleState> {
  LocaleInput(super.value);
  int reads = 0;
  bool fail = false;
  bool failRemoval = false;
  @override
  void removeListener(VoidCallback listener) {
    if (failRemoval) throw StateError('Application listener cleanup failed');
    super.removeListener(listener);
  }

  @override
  readout.FlutterLocaleState get value {
    reads++;
    if (fail) throw StateError('Application locale unavailable');
    return super.value;
  }

  @override
  set value(readout.FlutterLocaleState value) => super.value = value;
}

void main() {
  testWidgets(
    'application dependency observations follow actual Localizations changes',
    (tester) async {
      final access = readout.DeviceAccess.isolated(forbiddenFactory);
      final input = LocaleInput(
        readout.FlutterLocaleState(currentLocale: null),
      );
      final observer = readout.FlutterLocaleObserver.attach(
        access,
        state: input,
      );
      try {
        widgets.Widget tree(ui.Locale locale) => widgets.Localizations(
          locale: locale,
          delegates: const [widgets.DefaultWidgetsLocalizations.delegate],
          child: LocaleFeed(input),
        );
        await tester.pumpWidget(tree(const ui.Locale('ja', 'JP')));
        await tester.runAsync(() async {
          expect(
            (await access.get(readout.Entities.locale)).currentLanguageTag,
            'ja-JP',
          );
        });
        await tester.pumpWidget(tree(const ui.Locale('ar', 'EG')));
        await tester.runAsync(() async {
          final value = await access.get(readout.Entities.locale);
          expect(value.currentLanguageTag, 'ar-EG');
          expect(value.regionCode, 'EG');
          expect(value.systemLanguageTags, isNull);
          expect(value.appLanguageTags, isNull);
          expect(
            value.scriptCode,
            isNull,
            reason: 'An unspecified script is not inferred',
          );
        });
        await tester.pumpWidget(LocaleFeed(input));
        await tester.runAsync(() async {
          expect(
            (await access.get(readout.Entities.locale)).currentLanguageTag,
            isNull,
          );
        });
      } finally {
        observer.dispose();
        access.dispose();
        input.dispose();
      }
    },
  );
  testWidgets(
    'locale source failures recover without clearing app policy or leaking ownership',
    (tester) async {
      await tester.runAsync(() async {
        final access = readout.DeviceAccess.isolated(forbiddenFactory);
        final input = LocaleInput(
          readout.FlutterLocaleState(currentLocale: const ui.Locale('en')),
        );
        final observer = readout.FlutterLocaleObserver.attach(
          access,
          state: input,
        );
        StreamSubscription<readout.LocaleSnapshot>? subscription;
        try {
          final initial = Completer<void>();
          final failed = Completer<Object>();
          subscription = access.watch(readout.Entities.locale).listen((_) {
            if (!initial.isCompleted) initial.complete();
          }, onError: (Object error) => failed.complete(error));
          await initial.future;
          input.fail = true;
          input.value = readout.FlutterLocaleState(
            currentLocale: const ui.Locale('fr'),
          );
          expect(
            await failed.future,
            isA<readout.DeviceReadoutException>().having(
              (e) => e.code,
              'code',
              readout.ErrorCode.readFailed,
            ),
          );
          await expectLater(
            access.get(readout.Entities.locale),
            throwsA(
              isA<readout.DeviceReadoutException>().having(
                (e) => e.code,
                'code',
                readout.ErrorCode.readFailed,
              ),
            ),
          );
          const policy = readout.DeviceReadoutException(
            readout.ErrorCode.permissionDenied,
            'App policy',
          );
          access.observers.failure(readout.Entities.locale, policy);
          input.fail = false;
          input.value = readout.FlutterLocaleState(
            currentLocale: const ui.Locale('ja', 'JP'),
          );
          await expectLater(
            access.get(readout.Entities.locale),
            throwsA(same(policy)),
          );
          access.observers.failure(readout.Entities.locale, null);
          expect(
            (await access.get(readout.Entities.locale)).currentLanguageTag,
            'ja-JP',
          );
          input.failRemoval = true;
          expect(
            observer.dispose,
            returnsNormally,
            reason:
                'An application cleanup exception must not escape SDK disposal',
          );
          final newer = access.observers.stateSource(readout.Entities.locale);
          newer.publish(readout.LocaleSnapshot(currentLanguageTag: 'de-DE'));
          input.value = readout.FlutterLocaleState(
            currentLocale: const ui.Locale('fr'),
          );
          observer.dispose();
          expect(
            (await access.get(readout.Entities.locale)).currentLanguageTag,
            'de-DE',
          );
          newer.dispose();
        } finally {
          await subscription?.cancel();
          observer.dispose();
          access.dispose();
          input.dispose();
        }
      });
    },
  );

  testWidgets(
    'app locale snapshots keep resolved, preferred and system scopes separate',
    (tester) async {
      await tester.runAsync(() async {
        final access = readout.DeviceAccess.isolated(forbiddenFactory);
        final input = LocaleInput(
          readout.FlutterLocaleState(
            currentLocale: const ui.Locale.fromSubtags(
              languageCode: 'zh',
              scriptCode: 'Hant',
              countryCode: 'TW',
            ),
            preferredLocales: const [
              ui.Locale('zh', 'TW'),
              ui.Locale('en', 'US'),
            ],
            systemLocales: const [ui.Locale('ko', 'KR')],
            appLocales: const [],
            calendar: 'gregory',
            numberingSystem: 'latn',
            hourCycle: readout.HourCycle.h23,
            firstWeekday: readout.Weekday.monday,
            measurementSystem: readout.MeasurementSystem.metric,
          ),
        );
        final observer = readout.FlutterLocaleObserver.attach(
          access,
          state: input,
        );
        StreamSubscription<readout.LocaleSnapshot>? subscription;
        try {
          final value = await access.get(readout.Entities.locale);
          expect(value.currentLanguageTag, 'zh-Hant-TW');
          expect(value.regionCode, 'TW');
          expect(value.scriptCode, 'Hant');
          expect(value.preferredLanguageTags, ['zh-TW', 'en-US']);
          expect(value.systemLanguageTags, ['ko-KR']);
          expect(value.appLanguageTags, isEmpty);
          expect(value.calendar, 'gregory');
          expect(value.numberingSystem, 'latn');
          expect(value.hourCycle, readout.HourCycle.h23);
          expect(value.firstWeekday, readout.Weekday.monday);
          expect(value.measurementSystem, readout.MeasurementSystem.metric);
          final initial = Completer<void>();
          final changed = Completer<void>();
          final snapshots = <readout.LocaleSnapshot>[];
          subscription = access.watch(readout.Entities.locale).listen((value) {
            snapshots.add(value);
            if (snapshots.length == 1) initial.complete();
            if (snapshots.length == 3) changed.complete();
          });
          await initial.future;
          final reads = input.reads;
          await access.get(readout.Entities.locale);
          expect(
            input.reads,
            reads,
            reason: 'get/watch consume captured values only',
          );
          input.value = readout.FlutterLocaleState(
            currentLocale: const ui.Locale('fr'),
          );
          input.value = readout.FlutterLocaleState(
            currentLocale: const ui.Locale('fr'),
          );
          await changed.future;
          expect(snapshots.map((s) => s.currentLanguageTag), [
            'zh-Hant-TW',
            'fr',
            'fr',
          ]);
          expect(snapshots.last.regionCode, isNull);
          expect(snapshots.last.scriptCode, isNull);
          expect(snapshots.last.calendar, isNull);
          expect(snapshots.last.systemLanguageTags, isNull);
          expect(value.currentLanguageTag, 'zh-Hant-TW');
        } finally {
          await subscription?.cancel();
          observer.dispose();
          access.dispose();
          input.dispose();
        }
      });
    },
  );
}

/// Application integration: observe the selected widget scope in its lifecycle,
/// then publish immutable state. The SDK never retains a BuildContext.
final class LocaleFeed extends widgets.StatefulWidget {
  final LocaleInput input;
  const LocaleFeed(this.input);
  @override
  widgets.State<LocaleFeed> createState() => _LocaleFeedState();
}

final class _LocaleFeedState extends widgets.State<LocaleFeed> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    widget.input.value = readout.FlutterLocaleState(
      currentLocale: widgets.Localizations.maybeLocaleOf(context),
    );
  }

  @override
  widgets.Widget build(widgets.BuildContext context) =>
      const widgets.SizedBox();
}
