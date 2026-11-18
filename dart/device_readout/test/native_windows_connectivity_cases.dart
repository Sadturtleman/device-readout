part of 'native_windows_connectivity_faults.dart';

Future<Map<String, Object?>> _exercise(
  String scenario,
  DeviceAccess access,
  int Function(int) counter,
  int Function() emit,
  void Function(int) configure,
  void Function() release,
) async {
  if (scenario.startsWith('wifi-')) {
    return _wifiExercise(scenario, access, counter, emit, configure, release);
  }
  if (scenario.startsWith('performance-')) {
    return _performanceExercise(
      scenario,
      access,
      counter,
      emit,
      configure,
      release,
    );
  }
  void typed(Object? error, ErrorCode code) => check(
    error is DeviceReadoutException && error.code == code,
    'Expected typed $code, got $error.',
  );
  final slow = access.withPollInterval(const Duration(hours: 1));
  if (scenario == 'field-errors') {
    final cases = <(int, ConnectionState?, bool?, bool?)>[
      (1, ConnectionState.disconnected, false, null),
      (2, null, null, null),
      (3, null, null, false),
      (4, ConnectionState.connected, true, null),
      (8, ConnectionState.connected, true, null),
      (9, ConnectionState.connected, false, true),
      (10, ConnectionState.disconnected, false, true),
      (11, ConnectionState.connected, false, false),
    ];
    for (final item in cases) {
      configure(item.$1);
      final value = await access.get(Entities.networkPath);
      check(
        value.connectionState == item.$2 &&
            value.internetValidated == item.$3 &&
            value.metered == item.$4 &&
            value.captivePortal == null,
        'Known native fixture ${item.$1} keeps field meanings and nulls distinct.',
      );
      check(
        counter(0) == 0 && counter(6) == 0,
        'Every read releases its COM objects in MTA.',
      );
    }
    for (final item in [
      (5, ErrorCode.permissionDenied),
      (6, ErrorCode.unsupportedEntity),
      (7, ErrorCode.readFailed),
      (12, ErrorCode.unsupportedEntity),
      (13, ErrorCode.readFailed),
    ]) {
      configure(item.$1);
      typed(await errorOf(access.get(Entities.networkPath)), item.$2);
      check(counter(0) == 0, 'Failed native outputs are released.');
    }
    configure(0);
    check(
      (await access.get(Entities.networkPath)).internetValidated == true,
      'Explicit reads recover.',
    );
    return {'fieldFixtures': cases.length + 5};
  }
  if (scenario.startsWith('held-') ||
      scenario == 'cancel-read' ||
      scenario == 'dispose-read') {
    var ticks = 0;
    final timer = Timer.periodic(
      const Duration(milliseconds: 5),
      (_) => ticks++,
    );
    StreamSubscription<NetworkPathSnapshot>? subscription;
    try {
      final token = CancellationToken();
      final limited = access.withReadTimeout(const Duration(milliseconds: 250));
      Future<Object?> pending;
      if (scenario == 'held-unregister') {
        final ready = Completer<void>();
        subscription = slow.watch(Entities.networkPath).listen((_) {
          if (!ready.isCompleted) ready.complete();
        });
        await ready.future;
        configure(22);
        pending = errorOf(subscription.cancel());
      } else {
        configure(scenario == 'held-register' ? 21 : 20);
        pending = errorOf(
          scenario == 'held-watch' || scenario == 'held-register'
              ? limited.watch(Entities.networkPath).first
              : limited.get(Entities.networkPath, cancellation: token),
        );
      }
      await _until(() => counter(8) == 1);
      final worker = counter(9), caller = counter(7), before = ticks;
      if (scenario == 'cancel-read') token.cancel();
      if (scenario == 'dispose-read') access.dispose();
      final error = await pending.timeout(const Duration(seconds: 1));
      if (scenario == 'held-unregister')
        check(
          error == null,
          'Public unsubscribe settles while native removal is held.',
        );
      else if (scenario == 'cancel-read' || scenario == 'dispose-read')
        check(
          error is DeviceReadoutCancelled,
          'Cancellation settles before native return.',
        );
      else
        typed(error, ErrorCode.readTimeout);
      // Windows timer resolution need not deliver three 5 ms ticks in 30 ms.
      // Observe actual progress under the retained native hold instead.
      await _until(() => ticks > before + 2);
      check(
        counter(8) == 1 && worker != caller && ticks > before + 2,
        'Native work is still held while the caller progresses.',
      );
      access.dispose();
      release();
      await _until(() => counter(8) == 0 && counter(2) == 0 && counter(0) == 0);
      check(counter(6) == 0, 'Held operations retain balanced MTA ownership.');
      return {
        'completedBeforeNativeReturn': true,
        'worker': worker,
        'caller': caller,
        'progress': ticks - before,
      };
    } finally {
      release();
      await subscription?.cancel();
      timer.cancel();
    }
  }
  if (scenario == 'poll-fallback') {
    configure(30);
    final values = await access
        .withPollInterval(const Duration(milliseconds: 20))
        .watch(Entities.networkPath)
        .take(3)
        .toList();
    check(
      values.length == 3 &&
          values.every((v) => v.internetValidated == true) &&
          counter(1) == 0,
      'Unsupported event registration preserves fresh equal-value polling.',
    );
    await _until(() => counter(0) == 0);
    return {'polls': values.length};
  }
  if (scenario == 'denied-registration') {
    configure(31);
    typed(
      await errorOf(slow.watch(Entities.networkPath).first),
      ErrorCode.permissionDenied,
    );
    await _until(() => counter(0) == 0);
    check(
      counter(2) == 0 &&
          (await access.get(Entities.networkPath)).internetValidated == true,
      'Registration denial does not leak or prevent a separate read.',
    );
    return {};
  }
  final values = <NetworkPathSnapshot>[],
      secondValues = <NetworkPathSnapshot>[],
      errors = <Object>[];
  StreamSubscription<NetworkPathSnapshot>? first, second;
  try {
    first = slow
        .watch(Entities.networkPath)
        .listen(values.add, onError: errors.add);
    await _until(() => values.length == 1 || errors.isNotEmpty);
    check(errors.isEmpty && counter(2) == 1, 'Initial state is available.');
    if (scenario == 'shared-observers') {
      second = slow
          .watch(Entities.networkPath)
          .listen(secondValues.add, onError: errors.add);
      await _until(() => secondValues.length == 1);
      check(counter(1) == 1, 'Two streams share one native registration.');
      configure(9);
      check(emit() == 0, 'Native state change starts.');
      await _until(() => values.length == 2 && secondValues.length == 2);
      check(
        values.last.internetValidated == false &&
            secondValues.last.metered == true,
        'Each stream refreshes changed native fields.',
      );
      await first.cancel();
      first = null;
      check(counter(2) == 1, 'A sibling keeps the native subscription.');
      check(emit() == 0, 'Equal-value event starts.');
      await _until(() => secondValues.length == 3);
      await second.cancel();
      second = null;
      await _until(() => counter(0) == 0 && counter(2) == 0);
      return {};
    }
    if (scenario == 'watch-error-recovery') {
      configure(5);
      check(emit() == 0, 'Failure update starts.');
      await _until(() => errors.length == 1);
      typed(errors.single, ErrorCode.permissionDenied);
      await _until(() => counter(2) == 0);
      configure(0);
      check(
        (await slow.watch(Entities.networkPath).first).internetValidated ==
            true,
        'Explicit new watch recovers.',
      );
      await _until(() => counter(0) == 0 && counter(2) == 0);
      return {};
    }
    configure(32);
    await first.cancel();
    first = null;
    await _until(() => counter(3) == 1);
    check(
      counter(2) == 1 && counter(0) == 1,
      'Failed native unregister retains ownership for cleanup.',
    );
    check(emit() == 0, 'Late callback starts after public unsubscribe.');
    await _until(() => counter(5) == 0);
    check(
      values.length == 1 &&
          errors.isEmpty &&
          (await access.get(Entities.networkPath)).internetValidated == true,
      'Retired callbacks are ignored while independent get stays usable.',
    );
    if (scenario == 'persistent-unregister') {
      access.dispose();
      await _until(() => counter(3) == 2);
      check(
        counter(2) == 1 && counter(0) == 1,
        'Persistent OS refusal retains one native owner without infinite retry.',
      );
      check(emit() == 0, 'Callback after context closure is safe.');
      await _until(() => counter(5) == 0);
      return {'persistentNativeOwner': true};
    }
    configure(0);
    check(
      (await slow.watch(Entities.networkPath).first).internetValidated == true,
      'Explicit resubscribe first retries retained cleanup.',
    );
    await _until(() => counter(0) == 0 && counter(2) == 0);
    check(
      counter(1) == 2 && counter(3) == 3,
      'Cleanup retry releases old owner before another subscription.',
    );
    return {};
  } finally {
    await first?.cancel();
    await second?.cancel();
  }
}
