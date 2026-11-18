part of 'native_windows_battery_faults.dart';

Future<Map<String, Object?>> _batteryExercise(
  String scenario,
  DeviceAccess access,
  Entity<BatterySnapshot> target,
  int Function(int) counter,
  int Function() emit,
  void Function(int) configure,
  void Function() release,
) async {
  void typed(Object? error, ErrorCode code) => check(
    error is DeviceReadoutException && error.code == code,
    'Expected $code, got $error.',
  );
  if (scenario == 'field-contracts') {
    final cases =
        <
          (
            int,
            bool?,
            BatteryState?,
            double?,
            double?,
            double?,
            double?,
            double?,
            Duration?,
          )
        >[
          (
            0,
            true,
            BatteryState.discharging,
            0.4,
            -5000,
            60000,
            50000,
            20000,
            const Duration(hours: 2),
          ),
          (1, false, null, null, null, null, null, null, null),
          (
            2,
            null,
            null,
            0.4,
            -5000,
            60000,
            50000,
            20000,
            const Duration(hours: 2),
          ),
          (3, true, BatteryState.discharging, null, 0, 0, 0, 0, Duration.zero),
          (
            4,
            true,
            BatteryState.idle,
            null,
            null,
            null,
            null,
            null,
            const Duration(hours: 2),
          ),
          (
            5,
            true,
            BatteryState.discharging,
            0.4,
            null,
            60000,
            50000,
            20000,
            const Duration(hours: 2),
          ),
          (
            6,
            true,
            BatteryState.discharging,
            0.4,
            null,
            60000,
            50000,
            20000,
            const Duration(hours: 2),
          ),
          (
            11,
            true,
            BatteryState.discharging,
            0.4,
            -5000,
            60000,
            50000,
            20000,
            null,
          ),
          (
            12,
            true,
            BatteryState.discharging,
            0.4,
            -5000,
            60000,
            50000,
            20000,
            null,
          ),
          (
            13,
            true,
            BatteryState.discharging,
            0.4,
            -5000,
            60000,
            50000,
            20000,
            null,
          ),
          (
            14,
            true,
            BatteryState.discharging,
            0.4,
            -5000,
            60000,
            50000,
            20000,
            null,
          ),
          (
            15,
            true,
            BatteryState.discharging,
            0.4,
            -5000,
            60000,
            50000,
            20000,
            const Duration(hours: 2),
          ),
          (
            16,
            true,
            BatteryState.discharging,
            null,
            -5000,
            null,
            null,
            null,
            const Duration(hours: 2),
          ),
          (
            17,
            true,
            BatteryState.discharging,
            0,
            -5000,
            60000,
            50000,
            0,
            const Duration(hours: 2),
          ),
          (
            19,
            true,
            BatteryState.charging,
            0.4,
            5000,
            60000,
            50000,
            20000,
            const Duration(hours: 2),
          ),
          (
            20,
            true,
            BatteryState.idle,
            1,
            0,
            60000,
            50000,
            50000,
            const Duration(hours: 2),
          ),
        ];
    for (final c in cases) {
      configure(c.$1);
      final value = await access.get(target);
      check(
        value.present == c.$2 &&
            value.state == c.$3 &&
            value.level == c.$4 &&
            value.chargeRateMilliwatts == c.$5 &&
            value.designEnergyMilliwattHours == c.$6 &&
            value.fullChargeEnergyMilliwattHours == c.$7 &&
            value.remainingEnergyMilliwattHours == c.$8 &&
            value.timeToEmpty == c.$9 &&
            value.timeToFull == null &&
            value.voltageMillivolts == null,
        'Battery fixture ${c.$1} retains meaningful fields, zero and null without stale absent measurements.',
      );
      check(
        counter(0) == 0 && counter(6) == 0,
        'Every report and boxed reference is released in its MTA.',
      );
    }
    for (final c in [
      (7, ErrorCode.permissionDenied),
      (8, ErrorCode.readFailed),
      (9, ErrorCode.readFailed),
      (18, ErrorCode.permissionDenied),
    ]) {
      configure(c.$1);
      typed(await errorOf(access.get(target)), c.$2);
      check(counter(0) == 0, 'Failed native outputs are also released.');
    }
    configure(10);
    check(
      await access.current(Entities.battery) == null,
      'Unavailable runtime class has no current endpoint.',
    );
    typed(await errorOf(access.get(target)), ErrorCode.unsupportedEntity);
    configure(0);
    check(
      target == await access.current(Entities.battery) &&
          (await access.get(target)).present == true,
      'The logical endpoint survives transient absence or runtime failure.',
    );
    return {'fieldFixtures': cases.length, 'failureFixtures': 5};
  }
  if (scenario == 'shared-observers') {
    final values = <BatterySnapshot>[],
        otherValues = <BatterySnapshot>[],
        errors = <Object>[];
    StreamSubscription<BatterySnapshot>? first, second;
    final slow = access.withPollInterval(const Duration(hours: 1));
    try {
      first = slow.watch(target).listen(values.add, onError: errors.add);
      second = slow.watch(target).listen(otherValues.add, onError: errors.add);
      await _until(
        () =>
            values.length == 1 && otherValues.length == 1 || errors.isNotEmpty,
      );
      check(
        errors.isEmpty && counter(1) == 1 && counter(2) == 1,
        'Watches share one report registration.',
      );
      configure(19);
      check(emit() == 0, 'Charging transition starts.');
      await _until(() => values.length == 2 && otherValues.length == 2);
      check(
        values.last.charging == true &&
            otherValues.last.chargeRateMilliwatts == 5000,
        'Both watches receive fresh native values.',
      );
      await first.cancel();
      first = null;
      check(
        counter(2) == 1 && emit() == 0,
        'The sibling keeps the native source.',
      );
      await _until(() => otherValues.length == 3);
      check(
        values.length == 2 &&
            otherValues.last.collectedAt.isAfter(otherValues[1].collectedAt),
        'Cancelled streams stop while equal sibling updates remain visible.',
      );
      await second.cancel();
      second = null;
      await _until(() => counter(0) == 0 && counter(2) == 0 && counter(5) == 0);
      return {
        'firstUpdates': values.length,
        'siblingUpdates': otherValues.length,
      };
    } finally {
      await first?.cancel();
      await second?.cancel();
    }
  }
  if (scenario == 'poll-fallback') {
    configure(30);
    final values = await access
        .withPollInterval(const Duration(milliseconds: 25))
        .watch(target)
        .take(3)
        .toList();
    check(
      values.length == 3 &&
          values.every((s) => s.level == 0.4) &&
          values.last.collectedAt.isAfter(values.first.collectedAt) &&
          counter(1) == 0 &&
          counter(0) == 0,
      'Unsupported native observation falls back to polling with equal-value delivery.',
    );
    return {'polls': values.length};
  }
  if (scenario == 'denied-registration') {
    configure(31);
    typed(
      await errorOf(access.watch(target).first),
      ErrorCode.permissionDenied,
    );
    await _until(() => counter(0) == 0);
    check(
      (await access.get(target)).present == true,
      'A denied event registration does not poison independent one-shot reads.',
    );
    configure(0);
    check(
      (await access.watch(target).first).present == true,
      'An explicit new stream can recover.',
    );
    await _until(() => counter(2) == 0 && counter(0) == 0);
    return {};
  }
  if (scenario == 'failed-unregister' || scenario == 'persistent-unregister') {
    final values = <BatterySnapshot>[], errors = <Object>[];
    StreamSubscription<BatterySnapshot>? stream;
    try {
      stream = access
          .withPollInterval(const Duration(hours: 1))
          .watch(target)
          .listen(values.add, onError: errors.add);
      await _until(() => values.length == 1 || errors.isNotEmpty);
      check(
        errors.isEmpty && counter(2) == 1,
        'Native report source is active.',
      );
      configure(32);
      await stream.cancel();
      stream = null;
      await _until(() => counter(3) == 1);
      check(
        counter(0) == 1 && counter(2) == 1 && emit() == 0,
        'Failed removal retains its native owner.',
      );
      await _until(() => counter(5) == 0);
      check(
        values.length == 1 &&
            errors.isEmpty &&
            (await access.get(target)).present == true,
        'Retired callbacks do not reach the cancelled watch or poison reads.',
      );
      if (scenario == 'persistent-unregister') {
        access.dispose();
        await _until(() => counter(3) == 2);
        check(
          counter(0) == 1 && counter(2) == 1 && emit() == 0,
          'Permanent native refusal retains one owner without unbounded retry.',
        );
        await _until(() => counter(5) == 0);
        return {'persistentNativeOwner': true};
      }
      configure(0);
      check(
        (await access.watch(target).first).present == true,
        'Explicit resubscription retries retained cleanup.',
      );
      await _until(() => counter(2) == 0 && counter(0) == 0);
      check(
        counter(1) == 2 && counter(3) == 3,
        'The old owner is released before a new registration.',
      );
      return {};
    } finally {
      await stream?.cancel();
    }
  }
  var ticks = 0;
  final timer = Timer.periodic(const Duration(milliseconds: 5), (_) => ticks++);
  final sibling = DeviceAccess.native();
  StreamSubscription<BatterySnapshot>? subscription;
  try {
    final token = CancellationToken();
    final limited = access.withReadTimeout(const Duration(milliseconds: 250));
    Future<Object?> pending;
    if (scenario == 'held-unregister') {
      final ready = Completer<void>();
      subscription = access
          .withPollInterval(const Duration(hours: 1))
          .watch(target)
          .listen((_) {
            if (!ready.isCompleted) ready.complete();
          });
      await ready.future;
      configure(53);
      pending = errorOf(subscription.cancel());
    } else {
      configure(
        scenario == 'held-register'
            ? 52
            : scenario == 'held-current'
            ? 54
            : scenario == 'held-reference'
            ? 51
            : 50,
      );
      pending = errorOf(
        scenario == 'held-current'
            ? limited.current(Entities.battery)
            : scenario == 'held-watch' || scenario == 'held-register'
            ? limited.watch(target).first
            : limited.get(target, cancellation: token),
      );
    }
    await _until(() => counter(8) == 1);
    final worker = counter(9), caller = counter(7), before = ticks;
    if (scenario == 'cancel-read') token.cancel();
    if (scenario == 'dispose-read') access.dispose();
    final error = await pending.timeout(const Duration(seconds: 1));
    if (scenario == 'held-unregister') {
      check(
        error == null,
        'Public cancellation does not join native unregister.',
      );
    } else if (scenario == 'cancel-read' || scenario == 'dispose-read') {
      check(
        error is DeviceReadoutCancelled,
        'Cancellation settles before native return.',
      );
    } else {
      typed(error, ErrorCode.readTimeout);
    }
    await _until(() => ticks > before + 2);
    final ram = await sibling.get(Entities.ram);
    check(
      ram.kernelAccessibleBytes != null && counter(8) == 1 && worker != caller,
      'A held collector does not stop the caller or an independent readable context.',
    );
    access.dispose();
    release();
    await _until(() => counter(8) == 0 && counter(2) == 0 && counter(0) == 0);
    check(
      counter(6) == 0,
      'Deferred cleanup balances native objects in the MTA.',
    );
    return {
      'completedBeforeNativeReturn': true,
      'worker': worker,
      'caller': caller,
      'progress': ticks - before,
      'siblingReadable': true,
    };
  } finally {
    release();
    await subscription?.cancel();
    timer.cancel();
    sibling.dispose();
  }
}
