import 'dart:async';

import 'package:device_readout/device_readout.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:device_readout_flutter/src/sensor_inventory.dart';

DeviceCollector _forbidden(Object? _) => throw StateError(
  'Observed sensors must not initialize a native state collector.',
);

final class _Transport implements SensorInventoryTransport {
  SensorInventoryRows rows = [(1, SensorDescription(name: 'first'))];
  Completer<void>? gate;
  Completer<void>? entered;
  DeviceReadoutException? failure;
  final removedCallbacks = <void Function()>[];
  int calls = 0, starts = 0, stops = 0;
  bool closed = false;

  @override
  Future<SensorInventoryRows> inventory(
    EntityKind kind,
    Duration timeout,
  ) async {
    if (kind != EntityKind.pressure) return [];
    calls++;
    final captured = List<(int, SensorDescription)>.from(rows);
    final wait = gate;
    gate = null;
    if (wait != null) {
      entered?.complete();
      await wait.future;
    }
    if (failure case final error?) throw error;
    return captured;
  }

  @override
  void Function() observe<S extends DeviceSnapshot>(
    int target,
    EntityKind kind,
    SensorObserverSession<S> session,
    void Function() removed,
  ) {
    starts++;
    removedCallbacks.add(removed);
    session.publish(PressureSnapshot(value: 100000 + target.toDouble()) as S);
    return () {
      stops++;
    };
  }

  @override
  void close() {
    closed = true;
  }
}

