import 'dart:async';

import 'package:device_readout/device_readout.dart';

import 'observers.dart' show check, errorOf;

DeviceCollector localeFactory(Object? _) => _LocaleCollector();

final class _LocaleCollector implements DeviceCollector {
  @override
  DeviceSnapshot read(EntityAddress entity, ReadContext context) =>
      LocaleSnapshot(currentLanguageTag: 'en-US', calendar: 'gregory');

  @override
  void dispose() {}
}

Future<void> ownedStateLifetime() async {
  final access = DeviceAccess.isolated(localeFactory);
  try {
    check(
      (await access.get(Entities.locale)).currentLanguageTag == 'en-US',
      'Native locale is available before an application source attaches.',
    );
    final source = access.observers.stateSource(Entities.locale);
    source.publish(LocaleSnapshot(currentLanguageTag: 'ko-KR'));
    final observed = await access.get(Entities.locale);
    check(
      observed.currentLanguageTag == 'ko-KR' && observed.calendar == null,
      'An app source supplies a complete snapshot, without mixing native formatting.',
    );
    final initial = Completer<void>();
    final failure = Completer<Object>();
    final subscription = access.watch(Entities.locale).listen((_) {
      if (!initial.isCompleted) initial.complete();
    }, onError: (Object error) => failure.complete(error));
    await initial.future;
    source.dispose();
    final error = await failure.future;
    check(
      error is DeviceReadoutException && error.code == ErrorCode.readFailed,
      'Detachment terminates watches instead of retaining stale app data.',
    );
    await subscription.cancel();
    check(
      (await access.get(Entities.locale)).currentLanguageTag == 'en-US',
      'A new read uses native collection after the owner detaches.',
    );
    final replacement = access.observers.stateSource(Entities.locale);
    replacement.publish(LocaleSnapshot(currentLanguageTag: 'fr-FR'));
    source.dispose();
    check(
      (await access.get(Entities.locale)).currentLanguageTag == 'fr-FR',
      'Disposing an old owner again cannot erase a newer source.',
    );
    replacement.dispose();
  } finally {
    access.dispose();
  }
}

final checks = <String, Future<void> Function()>{
  'owned app state detaches without stale snapshots or retiring the singleton':
      ownedStateLifetime,
  'state source ownership preserves application failures and pending deadlines':
      ownedStateFailures,
};

Future<void> ownedStateFailures() async {
  final access = DeviceAccess.isolated(localeFactory)
      .withReadTimeout(const Duration(milliseconds: 50));
  try {
    final source = access.observers.stateSource(Entities.locale);
    final duplicate = await errorOf(
      Future.sync(() => access.observers.stateSource(Entities.locale)),
    );
    final direct = await errorOf(
      Future.sync(
        () => access.observers.publish(
          Entities.locale,
          LocaleSnapshot(currentLanguageTag: 'de-DE'),
        ),
      ),
    );
    check(
      [duplicate, direct].every(
        (error) =>
            error is DeviceReadoutException &&
            error.code == ErrorCode.invalidConfiguration,
      ),
      'A second writer cannot silently replace the registered owner.',
    );
    final missing = await errorOf(access.get(Entities.locale));
    check(
      missing is DeviceReadoutException &&
          missing.code == ErrorCode.readTimeout,
      'A registered source without data must wait with the configured deadline.',
    );
    final pending = errorOf(access.get(Entities.locale));
    source.dispose();
    final detached = await pending;
    check(
      detached is DeviceReadoutException &&
          detached.code == ErrorCode.readFailed,
      'A pending read is invalidated immediately when its source disappears.',
    );
    final replacement = access.observers.stateSource(Entities.locale);
    const policy = DeviceReadoutException(
      ErrorCode.permissionDenied,
      'App policy',
    );
    access.observers.failure(Entities.locale, policy);
    replacement.publish(LocaleSnapshot(currentLanguageTag: 'ko-KR'));
    replacement.dispose();
    check(
      identical(await errorOf(access.get(Entities.locale)), policy),
      'Publishing or releasing a source must not clear application failure policy.',
    );
    access.observers.failure(Entities.locale, null);
    check(
      (await access.get(Entities.locale)).currentLanguageTag == 'en-US',
      'The native source is still usable after the app clears its own failure.',
    );
    final closed = access.observers.stateSource(Entities.locale);
    access.dispose();
    closed.dispose();
    check(
      await errorOf(Future.sync(() => closed.publish(LocaleSnapshot())))
          is DeviceReadoutCancelled,
      'A disposed source cannot publish late values.',
    );
  } finally {
    access.dispose();
  }
}

Future<void> main() async {
  for (final entry in checks.entries) {
    await entry.value().timeout(const Duration(seconds: 8));
    print('PASS ${entry.key}');
  }
}
