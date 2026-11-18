part of 'native_windows_network_events.dart';

Future<Map<String, Object?>> _realOSRegistration() async {
  final path = File(
    '.tools/windows-memory-probe/Release/device_readout_network_live.dll',
  ).absolute.path;
  final library = ffi.DynamicLibrary.open(path);
  final counter = library
      .lookupFunction<ffi.Uint32 Function(ffi.Uint32), int Function(int)>(
        'readout_network_live_counter',
      );
  final access = DeviceAccess.isolated(
    createNativeCollector,
    initialData: NativeCollectorBindings(windowsNetworkLibrary: path),
  );
  final subscriptions = <StreamSubscription<NetworkInterfaceSnapshot>>[];
  try {
    final target = (await access.networkInterfaces.list()).first;
    await access.get(target);
    check(
      counter(1) == 0 && counter(2) == 0,
      'Real OS get/list remain observation-free.',
    );
    final values = <NetworkInterfaceSnapshot>[], errors = <Object>[];
    final view = access.withPollInterval(const Duration(seconds: 10));
    final first = view.watch(target).listen(values.add, onError: errors.add);
    subscriptions.add(first);
    await _until(() => values.isNotEmpty || errors.isNotEmpty);
    // AF_UNSPEC may acknowledge separately for each family. Verify each native
    // source rather than assuming one acknowledgement per registration.
    await _until(
      () => [6, 7, 8].every((field) => counter(field) > 0) || errors.isNotEmpty,
    );
    check(
      errors.isEmpty && counter(1) == 3 && counter(2) == 3,
      'All three actual Windows registrations acknowledge through the production callback bridge.',
    );
    final second = view.watch(target).listen(values.add, onError: errors.add);
    subscriptions.add(second);
    await _until(() => values.length >= 2 || errors.isNotEmpty);
    check(
      errors.isEmpty && counter(2) == 3,
      'Actual native registrations are shared.',
    );
    await first.cancel();
    check(
      counter(1) == 3,
      'Another real OS watch retains the registration group.',
    );
    await second.cancel();
    await _until(() => counter(1) == 0);
    check(
      counter(3) == 3 && counter(0) == 0,
      'Actual OS unsubscribe releases registrations and query buffers.',
    );
    return {
      'nativeAcknowledgements': counter(5),
      'acknowledgementsByKind': [counter(6), counter(7), counter(8)],
      'registrationCalls': counter(2),
      'unregisterCalls': counter(3),
      'activeRegistrations': counter(1),
      'updates': values.length,
    };
  } finally {
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    access.dispose();
    library.close();
  }
}

