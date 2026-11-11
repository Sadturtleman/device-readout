import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/widgets.dart';
import 'package:device_readout_flutter/device_readout_flutter.dart';

import 'android_state.dart';

void require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void reportResult(Map<String, Object?> result) {
  // Android/Flutter log lines have finite length. ASCII chunks also avoid
  // splitting a Unicode surrogate pair in an error message or native label.
  final payload = base64Encode(utf8.encode(jsonEncode(result)));
  const size = 600;
  final count = (payload.length + size - 1) ~/ size;
  for (var index = 0; index < count; index++) {
    final end = (index + 1) * size;
    print(
      'DEVICE_READOUT_ANDROID_RESULT_PART:$index/$count:${payload.substring(index * size, end < payload.length ? end : payload.length)}',
    );
  }
}

DeviceCollector blockedCollector(Object? initial) =>
    _BlockedCollector(initial! as SendPort);

final class _BlockedCollector implements DeviceCollector {
  final SendPort probe;
  _BlockedCollector(this.probe);
  @override
  DeviceSnapshot read(EntityAddress entity, ReadContext context) {
    if (entity.kind == EntityKind.runtime)
      return RuntimeSnapshot(processBitness: 64);
    probe.send('entered');
    sleep(const Duration(milliseconds: 600));
    probe.send('returned');
    return RamSnapshot(physicalBytes: BigInt.from(16384));
  }

  @override
  void dispose() {}
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: Text('DeviceReadout Android sensor verification')),
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(verify());
  });
}

