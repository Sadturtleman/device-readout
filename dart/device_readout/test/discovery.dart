import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:device_readout/device_readout.dart';

import 'observers.dart' show check, errorOf;

DeviceCollector discoveryCollector(Object? data) =>
    _DiscoveryCollector(data as SendPort);

final class _DiscoveryCollector
    implements DeviceCollector, DeviceDiscoveryCollector {
  final SendPort probe;
  final commands = ReceivePort();
  List<String> inventory = ['primary', 'external'];
  String? selected = 'external';
  bool blocked = false;
  _DiscoveryCollector(this.probe) {
    commands.listen((Object? raw) {
      final message = raw as List<Object?>;
      switch (message[0]) {
        case 'inventory':
          inventory = List<String>.from(message[1] as List);
        case 'current':
          selected = message[1] as String?;
        case 'blocked':
          blocked = message[1] as bool;
      }
      (message[2] as SendPort).send(true);
    });
    probe.send(['created', commands.sendPort, Isolate.current.debugName]);
  }
  @override
  List<String> list(EntityKind kind, ReadContext context) {
    waitIfBlocked();
    return inventory;
  }

  @override
  String? current(EntityKind kind, ReadContext context) {
    waitIfBlocked();
    return selected;
  }

  void waitIfBlocked() {
    if (!blocked) return;
    probe.send(['entered']);
    sleep(const Duration(milliseconds: 350));
    probe.send(['returned']);
  }

  @override
  DeviceSnapshot read(EntityAddress entity, ReadContext context) {
    if (!inventory.contains(entity.targetId)) {
      throw const DeviceReadoutException(
        ErrorCode.entityRemoved,
        'Fixture target removed.',
      );
    }
    return StorageVolumeSnapshot(name: entity.targetId);
  }

  @override
  void dispose() {
    commands.close();
    probe.send(['disposed']);
  }
}

Future<void> configure(SendPort control, String command, Object? value) async {
  final reply = ReceivePort();
  try {
    control.send([command, value, reply.sendPort]);
    await reply.first.timeout(const Duration(seconds: 2));
  } finally {
    reply.close();
  }
}

Future<void> nativeDiscoveryHandles() async {
  final probe = ReceivePort();
  final control = Completer<SendPort>();
  String? workerName;
  final listener = probe.listen((Object? raw) {
    final event = raw as List<Object?>;
    if (event[0] == 'created') {
      workerName = event[2] as String?;
      control.complete(event[1] as SendPort);
    }
  });
  final sdk = DeviceAccess.isolated(
    discoveryCollector,
    initialData: probe.sendPort,
  );
  final configured = sdk.withPollInterval(const Duration(milliseconds: 15));
  final other = DeviceAccess.native();
  try {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    check(
      !control.isCompleted,
      'Creating access must not perform native discovery.',
    );
    final found = await configured.storageVolumes.list();
    check(
      found.length == 2 && workerName != Isolate.current.debugName,
      'Native inventory must be discovered on the collection isolate.',
    );
    check(
      identical(found.first, (await sdk.storageVolumes.list()).first),
      'Repeated inventories and configured views retain live handles.',
    );
    check(
      identical(found.last, await sdk.storageVolumes.current()),
      'Current selection uses the platform-selected target, not the first entry.',
    );
    check(
      (await sdk.get(found.last)).name == 'external',
      'Typed handles must resolve back to their native collector identity.',
    );
    final updates = await configured.watch(found.first).take(2).toList();
    check(
      updates.every((value) => value.name == 'primary'),
      'Selected targets must work through the common watch fallback.',
    );
    final foreign = await errorOf(other.get(found.first));
    check(
      foreign is DeviceReadoutException &&
          foreign.code == ErrorCode.invalidConfiguration,
      'Native handles cannot be used by another context.',
    );
    await configure(await control.future, 'inventory', <String>[]);
    check(
      (await sdk.storageVolumes.list()).isEmpty,
      'A successful empty inventory is empty.',
    );
    final removed = await errorOf(sdk.get(found.first));
    check(
      removed is DeviceReadoutException &&
          removed.code == ErrorCode.entityRemoved,
      'Observed absence permanently retires the old native handle.',
    );
    await configure(await control.future, 'inventory', ['primary']);
    final replacement = (await sdk.storageVolumes.list()).single;
    check(
      !identical(found.first, replacement) &&
          (await sdk.get(replacement)).name == 'primary',
      'A reappearing native identity gets a fresh usable handle.',
    );
    await configure(await control.future, 'current', null);
    check(
      await sdk.storageVolumes.current() == null,
      'No selected native target must remain null even with a nonempty inventory.',
    );
  } finally {
    sdk.dispose();
    other.dispose();
    await listener.cancel();
    probe.close();
  }
}

