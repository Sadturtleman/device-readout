import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:device_readout/device_readout.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

DeviceCollector forbiddenNativeFactory(Object? _) => throw StateError(
  'An app-observed read must not initialize a native collector.',
);

Future<Object?> errorOf(Future<Object?> future) async {
  try {
    await future;
    return null;
  } catch (error) {
    return error;
  }
}

Future<void> observedScreenRead() async {
  final sdk = DeviceAccess.isolated(forbiddenNativeFactory);
  final other = DeviceAccess.isolated(forbiddenNativeFactory);
  try {
    final display = sdk.observers.target(Entities.display, 'app-screen');
    sdk.observers.publish(
      display,
      DisplaySnapshot(
        label: 'Observed screen',
        pixelSize: const Size(1920, 1080),
        brightness: 0,
        logicalBounds: const Rect(0, 0, double.nan, 1080),
      ),
    );
    final start = DateTime.now().toUtc();
    final value = await sdk
        .withReadTimeout(const Duration(seconds: 2))
        .get(display);
    check(
      value.label == 'Observed screen' &&
          value.pixelSize?.width == 1920 &&
          value.brightness == 0 &&
          value.logicalBounds == null,
      'Observed values must reach the typed normalized snapshot without UI/native reads.',
    );
    check(
      !value.collectedAt.isBefore(start),
      'Observed reads get a new completion timestamp.',
    );
    sdk.observers.publish(display, DisplaySnapshot(primary: false));
    final replacement = await sdk.get(display);
    check(
      replacement.primary == false &&
          replacement.label == null &&
          replacement.pixelSize == null,
      'A publication replaces the full observed state.',
    );
    final crossContext = await errorOf(other.get(display));
    check(
      crossContext is DeviceReadoutException &&
          crossContext.code == ErrorCode.invalidConfiguration,
      'Observed handles must belong to their owning access context.',
    );
  } finally {
    sdk.dispose();
    other.dispose();
  }
}

Future<void> observedScreenEvents() async {
  final sdk = DeviceAccess.isolated(forbiddenNativeFactory)
      .withPollInterval(const Duration(seconds: 10));
  final display = sdk.observers.target(Entities.display, 'event-screen');
  sdk.observers.publish(display, DisplaySnapshot(label: 'initial'));
  final values = <DisplaySnapshot>[];
  final initial = Completer<void>(), updated = Completer<void>();
  final errors = <Object>[];
  final subscription = sdk
      .watch(display)
      .listen(
        (value) {
          values.add(value);
          if (values.length == 1) initial.complete();
          if (values.length == 4) updated.complete();
        },
        onError: (Object error) {
          errors.add(error);
        },
      );
  try {
    await initial.future.timeout(const Duration(seconds: 2));
    sdk.observers.publish(display, DisplaySnapshot(label: 'first'));
    sdk.observers.publish(display, DisplaySnapshot(label: 'second'));
    sdk.observers.publish(display, DisplaySnapshot(label: 'second'));
    await updated.future.timeout(const Duration(seconds: 2));
    check(
      values.map((v) => v.label).join(',') == 'initial,first,second,second',
      'Observer updates retain publication order, intermediate values and duplicates.',
    );
    check(errors.isEmpty, 'Observed events do not read native screen APIs.');
    await subscription.cancel();
    sdk.observers.publish(display, DisplaySnapshot(label: 'after-cancel'));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    check(values.length == 4, 'Cancelled observers deliver no later events.');
  } finally {
    await subscription.cancel();
    sdk.dispose();
  }
}

