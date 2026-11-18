import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:device_readout/device_readout.dart';
import 'package:device_readout/src/transport_native.dart'
    show NativeCollectorBindings, createNativeCollector;

import 'observers.dart' show check, errorOf;
part 'native_windows_battery_pack_cases.dart';

const _flag = '--device-readout-battery-packs-child';
const _scenarios = [
  'discovery-fields',
  'retirement-after-close-failure',
  'interface-lifetime',
  'held-read',
  'remove-during-read',
];

Future<ErrorCode?> _errorCode(Future<Object?> operation) async {
  final error = await errorOf(operation);
  if (error == null) return null;
  if (error is DeviceReadoutException) return error.code;
  throw error;
}

Future<bool> runChildIfRequested(List<String> args) async {
  if (args.isEmpty || args.first != _flag) return false;
  check(
    args.length == 3 &&
        int.parse(args[1]) != pid &&
        _scenarios.contains(args[2]),
    'Owned battery-pack child arguments.',
  );
  final path = File(
    '.tools/windows-memory-probe/Release/device_readout_battery_packs_fixture.dll',
  ).absolute.path;
  final fixture = ffi.DynamicLibrary.open(path);
  final counter = fixture
      .lookupFunction<ffi.Uint32 Function(ffi.Uint32), int Function(int)>(
        'readout_pack_counter',
      );
  final configure = fixture
      .lookupFunction<
        ffi.Void Function(ffi.Uint32, ffi.Uint32),
        void Function(int, int)
      >('readout_pack_configure');
  configure(0, 0);
  final access = DeviceAccess.isolated(
    createNativeCollector,
    initialData: NativeCollectorBindings(windowsBatteryLibrary: path),
  );
  try {
    final targets = await access.list(Entities.battery);
    check(
      targets.length == 2 && targets[0] != targets[1],
      'Two individual battery slots produce distinct typed handles.',
    );
    if (args[2] != 'discovery-fields' &&
        args[2] != 'retirement-after-close-failure') {
      final emit = fixture
          .lookupFunction<
            ffi.Uint32 Function(ffi.Uint32, ffi.Uint32),
            int Function(int, int)
          >('readout_pack_emit');
      final release = fixture
          .lookupFunction<ffi.Void Function(), void Function()>(
            'readout_pack_release',
          );
      final extra = await _packExercise(
        args[2],
        access,
        targets,
        counter,
        configure,
        emit,
        release,
      );
      access.dispose();
      await _until(() => counter(2) == 0 && counter(10) == 0);
      check(
        counter(0) == 0 && counter(1) == 0 && counter(6) == 0,
        'All native pack resources close after the scenario.',
      );
      print(
        'BATTERY_PACK_CHILD ${jsonEncode({'childPid': pid, 'scenario': args[2], 'passed': true, 'handles': counter(0), 'inventories': counter(1), 'registrations': counter(2), ...extra})}',
      );
      return true;
    }
    if (args[2] == 'retirement-after-close-failure') {
      configure(1, 303);
      configure(0, 6);
      check(
        await _errorCode(access.list(Entities.battery)) ==
            ErrorCode.permissionDenied,
        'Native close failure is reported and the still-owned handle is retained.',
      );
      check(
        counter(0) == 1 && counter(9) == 1,
        'Failed close does not claim the native handle was released.',
      );
      configure(1, 101);
      check(
        await _errorCode(access.get(targets.first)) == ErrorCode.entityRemoved,
        'A confirmed replacement remains retired even when the original tag returns after failed inventory cleanup.',
      );
      check(
        (await access.get(targets.last)).present == true,
        'An unrelated target survives the failed inventory.',
      );
      final refreshed = await access.list(Entities.battery);
      check(
        refreshed.first != targets.first && refreshed.last == targets.last,
        'Rediscovery creates only the replaced lifetime anew.',
      );
      access.dispose();
      final end = DateTime.now().add(const Duration(seconds: 2));
      while (counter(2) != 0) {
        check(DateTime.now().isBefore(end), 'Pack cleanup completes.');
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      check(
        counter(0) == 0 && counter(1) == 0,
        'Retained native handles are released on subsequent worker operations.',
      );
      print(
        'BATTERY_PACK_CHILD ${jsonEncode({'childPid': pid, 'scenario': args[2], 'passed': true, 'handles': counter(0), 'inventories': counter(1), 'registrations': counter(2), 'closeFailures': counter(9)})}',
      );
      return true;
    }
    final again = await access
        .withPollInterval(const Duration(seconds: 2))
        .list(Entities.battery);
    check(
      again[0] == targets[0] && again[1] == targets[1],
      'Unchanged pack tags preserve handles across views.',
    );
    check(
      await access.current(Entities.battery) == null,
      'No arbitrary individual pack replaces the unavailable aggregate.',
    );
    final value = await access.get(targets.first);
    check(
      value.present == true &&
          value.level == 0.4 &&
          value.charging == false &&
          value.state == BatteryState.discharging,
      'Selected battery status and level.',
    );
    check(
      value.designEnergyMilliwattHours == 60000 &&
          value.fullChargeEnergyMilliwattHours == 50000 &&
          value.remainingEnergyMilliwattHours == 20000,
      'Distinct native energy capacities.',
    );
    check(
      value.voltageMillivolts == 10000 &&
          value.chargeRateMilliwatts == -5000 &&
          value.currentMicroamps == -500000,
      'Signed power and current retain their units.',
    );
    check(
      value.temperatureCelsius != null &&
          (value.temperatureCelsius! - 24.95).abs() < 0.000001 &&
          value.timeToEmpty == const Duration(hours: 2) &&
          value.technology == 'LION' &&
          value.cycleCount == BigInt.from(42),
      'Native temperature, runtime, chemistry and cycles.',
    );
    check(
      value.timeToFull == null &&
          value.averageCurrentMicroamps == null &&
          value.chargeCounterMicroampHours == null &&
          value.health == null,
      'Unsupported meanings stay null.',
    );
    final relative = await access.get(targets.last);
    check(
      relative.level == 0.4 &&
          relative.voltageMillivolts == 10000 &&
          relative.designEnergyMilliwattHours == null &&
          relative.fullChargeEnergyMilliwattHours == null &&
          relative.remainingEnergyMilliwattHours == null &&
          relative.chargeRateMilliwatts == null &&
          relative.currentMicroamps == null,
      'Relative units permit a ratio but not fabricated physical energy or power.',
    );
    final values = await access
        .withPollInterval(const Duration(milliseconds: 15))
        .watch(targets.first)
        .take(3)
        .toList();
    check(
      values.every((s) => s.level == 0.4) &&
          values.last.collectedAt.isAfter(values.first.collectedAt),
      'Individual watch emits fresh equal snapshots.',
    );
    check(
      counter(0) == 0 && counter(1) == 0 && counter(2) == 1 && counter(6) == 0,
      'Read-only native handles close; interface observation precedes inventory and survives idle watches.',
    );
    access.dispose();
    final end = DateTime.now().add(const Duration(seconds: 2));
    while (counter(2) != 0) {
      check(DateTime.now().isBefore(end), 'Native pack context closes.');
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    check(
      counter(7) == 1,
      'The persistent interface registration is removed exactly once.',
    );
    print(
      'BATTERY_PACK_CHILD ${jsonEncode({'childPid': pid, 'scenario': args[2], 'passed': true, 'handles': counter(0), 'inventories': counter(1), 'registrations': counter(2), 'worker': counter(4), 'caller': counter(5)})}',
    );
  } finally {
    access.dispose();
  }
  return true;
}

Future<void> _run(String scenario) async {
  if (!Platform.isWindows) return;
  var executable = Platform.resolvedExecutable;
  final jit =
      executable.toLowerCase().endsWith('dart.exe') ||
      executable.toLowerCase().endsWith('dartvm.exe');
  if (jit)
    executable = File.fromUri(File(executable).parent.uri.resolve('dartvm.exe'))
        .path;
  final child = await Process.start(executable, [
    if (jit) Platform.script.toFilePath(),
    _flag,
    '$pid',
    scenario,
  ]);
  final output = child.stdout.transform(utf8.decoder).join(),
      errors = child.stderr.transform(utf8.decoder).join();
  var terminal = false;
  try {
    final exit = await child.exitCode.timeout(const Duration(seconds: 9));
    terminal = true;
    final stdout = await output, stderr = await errors;
    check(
      exit == 0,
      'Battery-pack child ${child.pid} $scenario failed ($exit): $stdout $stderr',
    );
    final line = const LineSplitter()
        .convert(stdout)
        .singleWhere((s) => s.startsWith('BATTERY_PACK_CHILD '));
    final report =
        jsonDecode(line.substring('BATTERY_PACK_CHILD '.length)) as Map;
    check(
      report['passed'] == true &&
          report['childPid'] == child.pid &&
          report['scenario'] == scenario,
      'Report belongs to the owned battery-pack child.',
    );
    print(line);
  } finally {
    if (!terminal) {
      child.kill();
      await child.exitCode;
    }
  }
}

final checks = <String, Future<void> Function()>{
  for (final scenario in _scenarios)
    'native Windows battery packs $scenario': () => _run(scenario),
};
Future<void> main(List<String> args) async {
  if (await runChildIfRequested(args)) return;
  if (args.isNotEmpty) {
    await _run(args.single);
    return;
  }
  for (final test in checks.values) {
    await test();
  }
}