Future<void> nativeRemovalInvalidatesWatch() async {
  final probe = ReceivePort();
  final control = probe.first.then(
    (event) => (event as List<Object?>)[1] as SendPort,
  );
  final sdk = DeviceAccess.isolated(
    discoveryCollector,
    initialData: probe.sendPort,
  ).withPollInterval(const Duration(minutes: 1));
  StreamSubscription<StorageVolumeSnapshot>? subscription;
  try {
    final target = (await sdk.storageVolumes.list()).first;
    await configure(await control, 'inventory', ['primary', 'primary']);
    final malformed = await errorOf(sdk.storageVolumes.list());
    check(
      malformed is DeviceReadoutException &&
          malformed.code == ErrorCode.readFailed &&
          (await sdk.get(target)).name == 'primary',
      'A malformed inventory must fail atomically without retiring existing handles.',
    );
    final first = Completer<void>(), failed = Completer<Object>();
    subscription = sdk
        .watch(target)
        .listen(
          (_) => first.complete(),
          onError: (Object error) => failed.complete(error),
        );
    await first.future.timeout(const Duration(seconds: 2));
    await configure(await control, 'inventory', <String>[]);
    final removed = await errorOf(sdk.get(target));
    check(
      removed is DeviceReadoutException &&
          removed.code == ErrorCode.entityRemoved,
      'A native removal error must retire its selected handle.',
    );
    final watchFailure = await failed.future.timeout(
      const Duration(milliseconds: 200),
    );
    check(
      watchFailure is DeviceReadoutException &&
          watchFailure.code == ErrorCode.entityRemoved,
      'Another operation observing removal must end the existing watch without waiting for its next poll.',
    );
    await configure(await control, 'inventory', ['primary']);
    final replacement = (await sdk.storageVolumes.list()).single;
    check(
      !identical(target, replacement),
      'A native removal error requires a fresh generation on rediscovery.',
    );
  } finally {
    await subscription?.cancel();
    sdk.dispose();
    probe.close();
  }
}

