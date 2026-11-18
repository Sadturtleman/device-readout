import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:device_readout/device_readout.dart';
// Inject only the internal native-adapter binding; assertions use public SDK APIs.
import 'package:device_readout/src/transport_native.dart'
    show NativeCollectorBindings, createNativeCollector;

import 'observers.dart' show check, errorOf;

const _childFlag = '--device-readout-storage-child';
const _scenarios = {
  'name-unterminated': 1,
  'name-surrogate': 2,
  'filesystem-unterminated': 3,
  'filesystem-surrogate': 4,
  'unicode-empty': 5,
  'metadata-failure': 6,
  'free-space-failure': 7,
  'capacity-failure': 8,
  'all-denied': 9,
  'root-open-failure': 10,
  'first-enumeration-failure': 11,
  'partial-enumeration-failure': 12,
  'malformed-inventory': 13,
  'duplicate-inventory': 14,
  'removed': 15,
  'removed-during-read': 16,
  'invalid-geometry': 21,
  'capacity-overflow': 22,
  'unknown-drive-kind': 23,
  'zero-capacity': 24,
  'unsigned-capacity': 25,
  'held-get': 17,
  'held-list': 18,
  'held-metadata': 19,
  'held-close': 20,
  'held-cancel': 17,
  'held-dispose': 17,
  'held-watch-initial': 17,
  'held-watch-poll': 17,
};