Future<void> firstObservedValueAndDeadline() async {
  final sdk = DeviceAccess.isolated(forbiddenNativeFactory);
  final target = sdk.observers.target(Entities.viewport, 'pending-window');
  try {
    final pending = sdk.get(target);
    final captured = errorOf(pending);
    await Future<void>.delayed(const Duration(milliseconds: 35));
    sdk.observers.publish(target, ViewportSnapshot(size: const Size(800, 600)));
    check(
      await captured == null && (await pending).size?.width == 800,
      'An observed target without a first value waits for its app observer.',
    );
    final missing = sdk.observers.target(Entities.viewport, 'missing-window');
    final timeout = await errorOf(
      sdk.withReadTimeout(const Duration(milliseconds: 45)).get(missing),
    );
    check(
      timeout is DeviceReadoutException &&
          timeout.code == ErrorCode.readTimeout,
      'Waiting for initial observed state is part of the read timeout.',
    );
    final token = CancellationToken();
    final cancelled = errorOf(sdk.get(missing, cancellation: token));
    token.cancel();
    check(
      await cancelled is DeviceReadoutCancelled,
      'Initial observed-state waits respond to caller cancellation.',
    );
    final closed = errorOf(sdk.get(missing));
    sdk.dispose();
    check(
      await closed is DeviceReadoutCancelled,
      'Context closure also cancels initial observed-state waits.',
    );
  } finally {
    sdk.dispose();
  }
}

DeviceCollector heldRamFactory(Object? data) => _HeldRam(data as SendPort);

final class _HeldRam implements DeviceCollector {
  final SendPort probe;
  _HeldRam(this.probe);
  @override
  DeviceSnapshot read(EntityAddress entity, ReadContext context) {
    if (entity.kind == EntityKind.runtime)
      return RuntimeSnapshot(processBitness: 64);
    probe.send('entered');
    sleep(const Duration(milliseconds: 350));
    return RamSnapshot(physicalBytes: BigInt.from(16384));
  }

  @override
  void dispose() {
    probe.send('disposed');
  }
}

Future<void> failuresInvalidatePendingAndCachedReads() async {
  final probe = ReceivePort();
  final entered = Completer<void>(), disposed = Completer<void>();
  final probeListener = probe.listen((Object? event) {
    if (event == 'entered') entered.complete();
    if (event == 'disposed') disposed.complete();
  });
  final sdk = DeviceAccess.isolated(
    heldRamFactory,
    initialData: probe.sendPort,
  );
  final screen = sdk.observers.target(Entities.display, 'failure-screen');
  sdk.observers.publish(screen, DisplaySnapshot(label: 'old'));
  final values = <DisplaySnapshot>[], errors = <Object>[];
  final first = Completer<void>(), ended = Completer<void>();
  final stream = sdk
      .withPollInterval(const Duration(seconds: 60))
      .watch(screen)
      .listen(
        (v) {
          values.add(v);
          if (!first.isCompleted) first.complete();
        },
        onError: (Object e) {
          errors.add(e);
        },
        onDone: ended.complete,
      );
  const failure = DeviceReadoutException(
    ErrorCode.permissionDenied,
    'The app observer reports the operation is blocked.',
  );
  try {
    await first.future.timeout(const Duration(seconds: 2));
    sdk.observers.failure(Entities.display, failure);
    await ended.future.timeout(const Duration(milliseconds: 200));
    final blocked = await errorOf(sdk.get(screen));
    check(
      errors.length == 1 && errors.single == failure && blocked == failure,
      'A collection failure must end streams immediately and gate new reads.',
    );
    sdk.observers.failure(Entities.display, null);
    final stale = await errorOf(
      sdk.withReadTimeout(const Duration(milliseconds: 35)).get(screen),
    );
    check(
      stale is DeviceReadoutException && stale.code == ErrorCode.readTimeout,
      'Clearing a failure must not restore invalidated cached state.',
    );
    sdk.observers.publish(screen, DisplaySnapshot(label: 'fresh'));
    check(
      (await sdk.get(screen)).label == 'fresh' && values.length == 1,
      'Fresh state enables new reads without restarting failed streams.',
    );
    await sdk.get(Entities.runtime);
    final pending = errorOf(sdk.get(Entities.ram));
    await entered.future.timeout(const Duration(seconds: 2));
    sdk.observers.failure(Entities.ram, failure);
    sdk.observers.failure(Entities.ram, null);
    check(
      await pending.timeout(const Duration(milliseconds: 100)) == failure,
      'A failure/recovery race must reject a native result already in flight.',
    );
    sdk.dispose();
    await disposed.future.timeout(const Duration(seconds: 2));
  } finally {
    sdk.dispose();
    await stream.cancel();
    await probeListener.cancel();
    probe.close();
  }
}

