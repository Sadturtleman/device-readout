import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:device_readout/device_readout.dart';

import 'observers.dart' show check;

DeviceCollector eventCollector(Object? data) =>
    _EventCollector(data as SendPort);

final class _EventCollector implements DeviceCollector, DeviceStateCollector {
  final SendPort probe;
  _EventCollector(this.probe) {
    probe.send(['constructed', Isolate.current.debugName]);
  }
  @override
  DeviceSnapshot read(EntityAddress entity, ReadContext context) =>
      RamSnapshot(availableBytes: BigInt.from(99));

  @override
  Stream<SnapshotRead>? watch(EntityAddress entity, StateWatchContext context) {
    probe.send([
      'watch',
      context.pollInterval.inMilliseconds,
      context.readTimeout.inMilliseconds,
      Isolate.current.debugName,
    ]);
    return Stream<SnapshotRead>.fromIterable([
      for (final amount in [7, 7, 9])
        () => RamSnapshot(availableBytes: BigInt.from(amount)),
    ]);
  }

  @override
  void dispose() => probe.send(['disposed', Isolate.current.debugName]);
}

Future<void> nativeStateStreamSettings() async {
  final probe = ReceivePort();
  final events = <List<Object?>>[];
  final disposed = Completer<void>();
  final listener = probe.listen((Object? message) {
    final event = message as List<Object?>;
    events.add(event);
    if (event[0] == 'disposed') disposed.complete();
  });
  final access = DeviceAccess.isolated(
    eventCollector,
    initialData: probe.sendPort,
  );
  final configured = access
      .withPollInterval(const Duration(milliseconds: 17))
      .withReadTimeout(const Duration(milliseconds: 700));
  final stream = configured.watch(Entities.ram);
  try {
    await Future<void>.delayed(const Duration(milliseconds: 30));
    check(
      events.isEmpty,
      'Constructing a native state watch must remain inert.',
    );
    final started = DateTime.now().toUtc();
    final values = await stream.toList().timeout(const Duration(seconds: 2));
    check(
      values.map((value) => value.availableBytes.toString()).join(',') ==
          '7,7,9',
      'The native stream must supply its initial state and duplicate updates.',
    );
    final watch = events.where((event) => event[0] == 'watch').single;
    check(
      watch[1] == 17 &&
          watch[2] == 700 &&
          watch[3] != Isolate.current.debugName,
      'Observation uses captured settings on the collection isolate.',
    );
    check(
      values.every(
        (value) =>
            value.collectedAt.isUtc && !value.collectedAt.isBefore(started),
      ),
      'Every native state update is normalized and stamped by the worker.',
    );
    check(
      (await access.get(Entities.ram)).availableBytes == BigInt.from(99),
      'A get remains a fresh read rather than replaying the last native event.',
    );
    access.dispose();
    await disposed.future.timeout(const Duration(seconds: 2));
    check(
      events.last[1] != Isolate.current.debugName,
      'Native disposal stays worker-owned.',
    );
  } finally {
    access.dispose();
    await listener.cancel();
    probe.close();
  }
}

DeviceCollector controlledCollector(Object? data) =>
    _ControlledCollector(data as SendPort);

final class _ControlledCollector
    implements DeviceCollector, DeviceStateCollector {
  final SendPort probe;
  _ControlledCollector(this.probe);
  @override
  DeviceSnapshot read(EntityAddress entity, ReadContext context) =>
      RamSnapshot(availableBytes: BigInt.from(99));

  @override
  Stream<SnapshotRead>? watch(EntityAddress entity, StateWatchContext context) {
    final commands = ReceivePort();
    late final StreamController<SnapshotRead> updates;
    updates = StreamController<SnapshotRead>(
      onListen: () {
        updates.add(() => RamSnapshot(availableBytes: BigInt.one));
        probe.send(['control', commands.sendPort]);
      },
      onCancel: () {
        commands.close();
        probe.send(['released']);
      },
    );
    commands.listen((Object? command) {
      if (command == 'block') {
        updates.add(() {
          probe.send(['entered']);
          sleep(const Duration(milliseconds: 350));
          probe.send(['returned']);
          return RamSnapshot(availableBytes: BigInt.two);
        });
      } else if (command is int) {
        for (var index = 0; index < command; index++) {
          final amount = index < 2 ? 2 : index + 1;
          final last = index == command - 1;
          updates.add(() {
            if (last) probe.send(['burstRead']);
            return RamSnapshot(availableBytes: BigInt.from(amount));
          });
        }
      }
    });
    return updates.stream;
  }

  @override
  void dispose() => probe.send(['disposed']);
}

