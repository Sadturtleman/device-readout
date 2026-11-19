part of 'native_windows_battery_packs.dart';

Future<void> _until(bool Function() condition) async {
  final end = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    check(DateTime.now().isBefore(end), 'Native pack operation completes.');
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

Future<Map<String, Object?>> _packExercise(
  String scenario,
  DeviceAccess access,
  List<Entity<BatterySnapshot>> targets,
  int Function(int) counter,
  void Function(int, int) configure,
  int Function(int, int) emit,
  void Function() release,
) async {
  if (scenario == 'status-delayed-cancel' ||
      scenario == 'status-removal-during-read') {
    final fixture = ffi.DynamicLibrary.open(
      File(
        '.tools/windows-memory-probe/Release/device_readout_battery_packs_fixture.dll',
      ).absolute.path,
    );
    final fail = fixture
        .lookupFunction<
          ffi.Uint32 Function(ffi.Uint32, ffi.Uint32),
          int Function(int, int)
        >('readout_pack_status_fail');
    final values = <BatterySnapshot>[], errors = <Object>[];
    final stream = access
        .withPollInterval(const Duration(hours: 1))
        .watch(targets.first)
        .listen(values.add, onError: errors.add);
    var progress = 0;
    final heartbeat = Timer.periodic(
      const Duration(milliseconds: 2),
      (_) => progress++,
    );
    try {
      await _until(
        () => counter(13) == 1 && values.isNotEmpty || errors.isNotEmpty,
      );
      check(
        errors.isEmpty,
        'Status observation starts before lifecycle verification.',
      );
      if (scenario == 'status-delayed-cancel') {
        await stream.cancel().timeout(const Duration(milliseconds: 250));
        await _until(() => counter(16) == 1);
        check(
          counter(12) == 1 && counter(13) == 1 && counter(15) == 0,
          'Cancellation keeps pending buffers and native ownership until actual completion.',
        );
        check(
          (await access.get(Entities.ram)).kernelAccessibleBytes != null,
          'The same context remains readable during delayed native cancellation.',
        );
        access.dispose();
        await _until(() => counter(2) == 0);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        check(
          counter(12) == 1 && counter(13) == 1 && progress > 2,
          'Context disposal and caller progress do not wait for the status driver.',
        );
        release();
        await _until(() => counter(12) == 0);
        check(
          counter(13) == 0 &&
              counter(15) == 1 &&
              counter(6) == 0 &&
              errors.isEmpty,
          'Late native completion safely closes the status handle after context disposal.',
        );
        return {
          'cancelBeforeCompletion': true,
          'disposeBeforeCompletion': true,
          'progress': progress,
          'statusCompletions': counter(15),
        };
      }
      configure(0, 50);
      final pending = _errorCode(access.get(targets.first));
      await _until(() => counter(11) == 1);
      check(
        fail(0, 2) == 0,
        'The pending status operation reports the pack was removed.',
      );
      await _until(() => counter(12) == 0);
      check(
        counter(11) == 1,
        'Status removal completes independently of the blocked collection lane.',
      );
      release();
      check(
        await pending == ErrorCode.entityRemoved,
        'A report spanning observed status removal cannot escape after native completion.',
      );
      await _until(() => errors.isNotEmpty);
      check(
        errors.single is DeviceReadoutException &&
            (errors.single as DeviceReadoutException).code ==
                ErrorCode.entityRemoved,
        'Status removal terminates its public watch.',
      );
      final fresh = await access.list(Entities.battery);
      check(
        fresh.first != targets.first && fresh.last == targets.last,
        'Status removal retires only its target despite path/tag reuse.',
      );
      check(
        (await access.get(fresh.first)).present == true,
        'Rediscovered replacement remains readable.',
      );
      return {
        'statusRemovalRetiresHandle': true,
        'rejectedInFlightReport': true,
        'progress': progress,
      };
    } finally {
      release();
      heartbeat.cancel();
      await stream.cancel();
    }
  }
  if (scenario == 'status-events' || scenario == 'status-kernel-completion') {
    final fixture = ffi.DynamicLibrary.open(
      File(
        '.tools/windows-memory-probe/Release/device_readout_battery_packs_fixture.dll',
      ).absolute.path,
    );
    final change = fixture
        .lookupFunction<
          ffi.Uint32 Function(ffi.Uint32, ffi.Uint32, ffi.Uint32, ffi.Int32),
          int Function(int, int, int, int)
        >('readout_pack_status_emit');
    final values = <BatterySnapshot>[], errors = <Object>[];
    final subscription = access
        .withPollInterval(const Duration(hours: 1))
        .watch(targets.first)
        .listen(values.add, onError: errors.add);
    try {
      await _until(() => values.isNotEmpty || errors.isNotEmpty);
      check(
        errors.isEmpty && values.first.level == 0.4,
        'Individual status watch has an immediate snapshot.',
      );
      final deadline = DateTime.now().add(const Duration(seconds: 2));
      while (counter(13) == 0 &&
          errors.isEmpty &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      check(
        counter(13) == 1 && errors.isEmpty,
        'watch subscribes to a pending native battery status operation before the one-hour poll.',
      );
      check(
        (await access.get(Entities.ram)).kernelAccessibleBytes != null,
        'A pending status wait leaves the same collection context available.',
      );
      check(
        change(0, 5, 25000, 3000) == 0,
        'The driver completes with a charging status.',
      );
      await _until(
        () =>
            values.any((s) => s.state == BatteryState.charging) ||
            errors.isNotEmpty,
      );
      final charged = values.last;
      check(
        errors.isEmpty &&
            charged.state == BatteryState.charging &&
            charged.level == 0.5 &&
            charged.chargeRateMilliwatts == 3000 &&
            charged.currentMicroamps == 300000 &&
            charged.designEnergyMilliwattHours == 60000,
        'Captured status supplies its own level, power and current together with the remaining pack metadata.',
      );
      check(
        (await access.get(targets.first)).state == BatteryState.discharging,
        'The event is preserved even when a subsequent direct query already has another status.',
      );
      await _until(() => counter(13) == 1);
      check(
        change(0, 5, 25000, 3000) == 0,
        'An equal native status is accepted.',
      );
      await _until(
        () =>
            values.where((s) => s.state == BatteryState.charging).length == 2 ||
            errors.isNotEmpty,
      );
      check(
        errors.isEmpty && values.last.collectedAt.isAfter(charged.collectedAt),
        'Equal native statuses produce separate fresh snapshots.',
      );
      await _until(() => counter(13) == 1);
      await subscription.cancel();
      await _until(() => counter(12) == 0);
      check(
        counter(13) == 0 &&
            counter(16) == 1 &&
            counter(15) == 3 &&
            counter(6) == 0,
        'Cancellation drains native completion before closing the status handle.',
      );
      return {
        'capturedEvents': 2,
        'pendingWaitKeepsContextReadable': true,
        'statusCompletions': counter(15),
        'statusCancellations': counter(16),
        'kernelCompletion': scenario == 'status-kernel-completion',
      };
    } finally {
      await subscription.cancel();
    }
  }
  if (scenario == 'interface-lifetime') {
    final values = <BatterySnapshot>[], failures = <Object>[];
    final stream = access
        .withPollInterval(const Duration(hours: 1))
        .watch(targets.first)
        .listen(values.add, onError: failures.add);
    try {
      await _until(() => values.isNotEmpty || failures.isNotEmpty);
      check(failures.isEmpty, 'Individual watch starts successfully.');
      check(emit(0, 1) == 0, 'A native thread reports removal.');
      await _until(() => counter(3) == 1);
      check(emit(0, 0) == 0, 'The same path and tag arrive again.');
      await _until(() => counter(3) == 2 && failures.isNotEmpty);
      check(
        failures.single is DeviceReadoutException &&
            (failures.single as DeviceReadoutException).code ==
                ErrorCode.entityRemoved,
        'Removal terminates the old watch before its one-hour poll.',
      );
      check(
        await _errorCode(access.get(targets.first)) == ErrorCode.entityRemoved,
        'The original handle remains retired after same-tag arrival.',
      );
      configure(0, 1);
      check(
        await _errorCode(access.list(Entities.battery)) ==
            ErrorCode.permissionDenied,
        'A failed inventory preserves prior removal evidence.',
      );
      configure(0, 0);
      final fresh = await access.list(Entities.battery);
      check(
        fresh.first != targets.first && fresh.last == targets.last,
        'Only the removed pack receives a new lifetime.',
      );
      check(
        (await access.get(fresh.first)).present == true &&
            (await access.get(targets.last)).present == true,
        'New and unaffected pack handles remain readable.',
      );
      check(
        emit(0, 1) == 0,
        'Idle handles still have native interface observation.',
      );
      await _until(() => counter(3) == 3);
      check(emit(0, 0) == 0, 'Idle same-tag arrival.');
      await _until(() => counter(3) == 4);
      check(
        await _errorCode(access.get(fresh.first)) == ErrorCode.entityRemoved,
        'Removal is remembered without an active watch.',
      );
      return {
        'nativeCallbacks': counter(3),
        'watchSnapshots': values.length,
        'watchFailures': failures.length,
      };
    } finally {
      await stream.cancel();
    }
  }
  configure(0, 50);
  var progress = 0;
  final heartbeat = Timer.periodic(
    const Duration(milliseconds: 2),
    (_) => progress++,
  );
  try {
    if (scenario == 'held-read') {
      final pending = _errorCode(
        access
            .withReadTimeout(const Duration(milliseconds: 150))
            .get(targets.first),
      );
      await _until(() => counter(11) == 1);
      final error = await pending;
      check(
        error == ErrorCode.readTimeout && counter(11) == 1 && progress > 2,
        'Public timeout completes while native pack information is still blocked.',
      );
      final sibling = DeviceAccess.native();
      try {
        check(
          (await sibling.get(Entities.ram)).kernelAccessibleBytes != null,
          'Independent contexts remain readable.',
        );
      } finally {
        sibling.dispose();
      }
      final worker = counter(4), caller = counter(5);
      check(worker != caller, 'Held native I/O uses another OS thread.');
      final recorded = progress;
      release();
      await _until(() => counter(11) == 0);
      check(
        (await access.get(targets.first)).present == true,
        'A timed-out read does not retire the still-present battery.',
      );
      return {
        'completedBeforeNativeReturn': true,
        'progress': recorded,
        'siblingReadable': true,
        'worker': worker,
        'caller': caller,
      };
    }
    final pending = _errorCode(access.get(targets.first));
    await _until(() => counter(11) == 1);
    check(
      emit(0, 1) == 0,
      'Removal arrives while information IOCTL is blocked.',
    );
    await _until(() => counter(3) == 1);
    check(emit(0, 0) == 0, 'Same-tag arrival also precedes native completion.');
    await _until(() => counter(3) == 2);
    check(
      counter(11) == 1,
      'Notifications do not wait for the collection isolate.',
    );
    release();
    check(
      await pending == ErrorCode.entityRemoved,
      'An in-flight report cannot escape after a native removal.',
    );
    final fresh = await access.list(Entities.battery);
    check(
      fresh.first != targets.first && fresh.last == targets.last,
      'Same-tag replacement is discovered with a new handle.',
    );
    return {
      'nativeCallbacks': counter(3),
      'rejectedInFlightReport': true,
      'progress': progress,
    };
  } finally {
    release();
    heartbeat.cancel();
  }
}