Future<void> observedDiscoveryAndRemoval() async {
  final sdk = DeviceAccess.isolated(forbiddenNativeFactory);
  StreamSubscription<DisplaySnapshot>? subscription;
  try {
    final left = sdk.observers.target(Entities.display, 'left');
    final right = sdk.observers.target(Entities.display, 'right');
    sdk.observers.publish(left, DisplaySnapshot(label: 'Left'));
    sdk.observers.publish(right, DisplaySnapshot(label: 'Right'));
    final displays = await sdk.displays.list();
    check(
      displays.length == 2 &&
          displays.contains(left) &&
          displays.contains(right),
      'Discovery returns typed, reusable context-owned handles.',
    );
    check(
      await sdk.displays.current() == null,
      'Current must not silently select the first target.',
    );
    sdk.observers.current(Entities.display, right);
    check(
      await sdk.displays.current() == right,
      'Current follows the app observer.',
    );
    final seen = Completer<void>(), ended = Completer<void>();
    final errors = <Object>[];
    subscription = sdk
        .watch(right)
        .listen(
          (_) {
            if (!seen.isCompleted) seen.complete();
          },
          onError: (Object e) {
            errors.add(e);
          },
          onDone: ended.complete,
        );
    await seen.future.timeout(const Duration(seconds: 2));
    sdk.observers.remove(right);
    await ended.future.timeout(const Duration(milliseconds: 200));
    sdk.observers.publish(right, DisplaySnapshot(label: 'late-callback'));
    final removed = await errorOf(sdk.get(right));
    check(
      removed is DeviceReadoutException &&
          removed.code == ErrorCode.entityRemoved &&
          errors.single is DeviceReadoutException &&
          (errors.single as DeviceReadoutException).code ==
              ErrorCode.entityRemoved,
      'Removal permanently retires the handle and terminates its watch.',
    );
    check(
      await sdk.displays.current() == null &&
          (await sdk.displays.list()).single == left,
      'A removed current target is absent, without selecting a replacement.',
    );
    sdk.observers.remove(left);
    check(
      (await sdk.displays.list()).isEmpty,
      'A known observed collection with no targets returns an empty list.',
    );
  } finally {
    await subscription?.cancel();
    sdk.dispose();
  }
}

Future<void> explicitPermissionRequestsUseObservedResponses() async {
  final sdk = DeviceAccess.isolated(forbiddenNativeFactory)
      .withReadTimeout(const Duration(milliseconds: 50));
  final screen = sdk.observers.target(Entities.display, 'permission-screen');
  sdk.observers.publish(
    screen,
    DisplaySnapshot(label: 'Allowed partial fields'),
  );
  final requested = Completer<void>();
  var requests = 0;
  PermissionRequest? appRequest;
  void Function()? detach;
  try {
    sdk.observers.permission(Entities.display, PermissionStatus.notDetermined);
    detach = sdk.observers.onPermissionRequest((request) {
      requests++;
      appRequest = request;
      if (!requested.isCompleted) requested.complete();
    });
    check(
      await sdk.permissions.check(screen) == PermissionStatus.notDetermined,
      'Kind-level permission state is inherited by targets.',
    );
    await sdk.withReadTimeout(const Duration(seconds: 2)).get(screen);
    await sdk.displays.list();
    await sdk.watch(screen).first;
    check(
      requests == 0,
      'get/watch/list/check never invoke a permission coordinator.',
    );
    var finished = false;
    final permission = sdk.permissions.request(screen).then((value) {
      finished = true;
      return value;
    });
    await requested.future.timeout(const Duration(seconds: 2));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    sdk.observers.publish(
      screen,
      DisplaySnapshot(label: 'unrelated screen update'),
    );
    check(
      !finished,
      'Permission response waits are outside readTimeout and ignore state publications.',
    );
    sdk.observers.permission(Entities.display, PermissionStatus.granted);
    check(
      await permission == PermissionStatus.granted &&
          requests == 1 &&
          appRequest?.kind == EntityKind.display &&
          appRequest?.targetId == 'permission-screen',
      'Only explicit requests call the app coordinator, then finish from observed permission state.',
    );
    check(
      appRequest!.cancellation.isCancelled,
      'The coordinator lifetime ends when the observed response completes.',
    );
    check(
      await sdk.permissions.request(screen) == PermissionStatus.granted &&
          requests == 1,
      'Already granted permission does not start another UI interaction.',
    );
  } finally {
    detach?.call();
    sdk.dispose();
  }
}