Future<void> nativeDiscoveryDeadline() async {
  for (final current in [false, true]) {
    final probe = ReceivePort();
    final control = Completer<SendPort>();
    final entered = Completer<void>(),
        returned = Completer<void>(),
        disposed = Completer<void>();
    final listener = probe.listen((Object? raw) {
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
      discoveryCollector,
      initialData: probe.sendPort,
    );
    var ticks = 0;
    final timer = Timer.periodic(
      const Duration(milliseconds: 10),
      (_) => ticks++,
    );
    try {
      await sdk.storageVolumes.list();
      await configure(await control.future, 'blocked', true);
      final timed = sdk.withReadTimeout(const Duration(milliseconds: 80));
      final result = errorOf(
        current ? timed.storageVolumes.current() : timed.storageVolumes.list(),
      );
      await entered.future.timeout(const Duration(seconds: 2));
      final ticksAtEntry = ticks;
      final error = await result.timeout(const Duration(milliseconds: 200));
      check(
        error is DeviceReadoutException &&
            error.code == ErrorCode.readTimeout &&
            ticks - ticksAtEntry >= 3 &&
            !returned.isCompleted,
        'List/current deadlines and host callbacks must not wait for blocked native discovery.',
      );
      sdk.dispose();
      check(
        !returned.isCompleted,
        'Context disposal cannot join a blocked inventory read.',
      );
      await disposed.future.timeout(const Duration(seconds: 2));
      check(
        returned.isCompleted,
        'Discovery resources stay owned until native work returns.',
      );
    } finally {
      timer.cancel();
      sdk.dispose();
      await listener.cancel();
      probe.close();
    }
  }
}

Future<void> observerRemovalRetiresNativeGeneration() async {
  final probe = ReceivePort();
  final listener = probe.listen((_) {});
  final sdk = DeviceAccess.isolated(
    discoveryCollector,
    initialData: probe.sendPort,
  );
  try {
    final old = (await sdk.storageVolumes.list()).first;
    sdk.observers.remove(old);
    final fresh = (await sdk.storageVolumes.list()).first;
    check(
      !identical(old, fresh) && (await sdk.get(fresh)).name == 'primary',
      'An app-observed removal must retire the native generation before rediscovery.',
    );
    sdk.observers.current(Entities.storageVolume, fresh);
    check(
      (await sdk.storageVolumes.list()).length == 2 &&
          identical(await sdk.storageVolumes.current(), fresh),
      'An app-selected native target must not erase its native inventory.',
    );
    sdk.observers.current(Entities.storageVolume, null);
    check(
      (await sdk.storageVolumes.list()).length == 2 &&
          await sdk.storageVolumes.current() == null,
      'Clearing an app selection does not fabricate an empty native collection.',
    );
    final observed = sdk.observers.target(Entities.storageVolume, 'app-volume');
    sdk.observers.publish(observed, StorageVolumeSnapshot(name: 'app-owned'));
    sdk.observers.current(Entities.storageVolume, observed);
    check(
      identical((await sdk.storageVolumes.list()).single, observed) &&
          identical(await sdk.storageVolumes.current(), observed),
      'App-owned inventories must not merge in native targets or overwrite app selection.',
    );
  } finally {
    sdk.dispose();
    await listener.cancel();
    probe.close();
  }
}

Future<void> discoveryInvalidationAndCancellation() async {
  for (final current in [false, true]) {
    for (final policy in [false, true]) {
      final probe = ReceivePort();
      final control = Completer<SendPort>();
      final entered = Completer<void>(), returned = Completer<void>();
      final listener = probe.listen((Object? raw) {
        final event = raw as List<Object?>;
        switch (event[0]) {
          case 'created':
            control.complete(event[1] as SendPort);
          case 'entered':
            entered.complete();
          case 'returned':
            returned.complete();
        }
      });
      final sdk = DeviceAccess.isolated(
        discoveryCollector,
        initialData: probe.sendPort,
      );
      try {
        final old = (await sdk.storageVolumes.list()).first;
        await configure(await control.future, 'blocked', true);
        final cancellation = CancellationToken();
        final pending = errorOf(
          current
              ? sdk.storageVolumes.current(cancellation: cancellation)
              : sdk.storageVolumes.list(cancellation: cancellation),
        );
        await entered.future.timeout(const Duration(seconds: 2));
        if (policy) {
          sdk.observers.failure(
            Entities.storageVolume,
            const DeviceReadoutException(
              ErrorCode.permissionDenied,
              'Policy revoked.',
            ),
          );
          sdk.observers.failure(Entities.storageVolume, null);
        } else {
          cancellation.cancel();
        }
        final error = await pending.timeout(const Duration(milliseconds: 150));
        check(
          !returned.isCompleted &&
              (policy
                  ? error is DeviceReadoutException &&
                        error.code == ErrorCode.permissionDenied
                  : error is DeviceReadoutCancelled),
          'Pending discovery must reject cancellation or policy failure immediately, even after immediate recovery.',
        );
        await returned.future.timeout(const Duration(seconds: 2));
        await configure(await control.future, 'blocked', false);
        check(
          identical(old, (await sdk.storageVolumes.list()).first),
          'A canceled or invalidated late inventory cannot retire healthy target generations.',
        );
      } finally {
        sdk.dispose();
        await listener.cancel();
        probe.close();
      }
    }
  }
}

Future<void> observerNamesCannotAliasNativeHandles() async {
  final probe = ReceivePort();
  final listener = probe.listen((_) {});
  final sdk = DeviceAccess.isolated(
    discoveryCollector,
    initialData: probe.sendPort,
  );
  try {
    final native = (await sdk.storageVolumes.list()).first;
    for (final name in ['native:1', 'primary']) {
      final app = sdk.observers.target(Entities.storageVolume, name);
      sdk.observers.publish(app, StorageVolumeSnapshot(name: 'app:$name'));
      check(
        (await sdk.get(app)).name == 'app:$name' &&
            (await sdk.get(native)).name == 'primary',
        'Nonempty app identities must stay independent of native adapter and handle identities.',
      );
      sdk.observers.failure(
        app,
        const DeviceReadoutException(
          ErrorCode.permissionDenied,
          'App target denied.',
        ),
      );
      check(
        (await sdk.get(native)).name == 'primary',
        'A failure for an app target cannot affect a same-named native target.',
      );
    }
  } finally {
    sdk.dispose();
    await listener.cancel();
    probe.close();
  }
}

final checks = <String, Future<void> Function()>{
  'native discovery returns typed scoped handles and retires observed removals':
      nativeDiscoveryHandles,
  'native removal ends existing watches and malformed inventories preserve live handles':
      nativeRemovalInvalidatesWatch,
  'native list and current preserve host deadlines and nonjoining cleanup':
      nativeDiscoveryDeadline,
  'observer removal retires native generations and app inventories retain ownership':
      observerRemovalRetiresNativeGeneration,
  'pending discovery rejects cancellation and transient policy failure without stale mutation':
      discoveryInvalidationAndCancellation,
  'observer names and failures cannot alias native target identities':
      observerNamesCannotAliasNativeHandles,
};