Future<void> observedStateReplacesNativeStream() async {
  final probe = ReceivePort();
  final released = Completer<void>();
  final listener = probe.listen((Object? raw) {
    if ((raw as List<Object?>)[0] == 'released') released.complete();
  });
  final sdk = DeviceAccess.isolated(
    controlledCollector,
    initialData: probe.sendPort,
  );
  final first = Completer<void>(), replaced = Completer<void>();
  final failures = <Object>[];
  final values = <RamSnapshot>[];
  final stream = sdk
      .watch(Entities.ram)
      .listen(
        (value) {
          values.add(value);
          if (values.length == 1) first.complete();
          if (value.availableBytes == BigInt.from(42) && !replaced.isCompleted)
            replaced.complete();
        },
        onError: (Object error) {
          failures.add(error);
          if (!replaced.isCompleted) replaced.completeError(error);
        },
      );
  try {
    await first.future.timeout(const Duration(seconds: 2));
    sdk.observers.publish(
      Entities.ram,
      RamSnapshot(availableBytes: BigInt.from(42)),
    );
    await replaced.future.timeout(const Duration(seconds: 2));
    await released.future.timeout(const Duration(seconds: 2));
    check(
      failures.isEmpty && values.length == 2,
      'An app-owned state input must replace the native source without surfacing its cancellation.',
    );
  } finally {
    await stream.cancel();
    sdk.dispose();
    await listener.cancel();
    probe.close();
  }
}

Future<void> nativeEventReadDeadline() async {
  final probe = ReceivePort();
  final control = Completer<SendPort>();
  final entered = Completer<void>(),
      returned = Completer<void>(),
      disposed = Completer<void>();
  final listener = probe.listen((Object? raw) {
    final event = raw as List<Object?>;
    switch (event[0]) {
      case 'control':
        control.complete(event[1] as SendPort);
      case 'entered':
        entered.complete();
      case 'returned':
        returned.complete();
      case 'disposed':
        disposed.complete();
    }
  });
  final sdk = DeviceAccess.isolated(
    controlledCollector,
    initialData: probe.sendPort,
  );
  await sdk.get(Entities.ram);
  final first = Completer<void>(), failed = Completer<Object>();
  final subscription = sdk
      .withReadTimeout(const Duration(milliseconds: 80))
      .watch(Entities.ram)
      .listen(
        (_) {
          if (!first.isCompleted) first.complete();
        },
        onError: (Object error) {
          if (!failed.isCompleted) failed.complete(error);
        },
      );
  var ticks = 0;
  final heartbeat = Timer.periodic(const Duration(milliseconds: 10), (_) {
    ticks++;
  });
  try {
    await first.future.timeout(const Duration(seconds: 2));
    (await control.future).send('block');
    await entered.future.timeout(const Duration(seconds: 2));
    final error = await failed.future.timeout(
      const Duration(milliseconds: 200),
    );
    check(
      error is DeviceReadoutException &&
          error.code == ErrorCode.readTimeout &&
          ticks >= 3 &&
          !returned.isCompleted,
      'Each deferred native update must retain its deadline and the host heartbeat while its worker is blocked.',
    );
    sdk.dispose();
    check(
      !returned.isCompleted,
      'Context disposal cannot join a blocked event read.',
    );
    await disposed.future.timeout(const Duration(seconds: 2));
    check(
      returned.isCompleted,
      'Late source work must return before worker-owned resource disposal.',
    );
  } finally {
    heartbeat.cancel();
    await subscription.cancel();
    sdk.dispose();
    await listener.cancel();
    probe.close();
  }
}

DeviceCollector deadlineCollector(Object? _) => _DeadlineCollector();

final class _DeadlineCollector implements DeviceCollector {
  @override
  DeviceSnapshot read(EntityAddress entity, ReadContext context) => RamSnapshot(
    availableBytes: BigInt.from(context.readTimeout.inMicroseconds),
  );
  @override
  void dispose() {}
}

Future<void> collectorReadDeadline() async {
  final sdk = DeviceAccess.isolated(deadlineCollector)
      .withReadTimeout(const Duration(milliseconds: 700));
  try {
    final remaining = (await sdk.get(Entities.ram)).availableBytes!;
    check(
      remaining > BigInt.zero && remaining <= BigInt.from(700000),
      'Native bindings must receive the remaining caller read budget, not an independent default.',
    );
  } finally {
    sdk.dispose();
  }
}

Future<void> nativeStatePauseAndOverflow() async {
  final probe = ReceivePort();
  final control = Completer<SendPort>();
  final burstRead = Completer<void>(), released = Completer<void>();
  final listener = probe.listen((Object? raw) {
    final event = raw as List<Object?>;
    switch (event[0]) {
      case 'control':
        control.complete(event[1] as SendPort);
      case 'burstRead':
        if (!burstRead.isCompleted) burstRead.complete();
      case 'released':
        released.complete();
    }
  });
  final sdk = DeviceAccess.isolated(
    controlledCollector,
    initialData: probe.sendPort,
  );
  final values = <String>[];
  final first = Completer<void>(), resumed = Completer<void>();
  final failure = Completer<Object>();
  final subscription = sdk
      .watch(Entities.ram)
      .listen(
        (value) {
          values.add(value.availableBytes.toString());
          if (values.length == 1) first.complete();
          if (values.length == 4) resumed.complete();
        },
        onError: (Object error) {
          if (!failure.isCompleted) failure.complete(error);
        },
      );
  try {
    await first.future.timeout(const Duration(seconds: 2));
    subscription.pause();
    (await control.future).send(3);
    await burstRead.future.timeout(const Duration(seconds: 2));
    check(
      values.length == 1,
      'Paused consumers must not receive native updates.',
    );
    subscription.resume();
    await resumed.future.timeout(const Duration(seconds: 2));
    check(
      values.join(',') == '1,2,2,3',
      'Resuming preserves queued order and equal native values.',
    );
    subscription.pause();
    (await control.future).send(3000);
    await released.future.timeout(const Duration(seconds: 2));
    subscription.resume();
    final error = await failure.future.timeout(const Duration(seconds: 2));
    check(
      error is DeviceReadoutException && error.code == ErrorCode.readFailed,
      'Native source overload must release its source and surface a typed error.',
    );
    check(
      (await sdk.get(Entities.ram)).availableBytes == BigInt.from(99),
      'An overloaded subscription cannot poison the shared access context.',
    );
  } finally {
    await subscription.cancel();
    sdk.dispose();
    await listener.cancel();
    probe.close();
  }
}

