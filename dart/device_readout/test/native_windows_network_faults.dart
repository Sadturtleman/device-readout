import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:device_readout/device_readout.dart';
import 'package:device_readout/src/transport_native.dart'
    show NativeCollectorBindings, createNativeCollector;

import 'observers.dart' show check, errorOf;

const _childFlag = '--device-readout-network-child';
const _scenarios = {
  'values': 0,
  'unknown-enums': 1,
  'address-cycle': 2,
  'invalid-dns-pointer': 3,
  'invalid-unicode': 4,
  'unknown-address-family': 5,
  'failed-routes-with-output': 6,
  'invalid-routes': 7,
  'denied-inventory': 8,
  'inventory-cycle': 9,
  'removed-target': 10,
  'oversized-inventory': 11,
  'growing-inventory': 12,
  'invalid-output-size': 13,
  'unsigned-mtu': 14,
  'ipv6-scope': 15,
  'unknown-prefix': 16,
  'held-address-read': 20,
  'held-address-watch': 20,
  'held-route-read': 21,
  'held-route-watch': 21,
};

Future<bool> runChildIfRequested(List<String> args) async {
  if (args.isEmpty || args.first != _childFlag) return false;
  check(
    args.length == 3 &&
        int.parse(args[1]) != pid &&
        _scenarios.containsKey(args[2]),
    'Owned network child arguments.',
  );
  final scenario = args[2], mode = _scenarios[args[2]]!;
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
  final access = DeviceAccess.isolated(
    createNativeCollector,
    initialData: NativeCollectorBindings(windowsNetworkLibrary: path),
  );
  Map<String, Object?> extra = {};
  try {
    final target = (await access.networkInterfaces.list()).single;
    final baseline = await access.get(target);
    check(
      baseline.name == 'Fixture network' && baseline.routes?.length == 2,
      'Known native fixture is collected through public get.',
    );
    if (mode >= 20) {
      configure(mode);
      var ticks = 0;
      final timer = Timer.periodic(
        const Duration(milliseconds: 5),
        (_) => ticks++,
      );
      try {
        final limited = access.withReadTimeout(
          const Duration(milliseconds: 200),
        );
        final pending = errorOf(
          scenario.endsWith('watch')
              ? limited.watch(target).first
              : limited.get(target),
        );
        final deadline = DateTime.now().add(const Duration(seconds: 2));
        while (counter(1) == 0) {
          check(DateTime.now().isBefore(deadline), 'Native query starts.');
          await Future<void>.delayed(const Duration(milliseconds: 2));
        }
        final before = ticks;
        final error = await pending.timeout(const Duration(seconds: 1));
        check(
          error is DeviceReadoutException &&
              error.code == ErrorCode.readTimeout,
          'Public deadline completes while the native query remains blocked.',
        );
        check(
          counter(1) == 1 && ticks - before >= 2 && counter(2) != counter(3),
          'Host timers progress independently of the blocked native thread.',
        );
        extra = {
          'completedBeforeNativeReturn': true,
          'progressDuringHold': ticks - before,
          'workerThread': counter(2),
          'callerThread': counter(3),
        };
        release();
        check(
          (await access.get(target)).routes?.length == 2,
          'Reads recover after native completion.',
        );
      } finally {
        release();
        timer.cancel();
      }
    } else if (mode == 10) {
      final iterator = StreamIterator(
        access.withPollInterval(const Duration(milliseconds: 20)).watch(target),
      );
      try {
        check(await iterator.moveNext(), 'Watch emits its initial snapshot.');
        configure(mode);
        final error = await errorOf(iterator.moveNext());
        check(
          error is DeviceReadoutException &&
              error.code == ErrorCode.entityRemoved,
          'Observed disappearance ends watch with EntityRemoved.',
        );
        check(
          (await access.networkInterfaces.list()).isEmpty,
          'Successful empty inventory removes its target.',
        );
        configure(0);
        final replacement = (await access.networkInterfaces.list()).single;
        check(
          replacement != target,
          'Reappearing interface gets a new typed lifetime.',
        );
        final old = await errorOf(access.get(target));
        check(
          old is DeviceReadoutException && old.code == ErrorCode.entityRemoved,
          'Removed handles never revive.',
        );
        await access.get(replacement);
      } finally {
        await iterator.cancel();
      }
    } else if ({8, 9, 11, 13}.contains(mode)) {
      configure(mode);
      for (final operation in [
        access.networkInterfaces.list,
        () => access.get(target),
      ]) {
        final error = await errorOf(operation());
        check(
          error is DeviceReadoutException &&
              error.code ==
                  (mode == 8
                      ? ErrorCode.permissionDenied
                      : ErrorCode.readFailed),
          'Invalid inventory fails with the appropriate common error.',
        );
      }
      configure(0);
      check(
        (await access.networkInterfaces.list()).single == target,
        'Failed inventory does not retire a known target.',
      );
      await access.get(target);
    } else {
      configure(mode);
      final values = [
        await access.get(target),
        ...await access
            .withPollInterval(const Duration(milliseconds: 10))
            .watch(target)
            .take(3)
            .toList(),
      ];
      for (final value in values) {
        check(
          value.name == (mode == 4 ? null : 'Fixture network'),
          'Malformed optional Unicode stays null.',
        );
        check(
          value.interfaceType ==
                  (mode == 1 ? null : NetworkInterfaceType.ethernet) &&
              value.operationalState ==
                  (mode == 1 ? null : NetworkOperationalState.up),
          'Unknown enum values stay null.',
        );
        check(
          value.mtuBytes == BigInt.from(mode == 14 ? 4294967295 : 1500) &&
              value.hardwareAddress == '00:01:02:03:04:05',
          'MTU and hardware fields remain independent.',
        );
        check(
          mode == 2
              ? value.ipAddresses == null
              : value.ipAddresses?.single.address ==
                    (mode == 15 ? 'fe80::1%7' : '192.0.2.2'),
          'IP address lists preserve scope or fail as a whole.',
        );
        if (mode != 2)
          check(
            value.ipAddresses!.single.prefixLength ==
                (mode == 16
                    ? null
                    : mode == 15
                    ? 64
                    : 24),
            'Unknown prefix retains the known address.',
          );
        check(
          mode == 3
              ? value.dnsServers == null
              : value.dnsServers?.single == '192.0.2.53',
          'Out-of-buffer pointers cannot become DNS addresses.',
        );
        check(
          mode == 5
              ? value.gateways == null
              : value.gateways?.single == '192.0.2.1',
          'Unknown family invalidates its address field.',
        );
        if (mode == 6 || mode == 7) {
          check(value.routes == null, 'Failed or malformed routes stay null.');
        } else {
          check(
            value.routes?.length == 2 &&
                value.routes![0].destination == '192.0.2.0' &&
                value.routes![0].prefixLength == 24 &&
                value.routes![0].gateway == null &&
                value.routes![1].gateway == '192.0.2.1',
            'Routes preserve prefix and on-link semantics.',
          );
        }
      }
      check(
        values.last.collectedAt.isAfter(values[1].collectedAt),
        'Polling retains equal values with fresh completion times.',
      );
    }
    check(counter(0) == 0, 'All native query buffers are released.');
    print(
      'NETWORK_CHILD ${jsonEncode({'childPid': pid, 'scenario': scenario, 'passed': true, 'nativeBuffersRemaining': counter(0), ...extra})}',
    );
  } finally {
    release();
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
    check(code == 0, 'Network child $scenario failed ($code): $stdout $stderr');
    final line = const LineSplitter()
        .convert(stdout)
        .singleWhere((v) => v.startsWith('NETWORK_CHILD '));
    final report = jsonDecode(line.substring('NETWORK_CHILD '.length)) as Map;
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
  for (final scenario in _scenarios.keys)
    'native Windows network $scenario preserves read contracts': () =>
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
