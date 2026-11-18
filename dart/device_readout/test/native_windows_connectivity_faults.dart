import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:device_readout/device_readout.dart';
import 'package:device_readout/src/transport_native.dart'
    show NativeCollectorBindings, createNativeCollector;

import 'observers.dart' show check, errorOf;
part 'native_windows_connectivity_cases.dart';
part 'native_windows_performance_cases.dart';
part 'native_windows_wifi_cases.dart';

const _flag = '--device-readout-connectivity-child';
const _scenarios = [
  'wifi-fields',
  'wifi-lifetimes',
  'wifi-shared-events',
  'wifi-error-recovery',
  'wifi-retained-close',
  'wifi-permission-observers',
  'wifi-held-inventory',
  'wifi-held-identity',
  'wifi-held-ssid',
  'wifi-held-security',
  'wifi-held-open',
  'wifi-held-query',
  'wifi-held-close',
  'wifi-cancel',
  'wifi-dispose',
  'performance-fields',
  'performance-shared',
  'performance-source-failure',
  'performance-poll-fallback',
  'performance-held-plan-read',
  'performance-held-reference-read',
  'performance-held-value-read',
  'performance-held-value-watch',
  'performance-held-value-poll',
  'performance-held-value-event',
  'performance-cancel',
  'performance-dispose',
  'native-events',
  'field-errors',
  'shared-observers',
  'poll-fallback',
  'denied-registration',
  'watch-error-recovery',
  'held-read',
  'held-watch',
  'held-register',
  'held-unregister',
  'cancel-read',
  'dispose-read',
  'failed-unregister',
  'persistent-unregister',
];
Future<void> _until(bool Function() predicate) async {
  final end = DateTime.now().add(const Duration(seconds: 2));
  while (!predicate()) {
    check(
      DateTime.now().isBefore(end),
      'Native connectivity operation completes.',
    );
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

Future<bool> runChildIfRequested(List<String> args) async {
  if (args.isEmpty || args.first != _flag) return false;
  check(
    args.length == 3 &&
        int.parse(args[1]) != pid &&
        _scenarios.contains(args[2]),
    'Owned child arguments.',
  );
  final path = File(
    '.tools/windows-memory-probe/Release/device_readout_connectivity_fixture.dll',
  ).absolute.path;
  final fixture = ffi.DynamicLibrary.open(path);
  final counter = fixture
      .lookupFunction<ffi.Uint32 Function(ffi.Uint32), int Function(int)>(
        'readout_connectivity_counter',
      );
  final emit = fixture.lookupFunction<ffi.Uint32 Function(), int Function()>(
    'readout_connectivity_emit',
  );
  final configure = fixture
      .lookupFunction<ffi.Void Function(ffi.Int32), void Function(int)>(
        'readout_connectivity_configure',
      );
  final release = fixture.lookupFunction<ffi.Void Function(), void Function()>(
    'readout_connectivity_release',
  );
  final access = DeviceAccess.isolated(
    createNativeCollector,
    initialData: NativeCollectorBindings(windowsConnectivityLibrary: path),
  );
  StreamSubscription<NetworkPathSnapshot>? subscription;
  try {
    final value = await access.get(Entities.networkPath);
    check(
      value.connectionState == ConnectionState.connected &&
          value.internetValidated == true &&
          value.metered == false,
      'Native profile fields pass through public get.',
    );
    check(
      counter(0) == 0 && counter(1) == 0 && counter(6) == 0,
      'Read releases native objects in the MTA without subscribing.',
    );
    if (args[2] != 'native-events') {
      final extra = await _exercise(
        args[2],
        access,
        counter,
        emit,
        configure,
        release,
      );
      print(
        'CONNECTIVITY_CHILD ${jsonEncode({'childPid': pid, 'scenario': args[2], 'passed': true, 'objects': counter(0), 'activeRegistrations': counter(2), 'registrations': counter(1), 'removals': counter(3), 'callbacks': counter(4), 'badApartment': counter(6), ...extra})}',
      );
      return true;
    }
    final stream = access
        .withPollInterval(const Duration(hours: 1))
        .watch(Entities.networkPath);
    check(counter(1) == 0, 'Cold stream does not subscribe.');
    final values = <NetworkPathSnapshot>[], errors = <Object>[];
    subscription = stream.listen(values.add, onError: errors.add);
    await _until(() => values.isNotEmpty || errors.isNotEmpty);
    check(
      errors.isEmpty && values.length == 1 && counter(2) == 1,
      'Watch owns one native status subscription.',
    );
    check(emit() == 0, 'Native callback thread starts.');
    await _until(() => values.length == 2 || errors.isNotEmpty);
    check(
      errors.isEmpty &&
          values.last.internetValidated == true &&
          values.last.collectedAt.isAfter(values.first.collectedAt),
      'A native notification emits an equal but freshly read snapshot before the one-hour poll.',
    );
    await subscription.cancel();
    subscription = null;
    await _until(() => counter(2) == 0 && counter(0) == 0 && counter(5) == 0);
    check(
      counter(3) == 1 && counter(6) == 0,
      'Unsubscribe releases native ownership in an MTA.',
    );
    print(
      'CONNECTIVITY_CHILD ${jsonEncode({'childPid': pid, 'scenario': args[2], 'passed': true, 'objects': counter(0), 'registrations': counter(1), 'removals': counter(3), 'callbacks': counter(4), 'badApartment': counter(6)})}',
    );
  } finally {
    release();
    await subscription?.cancel();
    access.dispose();
  }
  // Keep native entrypoints loaded until this owned child exits.
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
    pid.toString(),
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
      'Connectivity child $scenario failed ($exit): $stdout $stderr',
    );
    final line = const LineSplitter()
        .convert(stdout)
        .singleWhere((v) => v.startsWith('CONNECTIVITY_CHILD '));
    final report =
        jsonDecode(line.substring('CONNECTIVITY_CHILD '.length)) as Map;
    check(
      report['childPid'] == child.pid &&
          report['scenario'] == scenario &&
          report['passed'] == true,
      'Report matches owned process.',
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
    'native Windows connectivity $scenario': () => _run(scenario),
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
