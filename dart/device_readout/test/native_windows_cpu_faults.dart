import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';

import 'package:device_readout/device_readout.dart';
// Only the native OS adapter is supplied; assertions use public SDK operations.
import 'package:device_readout/src/transport_native.dart'
    show NativeCollectorBindings, createNativeCollector;

import 'observers.dart' show check, errorOf;

const _childFlag = '--device-readout-cpu-fault-child';

DeviceCollector cpuFixtureCollector(Object? input) {
  final data = input as ({String path, SendPort disposed});
  return _CpuFixtureCollector(
    createNativeCollector(
      NativeCollectorBindings(windowsCpuLibrary: data.path),
    ),
    data.disposed,
  );
}

final class _CpuFixtureCollector implements DeviceCollector {
  final DeviceCollector delegate;
  final SendPort disposed;
  _CpuFixtureCollector(this.delegate, this.disposed);
  @override
  FutureOr<DeviceSnapshot> read(EntityAddress entity, ReadContext context) =>
      delegate.read(entity, context);
  @override
  Future<void> dispose() async {
    await delegate.dispose();
    disposed.send(null);
  }
}

const _scenarios = {
  'empty-system-set-list': 1,
  'empty-failed-system-set-list': 2,
  'empty-invalid-topology': 3,
  'unsigned-affinity-topology': 4,
  'duplicate-core-membership': 6,
  'truncated-topology': 7,
  'oversized-topology': 8,
  'unknown-cpu-set-flags': 9,
  'failed-topology-with-output': 10,
  'held-topology': 20,
  'held-affinity': 21,
  'held-default-sets': 22,
  'held-system-sets': 23,
  'held-cancel': 20,
  'held-dispose': 20,
  'held-watch-initial': 20,
  'held-watch-poll': 20,
};

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    check(
      DateTime.now().isBefore(deadline),
      'Native CPU fixture did not reach its expected state.',
    );
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

Future<Map<String, Object?>> _held(
  String scenario,
  DeviceAccess sdk,
  void Function(int) configure,
  int Function() buffers,
  int Function(int) counter,
  void Function() release,
  Future<void> disposed,
) async {
  final limited = sdk
      .withReadTimeout(const Duration(milliseconds: 200))
      .withPollInterval(const Duration(milliseconds: 15));
  final cancellation = CancellationToken();
  StreamSubscription<CpuSnapshot>? subscription;
  var ticks = 0;
  final timer = Timer.periodic(const Duration(milliseconds: 5), (_) => ticks++);
  try {
    late Future<Object?> pending;
    if (scenario == 'held-watch-poll') {
      final failed = Completer<Object?>(), initial = Completer<void>();
      subscription = limited
          .watch(Entities.cpu)
          .listen(
            (value) {
              if (!initial.isCompleted) {
                configure(20);
                initial.complete();
              }
            },
            onError: (Object error) {
              if (!failed.isCompleted) failed.complete(error);
            },
          );
      pending = failed.future;
      await initial.future;
    } else {
      configure(_scenarios[scenario]!);
      pending = errorOf(
        scenario == 'held-watch-initial'
            ? limited.watch(Entities.cpu).first
            : limited.get(Entities.cpu, cancellation: cancellation),
      );
    }
    await _until(() => counter(0) == 1);
    final before = ticks;
    await Future<void>.delayed(const Duration(milliseconds: 35));
    check(
      ticks - before >= 2,
      'Host timers run while the CPU native call is held.',
    );
    final worker = counter(1), caller = counter(2);
    check(worker != caller, 'CPU native work runs on a different thread.');
    if (scenario == 'held-cancel') cancellation.cancel();
    if (scenario == 'held-dispose') sdk.dispose();
    final error = await pending.timeout(const Duration(seconds: 1));
    if (scenario == 'held-cancel' || scenario == 'held-dispose') {
      check(
        error is DeviceReadoutCancelled,
        'Explicit cancellation remains distinct from timeout: $error',
      );
    } else {
      check(
        error is DeviceReadoutException && error.code == ErrorCode.readTimeout,
        'Host timeout remains independent of native completion: $error',
      );
    }
    check(counter(0) == 1, 'The public read completes before native return.');
    final progress = ticks - before;
    release();
    await _until(() => counter(0) == 0 && buffers() == 0);
    configure(0);
    if (scenario == 'held-dispose') {
      await disposed.timeout(const Duration(seconds: 2));
      check(
        await errorOf(sdk.get(Entities.cpu)) is DeviceReadoutCancelled,
        'A disposed context cannot restart a collector.',
      );
    } else {
      check(
        (await sdk.get(Entities.cpu)).availableLogicalProcessorCount == 3,
        'The same context recovers after native completion.',
      );
    }
    check(
      buffers() == 0,
      'Native CPU buffers are released after collection or completed disposal.',
    );
    return {
      'progressDuringHold': progress,
      'workerThread': worker,
      'callerThread': caller,
      'completedBeforeNativeReturn': true,
      'nativeBuffersRemaining': buffers(),
    };
  } finally {
    release();
    timer.cancel();
    await subscription?.cancel();
  }
}

