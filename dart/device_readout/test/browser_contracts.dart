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
    await pausedPolling().timeout(const Duration(seconds: 10));
    checks.add('paused consumers do not accumulate native polling snapshots');
    await completedPausedRead().timeout(const Duration(seconds: 10));
    checks.add(
      'completed reads do not time out while their consumer is paused',
    );
    await independentDeliveries().timeout(const Duration(seconds: 10));
    checks.add(
      'native events and other watches remain independent of paused polling',
    );
    await pendingDeliveryTermination().timeout(const Duration(seconds: 10));
    checks.add('cancellation and closure release watches awaiting delivery');
    await nativeEventOverflow().timeout(const Duration(seconds: 10));
    checks.add(
      'native event overload fails only its watch and keeps the worker usable',
    );
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
    await largeResponse().timeout(const Duration(seconds: 15));
    checks.add(
      'large typed responses yield to host tasks without losing values',
    );
    await largeObservedInput().timeout(const Duration(seconds: 15));
    checks.add('large app snapshots yield before worker publication');
    await transferTermination().timeout(const Duration(seconds: 15));
    checks.add(
      'cancel, close and deadlines stop active transfers independently',
    );
    await largeWatch().timeout(const Duration(seconds: 15));
    checks.add(
      'large streams preserve order, duplicates and pause/resume through end',
    );
    await boundedTransferAdmission().timeout(const Duration(seconds: 10));
    checks.add(
      'read admission includes outbound preparation and typed delivery',
    );
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

