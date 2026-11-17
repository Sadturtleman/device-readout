import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:device_readout/device_readout.dart';

import 'discovery.dart' show configure;
import 'observers.dart' show check, errorOf, forbiddenNativeFactory;

DeviceCollector capabilityCollector(Object? data) =>
    _CapabilityCollector(data as SendPort);

final class _CapabilityCollector
    implements
        DeviceCollector,
        DeviceCapabilityCollector,
        DeviceDiscoveryCollector {
  final SendPort probe;
  final commands = ReceivePort();
  bool blocked = false;
  _CapabilityCollector(this.probe) {
    commands.listen((Object? raw) {
      final message = raw as List<Object?>;
      blocked = message[1] as bool;
      (message[2] as SendPort).send(true);
    });
    probe.send(['created', commands.sendPort, Isolate.current.debugName]);
  }
  @override
  EntityCapabilities capabilities(EntityAddress entity, ReadContext context) {
    probe.send(['capabilities', entity.kind, entity.targetId]);
    if (blocked) {
      probe.send(['entered']);
      sleep(const Duration(milliseconds: 350));
      probe.send(['returned']);
    }
    return switch (entity.kind) {
      EntityKind.ram => const EntityCapabilities(
        readable: true,
        watchable: true,
      ),
      EntityKind.storageVolume => EntityCapabilities(
        readable: entity.targetId == 'volume',
        watchable: null,
      ),
      _ => const EntityCapabilities(readable: false, watchable: false),
    };
  }

  @override
  List<String> list(EntityKind kind, ReadContext context) => ['volume'];
  @override
  String? current(EntityKind kind, ReadContext context) => null;
  @override
  DeviceSnapshot read(EntityAddress entity, ReadContext context) =>
      throw StateError('Capability queries must not read snapshots.');
  @override
  void dispose() {
    commands.close();
    probe.send(['disposed']);
  }
}

Future<void> nativeCapabilitiesArePassive() async {
  final probe = ReceivePort();
  final events = <List<Object?>>[];
  final listener = probe.listen((raw) => events.add(raw as List<Object?>));
  final sdk = DeviceAccess.isolated(
    capabilityCollector,
    initialData: probe.sendPort,
  );
  final other = DeviceAccess.native();
  try {
    final query = sdk.capabilities;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    check(events.isEmpty, 'Obtaining the capability helper is inert.');
    var requests = 0;
    sdk.observers.onPermissionRequest((_) {
      requests++;
    });
    sdk.observers.permission(Entities.ram, PermissionStatus.denied);
    sdk.observers.failure(
      Entities.ram,
      const DeviceReadoutException(
        ErrorCode.permissionDenied,
        'Denied by app.',
      ),
    );
    final ram = await query.get(Entities.ram);
    check(
      ram.readable == true && ram.watchable == true && requests == 0,
      'Support must not depend on permission or prompt for permission.',
    );
    check(
      events.first[2] != Isolate.current.debugName,
      'Native support probing must run in the collection isolate.',
    );
    final unsupported = await query.get(Entities.processMemory);
    check(
      unsupported.readable == false && unsupported.watchable == false,
      'An implemented negative support answer remains false.',
    );
    final target = (await sdk.storageVolumes.list()).single;
    final selected = await sdk
        .withPollInterval(const Duration(seconds: 2))
        .capabilities
        .get(target);
    check(
      selected.readable == true && selected.watchable == null,
      'Selected probes preserve native identity and unknown support.',
    );
    final foreign = await errorOf(other.capabilities.get(target));
    check(
      foreign is DeviceReadoutException &&
          foreign.code == ErrorCode.invalidConfiguration,
      'Capability queries reject foreign handles before native work.',
    );
    final before = events.length;
    sdk.observers.remove(target);
    final removed = await query.get(target);
    check(
      removed.readable == false &&
          removed.watchable == false &&
          events.length == before,
      'A retired handle reports unsupported without probing its replacement.',
    );
  } finally {
    sdk.dispose();
    other.dispose();
    await listener.cancel();
    probe.close();
  }
}

Future<void> observedCapabilitiesDoNotStartSources() async {
  final sdk = DeviceAccess.isolated(forbiddenNativeFactory);
  try {
    final absentSensor = await sdk.capabilities.get(Entities.accelerometer);
    check(
      absentSensor.readable == false && absentSensor.watchable == false,
      'A sensor kind requires an attached observation source, not a native support guess.',
    );
    sdk.observers.current(Entities.display, null);
    final empty = await sdk.capabilities.get(Entities.display);
    check(
      empty.readable == false,
      'An explicit empty app inventory is unavailable.',
    );
    final display = sdk.observers.target(Entities.display, 'screen');
    final waiting = await sdk.capabilities.get(display);
    check(
      waiting.readable == true && waiting.watchable == true,
      'An observed state target supports waiting for its first snapshot.',
    );
    final sensor = sdk.observers.target(Entities.accelerometer, 'sensor');
    final unbound = await sdk.capabilities.get(sensor);
    check(
      unbound.readable == false && unbound.watchable == false,
      'A sensor target without an observation source is not readable.',
    );
    var starts = 0;
    final detach = sdk.observers.sensorSource(
      sensor,
      SensorObserverSource<AccelerometerSnapshot>(
        subscribe: (_) {
          starts++;
          return null;
        },
      ),
    );
    sdk.observers.sensorActivity(false);
    sdk.observers.permission(sensor, PermissionStatus.denied);
    final ready = await sdk.capabilities.get(sensor);
    final collection = await sdk.capabilities.get(Entities.accelerometer);
    check(
      ready.readable == true &&
          ready.watchable == true &&
          collection.readable == true &&
          starts == 0,
      'Sensor support comes from registration, without activating or subscribing.',
    );
    detach();
    check(
      (await sdk.capabilities.get(sensor)).readable == false,
      'Detaching the source retires capability support.',
    );
  } finally {
    sdk.dispose();
  }
}