Future<Map<String, Object?>> _exercise(
  String scenario,
  DeviceAccess access,
  Entity<NetworkInterfaceSnapshot> target,
  int Function(int) counter,
  int Function(int, int, int, int, int, int) emit,
  void Function(int) configure,
  void Function() release,
) async {
  final values = <NetworkInterfaceSnapshot>[], errors = <Object>[];
  final subscriptions = <StreamSubscription<NetworkInterfaceSnapshot>>[];
  Map<String, Object?> result = {};
  StreamSubscription<NetworkInterfaceSnapshot> listen({
    Duration interval = const Duration(seconds: 10),
    DeviceAccess? configured,
  }) {
    final subscription = (configured ?? access.withPollInterval(interval))
        .watch(target)
        .listen(values.add, onError: errors.add);
    subscriptions.add(subscription);
    return subscription;
  }

  Future<void> emitOnce(
    int kind, {
    int type = 0,
    int row = 1,
    int late = 0,
    int burst = 1,
    int value = 1,
  }) async {
    check(
      emit(kind, type, row, late, burst, value) == 0,
      'Owned native callback thread starts.',
    );
    await _until(() => counter(8) == 0);
  }

  try {
    if (scenario == 'held-registration' || scenario == 'held-unregister') {
      var ticks = 0;
      final timer = Timer.periodic(
        const Duration(milliseconds: 5),
        (_) => ticks++,
      );
      try {
        if (scenario == 'held-registration') {
          configure(30);
          listen(
            configured: access
                .withReadTimeout(const Duration(milliseconds: 200))
                .withPollInterval(const Duration(seconds: 10)),
          );
        } else {
          final subscription = listen();
          await _until(() => values.isNotEmpty);
          configure(31);
          await subscription.cancel().timeout(const Duration(seconds: 1));
        }
        await _until(() => counter(1) == 1);
        final before = ticks;
        await Future<void>.delayed(const Duration(milliseconds: 40));
        if (scenario == 'held-registration') {
          await _until(() => errors.isNotEmpty);
          check(
            errors.single is DeviceReadoutException &&
                (errors.single as DeviceReadoutException).code ==
                    ErrorCode.readTimeout,
            'Initial deadline includes blocked native registration.',
          );
        } else {
          await emitOnce(0);
        }
        check(
          counter(1) == 1 && counter(2) != counter(3) && ticks - before >= 2,
          'Host timers progress while native registration/unregister remains held on another thread.',
        );
        result = {
          'completedBeforeNativeReturn': true,
          'progressDuringHold': ticks - before,
          'workerThread': counter(2),
          'callerThread': counter(3),
        };
        release();
        await _until(() => counter(4) == 0 && counter(1) == 0);
        check(
          (await access.get(target)).name == 'Fixture network',
          'Ordinary reads recover after native completion.',
        );
      } finally {
        release();
        timer.cancel();
      }
    } else if (scenario == 'denied-registration' ||
        scenario == 'failed-registration-output' ||
        scenario == 'null-registration-handle') {
      final mode = scenario == 'denied-registration'
          ? 42
          : scenario == 'failed-registration-output'
          ? 43
          : 44;
      configure(mode);
      listen();
      await _until(() => errors.isNotEmpty);
      check(
        errors.single is DeviceReadoutException &&
            (errors.single as DeviceReadoutException).code ==
                (mode == 42
                    ? ErrorCode.permissionDenied
                    : ErrorCode.readFailed),
        'Registration failure preserves its common error kind.',
      );
      await _until(() => counter(4) == 0);
      check(
        counter(5) == counter(6),
        'Partial registration unwinds every returned native handle.',
      );
      check(
        values.isEmpty,
        'Failed observation does not emit a successful initial snapshot.',
      );
    } else if (scenario == 'poll-fallback' || scenario == 'partial-fallback') {
      configure(scenario == 'poll-fallback' ? 40 : 41);
      final subscription = listen(interval: const Duration(milliseconds: 20));
      await _until(() => values.length >= 3 || errors.isNotEmpty);
      check(
        errors.isEmpty &&
            values.take(3).every((v) => v.mtuBytes == BigInt.from(1500)),
        'Unsupported notifications retain duplicate polling snapshots.',
      );
      check(
        values[2].collectedAt.isAfter(values[1].collectedAt) &&
            counter(4) == (scenario == 'poll-fallback' ? 0 : 2),
        'Only available native sources remain registered.',
      );
      if (scenario == 'partial-fallback') {
        await emitOnce(2);
        await _until(() => values.last.mtuBytes == BigInt.from(1501));
      }
      await subscription.cancel();
      await _until(() => counter(4) == 0);
    } else if (scenario == 'shared-observers') {
      final first = listen();
      await _until(() => values.length == 1);
      final second = listen();
      await _until(() => values.length == 2);
      check(
        counter(4) == 3 && counter(5) == 3,
        'Context views share one set of native registrations.',
      );
      await emitOnce(0, value: 0);
      await _until(() => values.length == 4);
      check(
        values.every((v) => v.mtuBytes == BigInt.from(1500)),
        'Equal-value native events remain snapshots.',
      );
      await first.cancel();
      check(
        counter(4) == 3,
        'One unsubscribe leaves another subscriber active.',
      );
      await emitOnce(1, value: 2);
      await _until(() => values.length == 5);
      await second.cancel();
      await _until(() => counter(4) == 0);
      final third = listen();
      await _until(() => values.length == 6);
      check(
        counter(5) == 6,
        'A new subscription explicitly registers after the previous group ended.',
      );
      await third.cancel();
      await _until(() => counter(4) == 0);
    } else {
      final subscription = listen();
      await _until(() => values.length == 1 || errors.isNotEmpty);
      check(
        errors.isEmpty && counter(4) == 3,
        'Initial observation is registered.',
      );
      if (scenario == 'invalid-notification' || scenario == 'missing-row') {
        await emitOnce(
          0,
          type: scenario == 'invalid-notification' ? 4 : 0,
          row: scenario == 'missing-row' ? 0 : 1,
        );
        await _until(() => errors.isNotEmpty);
        check(
          errors.single is DeviceReadoutException &&
              (errors.single as DeviceReadoutException).code ==
                  ErrorCode.readFailed,
          'Malformed callbacks terminate with ReadFailed.',
        );
      } else if (scenario == 'protocol-deletion') {
        await emitOnce(1, type: 2);
        await _until(() => values.length == 2);
        check(
          errors.isEmpty &&
              (await access.networkInterfaces.list()).single == target,
          'Deleting an address row does not delete the adapter.',
        );
      } else if (scenario == 'event-removal') {
        configure(10);
        await emitOnce(0, type: 2);
        await _until(() => errors.isNotEmpty);
        check(
          errors.single is DeviceReadoutException &&
              (errors.single as DeviceReadoutException).code ==
                  ErrorCode.entityRemoved,
          'A native signal plus missing inventory retires the target.',
        );
        configure(0);
        check(
          (await access.networkInterfaces.list()).single != target,
          'The replacement has a new lifetime.',
        );
      } else if (scenario == 'late-notification') {
        await subscription.cancel();
        await _until(() => counter(4) == 0);
        final count = values.length;
        await emitOnce(0, late: 1);
        await Future<void>.delayed(const Duration(milliseconds: 40));
        check(
          values.length == count && errors.isEmpty,
          'A late native callback cannot enter the closed Dart trampoline.',
        );
      } else if (scenario == 'failed-unregister' ||
          scenario == 'persistent-unregister') {
        configure(32);
        await subscription.cancel();
        await _until(() => counter(6) == 3);
        await emitOnce(0);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        check(
          values.length == 1 && errors.isEmpty,
          'Unregister failure leaves native callbacks detached from Dart.',
        );
        if (scenario == 'persistent-unregister') {
          listen();
          await _until(() => errors.isNotEmpty);
          check(
            errors.single is DeviceReadoutException &&
                (errors.single as DeviceReadoutException).code ==
                    ErrorCode.permissionDenied &&
                counter(5) == 3 &&
                counter(4) == 3,
            'Repeated cleanup failure rejects new observation without accumulating registrations.',
          );
          errors.clear();
        }
        configure(0);
        final next = listen();
        await _until(() => values.length == 2 || errors.isNotEmpty);
        check(
          errors.isEmpty && counter(4) == 3,
          'Explicit resubscription cleans failed handles before registering again.',
        );
        await next.cancel();
        await _until(() => counter(4) == 0);
      } else if (scenario == 'callback-overflow') {
        configure(20);
        await emitOnce(0);
        await _until(() => counter(1) == 1);
        await emitOnce(0, burst: 4096);
        release();
        await _until(() => errors.isNotEmpty);
        check(
          errors.single is DeviceReadoutException &&
              (errors.single as DeviceReadoutException).code ==
                  ErrorCode.readFailed,
          'A native notification flood fails with a bounded queue.',
        );
      }
      await subscription.cancel();
      await _until(() => counter(4) == 0);
    }
    check(counter(8) == 0, 'Native emitters have finished.');
    return {
      'updates': values.length,
      'activeRegistrations': counter(4),
      'registrationCalls': counter(5),
      'unregisterCalls': counter(6),
      ...result,
    };
  } finally {
    release();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  }
}