Future<void> pausedPolling() async {
  final sdk = DeviceAccess.web(workerUri: Uri.base.resolve('/paced-worker.js'))
      .withPollInterval(const Duration(milliseconds: 5));
  int produced() =>
      globalContext.getProperty<JSNumber>('pacedSnapshots'.toJS).toDartInt;
  final baseline = produced();
  final values = <CpuSnapshot>[];
  final failures = <Object>[];
  final subscription = sdk
      .watch(Entities.cpu)
      .listen(values.add, onError: (Object error) => failures.add(error));
  subscription.pause();
  try {
    await until(() => produced() > baseline || failures.isNotEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    check(
      failures.isEmpty && values.isEmpty && produced() == baseline + 1,
      'A paused watch may retain its initial read but must not accumulate polling snapshots.',
    );
    subscription.resume();
    await until(() => values.length >= 3 || failures.isNotEmpty);
    check(
      failures.isEmpty &&
          values.length >= 3 &&
          values
              .take(3)
              .every(
                (value) =>
                    value.availableLogicalProcessorCount ==
                    values.first.availableLogicalProcessorCount,
              ),
      'Resuming preserves equal samples and starts subsequent polls.',
    );
    await subscription.cancel();
    final settled = produced();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    check(produced() <= settled + 1, 'Cancellation stops subsequent polling.');
    check(
      (await sdk.get(Entities.cpu)).availableLogicalProcessorCount != null,
      'A completed watch does not prevent later reads on the shared worker.',
    );
  } finally {
    await subscription.cancel();
    sdk.dispose();
  }
}

Future<void> completedPausedRead() async {
  final sdk = DeviceAccess.web(workerUri: Uri.base.resolve('/paced-worker.js'))
      .withReadTimeout(const Duration(milliseconds: 150));
  StreamSubscription<CpuSnapshot>? subscription;
  try {
    await sdk.get(Entities.cpu);
    final before = globalContext
        .getProperty<JSNumber>('pacedSnapshots'.toJS)
        .toDartInt;
    final values = <CpuSnapshot>[];
    final failures = <Object>[];
    subscription = sdk
        .watch(Entities.cpu)
        .listen(values.add, onError: (Object error) => failures.add(error));
    subscription.pause();
    await until(
      () =>
          globalContext.getProperty<JSNumber>('pacedSnapshots'.toJS).toDartInt >
          before,
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    subscription.resume();
    await until(() => values.isNotEmpty || failures.isNotEmpty);
    check(
      failures.isEmpty && values.length == 1,
      'A completed initial read must not become ReadTimeout solely because the consumer pauses delivery.',
    );
  } finally {
    await subscription?.cancel();
    sdk.dispose();
  }
}

Future<void> independentDeliveries() async {
  final sdk = DeviceAccess.web(workerUri: Uri.base.resolve('/paced-worker.js'))
      .withPollInterval(const Duration(milliseconds: 5));
  int produced() =>
      globalContext.getProperty<JSNumber>('pacedSnapshots'.toJS).toDartInt;
  final before = produced();
  final cpu = <CpuSnapshot>[];
  final failures = <Object>[];
  final subscription = sdk
      .watch(Entities.cpu)
      .listen(cpu.add, onError: (Object error) => failures.add(error));
  subscription.pause();
  try {
    await until(() => produced() > before);
    final locales = await sdk.watch(Entities.locale).take(3).toList();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    check(
      locales.length == 3 &&
          locales.every(
            (value) =>
                value.currentLanguageTag == locales.first.currentLanguageTag,
          ),
      'Native language events retain both equal updates while another watch is paused.',
    );
    check(
      failures.isEmpty && cpu.isEmpty && produced() == before + 4,
      'Delivery of another stream must not release the paused polling read.',
    );
    final other = await sdk.watch(Entities.cpu).take(3).toList();
    check(
      other.length == 3 && cpu.isEmpty,
      'Another polling subscription has an independent delivery lifetime.',
    );
    subscription.resume();
    await until(() => cpu.length >= 2 || failures.isNotEmpty);
    check(
      failures.isEmpty && cpu.length >= 2,
      'The paused subscription resumes independently.',
    );
  } finally {
    await subscription.cancel();
    sdk.dispose();
  }
}

Future<void> pendingDeliveryTermination() async {
  for (final close in [false, true]) {
    final sdk = DeviceAccess.web(
      workerUri: Uri.base.resolve('/paced-worker.js'),
    ).withPollInterval(const Duration(milliseconds: 5));
    int produced() =>
        globalContext.getProperty<JSNumber>('pacedSnapshots'.toJS).toDartInt;
    final before = produced();
    final failures = <Object>[];
    final values = <CpuSnapshot>[];
    final subscription = sdk
        .watch(Entities.cpu)
        .listen(values.add, onError: (Object error) => failures.add(error));
    subscription.pause();
    try {
      await until(() => produced() > before);
      if (close) sdk.dispose();
      await subscription.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      check(
        values.isEmpty && produced() == before + 1,
        'Ending a paused watch cannot release another poll or deliver retained state.',
      );
      if (!close) {
        final resumed = await sdk.watch(Entities.cpu).take(2).toList();
        check(
          resumed.length == 2,
          'Cancelling an undelivered read leaves the shared worker reusable.',
        );
      }
    } finally {
      await subscription.cancel();
      sdk.dispose();
    }
  }
}

Future<void> nativeEventOverflow() async {
  final sdk = DeviceAccess.web(
    workerUri: Uri.base.resolve('/paced-worker.js?burst'),
  );
  final before = globalContext
      .getProperty<JSNumber>('pacedErrors'.toJS)
      .toDartInt;
  final failures = <Object>[];
  final subscription = sdk
      .watch(Entities.locale)
      .listen((_) {}, onError: (Object error) => failures.add(error));
  subscription.pause();
  try {
    await until(
      () =>
          globalContext.getProperty<JSNumber>('pacedErrors'.toJS).toDartInt >
          before,
    );
    subscription.resume();
    await until(() => failures.isNotEmpty);
    check(
      failures.length == 1 &&
          failures.single is DeviceReadoutException &&
          (failures.single as DeviceReadoutException).code ==
              ErrorCode.readFailed,
      'An event source exceeding bounded delivery fails explicitly instead of dropping updates silently.',
    );
    check(
      (await sdk.get(Entities.cpu)).availableLogicalProcessorCount != null,
      'An overloaded watch cannot poison unrelated reads or its shared worker.',
    );
  } finally {
    await subscription.cancel();
    sdk.dispose();
  }
}

Future<void> boundedTransferAdmission() async {
  final sdk = DeviceAccess.web(
    workerUri: Uri.base.resolve('/packages/web/dist/dart-worker.js'),
  );
  try {
    final display = sdk.observers.target(Entities.display, 'bounded-input');
    sdk.observers.publish(
      display,
      DisplaySnapshot(
        supportedModes: List.filled(
          12000,
          const DisplayMode(refreshRateHz: 60),
        ),
      ),
    );
    final token = CancellationToken();
    final created = workersCreated;
    Timer.run(token.cancel);
    final outcomes = await Future.wait(
      List.generate(129, (_) => outcome(sdk.get(display, cancellation: token))),
    );
    check(
      outcomes.last is DeviceReadoutException &&
          (outcomes.last as DeviceReadoutException).code ==
              ErrorCode.readFailed,
      'Admission must reject excess reads before they marshal app snapshots.',
    );
    check(
      outcomes.take(128).every((value) => value is DeviceReadoutCancelled) &&
          workersCreated == created,
      'Cancelling admitted preparations releases them without starting a worker.',
    );
    check(
      (await sdk.get(Entities.cpu)).availableLogicalProcessorCount != null,
      'Cancelled transfer slots can be used by subsequent reads.',
    );
  } finally {
    sdk.dispose();
  }
}

Future<void> transferTermination() async {
  // Cancellation during outbound preparation never starts a collection worker.
  for (final close in [false, true]) {
    final sdk = DeviceAccess.web(
      workerUri: Uri.base.resolve('/packages/web/dist/dart-worker.js'),
    );
    try {
      final display = sdk.observers.target(Entities.display, 'large-cancel');
      sdk.observers.publish(
        display,
        DisplaySnapshot(
          supportedModes: List.filled(
            12000,
            const DisplayMode(refreshRateHz: 60),
          ),
        ),
      );
      final created = workersCreated;
      final token = CancellationToken();
      Timer.run(() => close ? sdk.dispose() : token.cancel());
      final failure = await outcome(sdk.get(display, cancellation: token));
      check(
        failure is DeviceReadoutCancelled && workersCreated == created,
        'Outbound cancellation/closure must finish before starting the worker.',
      );
    } finally {
      sdk.dispose();
    }
  }
  for (final mode in [
    'cancel',
    'close',
    'timeout',
    'watch-timeout',
    'watch-cancel',
  ]) {
    final sdk = DeviceAccess.web(
      workerUri: Uri.base.resolve('/large-worker.js'),
    );
    StreamSubscription<DisplaySnapshot>? subscription;
    try {
      final display = (await sdk.displays.list()).single;
      final starts = globalContext
          .getProperty<JSNumber>('largePayloadStarts'.toJS)
          .toDartInt;
      final ends = globalContext
          .getProperty<JSNumber>('largePayloadEnds'.toJS)
          .toDartInt;
      final token = CancellationToken();
      final stopped = Completer<Object?>();
      globalContext.setProperty(
        'largePayloadAction'.toJS,
        (() {
          if (mode == 'cancel') token.cancel();
          if (mode == 'close') sdk.dispose();
          if (mode == 'watch-cancel') {
            unawaited(
              subscription!.cancel().then(
                (_) => stopped.complete(const DeviceReadoutCancelled()),
              ),
            );
          }
        }).toJS,
      );
      final bounded = sdk.withReadTimeout(const Duration(milliseconds: 150));
      final future = mode == 'watch-cancel'
          ? stopped.future
          : mode == 'watch-timeout'
          ? outcome(bounded.watch(display).toList())
          : outcome(bounded.get(display, cancellation: token));
      if (mode == 'watch-cancel') {
        subscription = sdk
            .watch(display)
            .listen(
              (_) =>
                  stopped.complete('Unexpected snapshot after cancellation.'),
              onError: (Object error) {
                if (!stopped.isCompleted) stopped.complete(error);
              },
            );
      }
      final failure = await future;
      check(
        mode.endsWith('timeout')
            ? failure is DeviceReadoutException &&
                  failure.code == ErrorCode.readTimeout
            : failure is DeviceReadoutCancelled,
        'Active $mode preserves its original terminal outcome.',
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      check(
        globalContext
                    .getProperty<JSNumber>('largePayloadStarts'.toJS)
                    .toDartInt ==
                starts + 1 &&
            globalContext
                    .getProperty<JSNumber>('largePayloadEnds'.toJS)
                    .toDartInt ==
                ends,
        'Termination must stop traversal before the last array value.',
      );
      if (mode != 'close') {
        check(
          (await sdk.get(Entities.cpu)).availableLogicalProcessorCount == 2,
          'One cancelled or timed-out transfer does not fail its context.',
        );
      }
    } finally {
      globalContext.setProperty('largePayloadAction'.toJS, null);
      await subscription?.cancel();
      sdk.dispose();
    }
  }
}

Future<void> largeWatch() async {
  final sdk = DeviceAccess.web(workerUri: Uri.base.resolve('/large-worker.js'));
  StreamSubscription<DisplaySnapshot>? subscription;
  try {
    final display = (await sdk.displays.list()).single;
    final values = <DisplaySnapshot>[];
    final done = Completer<void>();
    subscription = sdk
        .watch(display)
        .listen(
          (value) {
            values.add(value);
            if (values.length == 1) {
              subscription!.pause();
              Timer(const Duration(milliseconds: 30), () {
                if (values.length != 1)
                  done.completeError(
                    StateError('A paused stream delivered another value.'),
                  );
                subscription!.resume();
              });
            }
          },
          onError: done.completeError,
          onDone: done.complete,
        );
    await done.future;
    check(
      values.length == 3 &&
          values[0].label == 'large' &&
          values[0].supportedModes?.length == 12000 &&
          values[1].label == 'small' &&
          values[2].label == 'small' &&
          values[1].supportedModes!.isEmpty &&
          values[2].supportedModes!.isEmpty,
      'Queued small updates and duplicates remain ordered behind a large update through normal end.',
    );
    check(
      globalContext.getProperty<JSBoolean>('largePayloadYielded'.toJS).toDart,
      'Large watch responses admit host tasks while materializing.',
    );
  } finally {
    await subscription?.cancel();
    sdk.dispose();
  }
}

Future<void> largeObservedInput() async {
  final sdk = DeviceAccess.web(
    workerUri: Uri.base.resolve('/packages/web/dist/dart-worker.js'),
  );
  try {
    final display = sdk.observers.target(Entities.display, 'large-screen');
    final source = DisplaySnapshot(
      primary: false,
      supportedModes: List.generate(
        12000,
        (i) => DisplayMode(
          pixelSize: const Size(1920, 1080),
          refreshRateHz: i == 0 ? double.nan : i.toDouble(),
        ),
      ),
    );
    sdk.observers.publish(display, source);
    globalContext.setProperty('outboundHostTurn'.toJS, false.toJS);
    Timer.run(
      () => globalContext.setProperty('outboundHostTurn'.toJS, true.toJS),
    );
    final value = await sdk.get(display);
    check(
      globalContext.getProperty<JSBoolean>('outboundYielded'.toJS).toDart,
      'Host tasks must run while a large observed snapshot is prepared for the worker.',
    );
    check(
      value.supportedModes?.length == 12000 &&
          value.supportedModes!.first.refreshRateHz == null &&
          value.supportedModes!.last.refreshRateHz == 11999 &&
          value.primary == false &&
          source.supportedModes!.first.refreshRateHz!.isNaN,
      'Worker normalization retains independent values and leaves app input unchanged.',
    );
  } finally {
    sdk.dispose();
  }
}

Future<void> largeResponse() async {
  final sdk = DeviceAccess.web(workerUri: Uri.base.resolve('/large-worker.js'));
  try {
    final display = (await sdk.displays.list()).single;
    final snapshot = await sdk.get(display);
    check(
      snapshot.supportedModes?.length == 12000 &&
          snapshot.supportedModes!.first.pixelSize?.width == 1920 &&
          snapshot.supportedModes!.last.refreshRateHz == 11999 &&
          snapshot.primary == false,
      'Large worker responses retain every mode, ordering and independent fields.',
    );
    check(
      globalContext.getProperty<JSBoolean>('largePayloadYielded'.toJS).toDart,
      'Host tasks must execute before the SDK finishes traversing a large response.',
    );
    var immutable = false;
    try {
      snapshot.supportedModes!.clear();
    } on UnsupportedError {
      immutable = true;
    }
    check(immutable, 'Delivered collections remain immutable.');
  } finally {
    sdk.dispose();
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