Future<void> verify() async {
  final probe = ReceivePort();
  final entered = Completer<void>(), returned = Completer<void>();
  final messages = probe.listen((Object? value) {
    if (value == 'entered') entered.complete();
    if (value == 'returned') returned.complete();
  });
  final access = DeviceAccess.isolated(
    blockedCollector,
    initialData: probe.sendPort,
  );
  final activity = FlutterSensorActivityObserver.attach(access);
  FlutterAndroidSensors? sensors;
  ObserverFailureSource? independentFailure;
  final checks = <String>[];
  List<String>? lifecycleStates;
  Map<String, Object?>? nativeState;
  try {
    nativeState = await verifyAndroidState(checks);
    lifecycleStates = nativeState['mixedLifecycle']! as List<String>;
    sensors = await FlutterAndroidSensors.attach(access);
    final targets = await access.list(Entities.accelerometer);
    require(
      targets.isNotEmpty,
      'The owned emulator must expose an accelerometer.',
    );
    final selected = targets.first;
    final support = await access.capabilities.get(selected);
    require(
      support.readable == true &&
          support.watchable == true &&
          (await access.capabilities.get(Entities.accelerometer)).readable ==
              true,
      'Explicit sensor attachment must make its registered sources available.',
    );
    final metadata = await access.describe(selected);
    require(
      metadata.kind == SensorKind.accelerometer && metadata.name != null,
      'Native metadata must describe the selected accelerometer.',
    );
    checks.add('native discovery, metadata and registered sensor capabilities');

    final sample = await access.get(selected);
    require(
      sample.value != null && sample.collectedAt.isUtc,
      'A native accelerometer sample must arrive through the collection isolate.',
    );
    checks.add('fresh native sensor get');

    final values = await access
        .withSensorSamplingRate(SensorSamplingRate.atHertz(60))
        .watch(selected)
        .take(3)
        .toList()
        .timeout(const Duration(seconds: 8));
    require(
      values.every((item) => item.value != null),
      'Continuous native watch must deliver actual typed samples.',
    );
    checks.add('native watch and subscription cancellation');

    await sensors.refresh(Entities.accelerometer);
    require(
      (await access.list(Entities.accelerometer)).contains(selected),
      'Refreshing an unchanged native inventory must preserve handles.',
    );
    checks.add('stable discovery handles');

    try {
      await sensors.refresh(selected);
      throw StateError('Refresh requires a collection, not a bound target.');
    } on DeviceReadoutException catch (error) {
      require(
        error.code == ErrorCode.invalidConfiguration,
        'Invalid refresh input must report InvalidConfiguration.',
      );
    }
    require(
      (await access.get(selected)).value != null,
      'Invalid refresh input must not poison a previously usable sensor.',
    );
    checks.add('invalid refresh leaves live targets usable');

    const applicationDenial = DeviceReadoutException(
      ErrorCode.permissionDenied,
      'Application collection policy is disabled.',
    );
    access.observers.failure(Entities.accelerometer, applicationDenial);
    try {
      await sensors.refresh(Entities.accelerometer);
      try {
        await access.get(selected);
        throw StateError('Native refresh must preserve application policy.');
      } on DeviceReadoutException catch (error) {
        require(
          identical(error, applicationDenial),
          'The original app-owned failure must still gate sensor reads.',
        );
      }
    } finally {
      access.observers.failure(Entities.accelerometer, null);
    }
    require(
      (await access.get(selected)).value != null,
      'Collection resumes only after the app clears its own policy.',
    );
    checks.add('refresh preserves app-owned permission policy');

    await access.get(Entities.runtime);
    final busy = access.get(Entities.ram);
    await entered.future;
    var ticks = 0;
    final heartbeat = Timer.periodic(const Duration(milliseconds: 10), (_) {
      ticks++;
    });
    try {
      try {
        await access
            .withReadTimeout(const Duration(milliseconds: 150))
            .get(selected);
        throw StateError(
          'A blocked normalizer must preserve the sensor read deadline.',
        );
      } on DeviceReadoutException catch (error) {
        require(
          error.code == ErrorCode.readTimeout,
          'Expected a sensor read timeout.',
        );
      }
      require(
        ticks >= 3 && !returned.isCompleted,
        'The Flutter main isolate must progress before the blocked collector returns.',
      );
    } finally {
      heartbeat.cancel();
    }
    await busy;
    checks.add('main-isolate heartbeat and independent sensor deadline');

    const independentDenial = DeviceReadoutException(
      ErrorCode.permissionDenied,
      'An independent altitude source is disabled.',
    );
    independentFailure = access.observers.failureSource(
      Entities.relativeAltitude,
    );
    independentFailure.publish(independentDenial);

    final active = Completer<void>(), ended = Completer<void>();
    final errors = <Object>[];
    final live = access
        .watch(selected)
        .listen(
          (_) {
            if (!active.isCompleted) active.complete();
          },
          onError: (Object error) {
            errors.add(error);
          },
          onDone: ended.complete,
        );
    try {
      await active.future.timeout(const Duration(seconds: 5));
      print('DEVICE_READOUT_ANDROID_ACTIVE');
      // Give the host fixture a window to inspect SensorManager's active list.
      await Future<void>.delayed(const Duration(seconds: 2));
      sensors.dispose();
      await ended.future.timeout(const Duration(seconds: 5));
      require(
        errors.length == 1 &&
            errors.single is DeviceReadoutException &&
            (errors.single as DeviceReadoutException).code ==
                ErrorCode.entityRemoved,
        'Disposing an active source must end its watch with EntityRemoved.',
      );
    } finally {
      await live.cancel();
    }
    try {
      await access.get(selected);
      throw StateError('Disposal must retire the old sensor handle.');
    } on DeviceReadoutException catch (error) {
      require(error.code == ErrorCode.entityRemoved, 'Expected EntityRemoved.');
    }
    final retiredSupport = await access.capabilities.get(selected);
    require(
      retiredSupport.readable == false && retiredSupport.watchable == false,
      'Sensor disposal must also retire its capability support.',
    );
    checks.add('adapter disposal retires sources and capability support');

    try {
      await access.list(Entities.relativeAltitude);
      throw StateError('Disposal must preserve another provider\'s failure.');
    } on DeviceReadoutException catch (error) {
      require(
        identical(error, independentDenial),
        'Only the detached Android provider\'s UnsupportedEntity must clear.',
      );
    }
    independentFailure.dispose();
    final altitude = access.observers.target(
      Entities.relativeAltitude,
      'application-altitude-after-native-detach',
    );
    final removeAltitude = access.observers.sensorSource(
      altitude,
      SensorObserverSource<RelativeAltitudeSnapshot>(
        subscribe: (session) {
          session.publish(RelativeAltitudeSnapshot(value: 12.5));
          return null;
        },
      ),
    );
    try {
      require(
        (await access.get(altitude)).value == 12.5,
        'A replacement source must not inherit a detached provider\'s failure.',
      );
    } finally {
      removeAltitude();
    }
    checks.add(
      'detachment preserves independent failures and permits replacement',
    );

    final retiredAdapter = sensors;
    access.observers.failure(Entities.accelerometer, applicationDenial);
    sensors = await FlutterAndroidSensors.attach(access);
    retiredAdapter.dispose();
    try {
      await access.list(Entities.accelerometer);
      throw StateError('Reattachment must preserve application policy.');
    } on DeviceReadoutException catch (error) {
      require(
        identical(error, applicationDenial),
        'Attaching fresh sensor sources cannot clear the app-owned gate.',
      );
    }
    access.observers.failure(Entities.accelerometer, null);
    final replacement = (await access.list(Entities.accelerometer)).first;
    require(
      replacement != selected && (await access.get(replacement)).value != null,
      'Reattachment must provide a fresh usable handle.',
    );
    try {
      await access.get(selected);
      throw StateError('Reattachment must not revive a removed handle.');
    } on DeviceReadoutException catch (error) {
      require(error.code == ErrorCode.entityRemoved, 'Expected EntityRemoved.');
    }
    sensors.dispose();
    checks.add('reattachment preserves app policy and creates fresh handles');

    for (var attempt = 0; attempt < 6; attempt++) {
      sensors = await FlutterAndroidSensors.attach(access);
      final target = (await access.list(Entities.accelerometer)).first;
      final first = Completer<void>(), finished = Completer<void>();
      final failures = <Object>[];
      final subscription = access
          .watch(target)
          .listen(
            (_) {
              if (!first.isCompleted) first.complete();
            },
            onError: (Object error) {
              failures.add(error);
            },
            onDone: finished.complete,
          );
      try {
        await first.future.timeout(const Duration(seconds: 5));
        final refresh = sensors
            .refresh(Entities.accelerometer)
            .then<Object?>((_) => null, onError: (Object error) => error);
        sensors.dispose();
        await finished.future.timeout(const Duration(seconds: 2));
        require(
          failures.length == 1 &&
              failures.single is DeviceReadoutException &&
              (failures.single as DeviceReadoutException).code ==
                  ErrorCode.entityRemoved &&
              await refresh is DeviceReadoutCancelled,
          'Disposal must finish active watches and pending inventory reads.',
        );
      } finally {
        await subscription.cancel();
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    checks.add('repeated disposal with sensor and inventory replies in flight');
    reportResult({
      'passed': true,
      'checks': checks,
      'lifecycle': lifecycleStates,
      'nativeState': nativeState,
    });
  } catch (error, stack) {
    reportResult({
      'passed': false,
      'checks': checks,
      'lifecycle': lifecycleStates,
      'error': '$error',
      'stack': '$stack',
    });
  } finally {
    independentFailure?.dispose();
    sensors?.dispose();
    activity.dispose();
    access.dispose();
    await messages.cancel();
    probe.close();
  }
}
