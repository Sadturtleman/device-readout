import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:math';

import 'package:device_readout/device_readout.dart';

import 'observers.dart' show check;

const _childFlag = '--device-readout-registry-child';
String get _fixturePath => File(
  '.tools/windows-memory-probe/Release/device_readout_registry_fixture.dll',
).absolute.path;

Future<bool> runChildIfRequested(List<String> arguments) async {
  if (arguments.isEmpty || arguments.first != _childFlag) return false;
  check(
    arguments.length == 4 && Platform.isWindows,
    'Invalid owned-child fixture arguments.',
  );
  final parent = int.parse(arguments[1]);
  final nonce = int.parse(arguments[2]);
  final scenario = int.parse(arguments[3]);
  check(
    parent != pid && parent > 0 && nonce > 0,
    'Registry overrides require a separate owned child.',
  );
  final fixture = ffi.DynamicLibrary.open(_fixturePath);
  final access = DeviceAccess.native();
  final start = fixture
      .lookupFunction<
        ffi.Int32 Function(ffi.Uint32, ffi.Uint64),
        int Function(int, int)
      >('readout_registry_start');
  final prepare = fixture
      .lookupFunction<ffi.Int32 Function(ffi.Int32), int Function(int)>(
        'readout_registry_prepare',
      );
  final finish = fixture.lookupFunction<ffi.Int32 Function(), int Function()>(
    'readout_registry_finish',
  );
  try {
    check(
      start(parent, nonce) == 0,
      'Cannot create the isolated child registry fixture.',
    );
    check(
      prepare(scenario) == 0,
      'Cannot populate the child registry fixture.',
    );
    final snapshot = await access.get(Entities.deviceInfo);
    if (scenario == 4) {
      final sizes = fixture
          .lookupFunction<ffi.Uint64 Function(), int Function()>(
            'readout_registry_sizes',
          )();
      print(
        'REGISTRY_SIZE ${jsonEncode({'storedBytes': sizes >> 32, 'sizingBytes': sizes & 0xffffffff})}',
      );
      check(
        snapshot.manufacturer == 'A' * 32767 &&
            snapshot.modelName == null &&
            snapshot.board == null,
        'A terminated 64 KiB value must survive; values exceeding the allocation bound must be null. Lengths: ${[snapshot.manufacturer?.length, snapshot.modelName?.length, snapshot.board?.length]}.',
      );
    } else if (scenario == 3) {
      check(
        snapshot.manufacturer == '가B' &&
            snapshot.modelName == '' &&
            snapshot.board == null,
        'OS-terminated strings must be preserved while odd byte counts become null: ${[snapshot.manufacturer, snapshot.modelName, snapshot.board]}.',
      );
    } else if (scenario == 2) {
      check(
        snapshot.manufacturer == null &&
            snapshot.modelName == null &&
            snapshot.board == 'Fixture board',
        'Unpaired UTF-16 surrogates must become null while valid fields survive.',
      );
    } else if (scenario == 1) {
      check(
        snapshot.manufacturer == '가🚀é' &&
            snapshot.modelName == '' &&
            snapshot.board == 'Fixture board',
        'Unicode and empty registry strings must survive native collection.',
      );
    } else {
      check(
        snapshot.manufacturer == null &&
            snapshot.modelName == 'Fixture model' &&
            snapshot.board == null,
        'Wrong-type and missing fields must stay null without hiding a readable model.',
      );
    }
    if (scenario == 5) {
      var beforeRecovery = 0, afterRecovery = 0;
      DateTime? previous;
      DeviceInfoSnapshot? first;
      await for (final current
          in access
              .withPollInterval(const Duration(milliseconds: 20))
              .watch(Entities.deviceInfo)
              .timeout(const Duration(seconds: 2))) {
        check(
          previous == null || current.collectedAt.isAfter(previous),
          'Each polled snapshot must have a fresh completion time.',
        );
        previous = current.collectedAt;
        first ??= current;
        if (current.manufacturer == null) {
          check(
            afterRecovery == 0 && current.modelName == 'Fixture model',
            'Before recovery, independently readable fields must survive.',
          );
          if (++beforeRecovery == 2) {
            check(prepare(1) == 0, 'Cannot restore readable registry fields.');
          }
        } else {
          check(
            beforeRecovery >= 2 &&
                current.manufacturer == '가🚀é' &&
                current.modelName == '' &&
                current.board == 'Fixture board',
            'The existing watch must recover without restarting or stale fields.',
          );
          if (++afterRecovery == 2) break;
        }
      }
      check(
        beforeRecovery >= 2 &&
            afterRecovery == 2 &&
            first?.manufacturer == null &&
            first?.modelName == 'Fixture model',
        'Equal snapshots must be delivered before and after recovery without mutating old snapshots.',
      );
    }
    print(
      'REGISTRY_CHILD ${jsonEncode({'childPid': pid, 'scenario': scenario, 'fieldsVerified': true})}',
    );
  } finally {
    access.dispose();
    final status = finish();
    fixture.close();
    check(status == 0, 'The child registry override must be restored.');
  }
  return true;
}