void _topology(CpuSnapshot value, {bool invalidTopology = false}) {
  check(
    value.logicalProcessorCount == 4 &&
        value.physicalCoreCount == (invalidTopology ? null : 2) &&
        value.processorPackageCount == (invalidTopology ? null : 1) &&
        value.socModel == null &&
        value.socManufacturer == null,
    'Independent topology fields survive CPU-set response changes.',
  );
}

Future<bool> runChildIfRequested(List<String> arguments) async {
  if (arguments.isEmpty || arguments.first != _childFlag) return false;
  check(
    arguments.length == 3 && Platform.isWindows,
    'Invalid child arguments.',
  );
  final parent = int.parse(arguments[1]), scenario = arguments[2];
  check(
    parent > 0 && parent != pid,
    'The native fixture runs in an owned child.',
  );
  final path = File(
    '.tools/windows-memory-probe/Release/device_readout_cpu_fixture.dll',
  ).absolute.path;
  final fixture = ffi.DynamicLibrary.open(path);
  final configure = fixture
      .lookupFunction<ffi.Void Function(ffi.Uint32), void Function(int)>(
        'readout_cpu_configure',
      );
  final buffers = fixture.lookupFunction<ffi.Uint32 Function(), int Function()>(
    'readout_cpu_buffers',
  );
  final counter = fixture
      .lookupFunction<ffi.Uint32 Function(ffi.Uint32), int Function(int)>(
        'readout_cpu_counter',
      );
  final release = fixture.lookupFunction<ffi.Void Function(), void Function()>(
    'readout_cpu_release',
  );
  final disposalEvents = ReceivePort();
  final disposed = disposalEvents.first.then<void>((_) {});
  final sdk = DeviceAccess.isolated(
    cpuFixtureCollector,
    initialData: (path: path, disposed: disposalEvents.sendPort),
  );
  try {
    final baseline = await sdk.get(Entities.cpu);
    _topology(baseline);
    check(
      baseline.availableLogicalProcessorCount == 3,
      'The fixture starts with three available processors.',
    );
    if (scenario.startsWith('held-')) {
      final evidence = await _held(
        scenario,
        sdk,
        configure,
        buffers,
        counter,
        release,
        disposed,
      );
      print(
        'CPU_FAULT_CHILD ${jsonEncode({'childPid': pid, 'scenario': scenario, 'passed': true, ...evidence})}',
      );
      return true;
    }
    configure(_scenarios[scenario]!);
    final snapshot = await sdk.get(Entities.cpu);
    final invalidTopology = {
      'empty-invalid-topology',
      'duplicate-core-membership',
      'truncated-topology',
      'oversized-topology',
      'failed-topology-with-output',
    }.contains(scenario);
    _topology(snapshot, invalidTopology: invalidTopology);
    final available =
        {
          'empty-failed-system-set-list',
          'unknown-cpu-set-flags',
        }.contains(scenario)
        ? null
        : 3;
    check(
      snapshot.availableLogicalProcessorCount == available,
      'The CPU response preserves known availability or reports unavailable data as null: ${snapshot.availableLogicalProcessorCount}',
    );
    if (scenario == 'oversized-topology') {
      check(
        counter(3) < 4096,
        'An excessive native size is rejected before allocating its buffer.',
      );
    }
    final values = await sdk
        .withPollInterval(const Duration(milliseconds: 15))
        .watch(Entities.cpu)
        .take(2)
        .toList();
    check(
      values.every(
            (value) => value.availableLogicalProcessorCount == available,
          ) &&
          values.last.collectedAt.isAfter(values.first.collectedAt),
      'Get and polling agree, including equal-value delivery.',
    );
    for (final value in values) {
      _topology(value, invalidTopology: invalidTopology);
    }
    configure(0);
    check(
      (await sdk.get(Entities.cpu)).availableLogicalProcessorCount == 3,
      'Ordinary collection recovers in the same context.',
    );
    check(buffers() == 0, 'Native buffers are released after collection.');
    print(
      'CPU_FAULT_CHILD ${jsonEncode({'childPid': pid, 'scenario': scenario, 'passed': true})}',
    );
  } finally {
    release();
    sdk.dispose();
    try {
      await disposed.timeout(const Duration(seconds: 2));
    } finally {
      disposalEvents.close();
      fixture.close();
    }
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
  final output = child.stdout.transform(utf8.decoder).join();
  final errors = child.stderr.transform(utf8.decoder).join();
  try {
    final exitCode = await child.exitCode.timeout(const Duration(seconds: 8));
    terminal = true;
    final stdout = await output, stderr = await errors;
    check(
      exitCode == 0,
      'CPU child $scenario failed ($exitCode): $stdout $stderr',
    );
    final line = const LineSplitter()
        .convert(stdout)
        .singleWhere((value) => value.startsWith('CPU_FAULT_CHILD '));
    final report = jsonDecode(line.substring('CPU_FAULT_CHILD '.length)) as Map;
    check(
      report['childPid'] == child.pid &&
          report['scenario'] == scenario &&
          report['passed'] == true,
      'The report belongs to the retained child process.',
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
    'native CPU $scenario preserves independent fields': () => _run(scenario),
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
