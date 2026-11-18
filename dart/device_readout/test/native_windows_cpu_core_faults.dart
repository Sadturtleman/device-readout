import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:device_readout/device_readout.dart';
import 'package:device_readout/src/transport_native.dart'
    show NativeCollectorBindings, createNativeCollector;

import 'observers.dart' show check, errorOf;

const _childFlag = '--device-readout-cpu-core-child';
const _scenarios = {
  'clock-values': 100,
  'clock-failure': 101,
  'duplicate-clock-number': 102,
  'invalid-clock-number': 103,
  'zero-clocks': 104,
  'unsigned-clocks': 105,
  'sparse-clock-mapping': 4,
  'multi-group-clock-mapping': 5,
  'core-removal': 30,
  'invalid-inventory': 6,
  'denied-inventory': 32,
  'held-core-read': 106,
  'held-core-watch': 106,
};

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    check(
      DateTime.now().isBefore(deadline),
      'CPU-core native call did not reach its expected state.',
    );
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

Future<Map<String, Object?>> _held(
  String scenario,
  DeviceAccess sdk,
  Entity<CpuCoreSnapshot> target,
  void Function(int) configure,
  int Function(int) counter,
  int Function() buffers,
  void Function() release,
) async {
  var ticks = 0;
  final timer = Timer.periodic(const Duration(milliseconds: 5), (_) => ticks++);
  try {
    await sdk.get(target);
    configure(106);
    final limited = sdk.withReadTimeout(const Duration(milliseconds: 200));
    final pending = errorOf(
      scenario == 'held-core-watch'
          ? limited.watch(target).first
          : limited.get(target),
    );
    await _until(() => counter(0) == 1);
    final before = ticks;
    await Future<void>.delayed(const Duration(milliseconds: 35));
    final error = await pending.timeout(const Duration(seconds: 1));
    check(
      error is DeviceReadoutException && error.code == ErrorCode.readTimeout,
      'The CPU-core deadline completes while native clock collection is blocked.',
    );
    check(
      counter(0) == 1 && ticks - before >= 2 && counter(1) != counter(2),
      'Host timers run independently of the blocked native worker.',
    );
    final progress = ticks - before, worker = counter(1), caller = counter(2);
    release();
    check(
      (await sdk.get(target)).currentClockHz == 2200000000.0,
      'The context resumes CPU-core reads after native completion.',
    );
    check(
      buffers() == 0,
      'Clock and topology buffers are released after recovery.',
    );
    return {
      'completedBeforeNativeReturn': true,
      'progressDuringHold': progress,
      'workerThread': worker,
      'callerThread': caller,
      'nativeBuffersRemaining': buffers(),
    };
  } finally {
    release();
    timer.cancel();
  }
}

Future<void> _inventory(
  String scenario,
  DeviceAccess sdk,
  List<Entity<CpuCoreSnapshot>> targets,
  void Function(int) configure,
) async {
  final byIndex = <int, Entity<CpuCoreSnapshot>>{};
  for (final target in targets) {
    byIndex[(await sdk.get(target)).logicalIndex!] = target;
  }
  if (scenario == 'invalid-inventory' || scenario == 'denied-inventory') {
    configure(_scenarios[scenario]!);
    final expectedError = scenario == 'denied-inventory'
        ? ErrorCode.permissionDenied
        : ErrorCode.readFailed;
    final failure = await errorOf(sdk.cpuCores.list());
    check(
      failure is DeviceReadoutException && failure.code == expectedError,
      'A failed native inventory preserves its typed error: $failure',
    );
    final readFailure = await errorOf(sdk.get(byIndex[3]!));
    check(
      readFailure is DeviceReadoutException &&
          readFailure.code == expectedError,
      'Whole-target read failures preserve the same error category.',
    );
    configure(0);
    final recovered = await sdk.cpuCores.list();
    check(
      targets.every(recovered.contains) &&
          (await sdk.get(byIndex[3]!)).logicalIndex == 3,
      'A failed inventory does not retire known CPU handles.',
    );
    return;
  }
  final removed = byIndex[3]!;
  sdk.observers.current(Entities.cpuCore, removed);
  final iterator = StreamIterator(
    sdk.withPollInterval(const Duration(milliseconds: 25)).watch(removed),
  );
  try {
    check(
      await iterator.moveNext(),
      'The selected CPU starts with a snapshot.',
    );
    configure(30);
    final failure = await errorOf(iterator.moveNext());
    check(
      failure is DeviceReadoutException &&
          failure.code == ErrorCode.entityRemoved,
      'Observed native CPU disappearance terminates the existing watch.',
    );
    check(
      (await sdk.cpuCores.list()).length == 3 &&
          await sdk.cpuCores.current() == null,
      'Removed CPU handles leave the inventory and current selection.',
    );
    configure(0);
    final fresh = await sdk.cpuCores.list();
    Entity<CpuCoreSnapshot>? replacement;
    for (final target in fresh) {
      if ((await sdk.get(target)).logicalIndex == 3) replacement = target;
    }
    check(
      replacement != null && replacement != removed,
      'Observed CPU reappearance creates a new handle generation.',
    );
    final stale = await errorOf(sdk.get(removed));
    check(
      stale is DeviceReadoutException && stale.code == ErrorCode.entityRemoved,
      'A retired logical CPU handle never revives.',
    );
  } finally {
    configure(0);
    await iterator.cancel();
  }
}