Future<void> _until(bool Function() condition) async {
  final end = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    if (DateTime.now().isAfter(end))
      throw StateError('Native fixture did not reach the expected state.');
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

Future<Map<String, Object?>> _held(
  String scenario,
  DeviceAccess sdk,
  Entity<StorageVolumeSnapshot> target,
  void Function(int) configure,
  int Function(int) counter,
  void Function() release,
) async {
  final limited = sdk
      .withReadTimeout(const Duration(milliseconds: 200))
      .withPollInterval(const Duration(milliseconds: 15));
  final token = CancellationToken();
  StreamSubscription<StorageVolumeSnapshot>? subscription;
  var ticks = 0;
  final heartbeat = Timer.periodic(
    const Duration(milliseconds: 5),
    (_) => ticks++,
  );
  try {
    late Future<Object?> result;
    if (scenario == 'held-watch-poll') {
      final failed = Completer<Object?>(), initial = Completer<void>();
      subscription = limited
          .watch(target)
          .listen(
            (_) {
              if (!initial.isCompleted) {
                configure(17);
                initial.complete();
              }
            },
            onError: (Object error) {
              if (!failed.isCompleted) failed.complete(error);
            },
          );
      result = failed.future;
      await initial.future;
    } else {
      configure(_scenarios[scenario]!);
      result = errorOf(switch (scenario) {
        'held-list' => limited.storageVolumes.list(),
        'held-watch-initial' => limited.watch(target).first,
        _ => limited.get(target, cancellation: token),
      });
    }
    await _until(() => counter(3) == 1);
    final startTicks = ticks;
    await Future<void>.delayed(const Duration(milliseconds: 35));
    check(
      ticks - startTicks >= 2,
      'The host timer progresses during a native call.',
    );
    final workerThread = counter(5), callerThread = counter(6);
    check(
      workerThread != callerThread,
      'Native blocking work runs off the caller thread.',
    );
    if (scenario == 'held-cancel') token.cancel();
    if (scenario == 'held-dispose') sdk.dispose();
    final error = await result.timeout(const Duration(seconds: 1));
    if (scenario == 'held-cancel' || scenario == 'held-dispose') {
      check(
        error is DeviceReadoutCancelled,
        'Cancellation/disposal stays distinct from timeout: $error',
      );
    } else {
      check(
        error is DeviceReadoutException && error.code == ErrorCode.readTimeout,
        'A held native operation has an independent host deadline: $error',
      );
    }
    check(counter(3) == 1, 'Public completion precedes native return.');
    final progressDuringHold = ticks - startTicks;
    release();
    await _until(
      () =>
          counter(3) == 0 &&
          counter(0) == 0 &&
          counter(1) == 0 &&
          counter(2) == 0,
    );
    configure(0);
    if (scenario != 'held-dispose') {
      check(
        (await sdk.get(target)).name == 'Fixture volume',
        'Released native work permits a fresh read.',
      );
    } else {
      check(
        await errorOf(sdk.get(target)) is DeviceReadoutCancelled,
        'Disposed context stays closed.',
      );
    }
    return {
      'progressDuringHold': progressDuringHold,
      'workerThread': workerThread,
      'callerThread': callerThread,
      'completedBeforeNativeReturn': true,
      'nativeResourcesRemaining':
          counter(0) + counter(1) + counter(2) + counter(3),
    };
  } finally {
    release();
    heartbeat.cancel();
    await subscription?.cancel();
  }
}

Future<bool> runChildIfRequested(List<String> arguments) async {
  if (arguments.isEmpty || arguments.first != _childFlag) return false;
  check(
    arguments.length == 3 && Platform.isWindows,
    'Invalid fixture arguments.',
  );
  final parent = int.parse(arguments[1]), scenario = arguments[2];
  check(
    parent > 0 && parent != pid,
    'The storage fixture requires an owned child.',
  );
  final fixturePath = File(
    '.tools/windows-memory-probe/Release/device_readout_storage_fixture.dll',
  ).absolute.path;
  final fixture = ffi.DynamicLibrary.open(fixturePath);
  final configure = fixture
      .lookupFunction<ffi.Void Function(ffi.Uint32), void Function(int)>(
        'readout_storage_configure',
      );
  final counter = fixture
      .lookupFunction<ffi.Uint32 Function(ffi.Uint32), int Function(int)>(
        'readout_storage_counter',
      );
  final release = fixture.lookupFunction<ffi.Void Function(), void Function()>(
    'readout_storage_release',
  );
  final sdk = DeviceAccess.isolated(
    createNativeCollector,
    initialData: NativeCollectorBindings(windowsStorageLibrary: fixturePath),
  );
  try {
    final target = (await sdk.storageVolumes.list()).single;
    if (scenario.startsWith('held-')) {
      final evidence = await _held(
        scenario,
        sdk,
        target,
        configure,
        counter,
        release,
      );
      print(
        'STORAGE_CHILD ${jsonEncode({'childPid': pid, 'scenario': scenario, 'passed': true, ...evidence})}',
      );
      return true;
    }
    final mode = _scenarios[scenario]!;
    configure(mode);
    final expectedError = switch (mode) {
      9 || 11 => ErrorCode.permissionDenied,
      12 || 13 || 14 => ErrorCode.readFailed,
      15 || 16 => ErrorCode.entityRemoved,
      _ => null,
    };
    if (expectedError != null) {
      final failure = await errorOf(sdk.get(target));
      check(
        failure is DeviceReadoutException && failure.code == expectedError,
        'Expected $expectedError for $scenario, received $failure.',
      );
      if (mode >= 11 && mode <= 14) {
        final discoveryFailure = await errorOf(sdk.storageVolumes.list());
        check(
          discoveryFailure is DeviceReadoutException &&
              discoveryFailure.code == expectedError,
          'An incomplete inventory must fail without retiring existing targets.',
        );
      }
      final watchFailure = await errorOf(sdk.watch(target).first);
      check(
        watchFailure is DeviceReadoutException &&
            watchFailure.code == expectedError,
        'Initial watch preserves the native failure category.',
      );
    } else {
      final metadataMissing = mode == 6 || mode == 10;
      final snapshot = await sdk.get(target);
      final expected = {
        'name': metadataMissing || mode == 1 || mode == 2
            ? null
            : mode == 5
            ? '가🚀é'
            : 'Fixture volume',
        'fileSystem': metadataMissing || mode == 3 || mode == 4
            ? null
            : mode == 5
            ? ''
            : 'NTFS',
        'readOnly': metadataMissing ? null : true,
        'totalBytes': mode == 8 || mode == 21 || mode == 22 ? null : '8192000',
        'totalBytesForCaller': mode == 7
            ? null
            : mode == 24
            ? '0'
            : mode == 25
            ? '18446744073709551615'
            : '6144000',
        'freeBytes': mode == 7
            ? null
            : mode == 24
            ? '0'
            : mode == 25
            ? '18446744073709551615'
            : '4096000',
        'availableToCallerBytes': mode == 7
            ? null
            : mode == 24
            ? '0'
            : mode == 25
            ? '18446744073709551615'
            : '2048000',
        'removable': mode == 23 ? null : false,
      };
      void matches(StorageVolumeSnapshot value) {
        final json = value.toJson();
        for (final entry in expected.entries) {
          check(
            json[entry.key] == entry.value,
            '$scenario ${entry.key}: ${json[entry.key]} != ${entry.value}',
          );
        }
      }

      matches(snapshot);
      final values = await sdk
          .withPollInterval(const Duration(milliseconds: 15))
          .watch(target)
          .take(2)
          .toList();
      for (final value in values) {
        matches(value);
      }
      check(
        values.last.collectedAt.isAfter(values.first.collectedAt),
        'Equal field results must still be emitted as fresh snapshots.',
      );
    }
    configure(0);
    if (mode == 15 || mode == 16) {
      final replacement = (await sdk.storageVolumes.list()).single;
      check(
        replacement != target,
        'A reappearing GUID requires a fresh handle.',
      );
      final stale = await errorOf(sdk.get(target));
      check(
        stale is DeviceReadoutException &&
            stale.code == ErrorCode.entityRemoved,
        'A removed generation never revives.',
      );
      check(
        (await sdk.get(replacement)).name == 'Fixture volume',
        'Fresh generation is readable.',
      );
    } else {
      check(
        (await sdk.get(target)).name == 'Fixture volume',
        'A later valid name recovers on the same handle.',
      );
    }
    check(
      counter(0) == 0 && counter(1) == 0 && counter(2) == 0,
      'Native buffers, directory handles and enumeration searches are released.',
    );
    print(
      'STORAGE_CHILD ${jsonEncode({'childPid': pid, 'scenario': scenario, 'passed': true})}',
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
  final output = child.stdout.transform(utf8.decoder).join();
  final errors = child.stderr.transform(utf8.decoder).join();
  try {
    final exitCode = await child.exitCode.timeout(const Duration(seconds: 8));
    terminal = true;
    final stdout = await output, stderr = await errors;
    check(
      exitCode == 0,
      'Storage child $scenario failed ($exitCode): $stdout $stderr',
    );
    final line = const LineSplitter()
        .convert(stdout)
        .singleWhere((value) => value.startsWith('STORAGE_CHILD '));
    final report = jsonDecode(line.substring('STORAGE_CHILD '.length)) as Map;
    check(
      report['childPid'] == child.pid &&
          report['scenario'] == scenario &&
          report['passed'] == true,
      'The successful report must come from the retained child process.',
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
    'native storage $scenario preserves field and target contracts': () =>
        _run(scenario),
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
