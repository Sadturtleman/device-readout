import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:device_readout/device_readout.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

int get workersCreated =>
    (globalContext.getProperty<JSNumber>('workersCreated'.toJS)).toDartInt;
int get workersClosed =>
    (globalContext.getProperty<JSNumber>('workersClosed'.toJS)).toDartInt;
int get heldOperations =>
    globalContext.getProperty<JSNumber>('heldOperations'.toJS).toDartInt;
int get releasedOperations =>
    globalContext.getProperty<JSNumber>('releasedOperations'.toJS).toDartInt;

Future<Object?> outcome(Future<Object?> future) async {
  try {
    return await future;
  } catch (error) {
    return error;
  }
}

Future<void> until(bool Function() ready) async {
  final clock = Stopwatch()..start();
  while (!ready()) {
    if (clock.elapsed > const Duration(seconds: 2))
      throw StateError('Worker fixture did not reach its boundary.');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Future<void> typedBrowserRead() async {
  final created = workersCreated, closed = workersClosed;
  final sdk = DeviceAccess.web(
    workerUri: Uri.base.resolve('/packages/web/dist/dart-worker.js'),
  );
  try {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    check(workersCreated == created, 'Constructing web access must be inert.');
    final before = DateTime.now().toUtc();
    final CpuSnapshot cpu = await sdk.get(Entities.cpu);
    final expected = globalContext
        .getProperty<JSNumber>('expectedCpuCount'.toJS)
        .toDartInt;
    check(
      cpu.availableLogicalProcessorCount == expected &&
          cpu.physicalCoreCount == null,
      'Worker CPU facts must reach the typed snapshot without invented fields.',
    );
    check(
      !cpu.collectedAt.isBefore(before) && cpu.collectedAt.isUtc,
      'The worker supplies its completion timestamp.',
    );
    final LocaleSnapshot locale = await sdk.get(Entities.locale);
    check(
      locale.currentLanguageTag?.isNotEmpty == true,
      'The browser worker supplies a language tag.',
    );
    check(
      workersCreated == created + 1,
      'Reads share one lazily created worker.',
    );
  } finally {
    sdk.dispose();
  }
  check(
    workersClosed == closed + 1,
    'Disposal terminates the owned worker once.',
  );
}

Future<void> main() async {
  final checks = <String>[];
  try {
    await typedBrowserRead().timeout(const Duration(seconds: 10));
    checks.add('lazy typed browser reads and owned worker cleanup');
    await browserWatch().timeout(const Duration(seconds: 10));
    checks.add('cold native state watch, equal polls and immutable cadence');
    await browserObservers().timeout(const Duration(seconds: 10));
    checks.add('observed state, sensors and metadata normalize in the worker');
    await workerDeadlines().timeout(const Duration(seconds: 10));
    checks.add(
      'held workers retain host heartbeat, deadlines, cancellation and context disposal',
    );
    await workerFailures().timeout(const Duration(seconds: 10));
    checks.add(
      'worker loading and malformed replies fail without retries or host errors',
    );
    await deliveryDeadlines().timeout(const Duration(seconds: 10));
    checks.add('read deadlines include live response materialization');
    globalContext.setProperty(
      'deviceReadoutWebReport'.toJS,
      {'passed': true, 'checks': checks}.jsify(),
    );
  } catch (error, stack) {
    globalContext.setProperty(
      'deviceReadoutWebReport'.toJS,
      {
        'passed': false,
        'checks': checks,
        'error': '$error',
        'stack': '$stack',
      }.jsify(),
    );
  }
}

Future<void> workerDeadlines() async {
  for (final mode in ['timeout', 'cancel', 'close', 'watch']) {
    final sdk = DeviceAccess.web(
      workerUri: Uri.base.resolve('/held-worker.js'),
    );
    final cancellation = CancellationToken();
    Timer? heartbeat;
    try {
      await sdk.get(Entities.cpu);
      final exact = await sdk.get(Entities.originStorage);
      check(
        exact.quotaBytes == BigInt.parse('18446744073709551615') &&
            exact.usageBytes == BigInt.zero &&
            exact.persistent == false &&
            exact.usageByCategory?[StorageCategory.caches] == BigInt.zero,
        'Worker integer strings retain full precision, zero and false.',
      );
      final held = heldOperations, released = releasedOperations;
      var ticks = 0;
      heartbeat = Timer.periodic(const Duration(milliseconds: 10), (_) {
        ticks++;
      });
      final pending = outcome(
        mode == 'watch'
            ? sdk
                  .withReadTimeout(const Duration(milliseconds: 90))
                  .watch(Entities.cpu)
                  .toList()
            : sdk
                  .withReadTimeout(const Duration(milliseconds: 90))
                  .get(Entities.ram, cancellation: cancellation),
      );
      await until(() => heldOperations > held);
      if (mode == 'cancel') cancellation.cancel();
      if (mode == 'close') sdk.dispose();
      final failure = await pending;
      check(
        mode == 'cancel' || mode == 'close'
            ? failure is DeviceReadoutCancelled
            : failure is DeviceReadoutException &&
                  failure.code == ErrorCode.readTimeout,
        'Held $mode must retain its terminal outcome.',
      );
      check(
        releasedOperations == released,
        'The caller must finish before the held worker returns.',
      );
      if (mode == 'timeout' || mode == 'watch')
        check(ticks >= 2, 'Host timers advance during held work.');
      if (mode != 'close') {
        final queued = await outcome(
          sdk
              .withReadTimeout(const Duration(milliseconds: 30))
              .get(Entities.cpu),
        );
        check(
          queued is DeviceReadoutException &&
              queued.code == ErrorCode.readTimeout,
          'A request queued behind held work keeps its own deadline.',
        );
        await until(() => releasedOperations > released);
        check(
          globalContext
                  .getProperty<JSNumber>('latePayloadReads'.toJS)
                  .toDartInt ==
              0,
          'Retired response payloads must be discarded before Dart materialization.',
        );
        check(
          (await sdk.get(Entities.cpu)).availableLogicalProcessorCount == 2,
          'Late values are ignored and subsequent reads recover.',
        );
      }
    } finally {
      heartbeat?.cancel();
      sdk.dispose();
    }
  }
}

Future<void> deliveryDeadlines() async {
  for (final watch in [false, true]) {
    final sdk = DeviceAccess.web(
      workerUri: Uri.base.resolve('/slow-delivery-worker.js'),
    );
    try {
      await sdk.get(Entities.cpu);
      final before = globalContext
          .getProperty<JSNumber>('slowPayloadReads'.toJS)
          .toDartInt;
      final bounded = sdk.withReadTimeout(const Duration(milliseconds: 100));
      final failure = await outcome(
        watch
            ? bounded.watch(Entities.cpu).take(2).toList()
            : bounded.get(Entities.ram),
      );
      check(
        globalContext
                .getProperty<JSNumber>('slowPayloadReads'.toJS)
                .toDartInt ==
            before + 1,
        'The fixture must enter the live response boundary.',
      );
      check(
        failure is DeviceReadoutException &&
            failure.code == ErrorCode.readTimeout,
        'Response materialization that crosses the deadline cannot report success.',
      );
    } finally {
      sdk.dispose();
    }
  }
}

Future<void> workerFailures() async {
  for (final path in ['/missing-worker.js', '/malformed-worker.js']) {
    final count = workersCreated;
    final sdk = DeviceAccess.web(workerUri: Uri.base.resolve(path));
    try {
      final error = await outcome(sdk.get(Entities.cpu));
      check(
        error is DeviceReadoutException && error.code == ErrorCode.readFailed,
        'Loading and protocol failures stay typed.',
      );
      final next = await outcome(sdk.get(Entities.cpu));
      check(
        next is DeviceReadoutException &&
            next.code == ErrorCode.readFailed &&
            workersCreated == count + 1,
        'A failed worker context must not silently restart.',
      );
    } finally {
      sdk.dispose();
    }
  }
}

Future<void> browserObservers() async {
  final sdk = DeviceAccess.web(
    workerUri: Uri.base.resolve('/packages/web/dist/dart-worker.js'),
  );
  try {
    final display = sdk.observers.target(Entities.display, 'screen');
    sdk.observers.publish(
      display,
      DisplaySnapshot(
        label: 'observed',
        primary: false,
        brightness: double.nan,
        logicalBounds: const Rect(-10, 0, 1920, 1080),
        supportedModes: const [DisplayMode(refreshRateHz: double.infinity)],
      ),
    );
    sdk.observers.current(Entities.display, display);
    check(
      (await sdk.displays.list()).single == display &&
          await sdk.displays.current() == display,
      'App-owned discovery retains typed handle identity.',
    );
    final values = <DisplaySnapshot>[];
    final errors = <Object>[];
    final first = Completer<void>(), done = Completer<void>();
    final subscription = sdk
        .watch(display)
        .take(2)
        .listen(
          (value) {
            values.add(value);
            if (!first.isCompleted) first.complete();
          },
          onError: (Object error) {
            errors.add(error);
            if (!first.isCompleted) first.complete();
          },
          onDone: () {
            if (!done.isCompleted) done.complete();
          },
        );
    try {
      await first.future;
      if (errors.isNotEmpty) throw errors.first;
      sdk.observers.publish(
        display,
        DisplaySnapshot(label: 'replacement', primary: false),
      );
      await done.future;
      if (errors.isNotEmpty) throw errors.first;
      check(
        values.first.brightness == null &&
            values.first.primary == false &&
            values.first.logicalBounds?.x == -10 &&
            values.first.supportedModes?.single.refreshRateHz == null &&
            values.last.label == 'replacement',
        'Worker normalization preserves independent state, false and whole updates.',
      );
    } finally {
      await subscription.cancel();
    }
    final sensor = sdk.observers.target(
      Entities.relativeOrientation,
      'rotation',
    );
    sdk.observers.sensorSource(
      sensor,
      SensorObserverSource<RelativeOrientationSnapshot>(
        description: SensorDescription(
          kind: SensorKind.accelerometer,
          name: 'Rotation',
          maximumRange: double.infinity,
        ),
        subscribe: (session) {
          session.publish(
            RelativeOrientationSnapshot(value: const Quaternion(0, 0, 3, 4)),
          );
          session.publish(
            RelativeOrientationSnapshot(value: const Quaternion(0, 0, 3, 4)),
          );
          return null;
        },
      ),
    );
    final read = await sdk.get(sensor);
    final samples = await sdk.watch(sensor).take(2).toList();
    for (final value in [read, ...samples]) {
      check(
        (value.value!.z - 0.6).abs() <= 1e-15 &&
            (value.value!.w - 0.8).abs() <= 1e-15,
        'Sensor get/watch returns worker-normalized unit quaternions.',
      );
    }
    final description = await sdk.describe(sensor);
    check(
      description.kind == SensorKind.relativeOrientation &&
          description.name == 'Rotation' &&
          description.maximumRange == null,
      'Passive metadata is normalized with the requested sensor kind.',
    );
    sdk.observers.remove(display);
    Object? failure;
    try {
      await sdk.get(display);
    } catch (error) {
      failure = error;
    }
    check(
      failure is DeviceReadoutException &&
          failure.code == ErrorCode.entityRemoved,
      'Removed observer handles stay invalid.',
    );
  } finally {
    sdk.dispose();
  }
}

Future<void> browserWatch() async {
  final created = workersCreated;
  final sdk = DeviceAccess.web(
    workerUri: Uri.base.resolve('/packages/web/dist/dart-worker.js'),
  );
  try {
    final fast = sdk.withPollInterval(const Duration(milliseconds: 30));
    final stream = fast.watch(Entities.cpu);
    final slower = fast.withPollInterval(const Duration(seconds: 10));
    check(
      workersCreated == created &&
          sdk.pollInterval == const Duration(seconds: 1) &&
          slower.pollInterval == const Duration(seconds: 10),
      'Creating a watch/configuration stays inert.',
    );
    final clock = Stopwatch()..start();
    final values = await stream.take(3).toList();
    check(
      clock.elapsed >= const Duration(milliseconds: 50),
      'Polling retains the configured interval.',
    );
    check(
      values.length == 3 &&
          values.every(
            (value) =>
                value.availableLogicalProcessorCount ==
                values.first.availableLogicalProcessorCount,
          ),
      'Equal native state values are delivered on every poll.',
    );
    final support = await sdk.capabilities.get(Entities.cpu);
    check(
      support.readable == true && support.watchable == true,
      'Connected worker support is readable and watchable.',
    );
    check(
      (await sdk.get(Entities.cpu)).availableLogicalProcessorCount != null,
      'Ending one watch preserves later reads in its context.',
    );
  } finally {
    sdk.dispose();
  }
}