Future<void> capabilityDeadlinesDoNotBlockHost() async {
  for (final mode in ['timeout', 'cancel', 'dispose', 'remove']) {
    final probe = ReceivePort();
    final control = Completer<SendPort>(), entered = Completer<void>();
    final returned = Completer<void>(), disposed = Completer<void>();
    final listener = probe.listen((raw) {
      final event = raw as List<Object?>;
      switch (event[0]) {
        case 'created':
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
      capabilityCollector,
      initialData: probe.sendPort,
    );
    var ticks = 0;
    final heartbeat = Timer.periodic(const Duration(milliseconds: 5), (_) {
      ticks++;
    });
    try {
      final target = (await sdk.storageVolumes.list()).single;
      await configure(await control.future, 'blocked', true);
      final cancellation = CancellationToken();
      final configured = sdk.withReadTimeout(
        Duration(milliseconds: mode == 'timeout' ? 140 : 1500),
      );
      final result = configured.capabilities
          .get(target, cancellation: cancellation)
          .then<Object>((value) => value, onError: (Object error) => error);
      await entered.future;
      final startTicks = ticks;
      await Future<void>.delayed(const Duration(milliseconds: 70));
      if (mode == 'cancel') cancellation.cancel();
      if (mode == 'dispose') sdk.dispose();
      if (mode == 'remove') sdk.observers.remove(target);
      final outcome = await result.timeout(const Duration(milliseconds: 180));
      check(
        !returned.isCompleted,
        '$mode must finish before the blocking capability probe returns.',
      );
      check(
        ticks - startTicks >= 3,
        '$mode must preserve the host heartbeat during a blocking capability probe.',
      );
      if (mode == 'timeout') {
        check(
          outcome is DeviceReadoutException &&
              outcome.code == ErrorCode.readTimeout,
          'The configured capability deadline is typed.',
        );
      } else if (mode == 'remove') {
        check(
          outcome is EntityCapabilities &&
              outcome.readable == false &&
              outcome.watchable == false,
          'A target removed during probing cannot regain support from a late answer.',
        );
      } else {
        check(
          outcome is DeviceReadoutCancelled,
          'Caller and context cancellation remain cancellation.',
        );
      }
      sdk.dispose();
      check(
        !disposed.isCompleted,
        'Native cleanup waits off the host until its probe releases ownership.',
      );
      await returned.future.timeout(const Duration(seconds: 2));
      await disposed.future.timeout(const Duration(seconds: 2));
    } finally {
      heartbeat.cancel();
      sdk.dispose();
      await listener.cancel();
      probe.close();
    }
  }
}

DeviceCollector legacyCollector(Object? _) => _LegacyCollector();

final class _LegacyCollector implements DeviceCollector {
  @override
  DeviceSnapshot read(EntityAddress entity, ReadContext context) =>
      throw StateError(
        'Missing capability metadata must not trigger collection.',
      );
  @override
  void dispose() {}
}

Future<void> capabilityUnknownAndNativeDefaults() async {
  final legacy = DeviceAccess.isolated(legacyCollector);
  final native = DeviceAccess.native();
  try {
    final unknown = await legacy.capabilities.get(Entities.ram);
    check(
      unknown.readable == null && unknown.watchable == null,
      'An older collector without the optional support probe remains unknown.',
    );
    final runtime = await native.capabilities.get(Entities.runtime);
    final cpu = await native.capabilities.get(Entities.cpu);
    check(
      runtime.readable == true &&
          runtime.watchable == true &&
          cpu.readable == false &&
          cpu.watchable == false,
      'The standalone adapter distinguishes implemented Runtime from missing CPU support.',
    );
    final cancellation = CancellationToken()..cancel();
    check(
      await errorOf(
        native.capabilities.get(Entities.runtime, cancellation: cancellation),
      ) is DeviceReadoutCancelled,
      'Pre-cancelled probes do not execute.',
    );
    native.dispose();
    check(
      await errorOf(native.capabilities.get(Entities.runtime))
          is DeviceReadoutCancelled,
      'A closed context cannot serve even cached support.',
    );
  } finally {
    legacy.dispose();
    native.dispose();
  }
}

final checks = <String, Future<void> Function()>{
  'capabilities query native support without collecting or requesting permission':
      nativeCapabilitiesArePassive,
  'observed capabilities use registrations without starting sources':
      observedCapabilitiesDoNotStartSources,
  'blocked capability probes honor deadlines, cancellation and target retirement':
      capabilityDeadlinesDoNotBlockHost,
  'capabilities preserve unknown metadata and standalone adapter boundaries':
      capabilityUnknownAndNativeDefaults,
};
