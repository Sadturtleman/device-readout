import 'dart:async';

import 'package:device_readout_flutter/device_readout_flutter.dart';

import 'android_lifecycle.dart';

void _require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

// A bounded test observer: retain only the latest snapshot and current waiters.
final class _Probe<S extends DeviceSnapshot> {
  final errors = <Object>[];
  final finished = Completer<void>();
  final _waiting = <Completer<S>>{};
  late final StreamSubscription<S> _subscription;
  S? latest;
  int count = 0;
  bool _cancelled = false;

  _Probe(DeviceAccess access, Entity<S> entity) {
    _subscription = access
        .watch(entity)
        .listen(
          (value) {
            latest = value;
            count++;
            final waiting = _waiting.toList();
            _waiting.clear();
            for (final pending in waiting) {
              pending.complete(value);
            }
          },
          onError: (Object error) {
            errors.add(error);
            final waiting = _waiting.toList();
            _waiting.clear();
            for (final pending in waiting) {
              pending.completeError(error);
            }
          },
          onDone: () {
            if (!finished.isCompleted) finished.complete();
          },
        );
  }

  Future<S> next() {
    if (errors.isNotEmpty) return Future.error(errors.first);
    if (_cancelled || finished.isCompleted)
      return Future.error(StateError('Watch ended.'));
    final pending = Completer<S>();
    _waiting.add(pending);
    return pending.future.timeout(const Duration(seconds: 5)).whenComplete(() {
      _waiting.remove(pending);
    });
  }

  Future<void> cancel() async {
    if (_cancelled) return;
    _cancelled = true;
    await _subscription.cancel();
  }
}

