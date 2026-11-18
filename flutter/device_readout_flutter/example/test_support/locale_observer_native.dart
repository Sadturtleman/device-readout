import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:device_readout_flutter/device_readout_flutter.dart' as readout;

Future<Map<String, Object?>> verifyLocaleObservation(
  readout.DeviceAccess access,
) async {
  final before = (await access.get(readout.Entities.locale)).toJson()
    ..remove('collectedAt');
  final input = ValueNotifier(readout.FlutterLocaleState(currentLocale: null));
  final observer = readout.FlutterLocaleObserver.attach(access, state: input);
  StreamSubscription<readout.LocaleSnapshot>? subscription;
  final delivered = <String?>[];
  try {
    Future<void> show(Locale locale) async {
      runApp(
        Localizations(
          locale: locale,
          delegates: const [DefaultWidgetsLocalizations.delegate],
          child: _LocaleFeed(input),
        ),
      );
      await WidgetsBinding.instance.endOfFrame.timeout(
        const Duration(seconds: 3),
      );
    }

    await show(
      const Locale.fromSubtags(
        languageCode: 'zh',
        scriptCode: 'Hant',
        countryCode: 'TW',
      ),
    );
    final first = await access.get(readout.Entities.locale);
    if (first.currentLanguageTag != 'zh-Hant-TW' ||
        first.regionCode != 'TW' ||
        first.scriptCode != 'Hant' ||
        first.systemLanguageTags != null ||
        first.calendar != null) {
      throw StateError(
        'Resolved app locale must not mix unrelated native preferences: ${first.toJson()}',
      );
    }
    final initial = Completer<void>();
    final changed = Completer<void>();
    final stopped = Completer<Object>();
    subscription = access.watch(readout.Entities.locale).listen((snapshot) {
      delivered.add(snapshot.currentLanguageTag);
      if (delivered.length == 1) initial.complete();
      if (snapshot.currentLanguageTag == 'fr-FR' && !changed.isCompleted)
        changed.complete();
    }, onError: (Object error) => stopped.complete(error));
    await initial.future.timeout(const Duration(seconds: 3));
    await show(const Locale('fr', 'FR'));
    await changed.future.timeout(const Duration(seconds: 3));
    final latest = await access.get(readout.Entities.locale);
    if (latest.currentLanguageTag != 'fr-FR' ||
        latest.scriptCode != null ||
        delivered.join(',') != 'zh-Hant-TW,fr-FR') {
      throw StateError(
        'Widget locale changes did not reach get/watch: $delivered',
      );
    }
    observer.dispose();
    final error = await stopped.future.timeout(const Duration(seconds: 3));
    if (error is! readout.DeviceReadoutException ||
        error.code != readout.ErrorCode.readFailed) {
      throw StateError('Detaching an app source must terminate its watch.');
    }
    final restored = (await access.get(readout.Entities.locale)).toJson()
      ..remove('collectedAt');
    if (jsonEncode(restored) != jsonEncode(before)) {
      throw StateError(
        'Native preferences changed or were not restored after observation.',
      );
    }
    return {
      'name': 'app Localizations observation and native fallback',
      'resolvedLocales': delivered,
      'nativeRestored': true,
      'detachError': error.code.name,
    };
  } finally {
    await subscription?.cancel();
    observer.dispose();
    input.dispose();
    runApp(const SizedBox.expand());
  }
}

final class _LocaleFeed extends StatefulWidget {
  final ValueNotifier<readout.FlutterLocaleState> input;
  const _LocaleFeed(this.input);
  @override
  State<_LocaleFeed> createState() => _LocaleFeedState();
}

final class _LocaleFeedState extends State<_LocaleFeed> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    widget.input.value = readout.FlutterLocaleState(
      currentLocale: Localizations.maybeLocaleOf(context),
    );
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
