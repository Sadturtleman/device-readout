import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:device_readout/device_readout.dart';
import 'package:device_readout/src/transport_native.dart'
    show NativeCollectorBindings, createNativeCollector;

import 'observers.dart' show check, errorOf;
part 'native_windows_battery_cases.dart';

const _flag = '--device-readout-battery-child';
const _scenarios = [
  'report-events',
  'field-contracts',
  'shared-observers',
  'poll-fallback',
  'denied-registration',
  'failed-unregister',
  'persistent-unregister',
  'held-current',
  'held-reference',
  'held-read',
  'held-watch',
  'held-register',
  'held-unregister',
  'cancel-read',
  'dispose-read',
];
Future<void> _until(bool Function() predicate) async {
  final end = DateTime.now().add(const Duration(seconds: 2));
  while (!predicate()) {
    check(DateTime.now().isBefore(end), 'Native battery operation completes.');
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

Future<bool> runChildIfRequested(List<String> args) async {
  if (args.isEmpty || args.first != _flag) return false;
  check(
    args.length == 3 &&
        int.parse(args[1]) != pid &&
        _scenarios.contains(args[2]),
    'Owned battery child arguments.',
  );
  final path = File(
    '.tools/windows-memory-probe/Release/device_readout_battery_fixture.dll',
  ).absolute.path;
  final fixture = ffi.DynamicLibrary.open(path);
  final counter = fixture
      .lookupFunction<ffi.Uint32 Function(ffi.Uint32), int Function(int)>(
        'readout_battery_counter',
      );
  final emit = fixture.lookupFunction<ffi.Uint32 Function(), int Function()>(
    'readout_battery_emit',
  );
  final configure = fixture
      .lookupFunction<ffi.Void Function(ffi.Int32), void Function(int)>(
        'readout_battery_configure',
      );
  final release = fixture.lookupFunction<ffi.Void Function(), void Function()>(
    'readout_battery_release',
  );
  final access = DeviceAccess.isolated(
    createNativeCollector,
    initialData: NativeCollectorBindings(windowsBatteryLibrary: path),
  );
  StreamSubscription<BatterySnapshot>? first;
  try {
    final target = await access.current(Entities.battery);
    check(
      target != null && counter(0) == 0 && counter(1) == 0,
      'Current acquires and releases the logical endpoint without subscribing.',
    );
    if (args[2] != 'report-events') {
      final extra = await _batteryExercise(
        args[2],
        access,
        target!,
        counter,
        emit,
        configure,
        release,
      );
      print(
        'BATTERY_CHILD ${jsonEncode({'childPid': pid, 'scenario': args[2], 'passed': true, 'objects': counter(0), 'registrations': counter(1), 'removals': counter(3), 'callbacks': counter(4), 'badApartment': counter(6), ...extra})}',
      );
      return true;
    }
    final values = <BatterySnapshot>[], errors = <Object>[];
    final stream = access
        .withPollInterval(const Duration(hours: 1))
        .watch(target!);
    check(counter(1) == 0, 'An uncollected stream is inert.');
    first = stream.listen(values.add, onError: errors.add);
    await _until(() => values.isNotEmpty || errors.isNotEmpty);
    check(
      errors.isEmpty && counter(2) == 1,
      'Aggregate watch subscribes to native ReportUpdated.',
    );
    check(
      values.single.present == true &&
          values.single.state == BatteryState.discharging &&
          values.single.charging == false &&
          values.single.level == 0.4 &&
          values.single.chargeRateMilliwatts == -5000 &&
          values.single.designEnergyMilliwattHours == 60000 &&
          values.single.fullChargeEnergyMilliwattHours == 50000 &&
          values.single.remainingEnergyMilliwattHours == 20000 &&
          values.single.timeToEmpty == const Duration(hours: 2) &&
          values.single.timeToFull == null,
      'Native fields retain distinct capacities, signed power and remaining runtime.',
    );
    check(emit() == 0, 'An independent native thread emits a report update.');
    await _until(() => values.length == 2 || errors.isNotEmpty);
    check(
      errors.isEmpty &&
          values.last.collectedAt.isAfter(values.first.collectedAt),
      'A native report event refreshes before the one-hour poll.',
    );
    await first.cancel();
    first = null;
    await _until(() => counter(0) == 0 && counter(2) == 0 && counter(5) == 0);
    check(
      counter(1) == 1 && counter(3) == 1 && counter(6) == 0,
      'Native observation is balanced and all COM operations stay in an MTA.',
    );
    print(
      'BATTERY_CHILD ${jsonEncode({'childPid': pid, 'scenario': args[2], 'passed': true, 'objects': counter(0), 'registrations': counter(1), 'removals': counter(3), 'callbacks': counter(4), 'badApartment': counter(6)})}',
    );
  } finally {
    release();
    await first?.cancel();
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
  var terminal = false;
  final output = child.stdout.transform(utf8.decoder).join(),
      errors = child.stderr.transform(utf8.decoder).join();
  try {
    final exit = await child.exitCode.timeout(const Duration(seconds: 9));
    terminal = true;
    final stdout = await output, stderr = await errors;
    check(
      exit == 0,
      'Battery child ${child.pid} $scenario failed ($exit): $stdout $stderr',
    );
    final line = const LineSplitter()
        .convert(stdout)
        .singleWhere((s) => s.startsWith('BATTERY_CHILD '));
    final report = jsonDecode(line.substring('BATTERY_CHILD '.length)) as Map;
    check(
      report['passed'] == true &&
          report['childPid'] == child.pid &&
          report['scenario'] == scenario,
      'Battery report belongs to the owned child.',
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
    'native Windows battery $scenario': () => _run(scenario),
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
