import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:device_readout/device_readout.dart';
import 'package:device_readout/src/transport_native.dart'
    show NativeCollectorBindings, createNativeCollector;

import 'observers.dart' show check;

part 'native_windows_network_event_cases.dart';

const _childFlag = '--device-readout-network-event-child';
const _scenarios = [
  'native-notifications',
  'shared-observers',
  'poll-fallback',
  'partial-fallback',
  'denied-registration',
  'failed-registration-output',
  'null-registration-handle',
  'invalid-notification',
  'missing-row',
  'protocol-deletion',
  'event-removal',
  'late-notification',
  'held-registration',
  'held-unregister',
  'failed-unregister',
  'persistent-unregister',
  'callback-overflow',
  'real-os-registration',
];
Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    check(
      DateTime.now().isBefore(deadline),
      'Network notification condition did not complete.',
    );
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

Future<bool> runChildIfRequested(List<String> args) async {
  if (args.isEmpty || args.first != _childFlag) return false;
  check(
    args.length == 3 &&
        int.parse(args[1]) != pid &&
        _scenarios.contains(args[2]),
    'Owned notification child.',
  );
  final scenario = args[2];
  if (scenario == 'real-os-registration') {
    final result = await _realOSRegistration();
    print(
      'NETWORK_EVENT_CHILD ${jsonEncode({'childPid': pid, 'scenario': scenario, 'passed': true, ...result})}',
    );
    return true;
  }
  final path = File(
    '.tools/windows-memory-probe/Release/device_readout_network_fixture.dll',
  ).absolute.path;
  final fixture = ffi.DynamicLibrary.open(path);
  final configure = fixture
      .lookupFunction<ffi.Void Function(ffi.Uint32), void Function(int)>(
        'readout_network_configure',
      );
  final release = fixture.lookupFunction<ffi.Void Function(), void Function()>(
    'readout_network_release',
  );
  final counter = fixture
      .lookupFunction<ffi.Uint32 Function(ffi.Uint32), int Function(int)>(
        'readout_network_counter',
      );
  final emit = fixture
      .lookupFunction<
        ffi.Uint32 Function(
          ffi.Uint32,
          ffi.Uint32,
          ffi.Uint32,
          ffi.Uint32,
          ffi.Uint32,
          ffi.Uint32,
        ),
        int Function(int, int, int, int, int, int)
      >('readout_network_emit');
  final access = DeviceAccess.isolated(
    createNativeCollector,
    initialData: NativeCollectorBindings(windowsNetworkLibrary: path),
  );
  StreamSubscription<NetworkInterfaceSnapshot>? subscription;
  try {
    final target = (await access.networkInterfaces.list()).single;
    await access.get(target);
    check(
      counter(4) == 0 && counter(5) == 0,
      'List/get do not register native observers.',
    );
    if (scenario != 'native-notifications') {
      final result = await _exercise(
        scenario,
        access,
        target,
        counter,
        emit,
        configure,
        release,
      );
      print(
        'NETWORK_EVENT_CHILD ${jsonEncode({'childPid': pid, 'scenario': scenario, 'passed': true, ...result})}',
      );
      return true;
    }
    final source = access
        .withPollInterval(const Duration(seconds: 10))
        .watch(target);
    check(counter(4) == 0, 'A cold watch has no native registration.');
    final values = <NetworkInterfaceSnapshot>[], errors = <Object>[];
    subscription = source.listen(values.add, onError: errors.add);
    await _until(() => values.isNotEmpty || errors.isNotEmpty);
    check(
      errors.isEmpty && values.single.mtuBytes == BigInt.from(1500),
      'Watch emits the initial full snapshot.',
    );
    check(
      counter(4) == 3,
      'Interface, unicast-address and route callbacks are registered.',
    );
    for (var kind = 0; kind < 3; kind++) {
      check(
        emit(kind, 0, 1, 0, 1, kind + 1) == 0,
        'Native test notification starts.',
      );
      await _until(() => values.length == kind + 2 || errors.isNotEmpty);
      check(
        errors.isEmpty && values.last.mtuBytes == BigInt.from(1501 + kind),
        'Each native callback re-reads current state before the ten-second poll.',
      );
    }
    await subscription.cancel();
    subscription = null;
    await _until(() => counter(4) == 0 && counter(8) == 0);
    check(
      counter(6) == 3,
      'Last unsubscribe deregisters all sources; thread ownership is checked during held calls because Dart can reuse idle OS threads.',
    );
    print(
      'NETWORK_EVENT_CHILD ${jsonEncode({'childPid': pid, 'scenario': scenario, 'passed': true, 'updates': values.length, 'activeRegistrations': counter(4)})}',
    );
  } finally {
    release();
    await subscription?.cancel();
    access.dispose();
    fixture.close();
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
    _childFlag,
    pid.toString(),
    scenario,
  ]);
  var terminal = false;
  final output = child.stdout.transform(utf8.decoder).join(),
      errors = child.stderr.transform(utf8.decoder).join();
  try {
    final code = await child.exitCode.timeout(const Duration(seconds: 8));
    terminal = true;
    final stdout = await output, stderr = await errors;
    check(
      code == 0,
      'Network event child $scenario failed ($code): $stdout $stderr',
    );
    final line = const LineSplitter()
        .convert(stdout)
        .singleWhere((v) => v.startsWith('NETWORK_EVENT_CHILD '));
    final report =
        jsonDecode(line.substring('NETWORK_EVENT_CHILD '.length)) as Map;
    check(
      report['childPid'] == child.pid &&
          report['scenario'] == scenario &&
          report['passed'] == true,
      'Report belongs to the retained child.',
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
    'native Windows network $scenario preserves event lifecycle': () =>
        _run(scenario),
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