DeviceCollector failingCleanupCollector(Object? data) =>
    _FailingCleanupCollector(data as SendPort);

final class _FailingCleanupCollector
    implements DeviceCollector, DeviceStateCollector {
  final SendPort probe;
  _FailingCleanupCollector(this.probe);
  @override
  DeviceSnapshot read(EntityAddress entity, ReadContext context) =>
      RamSnapshot(availableBytes: BigInt.from(99));

  @override
  Stream<SnapshotRead> watch(EntityAddress entity, StateWatchContext context) {
    context.cancellation.listen(
      () => throw StateError('Native cleanup failure.'),
    );
    context.cancellation.listen(() => probe.send('cancelled'));
    late final StreamController<SnapshotRead> updates;
    updates = StreamController<SnapshotRead>(
      onListen: () =>
          updates.add(() => RamSnapshot(availableBytes: BigInt.one)),
      onCancel: () => probe.send('released'),
    );
    return updates.stream;
  }

  @override
  void dispose() => probe.send('disposed');
}

Future<void> nativeCancellationFailureIsContained() async {
  final probe = ReceivePort();
  final cancelled = Completer<void>(), released = Completer<void>();
  final disposed = Completer<void>();
  final listener = probe.listen((Object? event) {
    switch (event) {
      case 'cancelled':
        cancelled.complete();
      case 'released':
        released.complete();
      case 'disposed':
        disposed.complete();
    }
  });
  final sdk = DeviceAccess.isolated(
    failingCleanupCollector,
    initialData: probe.sendPort,
  );
  final first = Completer<void>();
  final subscription = sdk.watch(Entities.ram).listen((_) => first.complete());
  try {
    await first.future.timeout(const Duration(seconds: 2));
    await subscription.cancel();
    await released.future.timeout(const Duration(seconds: 1));
    await cancelled.future.timeout(const Duration(seconds: 1));
    check(
      (await sdk.get(Entities.ram)).availableBytes == BigInt.from(99),
      'A failing adapter cancellation callback cannot kill the shared collector.',
    );
    sdk.dispose();
    await disposed.future.timeout(const Duration(seconds: 2));
  } finally {
    await subscription.cancel();
    sdk.dispose();
    await listener.cancel();
    probe.close();
  }
}

Future<void> completedReadSurvivesPause() async {
  final probe = ReceivePort();
  final listener = probe.listen((_) {});
  final sdk = DeviceAccess.isolated(
    eventCollector,
    initialData: probe.sendPort,
  );
  StreamSubscription<RamSnapshot>? subscription;
  try {
    await sdk.get(Entities.ram);
    final values = <RamSnapshot>[];
    final failures = <Object>[];
    final finished = Completer<void>();
    subscription = sdk
        .withReadTimeout(const Duration(milliseconds: 150))
        .watch(Entities.ram)
        .listen(
          values.add,
          onError: (Object error) => failures.add(error),
          onDone: finished.complete,
        );
    subscription.pause();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    subscription.resume();
    await finished.future.timeout(const Duration(seconds: 2));
    check(
      failures.isEmpty &&
          values.map((value) => value.availableBytes).join(',') == '7,7,9',
      'Completed native readings retain ordered duplicates beyond readTimeout while the consumer pauses delivery.',
    );
  } finally {
    await subscription?.cancel();
    sdk.dispose();
    await listener.cancel();
    probe.close();
  }
}

final checks = <String, Future<void> Function()>{
  'completed native readings do not expire during consumer pause':
      completedReadSurvivesPause,
  'native state streams are cold, worker-owned and preserve duplicate updates':
      nativeStateStreamSettings,
  'app-observed state replaces a native stream without leaking cancellation':
      observedStateReplacesNativeStream,
  'deferred native state reads retain deadlines and nonjoining cleanup':
      nativeEventReadDeadline,
  'native read contexts carry the remaining configured deadline':
      collectorReadDeadline,
  'paused native state streams retain ordered duplicates and contain overload':
      nativeStatePauseAndOverflow,
  'adapter cancellation failures preserve source release and subsequent reads':
      nativeCancellationFailureIsContained,
};