Future<void> _run(int scenario) async {
  if (!Platform.isWindows) return;
  final access = DeviceAccess.native();
  final fixture = ffi.DynamicLibrary.open(_fixturePath);
  final remove = fixture
      .lookupFunction<
        ffi.Int32 Function(ffi.Uint32, ffi.Uint64),
        int Function(int, int)
      >('readout_registry_remove');
  Process? child;
  var terminal = false;
  final random = Random.secure();
  final nonce = (random.nextInt(1 << 30) << 32) | random.nextInt(1 << 32) | 1;
  try {
    final before = await access.get(Entities.deviceInfo);
    var executable = Platform.resolvedExecutable;
    final jit =
        executable.toLowerCase().endsWith('dart.exe') ||
        executable.toLowerCase().endsWith('dartvm.exe');
    if (jit) {
      // The Dart CLI may delegate to another process. Retain the VM directly so
      // the process handle, report PID and fixture-key owner are the same child.
      executable = File.fromUri(
        File(executable).parent.uri.resolve('dartvm.exe'),
      ).path;
      check(
        File(executable).existsSync(),
        'The pinned Dart VM executable is required.',
      );
    }
    final args = <String>[
      if (jit) Platform.script.toFilePath(),
      _childFlag,
      pid.toString(),
      nonce.toString(),
      scenario.toString(),
    ];
    child = await Process.start(executable, args);
    print(
      'REGISTRY_LAUNCH ${jsonEncode({'childPid': child.pid, 'nonce': nonce, 'scenario': scenario})}',
    );
    final output = child.stdout.transform(utf8.decoder).join();
    final errors = child.stderr.transform(utf8.decoder).join();
    final code = await child.exitCode.timeout(const Duration(seconds: 8));
    terminal = true;
    final stdout = await output, stderr = await errors;
    check(code == 0, 'Owned registry child failed ($code): $stdout $stderr');
    for (final line in const LineSplitter().convert(stdout)) {
      if (line.startsWith('REGISTRY_SIZE ')) print(line);
    }
    final line = const LineSplitter()
        .convert(stdout)
        .singleWhere((line) => line.startsWith('REGISTRY_CHILD '));
    final report = jsonDecode(line.substring('REGISTRY_CHILD '.length)) as Map;
    check(
      report['childPid'] == child.pid && report['scenario'] == scenario,
      'The report must come from the retained child process: ${child.pid} != $report.',
    );
    final after = await access.get(Entities.deviceInfo);
    check(
      before.manufacturer == after.manufacturer &&
          before.modelName == after.modelName &&
          before.board == after.board &&
          before.deviceName == after.deviceName,
      'Child-only registry overrides must not alter the parent SDK readings.',
    );
    print(
      'WINDOWS_REGISTRY ${jsonEncode({'scenario': scenario, 'childPid': child.pid, 'parentUnchanged': true})}',
    );
  } finally {
    try {
      if (child != null) {
        if (!terminal) {
          child.kill();
          await child.exitCode;
        }
        final cleanup = remove(child.pid, nonce);
        check(
          cleanup == 0,
          'Cannot remove the exact owned fixture key: $cleanup.',
        );
        print(
          'REGISTRY_CLEANUP ${jsonEncode({'childPid': child.pid, 'nonce': nonce, 'absent': true})}',
        );
      }
    } finally {
      access.dispose();
      fixture.close();
    }
  }
}

final checks = <String, Future<void> Function()>{
  'native registry wrong-type and missing device fields preserve readable data':
      () => _run(0),
  'native registry Unicode and empty device fields retain their exact values':
      () => _run(1),
  'native registry malformed surrogates do not discard independent device fields':
      () => _run(2),
  'native registry terminator repair and odd byte lengths preserve field boundaries':
      () => _run(3),
  'native registry size bound accepts complete values and rejects excess data':
      () => _run(4),
  'native registry watch recovers fields and delivers unchanged snapshots':
      () => _run(5),
};

Future<void> main(List<String> arguments) async {
  if (await runChildIfRequested(arguments)) return;
  if (arguments.isNotEmpty) {
    await _run(int.parse(arguments.single));
  } else {
    for (final test in checks.values) {
      await test();
    }
  }
}