void main() {
  test(
    'terminal observation failure survives a late successful inventory',
    () async {
      final access = DeviceAccess.isolated(_forbidden);
      final transport = _Transport();
      final owner = SensorInventoryOwner(access, transport);
      const failed = DeviceReadoutException(
        ErrorCode.readFailed,
        'Observation ended.',
      );
      try {
        await owner.initialize();
        final gate = transport.gate = Completer<void>();
        final entered = transport.entered = Completer<void>();
        final refresh = owner.refresh(Entities.pressure);
        final result = expectLater(refresh, throwsA(same(failed)));
        await entered.future;
        owner.failed(failed);
        gate.complete();
        await result;
        await expectLater(
          access.list(Entities.pressure),
          throwsA(same(failed)),
        );
        await expectLater(
          owner.refresh(Entities.pressure),
          throwsA(same(failed)),
        );
        expect(transport.calls, 2);
      } finally {
        owner.dispose();
        access.dispose();
      }
    },
  );

  test(
    'native inventory events update metadata and retire only missing targets',
    () async {
      final access = DeviceAccess.isolated(_forbidden);
      final transport = _Transport();
      final owner = SensorInventoryOwner(access, transport);
      StreamSubscription<PressureSnapshot>? watch;
      try {
        await owner.initialize();
        final first = (await access.list(Entities.pressure)).single;
        final arrived = Completer<void>(), ended = Completer<void>();
        final errors = <Object>[];
        watch = access
            .watch(first)
            .listen(
              (_) {
                if (!arrived.isCompleted) arrived.complete();
              },
              onError: errors.add,
              onDone: ended.complete,
            );
        await arrived.future;
        transport.rows = [
          (1, SensorDescription(name: 'updated')),
          (2, SensorDescription(name: 'second')),
        ];
        await owner.changed(EntityKind.pressure);
        final targets = await access.list(Entities.pressure);
        expect(identical(targets.first, first), isTrue);
        expect((await access.describe(first)).name, 'updated');
        expect(transport.starts, 1);
        expect(transport.stops, 0);
        transport.rows = [transport.rows.last];
        await owner.changed(EntityKind.pressure);
        await ended.future;
        expect(
          errors.single,
          isA<DeviceReadoutException>().having(
            (e) => e.code,
            'code',
            ErrorCode.entityRemoved,
          ),
        );
        expect((await access.list(Entities.pressure)).single, targets.last);
        expect(transport.stops, 1);
      } finally {
        await watch?.cancel();
        owner.dispose();
        access.dispose();
      }
    },
  );

  test('an invalidation during refresh forces another native read', () async {
    final access = DeviceAccess.isolated(_forbidden);
    final transport = _Transport();
    final owner = SensorInventoryOwner(access, transport);
    try {
      await owner.initialize();
      final old = (await access.list(Entities.pressure)).single;
      final gate = transport.gate = Completer<void>();
      final entered = transport.entered = Completer<void>();
      final refresh = owner.refresh(Entities.pressure);
      await entered.future;
      transport.rows = [(2, SensorDescription(name: 'replacement'))];
      final event = owner.changed(EntityKind.pressure);
      gate.complete();
      await Future.wait<void>([refresh, event]);
      expect(transport.calls, 3);
      final current = (await access.list(Entities.pressure)).single;
      expect(identical(old, current), isFalse);
      expect((await access.describe(current)).name, 'replacement');
      expect((await access.capabilities.get(old)).readable, isFalse);
    } finally {
      owner.dispose();
      access.dispose();
    }
  });

  test('automatic refresh failure and recovery preserve app policy', () async {
    final access = DeviceAccess.isolated(_forbidden);
    final transport = _Transport();
    final owner = SensorInventoryOwner(access, transport);
    const nativeFailure = DeviceReadoutException(
      ErrorCode.readFailed,
      'Inventory unavailable.',
    );
    const appFailure = DeviceReadoutException(
      ErrorCode.permissionDenied,
      'App policy.',
    );
    try {
      await owner.initialize();
      final target = (await access.list(Entities.pressure)).single;
      transport.failure = nativeFailure;
      await owner.changed(EntityKind.pressure);
      await expectLater(
        access.list(Entities.pressure),
        throwsA(same(nativeFailure)),
      );
      access.observers.failure(Entities.pressure, appFailure);
      transport.failure = null;
      await owner.changed(EntityKind.pressure);
      await expectLater(access.get(target), throwsA(same(appFailure)));
      access.observers.failure(Entities.pressure, null);
      expect((await access.get(target)).value, 100001);
    } finally {
      owner.dispose();
      access.dispose();
    }
  });

  test(
    'disposed inventory owner discards late read results and notifications',
    () async {
      final access = DeviceAccess.isolated(_forbidden);
      final transport = _Transport();
      final owner = SensorInventoryOwner(access, transport);
      try {
        await owner.initialize();
        final gate = transport.gate = Completer<void>();
        final entered = transport.entered = Completer<void>();
        final refresh = owner.refresh(Entities.pressure);
        final outcome = expectLater(
          refresh,
          throwsA(isA<DeviceReadoutCancelled>()),
        );
        await entered.future;
        final event = owner.changed(EntityKind.pressure);
        owner.dispose();
        gate.complete();
        await outcome;
        await event;
        expect(transport.closed, isTrue);
        expect(transport.calls, 2);
        expect(await access.list(Entities.pressure), isEmpty);
      } finally {
        owner.dispose();
        access.dispose();
      }
    },
  );

  test('explicit target retirement gets a fresh binding and rejects old removal callbacks', () async {
    final access = DeviceAccess.isolated(_forbidden);
    final transport = _Transport();
    final owner = SensorInventoryOwner(access, transport);
    try {
      await owner.initialize();
      final old = (await access.list(Entities.pressure)).single;
      await access.get(old);
      final lateRemoval = transport.removedCallbacks.single;
      access.observers.remove(old);
      await owner.changed(EntityKind.pressure);
      final fresh = (await access.list(Entities.pressure)).single;
      expect(identical(old, fresh), isFalse);
      expect((await access.get(fresh)).value, 100001);
      lateRemoval();
      expect((await access.get(fresh)).value, 100001);
      expect((await access.capabilities.get(old)).readable, isFalse);
    } finally {
      owner.dispose();
      access.dispose();
    }
  });
}
