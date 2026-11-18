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