Future<void> permissionOverridesCancellationAndLateErrors() async {
  final sdk = DeviceAccess.isolated(forbiddenNativeFactory);
  final screen = sdk.observers.target(
    Entities.display,
    'overridden-permission',
  );
  sdk.observers.permission(Entities.display, PermissionStatus.granted);
  sdk.observers.permission(screen, null);
  var entered = Completer<void>();
  final lateFailure = Completer<void>();
  PermissionRequest? currentRequest;
  var calls = 0;
  final unregister = sdk.observers.onPermissionRequest((request) {
    currentRequest = request;
    entered.complete();
    calls++;
    if (calls == 1) return lateFailure.future;
  });
  try {
    check(
      await sdk.permissions.check(screen) == null,
      'Explicit null target permission overrides a kind-level granted value.',
    );
    var finished = false;
    final pending = sdk.permissions.request(screen).then((value) {
      finished = true;
      return value;
    });
    await entered.future;
    sdk.observers.permission(Entities.display, PermissionStatus.denied);
    await Future<void>.delayed(const Duration(milliseconds: 25));
    check(
      !finished,
      'A kind-level update must not complete an overridden target request.',
    );
    sdk.observers.permission(screen, PermissionStatus.denied);
    check(
      await pending == PermissionStatus.denied,
      'The matching target observation completes its request.',
    );
    lateFailure.completeError(
      StateError('Coordinator failed after observed completion'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    const blocked = DeviceReadoutException(
      ErrorCode.permissionDenied,
      'Observer reports blocked access',
    );
    sdk.observers.failure(screen, blocked);
    check(
      await sdk.permissions.check(screen) == PermissionStatus.denied,
      'Permission status remains readable during an observer failure.',
    );
    entered = Completer<void>();
    final token = CancellationToken();
    final cancelled = errorOf(
      sdk.permissions.request(screen, cancellation: token),
    );
    await entered.future;
    token.cancel();
    check(
      await cancelled is DeviceReadoutCancelled &&
          currentRequest!.cancellation.isCancelled,
      'Caller cancellation also ends the app coordinator lifetime.',
    );
    entered = Completer<void>();
    final closing = errorOf(sdk.permissions.request(screen));
    await entered.future;
    sdk.dispose();
    check(
      await closing is DeviceReadoutCancelled &&
          currentRequest!.cancellation.isCancelled,
      'Context closure cancels pending permission waits.',
    );
  } finally {
    unregister();
    sdk.dispose();
  }
}

Future<void> boundedObserverDelivery() async {
  final sdk = DeviceAccess.isolated(forbiddenNativeFactory);
  final target = sdk.observers.target(Entities.display, 'paused-screen');
  sdk.observers.publish(target, DisplaySnapshot(label: 'initial'));
  final first = Completer<void>(), done = Completer<void>();
  final values = <DisplaySnapshot>[], errors = <Object>[];
  final subscription = sdk
      .watch(target)
      .listen(
        (value) {
          values.add(value);
          if (!first.isCompleted) first.complete();
        },
        onError: (Object error) {
          errors.add(error);
        },
        onDone: done.complete,
      );
  try {
    await first.future;
    subscription.pause();
    for (var i = 0; i < 2049; i++) {
      sdk.observers.publish(target, DisplaySnapshot(label: '$i'));
    }
    subscription.resume();
    await done.future.timeout(const Duration(seconds: 2));
    check(
      values.length == 1 &&
          errors.length == 1 &&
          errors.single is DeviceReadoutException &&
          (errors.single as DeviceReadoutException).code ==
              ErrorCode.readFailed,
      'A stalled observer consumer fails at the bounded queue instead of silently dropping updates.',
    );
    check(
      (await sdk.get(target)).label == '2048',
      'A failed stream does not erase the latest app-observed state for new reads.',
    );
  } finally {
    await subscription.cancel();
    sdk.dispose();
  }
}

Future<void> permissionCoordinatorLifetimes() async {
  final sdk = DeviceAccess.isolated(forbiddenNativeFactory);
  var calls = 0;
  void coordinator(PermissionRequest request) {
    calls++;
    sdk.observers.permission(Entities.display, PermissionStatus.granted);
  }

  void Function()? unregister;
  try {
    final old = sdk.observers.onPermissionRequest(coordinator);
    Object? duplicate;
    try {
      sdk.observers.onPermissionRequest(coordinator);
    } catch (error) {
      duplicate = error;
    }
    check(
      duplicate is DeviceReadoutException &&
          duplicate.code == ErrorCode.invalidConfiguration,
      'Two app permission coordinators must not race for the same context.',
    );
    old();
    unregister = sdk.observers.onPermissionRequest(coordinator);
    old(); // A stale teardown must not detach a replacement registration.
    check(
      await sdk.permissions.request(Entities.display) ==
              PermissionStatus.granted &&
          calls == 1,
      'Coordinator registrations have their own lifetime, even with the same callback.',
    );
    unregister();
    sdk.observers.permission(Entities.display, PermissionStatus.notDetermined);
    final missing = await errorOf(sdk.permissions.request(Entities.display));
    check(
      missing is DeviceReadoutException &&
          missing.code == ErrorCode.unsupportedEntity,
      'A request without an app coordinator fails without opening UI.',
    );
    unregister = sdk.observers.onPermissionRequest((_) async {
      await Future<void>.delayed(Duration.zero);
      throw StateError('Application coordination failed');
    });
    final failed = await errorOf(sdk.permissions.request(Entities.display));
    check(
      failed is DeviceReadoutException && failed.code == ErrorCode.readFailed,
      'An asynchronous app coordinator failure must become a typed SDK error.',
    );
  } finally {
    unregister?.call();
    sdk.dispose();
  }
}

final checks = <String, Future<void> Function()>{
  'observed screen reads normalize state without native or UI collection':
      observedScreenRead,
  'observed screen watches preserve event order and equal values without polling':
      observedScreenEvents,
  'first observed values obey caller deadlines, cancellation and closure':
      firstObservedValueAndDeadline,
  'observer failures invalidate caches, end streams and reject in-flight native results':
      failuresInvalidatePendingAndCachedReads,
  'observed discovery and current selection preserve permanently removed handles':
      observedDiscoveryAndRemoval,
  'permission requests are explicit and finish from observer state outside read timeouts':
      explicitPermissionRequestsUseObservedResponses,
  'permission overrides, cancellation and late coordinator failures are contained':
      permissionOverridesCancellationAndLateErrors,
  'paused observer streams fail explicitly at a bounded delivery queue':
      boundedObserverDelivery,
  'permission coordinator registrations and asynchronous failures have explicit lifetimes':
      permissionCoordinatorLifetimes,
};
