part of 'native_windows_connectivity_faults.dart';

Future<Map<String, Object?>> _performanceExercise(
  String scenario,
  DeviceAccess access,
  int Function(int) counter,
  int Function() emit,
  void Function(int) configure,
  void Function() release,
) async {
  final slow = access.withPollInterval(const Duration(hours: 1));
  if (scenario.contains('-held-') ||
      scenario == 'performance-cancel' ||
      scenario == 'performance-dispose') {
    var ticks = 0;
    final timer = Timer.periodic(
      const Duration(milliseconds: 5),
      (_) => ticks++,
    );
    final sibling = DeviceAccess.native();
    StreamSubscription<NetworkPerformanceSnapshot>? subscription;
    final cancellation = CancellationToken();
    try {
      await sibling.capabilities.get(Entities.ram);
      final limited = access.withReadTimeout(const Duration(milliseconds: 250));
      Future<Object?> pending;
      if (scenario.endsWith('-poll') || scenario.endsWith('-event')) {
        final ready = Completer<void>(), failed = Completer<Object>();
        subscription = limited
            .withPollInterval(
              scenario.endsWith('-event')
                  ? const Duration(hours: 1)
                  : const Duration(milliseconds: 25),
            )
            .watch(Entities.networkPerformance)
            .listen(
              (_) {
                if (!ready.isCompleted) ready.complete();
              },
              onError: (Object error) {
                if (!failed.isCompleted) failed.complete(error);
              },
            );
        await ready.future;
        configure(52);
        pending = failed.future;
        if (scenario.endsWith('-event'))
          check(emit() == 0, 'Held update starts from a native event.');
      } else {
        configure(
          scenario.contains('-plan-')
              ? 50
              : scenario.contains('-reference-')
              ? 51
              : 52,
        );
        pending = errorOf(
          scenario.endsWith('-watch')
              ? limited.watch(Entities.networkPerformance).first
              : limited.get(
                  Entities.networkPerformance,
                  cancellation: cancellation,
                ),
        );
      }
      await _until(() => counter(8) == 1);
      final worker = counter(9), caller = counter(7), before = ticks;
      if (scenario == 'performance-cancel') cancellation.cancel();
      if (scenario == 'performance-dispose') access.dispose();
      final error = await pending.timeout(const Duration(seconds: 1));
      if (scenario == 'performance-cancel' ||
          scenario == 'performance-dispose') {
        check(
          error is DeviceReadoutCancelled,
          'Public cancellation settles before the native rate call returns.',
        );
      } else {
        check(
          error is DeviceReadoutException &&
              error.code == ErrorCode.readTimeout,
          'Each blocked native phase retains the read deadline.',
        );
      }
      check(
        (await sibling.get(Entities.ram)).physicalBytes != null,
        'An independent SDK context remains usable during the native hold.',
      );
      await _until(() => ticks > before + 2);
      check(
        counter(8) == 1 && worker != caller,
        'The caller and independent collector progress while native work is still held.',
      );
      access.dispose();
      release();
      await _until(() => counter(8) == 0 && counter(0) == 0 && counter(2) == 0);
      check(
        counter(6) == 0,
        'Delayed plan/reference objects are cleaned up in MTA.',
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
      sibling.dispose();
      timer.cancel();
    }
  }
  if (scenario == 'performance-poll-fallback') {
    configure(30);
    final values = await access
        .withPollInterval(const Duration(milliseconds: 25))
        .watch(Entities.networkPerformance)
        .take(3)
        .toList();
    check(
      values.every(
            (v) => v.downlinkBps == 25000000 && v.uplinkBps == 5000000,
          ) &&
          counter(1) == 0,
      'Unavailable native events retain complete performance polling.',
    );
    for (var i = 1; i < values.length; i++)
      check(
        values[i].collectedAt.isAfter(values[i - 1].collectedAt),
        'Equal rates retain fresh timestamps.',
      );
    await _until(() => counter(0) == 0);
    return {'polls': values.length};
  }
  if (scenario == 'performance-fields') {
    final cases = <(int, double?, double?)>[
      (0, 25000000, 5000000),
      (40, 250000000, 50000000),
      (1, null, null),
      (41, null, null),
      (43, null, null),
      (44, null, 5000000),
      (45, null, 5000000),
      (46, 25000000, null),
      (48, 18446744073709551616.0, 9223372036854775808.0),
      (49, 0, 0),
      (53, null, null),
      (54, 25000000, null),
      (56, 1000000007, 18446744073709551616.0),
    ];
    for (final item in cases) {
      configure(item.$1);
      final value = await access.get(Entities.networkPerformance);
      check(
        value.downlinkBps == item.$2 &&
            value.uplinkBps == item.$3 &&
            value.roundTripTime == null &&
            value.effectiveType == null &&
            value.browserOnline == null,
        'Plan fixture ${item.$1} preserves rates, zero, unsigned conversion and unavailable fields.',
      );
      check(
        counter(0) == 0 && counter(6) == 0,
        'Plan and nullable references release within MTA.',
      );
    }
    for (final item in [
      (42, ErrorCode.readFailed),
      (47, ErrorCode.permissionDenied),
      (7, ErrorCode.readFailed),
      (6, ErrorCode.unsupportedEntity),
    ]) {
      configure(item.$1);
      final error = await errorOf(access.get(Entities.networkPerformance));
      check(
        error is DeviceReadoutException && error.code == item.$2,
        'Whole plan failure is typed: ${item.$1}: $error',
      );
      check(
        counter(0) == 0 && counter(6) == 0,
        'Failed native outputs must still be released.',
      );
    }
    configure(0);
    check(
      (await access.get(Entities.networkPerformance)).downlinkBps == 25000000,
      'Explicit read recovers.',
    );
    return {'performanceFieldFixtures': cases.length + 4};
  }
  final rates = <NetworkPerformanceSnapshot>[],
      paths = <NetworkPathSnapshot>[],
      errors = <Object>[];
  StreamSubscription<NetworkPerformanceSnapshot>? rateSubscription;
  StreamSubscription<NetworkPathSnapshot>? pathSubscription;
  try {
    final source = slow.watch(Entities.networkPerformance);
    check(counter(1) == 0, 'Unconsumed performance stream is inert.');
    rateSubscription = source.listen(rates.add, onError: errors.add);
    pathSubscription = slow
        .watch(Entities.networkPath)
        .listen(paths.add, onError: errors.add);
    await _until(
      () => rates.length == 1 && paths.length == 1 || errors.isNotEmpty,
    );
    check(
      errors.isEmpty && counter(1) == 1 && counter(2) == 1,
      'Path and performance share one native status registration.',
    );
    if (scenario == 'performance-source-failure') {
      configure(42);
      check(emit() == 0, 'Plan failure starts from native invalidation.');
      await _until(() => errors.length == 1 && paths.length == 2);
      check(
        errors.single is DeviceReadoutException &&
            (errors.single as DeviceReadoutException).code ==
                ErrorCode.readFailed &&
            counter(2) == 1,
        'A performance read failure does not terminate its path sibling or shared registration.',
      );
      configure(40);
      check(emit() == 0, 'Surviving path receives another event.');
      await _until(() => paths.length == 3);
      check(
        rates.length == 1 && errors.length == 1,
        'Failed performance watch does not restart itself.',
      );
      final recovered = await slow.watch(Entities.networkPerformance).first;
      check(
        recovered.downlinkBps == 250000000 && counter(1) == 1,
        'Explicit performance watch recovers using the surviving shared registration.',
      );
      await pathSubscription.cancel();
      pathSubscription = null;
      await rateSubscription.cancel();
      rateSubscription = null;
      await _until(() => counter(0) == 0 && counter(2) == 0 && counter(5) == 0);
      return {
        'rateUpdates': rates.length,
        'pathUpdates': paths.length,
        'terminalErrors': errors.length,
      };
    }
    configure(40);
    check(emit() == 0, 'Rate update originates on a native callback thread.');
    await _until(
      () => rates.length == 2 && paths.length == 2 || errors.isNotEmpty,
    );
    check(
      errors.isEmpty &&
          rates.last.downlinkBps == 250000000 &&
          rates.last.uplinkBps == 50000000 &&
          paths.last.connectionState == ConnectionState.connected,
      'Shared invalidation refreshes each typed entity.',
    );
    await pathSubscription.cancel();
    pathSubscription = null;
    check(
      counter(2) == 1,
      'Performance owns the remaining shared registration.',
    );
    check(emit() == 0, 'Equal rate event starts.');
    await _until(() => rates.length == 3 || errors.isNotEmpty);
    check(
      errors.isEmpty &&
          rates.last.downlinkBps == rates[1].downlinkBps &&
          rates.last.collectedAt.isAfter(rates[1].collectedAt),
      'Equal rate events are not discarded.',
    );
    await rateSubscription.cancel();
    rateSubscription = null;
    await _until(() => counter(0) == 0 && counter(2) == 0 && counter(5) == 0);
    check(
      counter(3) == 1 && counter(6) == 0,
      'The final owner unregisters once and cleans up in MTA.',
    );
    return {'rateUpdates': rates.length, 'pathUpdates': paths.length};
  } finally {
    await rateSubscription?.cancel();
    await pathSubscription?.cancel();
  }
}