/// Both Android adapters feed the same public DeviceAccess and normalization
/// worker. This deliberately closes that context in the final lifetime check.
Future<List<String>> verifyAndroidMixed(
  DeviceAccess access,
  List<String> checks,
) async {
  final activity = FlutterSensorActivityObserver.attach(access);
  FlutterAndroidSensors? sensors;
  _Probe<OsSnapshot>? os;
  _Probe<CpuCoreSnapshot>? cpu;
  _Probe<AccelerometerSnapshot>? first, second;
  try {
    sensors = await FlutterAndroidSensors.attach(access);
    final target = (await access.list(Entities.accelerometer)).first;
    final core = (await access.cpuCores.list()).first;
    final fast = access.withPollInterval(const Duration(milliseconds: 40));
    os = _Probe(fast, Entities.os);
    cpu = _Probe(
      access.withPollInterval(const Duration(milliseconds: 70)),
      core,
    );
    first = _Probe(
      access.withSensorSamplingRate(SensorSamplingRate.atHertz(60)),
      target,
    );
    second = _Probe(
      access.withSensorSamplingRate(SensorSamplingRate.atHertz(15)),
      target,
    );
    final initial = await Future.wait<DeviceSnapshot>([
      os.next(),
      cpu.next(),
      first.next(),
      second.next(),
    ]);
    _require(
      initial.every((value) => value.collectedAt.isUtc) &&
          os.latest!.family == OsFamily.android &&
          cpu.latest!.logicalIndex != null &&
          first.latest!.value != null &&
          second.latest!.value != null,
      'Native state and sensor streams must coexist with typed actual values.',
    );
    final values = await Future.wait<Object?>([
      access.get(Entities.ram),
      access.get(core),
      access.get(target),
      access.cpuCores.list(),
      access.capabilities.get(core),
      access.describe(target),
    ]);
    _require(
      (values[0]! as RamSnapshot).kernelAccessibleBytes! > BigInt.zero &&
          (values[1]! as CpuCoreSnapshot).logicalIndex ==
              cpu.latest!.logicalIndex &&
          (values[2]! as AccelerometerSnapshot).value != null &&
          (values[3]! as List<Entity<CpuCoreSnapshot>>).contains(core) &&
          (values[4]! as EntityCapabilities).readable == true &&
          (values[5]! as SensorDescription).kind == SensorKind.accelerometer,
      'Shared reads, discovery, capabilities and metadata must retain their native meanings.',
    );
    await Future.wait<DeviceSnapshot>([os.next(), first.next()]);
    checks.add(
      'shared access interleaves native state, sensors, discovery and metadata',
    );

    await second.cancel();
    final cancelledSensorCount = second.count;
    await cpu.cancel();
    final cancelledCpuCount = cpu.count;
    await Future.wait<DeviceSnapshot>([os.next(), first.next()]);
    _require(
      second.count == cancelledSensorCount &&
          cpu.count == cancelledCpuCount &&
          os.errors.isEmpty &&
          first.errors.isEmpty,
      'Cancelling either kind of stream must not cancel sibling streams.',
    );
    checks.add(
      'individual native and sensor cancellation preserves sibling subscriptions',
    );

    try {
      await access.get(Entities.hardwareSerial);
      throw StateError('The ordinary app cannot read the hardware serial.');
    } on DeviceReadoutException catch (error) {
      _require(
        error.code == ErrorCode.permissionDenied,
        'Native denial remains typed.',
      );
    }
    await Future.wait<DeviceSnapshot>([os.next(), first.next()]);
    const denied = DeviceReadoutException(
      ErrorCode.permissionDenied,
      'App sensor policy denied.',
    );
    access.observers.failure(target, denied);
    await first.finished.future.timeout(const Duration(seconds: 5));
    _require(
      first.errors.length == 1 && identical(first.errors.single, denied),
      'The affected sensor watch must end with the app-owned error.',
    );
    await os.next();
    access.observers.failure(target, null);
    first = _Probe(
      access.withSensorSamplingRate(SensorSamplingRate.atHertz(60)),
      target,
    );
    await first.next();
    checks.add(
      'native and sensor failures remain scoped while sibling streams continue',
    );

    final runningOs = os;
    final lifecycle = await verifyAndroidLifecycle(
      access,
      target,
      whilePaused: () async {
        final state = await runningOs.next();
        final ram = await access.get(Entities.ram);
        _require(
          state.family == OsFamily.android &&
              ram.kernelAccessibleBytes! > BigInt.zero &&
              !runningOs.finished.isCompleted &&
              runningOs.errors.isEmpty,
          'Sensor suspension and its get timeout must leave native state work usable.',
        );
        checks.add(
          'paused sensor timeout preserves shared native state reads and polling',
        );
      },
    );
    await Future.wait<DeviceSnapshot>([os.next(), first.next()]);
    checks.add(
      'real Activity pause and resume preserve shared native and sensor watches',
    );

    final retired = sensors;
    sensors.dispose();
    await first.finished.future.timeout(const Duration(seconds: 5));
    _require(
      first.errors.length == 1 &&
          first.errors.single is DeviceReadoutException &&
          (first.errors.single as DeviceReadoutException).code ==
              ErrorCode.entityRemoved,
      'Detaching only sensors must retire their watch.',
    );
    await os.next();
    sensors = await FlutterAndroidSensors.attach(access);
    retired.dispose();
    final replacement = (await access.list(Entities.accelerometer)).first;
    _require(
      !identical(target, replacement) &&
          (await access.capabilities.get(target)).readable == false &&
          (await access.get(core)).logicalIndex == cpu.latest!.logicalIndex,
      'Sensor replacement must preserve native targets and retire the old sensor handle.',
    );
    first = _Probe(access, replacement);
    await Future.wait<DeviceSnapshot>([os.next(), first.next()]);
    checks.add(
      'sensor provider replacement preserves native targets and active state streams',
    );

    access.dispose();
    await Future.wait<void>([os.finished.future, first.finished.future])
        .timeout(const Duration(seconds: 5));
    _require(
      os.errors.length == 1 &&
          os.errors.single is DeviceReadoutCancelled &&
          first.errors.length == 1 &&
          first.errors.single is DeviceReadoutCancelled,
      'Context disposal must terminate native and sensor streams once with cancellation.',
    );
    checks.add(
      'shared context disposal cancels both native and sensor streams',
    );
    return lifecycle;
  } finally {
    await first?.cancel();
    await second?.cancel();
    await os?.cancel();
    await cpu?.cancel();
    sensors?.dispose();
    activity.dispose();
  }
}
