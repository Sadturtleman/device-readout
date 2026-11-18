import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:device_readout/device_readout.dart';

import 'observers.dart' show check;

const _flag = '--device-readout-cpu-child';

Future<bool> runChildIfRequested(List<String> args) async {
  if (args.isEmpty || args.first != _flag) return false;
  check(
    Platform.isWindows && args.length == 3,
    'Invalid owned-child CPU arguments.',
  );
  final parent = int.parse(args[1]), mode = int.parse(args[2]);
  check(
    parent != pid && parent > 0 && mode >= 1 && mode <= 4,
    'CPU policy controls require an owned child.',
  );
  final controls = ffi.DynamicLibrary.open(
    File('.tools/windows-memory-probe/Release/device_readout_cpu_controls.dll')
        .absolute
        .path,
  );
  final probe = ffi.DynamicLibrary.open(
    File('.tools/windows-memory-probe/Release/device_readout_memory_probe.dll')
        .absolute
        .path,
  );
  int Function(int) argument(String name) => controls
      .lookupFunction<ffi.Uint32 Function(ffi.Uint32), int Function(int)>(name);
  final begin = argument('readout_cpu_controls_begin'),
      apply = argument('readout_cpu_controls_apply'),
      verify = argument('readout_cpu_controls_verify');
  final restore = controls
      .lookupFunction<ffi.Uint32 Function(), int Function()>(
        'readout_cpu_controls_restore',
      );
  final finish = controls.lookupFunction<ffi.Uint32 Function(), int Function()>(
    'readout_cpu_controls_finish',
  );
  final refresh = probe.lookupFunction<ffi.Void Function(), void Function()>(
    'readout_probe_cpu_refresh',
  );
  final reference = probe
      .lookupFunction<ffi.Uint32 Function(ffi.Uint32), int Function(int)>(
        'readout_probe_cpu_count',
      );
  final sdk = DeviceAccess.native();
  StreamIterator<CpuSnapshot>? iterator;
  try {
    check(
      begin(parent) == 0,
      'Cannot initialize the owned-child CPU policy fixture.',
    );
    final original = await sdk.get(Entities.cpu);
    check(
      original.availableLogicalProcessorCount! >= 2,
      'This native fixture requires two eligible CPUs.',
    );
    final status = apply(mode);
    check(status == 0, 'Cannot apply the owned-child policy (Win32 $status).');
    final expected = mode == 4 ? 2 : 1;
    refresh();
    check(
      reference(3) == expected,
      'Independent same-process availability reference differs.',
    );
    void matches(CpuSnapshot value) {
      check(
        value.availableLogicalProcessorCount == expected,
        'Live process availability ${value.availableLogicalProcessorCount} != $expected.',
      );
      check(
        value.logicalProcessorCount == original.logicalProcessorCount &&
            value.physicalCoreCount == original.physicalCoreCount &&
            value.processorPackageCount == original.processorPackageCount,
        'Process policy must not change whole-system topology fields.',
      );
      check(
        verify(mode) == 0,
        'SDK reads must leave affinity, CPU-set and job policy unchanged.',
      );
    }

    matches(await sdk.get(Entities.cpu));
    iterator = StreamIterator(
      sdk
          .withPollInterval(const Duration(milliseconds: 25))
          .watch(Entities.cpu),
    );
    for (var i = 0; i < 2; i++) {
      check(await iterator.moveNext(), 'CPU watch ended early.');
      matches(iterator.current);
    }
    check(restore() == 0, 'Owned-child CPU policy restoration failed.');
    var restored = false;
    for (var i = 0; i < 5; i++) {
      check(
        await iterator.moveNext(),
        'The same CPU watch must survive policy restoration.',
      );
      if (iterator.current.availableLogicalProcessorCount ==
          original.availableLogicalProcessorCount) {
        restored = true;
        break;
      }
    }
    check(
      restored,
      'The existing watch must observe restored process availability.',
    );
    print(
      'CPU_CHILD ${jsonEncode({'childPid': pid, 'mode': mode, 'originalAvailability': original.availableLogicalProcessorCount, 'restrictedAvailability': expected, 'systemLogicalCount': original.logicalProcessorCount, 'restoredInSameWatch': restored, 'policyUnchangedBySdk': true})}',
    );
  } finally {
    await iterator?.cancel();
    sdk.dispose();
    final restored = finish();
    controls.close();
    probe.close();
    check(
      restored == 0,
      'The owned-child policy must be restored before exit.',
    );
  }
  return true;
}

Future<void> _run(int mode) async {
  if (!Platform.isWindows) return;
  final sdk = DeviceAccess.native();
  Process? child;
  var terminal = false;
  try {
    final before = await sdk.get(Entities.cpu);
    var executable = Platform.resolvedExecutable;
    final jit =
        executable.toLowerCase().endsWith('dart.exe') ||
        executable.toLowerCase().endsWith('dartvm.exe');
    if (jit)
      executable = File.fromUri(
        File(executable).parent.uri.resolve('dartvm.exe'),
      ).path;
    child = await Process.start(executable, [
      if (jit) Platform.script.toFilePath(),
      _flag,
      pid.toString(),
      mode.toString(),
    ]);
    final output = child.stdout.transform(utf8.decoder).join(),
        errors = child.stderr.transform(utf8.decoder).join();
    final code = await child.exitCode.timeout(const Duration(seconds: 8));
    terminal = true;
    final stdout = await output, stderr = await errors;
    check(code == 0, 'CPU child failed ($code): $stdout $stderr');
    final line = const LineSplitter()
        .convert(stdout)
        .singleWhere((line) => line.startsWith('CPU_CHILD '));
    final report = jsonDecode(line.substring('CPU_CHILD '.length)) as Map;
    check(
      report['childPid'] == child.pid && report['mode'] == mode,
      'The CPU report must belong to the retained child.',
    );
    final after = await sdk.get(Entities.cpu);
    check(
      before.availableLogicalProcessorCount ==
              after.availableLogicalProcessorCount &&
          before.logicalProcessorCount == after.logicalProcessorCount,
      'Child controls leave parent CPU availability and topology unchanged.',
    );
    print(line);
  } finally {
    if (child != null && !terminal) {
      child.kill();
      await child.exitCode;
    }
    sdk.dispose();
  }
}

final checks = <String, Future<void> Function()>{
  'native Windows CPU reads live process affinity without changing it': () =>
      _run(1),
  'native Windows CPU respects process-default CPU sets': () => _run(2),
  'native Windows CPU retains hard affinity when CPU-set preferences conflict':
      () => _run(3),
  'native Windows CPU does not convert a job time quota into a CPU count': () =>
      _run(4),
};
Future<void> main(List<String> arguments) async {
  if (await runChildIfRequested(arguments)) return;
  for (final test in checks.values) {
    await test();
  }
}
