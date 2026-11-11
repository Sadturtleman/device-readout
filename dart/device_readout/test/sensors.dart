import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:device_readout/device_readout.dart';

import 'observers.dart' show check, errorOf, forbiddenNativeFactory;

Future<void> until(bool Function() condition) async {
  final clock = Stopwatch()..start();
  while (!condition()) {
    if (clock.elapsed > const Duration(seconds: 2))
      throw StateError('Sensor observation did not settle.');
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

Future<void> activityReleasesAndResumes() async {
  final sdk = DeviceAccess.isolated(forbiddenNativeFactory);
  final target = sdk.observers.target(
    Entities.accelerometer,
    'foreground-sensor',
  );
  final sessions = <SensorObserverSession<AccelerometerSnapshot>>[];
  var cleanups = 0;
  sdk.observers.sensorSource(
    target,
    SensorObserverSource<AccelerometerSnapshot>(
      subscribe: (session) {
        sessions.add(session);
        return () {
          cleanups++;
        };
      },
    ),
  );
  sdk.observers.sensorActivity(false);
  final values = <AccelerometerSnapshot>[], errors = <Object>[];
  final first = Completer<void>();
  final subscription = sdk
      .withReadTimeout(const Duration(milliseconds: 60))
      .withSensorSamplingRate(SensorSamplingRate.atHertz(60))
      .watch(target)
      .listen(
        (value) {
          values.add(value);
          if (!first.isCompleted) first.complete();
        },
        onError: (Object error) {
          errors.add(error);
        },
      );
  final pending = sdk.withReadTimeout(const Duration(seconds: 1)).get(target);
  final result = errorOf(pending.then<Object?>((value) => value));
  try {
    await Future<void>.delayed(const Duration(milliseconds: 90));
    check(
      sessions.isEmpty && errors.isEmpty,
      'Inactive observations must not start sources or spend a watch initial-read deadline.',
    );
    sdk.observers.sensorActivity(true);
    await until(() => sessions.length == 2);
    sdk.observers.sensorActivity(false);
    check(
      sessions.every((session) => session.cancellation.isCancelled),
      'Inactivity must release both one-shot and watch sources.',
    );
    for (final session in sessions) {
      session.publish(AccelerometerSnapshot(value: const Vector3(99, 0, 0)));
    }
    await Future<void>.delayed(const Duration(milliseconds: 90));
    check(
      values.isEmpty && errors.isEmpty,
      'Inactive or late samples must not escape suspended sessions.',
    );
    sdk.observers.sensorActivity(true);
    await until(() => sessions.length == 4);
    for (final session in sessions.skip(2)) {
      session.publish(
        AccelerometerSnapshot(
          value: Vector3(session.samplingRate.hertz == 60 ? 2 : 3, 0, 0),
        ),
      );
    }
    await first.future;
    final read = await pending;
    check(
      read.value?.x == 3 && values.single.value?.x == 2 && await result == null,
      'Resume must use fresh per-operation sessions and retain their sampling settings.',
    );
    await subscription.cancel();
    check(
      cleanups == 4,
      'Every opened source must clean up once across suspension and completion.',
    );
  } finally {
    await subscription.cancel();
    sdk.dispose();
  }
}

Future<void> sourceDemandAndSampling() async {
  final sdk = DeviceAccess.isolated(forbiddenNativeFactory);
  final target = sdk.observers.target(
    Entities.accelerometer,
    'app-accelerometer',
  );
  final sessions = <SensorObserverSession<AccelerometerSnapshot>>[];
  final stopped = <int>[];
  final unregister = sdk.observers.sensorSource(
    target,
    SensorObserverSource<AccelerometerSnapshot>(
      subscribe: (session) {
        sessions.add(session);
        final id = sessions.length;
        session.publish(
          AccelerometerSnapshot(value: Vector3(id.toDouble(), 0, 9.8)),
        );
        return () {
          stopped.add(id);
        };
      },
    ),
  );
  StreamSubscription<AccelerometerSnapshot>? subscription;
  try {
    final configured = sdk
        .withSensorSamplingRate(SensorSamplingRate.atHertz(60))
        .withReadTimeout(const Duration(seconds: 7));
    final stream = configured.watch(target);
    check(
      sessions.isEmpty,
      'Registration and watch construction must not open a native observation.',
    );
    final first = Completer<AccelerometerSnapshot>();
    subscription = stream.listen(first.complete);
    final start = DateTime.now().toUtc();
    final watched = await first.future;
    check(
      watched.value?.x == 1 &&
          sessions.single.samplingRate.hertz == 60 &&
          sessions.single.readTimeout == const Duration(seconds: 7),
      'A continuous watch requests its captured frequency and receives an actual sample.',
    );
    check(
      watched.collectedAt.isUtc && !watched.collectedAt.isBefore(start),
      'Observed samples are normalized and stamped by the worker.',
    );
    final next = await configured.get(target);
    check(
      next.value?.x == 2 &&
          sessions[1].samplingRate == SensorSamplingRate.platformDefault,
      'One-shot reads need a fresh source sample and use platform default sampling.',
    );
    await subscription.cancel();
    check(
      sessions.every((session) => session.cancellation.isCancelled),
      'Each finished operation must cancel its own source session.',
    );
    check(
      stopped.length == 2 && stopped.contains(1) && stopped.contains(2),
      'Both source subscriptions must clean up exactly once.',
    );
    unregister();
    final error = await errorOf(sdk.get(target));
    check(
      error is DeviceReadoutException && error.code == ErrorCode.entityRemoved,
      'Unregistering a source permanently retires its handle.',
    );
  } finally {
    await subscription?.cancel();
    unregister();
    sdk.dispose();
  }
}

Future<void> eventSensorsWaitAndRejectFabricatedEvents() async {
  final sdk = DeviceAccess.isolated(forbiddenNativeFactory)
      .withReadTimeout(const Duration(milliseconds: 40))
      .withSensorSamplingRate(SensorSamplingRate.atHertz(120));
  final target = sdk.observers.target(Entities.stepDetected, 'steps');
  final sessions = <SensorObserverSession<StepDetectedSnapshot>>[];
  sdk.observers.sensorSource(
    target,
    SensorObserverSource<StepDetectedSnapshot>(
      subscribe: (session) {
        sessions.add(session);
        return null;
      },
    ),
  );
  try {
    Object? outcome;
    final waiting = sdk
        .watch(target)
        .first
        .then<void>(
          (value) {
            outcome = value;
          },
          onError: (Object error) {
            outcome = error;
          },
        );
    await Future<void>.delayed(const Duration(milliseconds: 90));
    check(
      outcome == null &&
          sessions.single.samplingRate == SensorSamplingRate.platformDefault,
      'An event watch must wait without an idle deadline or requested sampling frequency.',
    );
    final timedOut = await errorOf(sdk.get(target));
    check(
      timedOut is DeviceReadoutException &&
          timedOut.code == ErrorCode.readTimeout &&
          sessions[1].cancellation.isCancelled,
      'An event one-shot must time out and release its own observation.',
    );
    sessions[0].publish(StepDetectedSnapshot(value: false));
    await waiting;
    check(
      outcome is DeviceReadoutException &&
          (outcome as DeviceReadoutException).code == ErrorCode.readFailed,
      'False/null cannot be returned as fabricated step events. A malformed source must fail.',
    );
    check(
      sessions[0].cancellation.isCancelled,
      'Malformed events must terminate the source session.',
    );
  } finally {
    sdk.dispose();
  }
}

Future<void> delayedRegistrationAndFailureCleanup() async {
  final escaped = <Object>[];
  await runZonedGuarded<Future<void>>(
    () async {
      final sdk = DeviceAccess.isolated(forbiddenNativeFactory);
      final target = sdk.observers.target(
        Entities.accelerometer,
        'delayed-registration',
      );
      final sessions = <SensorObserverSession<AccelerometerSnapshot>>[];
      final registrations = <Completer<SensorObserverCleanup?>>[];
      var cleaned = 0;
      sdk.observers.sensorSource(
        target,
        SensorObserverSource<AccelerometerSnapshot>(
          subscribe: (session) {
            sessions.add(session);
            final setup = Completer<SensorObserverCleanup?>();
            registrations.add(setup);
            return setup.future;
          },
        ),
      );
      try {
        final cancellation = CancellationToken();
        final cancelled = errorOf(sdk.get(target, cancellation: cancellation));
        await until(() => sessions.length == 1);
        cancellation.cancel();
        check(
          await cancelled is DeviceReadoutCancelled &&
              sessions[0].cancellation.isCancelled,
          'Cancellation must finish without joining pending application registration.',
        );
        registrations[0].complete(() async {
          cleaned++;
          await Future<void>.delayed(Duration.zero);
          throw StateError('Late native cleanup failure.');
        });
        await until(() => cleaned == 1);
        final failure = errorOf(sdk.get(target));
        await until(() => sessions.length == 2);
        sessions[1].fail(
          const DeviceReadoutException(
            ErrorCode.permissionDenied,
            'Source permission denied.',
          ),
        );
        final error = await failure;
        check(
          error is DeviceReadoutException &&
              error.code == ErrorCode.permissionDenied,
          'Source failures must retain their typed error and terminate the operation.',
        );
        registrations[1].completeError(
          StateError('Late registration failure after denial.'),
        );
        final closing = errorOf(sdk.watch(target).first);
        await until(() => sessions.length == 3);
        sdk.dispose();
        check(
          await closing is DeviceReadoutCancelled &&
              sessions[2].cancellation.isCancelled,
          'Context closure must promptly end pending sensor observation.',
        );
        registrations[2].complete(() {
          cleaned++;
        });
        await until(() => cleaned == 2);
        for (final session in sessions) {
          session.publish(
            AccelerometerSnapshot(value: const Vector3(99, 99, 99)),
          );
          session.fail(
            const DeviceReadoutException(
              ErrorCode.readFailed,
              'Late sample failure.',
            ),
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      } finally {
        sdk.dispose();
      }
    },
    (Object error, StackTrace stack) {
      escaped.add(error);
    },
  );
  check(
    escaped.isEmpty,
    'Late application errors must not escape into the host zone.',
  );
}

Future<void> inactiveFailureIsTerminal() async {
  final sdk = DeviceAccess.isolated(forbiddenNativeFactory);
  final target = sdk.observers.target(Entities.gyroscope, 'inactive-failure');
  var starts = 0;
  sdk.observers.sensorSource(
    target,
    SensorObserverSource<GyroscopeSnapshot>(
      subscribe: (_) {
        starts++;
        return null;
      },
    ),
  );
  sdk.observers.sensorActivity(false);
  try {
    final watch = errorOf(sdk.watch(target).first);
    final get = errorOf(sdk.get(target));
    sdk.observers.failure(
      Entities.gyroscope,
      const DeviceReadoutException(
        ErrorCode.permissionDenied,
        'Permission revoked while inactive.',
      ),
    );
    sdk.observers.failure(Entities.gyroscope, null);
    for (final failure in await Future.wait([watch, get])) {
      check(
        failure is DeviceReadoutException &&
            failure.code == ErrorCode.permissionDenied,
        'Failure/recovery must still reject requests that crossed the failure.',
      );
    }
    sdk.observers.sensorActivity(true);
    check(
      starts == 0,
      'Failed suspended subscriptions must not restart or open any source.',
    );
  } finally {
    sdk.dispose();
  }
}

Future<void> metadataDoesNotStartSampling() async {
  final sdk = DeviceAccess.isolated(forbiddenNativeFactory);
  final target = sdk.observers.target(
    Entities.accelerometer,
    'described-sensor',
  );
  var starts = 0;
  sdk.observers.sensorSource(
    target,
    SensorObserverSource<AccelerometerSnapshot>(
      description: SensorDescription(
        kind: SensorKind.pressure,
        name: 'App accelerometer',
        vendor: 'Native provider',
        minimumInterval: const Duration(microseconds: 2500),
        resolution: double.nan,
        fifoCapacity: 0,
      ),
      subscribe: (_) {
        starts++;
        return null;
      },
    ),
  );
  sdk.observers.sensorActivity(false);
  try {
    final start = DateTime.now().toUtc();
    final description = await sdk.describe(target);
    check(
      description.kind == SensorKind.accelerometer &&
          description.name == 'App accelerometer' &&
          description.vendor == 'Native provider' &&
          description.fifoCapacity == 0 &&
          description.resolution == null &&
          description.minimumInterval == const Duration(microseconds: 2500),
      'Metadata must use the target sensor kind and normalize optional fields independently.',
    );
    check(
      starts == 0 &&
          description.collectedAt.isUtc &&
          !description.collectedAt.isBefore(start),
      'Description must normalize in the worker without starting an inactive sensor source.',
    );
    final invalid = await errorOf(sdk.describe(Entities.ram));
    check(
      invalid is DeviceReadoutException &&
          invalid.code == ErrorCode.unsupportedEntity,
      'Sensor description is not a state-entity read.',
    );
    sdk.observers.remove(target);
    final removed = await errorOf(sdk.describe(target));
    check(
      removed is DeviceReadoutException &&
          removed.code == ErrorCode.entityRemoved,
      'Removed sensors must not retain readable cached metadata.',
    );
  } finally {
    sdk.dispose();
  }
}

Future<void> reentrantActivityKeepsLatestState() async {
  final sdk = DeviceAccess.isolated(forbiddenNativeFactory);
  final target = sdk.observers.target(Entities.pressure, 'reentrant-activity');
  final sessions = <SensorObserverSession<PressureSnapshot>>[];
  var resumeDuringCleanup = false;
  sdk.observers.sensorSource(
    target,
    SensorObserverSource<PressureSnapshot>(
      subscribe: (session) {
        sessions.add(session);
        session.publish(PressureSnapshot(value: 101325));
        return () {
          if (resumeDuringCleanup) {
            resumeDuringCleanup = false;
            sdk.observers.sensorActivity(true);
          }
        };
      },
    ),
  );
  var delivered = 0;
  final one = sdk.watch(target).listen((_) {
    delivered++;
  });
  final two = sdk.watch(target).listen((_) {
    delivered++;
  });
  try {
    await until(() => delivered == 2);
    resumeDuringCleanup = true;
    sdk.observers.sensorActivity(false);
    await until(() => sessions.length == 4);
    check(
      sessions.take(2).every((session) => session.cancellation.isCancelled) &&
          sessions
              .skip(2)
              .every((session) => !session.cancellation.isCancelled),
      'A resumed state from source cleanup must supersede the older suspension for every subscriber.',
    );
    await until(() => delivered == 4);
  } finally {
    await one.cancel();
    await two.cancel();
    sdk.dispose();
  }
}

Future<void> duplicateSamplesAndBoundedPause() async {
  final sdk = DeviceAccess.isolated(forbiddenNativeFactory);
  final target = sdk.observers.target(Entities.accelerometer, 'ordered-source');
  late SensorObserverSession<AccelerometerSnapshot> session;
  sdk.observers.sensorSource(
    target,
    SensorObserverSource<AccelerometerSnapshot>(
      subscribe: (value) {
        session = value;
        return null;
      },
    ),
  );
  try {
    final pending = sdk.watch(target).take(3).toList();
    session.publish(AccelerometerSnapshot(value: const Vector3(1, 0, 9.8)));
    session.publish(AccelerometerSnapshot(value: const Vector3(1, 0, 9.8)));
    session.publish(
      AccelerometerSnapshot(value: const Vector3(2, double.nan, 9.8)),
    );
    final values = await pending;
    check(
      values.length == 3 &&
          values[0].value?.x == 1 &&
          values[1].value?.x == 1 &&
          values[2].value == null,
      'Sensor events retain order and duplicates, while an invalid vector becomes one null value.',
    );
    check(
      session.cancellation.isCancelled,
      'take must release its completed native observation.',
    );
    final errors = <Object>[];
    final ended = Completer<void>();
    final subscription = sdk
        .watch(target)
        .listen(
          (_) {},
          onError: (Object error) {
            errors.add(error);
          },
          onDone: ended.complete,
        );
    subscription.pause();
    for (var i = 0; i < 2049; i++) {
      session.publish(
        AccelerometerSnapshot(value: Vector3(i.toDouble(), 0, 0)),
      );
    }
    check(
      session.cancellation.isCancelled,
      'Overflow must stop the source before more memory can accumulate.',
    );
    subscription.resume();
    await ended.future;
    check(
      errors.single is DeviceReadoutException &&
          (errors.single as DeviceReadoutException).code ==
              ErrorCode.readFailed,
      'A full delivery queue fails explicitly instead of silently dropping samples.',
    );
    await subscription.cancel();
  } finally {
    sdk.dispose();
  }
}

DeviceCollector sensorBusyFactory(Object? data) =>
    SensorBusyCollector(data! as SendPort);

final class SensorBusyCollector implements DeviceCollector {
  final SendPort probe;
  SensorBusyCollector(this.probe);
  @override
  DeviceSnapshot read(EntityAddress entity, ReadContext context) {
    if (entity.kind == EntityKind.runtime)
      return RuntimeSnapshot(processBitness: 64);
    probe.send('entered');
    sleep(const Duration(milliseconds: 500));
    probe.send('returned');
    return RamSnapshot(physicalBytes: BigInt.from(16384));
  }

  @override
  void dispose() {
    probe.send('disposed');
  }
}

Future<void> busyWorkerDoesNotBlockSensorDeadlines() async {
  final probe = ReceivePort();
  final entered = Completer<void>(),
      returned = Completer<void>(),
      disposed = Completer<void>();
  final messages = probe.listen((Object? value) {
    if (value == 'entered') entered.complete();
    if (value == 'returned') returned.complete();
    if (value == 'disposed') disposed.complete();
  });
  final sdk = DeviceAccess.isolated(
    sensorBusyFactory,
    initialData: probe.sendPort,
  );
  final target = sdk.observers.target(Entities.stepDetected, 'busy-normalizer');
  final sessions = <SensorObserverSession<StepDetectedSnapshot>>[];
  sdk.observers.sensorSource(
    target,
    SensorObserverSource<StepDetectedSnapshot>(
      subscribe: (session) {
        sessions.add(session);
        session.publish(StepDetectedSnapshot(value: true));
        return null;
      },
    ),
  );
  Timer? heartbeat;
  try {
    await sdk.get(Entities.runtime);
    final native = errorOf(sdk.get(Entities.ram));
    await entered.future;
    var ticks = 0;
    heartbeat = Timer.periodic(const Duration(milliseconds: 10), (_) {
      ticks++;
    });
    final bounded = sdk.withReadTimeout(const Duration(milliseconds: 100));
    final failures = await Future.wait([
      errorOf(bounded.get(target)),
      errorOf(bounded.watch(target).first),
      errorOf(bounded.describe(target)),
    ]);
    check(
      failures.every(
        (error) =>
            error is DeviceReadoutException &&
            error.code == ErrorCode.readTimeout,
      ),
      'Sensor get, event normalization and metadata must each retain an independent deadline.',
    );
    check(
      ticks >= 3 &&
          !returned.isCompleted &&
          sessions.every((session) => session.cancellation.isCancelled),
      'A busy collector must not block the host heartbeat, sensor callbacks or deadline cleanup.',
    );
    sdk.dispose();
    check(
      await native is DeviceReadoutCancelled,
      'Closing the context must not join the native call.',
    );
    await disposed.future.timeout(const Duration(seconds: 2));
    check(
      returned.isCompleted,
      'Worker-owned cleanup follows the native return.',
    );
  } finally {
    heartbeat?.cancel();
    sdk.dispose();
    await messages.cancel();
    probe.close();
  }
}

Future<void> activityInvalidatesPausedDelivery() async {
  final probe = ReceivePort();
  final entered = Completer<void>();
  final messages = probe.listen((Object? value) {
    if (value == 'entered') entered.complete();
  });
  final sdk = DeviceAccess.isolated(
    sensorBusyFactory,
    initialData: probe.sendPort,
  );
  final target = sdk.observers.target(Entities.pressure, 'paused-lifecycle');
  final sessions = <SensorObserverSession<PressureSnapshot>>[];
  sdk.observers.sensorSource(
    target,
    SensorObserverSource<PressureSnapshot>(
      subscribe: (session) {
        sessions.add(session);
        return null;
      },
    ),
  );
  final values = <double?>[];
  final subscription = sdk.watch(target).listen((sample) {
    values.add(sample.value);
  });
  try {
    await sdk.get(Entities.runtime);
    final native = sdk.get(Entities.ram);
    await entered.future;
    sessions.single.publish(PressureSnapshot(value: 100000));
    // Let sensor normalization enter the serial worker queue while the native
    // fixture is still blocked, then pause before that normalization completes.
    await Future<void>.delayed(Duration.zero);
    subscription.pause();
    await native;
    await sdk.describe(target);
    sdk.observers.sensorActivity(false);
    subscription.resume();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    check(
      values.isEmpty,
      'Inactivity must invalidate a normalized sample held for a paused subscriber.',
    );
    sdk.observers.sensorActivity(true);
    sessions.last.publish(PressureSnapshot(value: 101325));
    await until(() => values.isNotEmpty);
    check(
      values.length == 1 && values.single == 101325,
      'The resumed watch must deliver only the new active session.',
    );
  } finally {
    await subscription.cancel();
    sdk.dispose();
    await messages.cancel();
    probe.close();
  }
}

final checks = <String, Future<void> Function()>{
  'inactivity invalidates samples normalized while a subscriber is paused':
      activityInvalidatesPausedDelivery,
  'sensor samples retain duplicates and paused delivery fails at a bounded queue':
      duplicateSamplesAndBoundedPause,
  'blocked native work preserves sensor get/watch/description deadlines and host heartbeat':
      busyWorkerDoesNotBlockSensorDeadlines,
  'reentrant activity changes preserve the latest state for every sensor watch':
      reentrantActivityKeepsLatestState,
  'sensor metadata is separate from sampling and normalized in the worker':
      metadataDoesNotStartSampling,
  'delayed sensor registration and cleanup failures cannot escape the host':
      delayedRegistrationAndFailureCleanup,
  'inactive sensor failures remain terminal across immediate recovery':
      inactiveFailureIsTerminal,
  'event sensors have no idle watch timeout and reject fabricated events':
      eventSensorsWaitAndRejectFabricatedEvents,
  'sensor activity releases subscriptions and resumes fresh per-operation sessions':
      activityReleasesAndResumes,
  'sensor sources start on demand with per-operation sampling and cleanup':
      sourceDemandAndSampling,
};