Future<bool> runChildIfRequested(List<String> arguments) async {
  if (arguments.isEmpty || arguments.first != _childFlag) return false;
  check(
    arguments.length == 3 && Platform.isWindows,
    'Invalid CPU-core child arguments.',
  );
  final parent = int.parse(arguments[1]), scenario = arguments[2];
  check(
    parent > 0 && parent != pid,
    'The CPU-core fixture requires an owned child.',
  );
  final path = File(
    '.tools/windows-memory-probe/Release/device_readout_cpu_fixture.dll',
  ).absolute.path;
  final fixture = ffi.DynamicLibrary.open(path);
  final configure = fixture
      .lookupFunction<ffi.Void Function(ffi.Uint32), void Function(int)>(
        'readout_cpu_configure',
      );
  final release = fixture.lookupFunction<ffi.Void Function(), void Function()>(
    'readout_cpu_release',
  );
  final counter = fixture
      .lookupFunction<ffi.Uint32 Function(ffi.Uint32), int Function(int)>(
        'readout_cpu_counter',
      );
  final buffers = fixture.lookupFunction<ffi.Uint32 Function(), int Function()>(
    'readout_cpu_buffers',
  );
  final sdk = DeviceAccess.isolated(
    createNativeCollector,
    initialData: NativeCollectorBindings(windowsCpuLibrary: path),
  );
  try {
    configure(0);
    var targets = await sdk.cpuCores.list();
    if (scenario.startsWith('held-')) {
      final evidence = await _held(
        scenario,
        sdk,
        targets.first,
        configure,
        counter,
        buffers,
        release,
      );
      print(
        'CPU_CORE_CHILD ${jsonEncode({'childPid': pid, 'scenario': scenario, 'passed': true, ...evidence})}',
      );
      return true;
    }
    if (scenario == 'core-removal' ||
        scenario == 'invalid-inventory' ||
        scenario == 'denied-inventory') {
      await _inventory(scenario, sdk, targets, configure);
      print(
        'CPU_CORE_CHILD ${jsonEncode({'childPid': pid, 'scenario': scenario, 'passed': true})}',
      );
      return true;
    }
    configure(_scenarios[scenario]!);
    targets = await sdk.cpuCores.list();
    check(
      targets.length == 4,
      'Four logical CPUs belong to two fixture cores.',
    );
    const expected = {
      0: (core: 0, current: 2200000000.0, maximum: 3200000000.0),
      1: (core: 0, current: 2300000000.0, maximum: 3300000000.0),
      2: (core: 1, current: 2400000000.0, maximum: 3400000000.0),
      3: (core: 1, current: 2500000000.0, maximum: 3500000000.0),
    };
    void matches(CpuCoreSnapshot value) {
      if (scenario == 'sparse-clock-mapping' ||
          scenario == 'multi-group-clock-mapping') {
        final members = scenario == 'sparse-clock-mapping'
            ? {0: 0, 63: 0, 1: 1, 62: 1}
            : {0: 0, 1: 0, 64: 1, 65: 1};
        check(
          members.containsKey(value.logicalIndex) &&
              value.coreIndex == members[value.logicalIndex] &&
              value.packageIndex == 0 &&
              value.online == true &&
              value.currentClockHz == null &&
              value.maximumClockHz == null,
          'Group-aware topology remains readable without guessing a sparse or multi-group clock mapping.',
        );
        return;
      }
      final record = expected[value.logicalIndex];
      check(
        record != null &&
            value.coreIndex == record.core &&
            value.packageIndex == 0 &&
            value.online == true,
        'Core topology is independent of the order of power records.',
      );
      final failed = {
        'clock-failure',
        'duplicate-clock-number',
        'invalid-clock-number',
      }.contains(scenario);
      final current = failed
          ? null
          : scenario == 'zero-clocks'
          ? 0.0
          : scenario == 'unsigned-clocks'
          ? 4294967295000000.0
          : record!.current;
      final maximum = failed
          ? null
          : scenario == 'zero-clocks'
          ? 0.0
          : scenario == 'unsigned-clocks'
          ? 4294967295000000.0
          : record!.maximum;
      check(
        value.currentClockHz == current && value.maximumClockHz == maximum,
        'Clock values map the native processor Number and convert MHz to Hz: ${value.toJson()}',
      );
    }

    for (final target in targets) {
      matches(await sdk.get(target));
    }
    final samples = await sdk
        .withPollInterval(const Duration(milliseconds: 15))
        .watch(targets.first)
        .take(3)
        .toList();
    for (final sample in samples) {
      matches(sample);
    }
    check(
      samples.last.collectedAt.isAfter(samples.first.collectedAt),
      'Clock polling recollects equal values.',
    );
    print(
      'CPU_CORE_CHILD ${jsonEncode({'childPid': pid, 'scenario': scenario, 'passed': true})}',
    );
  } finally {
    release();
    sdk.dispose();
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
      'CPU-core child $scenario failed ($code): $stdout $stderr',
    );
    final line = const LineSplitter()
        .convert(stdout)
        .singleWhere((value) => value.startsWith('CPU_CORE_CHILD '));
    final report = jsonDecode(line.substring('CPU_CORE_CHILD '.length)) as Map;
    check(
      report['childPid'] == child.pid &&
          report['scenario'] == scenario &&
          report['passed'] == true,
      'The report belongs to the retained child.',
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
    'native CPU-core $scenario preserves field semantics': () => _run(scenario),
};
Future<void> main(List<String> arguments) async {
  if (await runChildIfRequested(arguments)) return;
  if (arguments.isNotEmpty) {
    await _run(arguments.single);
    return;
  }
  for (final test in checks.values) {
    await test();
  }
}
