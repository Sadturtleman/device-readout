import 'dart:async';
import 'dart:isolate';

import 'package:device_readout/device_readout.dart';

import 'observers.dart'
    show check, errorOf, forbiddenNativeFactory, heldRamFactory;

Future<void> independentFailuresAndAppPolicy() async {
  final sdk = DeviceAccess.isolated(forbiddenNativeFactory);
  final display = sdk.observers.target(Entities.display, 'owned-failures');
  final first = sdk.observers.failureSource(Entities.display);
  final second = sdk.observers.failureSource(Entities.display);
  const sourceFailure = DeviceReadoutException(
    ErrorCode.readFailed,
    'Source unavailable.',
  );
  const otherFailure = DeviceReadoutException(
    ErrorCode.unsupportedEntity,
    'Other source unavailable.',
  );
  const appFailure = DeviceReadoutException(
    ErrorCode.permissionDenied,
    'Application policy.',
  );
  final initial = Completer<void>(), ended = Completer<void>();
  final errors = <Object>[], values = <DisplaySnapshot>[];
  sdk.observers.publish(display, DisplaySnapshot(label: 'initial'));
  final stream = sdk
      .watch(display)
      .listen(
        (value) {
          values.add(value);
          if (!initial.isCompleted) initial.complete();
        },
        onError: (Object error) {
          errors.add(error);
        },
        onDone: ended.complete,
      );
  try {
    await initial.future;
    first.publish(sourceFailure);
    second.publish(otherFailure);
    await ended.future;
    check(
      errors.length == 1 && identical(errors.single, sourceFailure),
      'A scoped failure must end an existing watch without awaiting a poll.',
    );
    sdk.observers.failure(Entities.display, appFailure);
    first.dispose();
    second.publish(sourceFailure);
    check(
      identical(await errorOf(sdk.get(display)), appFailure),
      'Source recovery and replacement must never clear or replace app policy.',
    );
    sdk.observers.failure(Entities.display, null);
    check(
      identical(await errorOf(sdk.get(display)), sourceFailure),
      'Clearing app policy must leave an independent source failure intact.',
    );
    second.dispose();
    final stale = await errorOf(
      sdk.withReadTimeout(const Duration(milliseconds: 40)).get(display),
    );
    check(
      stale is DeviceReadoutException && stale.code == ErrorCode.readTimeout,
      'Releasing failure owners cannot restore invalidated cached state.',
    );
    sdk.observers.publish(display, DisplaySnapshot(label: 'fresh'));
    check(
      (await sdk.get(display)).label == 'fresh' && values.length == 1,
      'Fresh reads recover after all owners release failures; ended streams stay ended.',
    );

    final replacement = sdk.observers.failureSource(Entities.display);
    replacement.publish(otherFailure);
    first.dispose();
    second.dispose();
    check(
      identical(await errorOf(sdk.displays.list()), otherFailure),
      'Stale cleanup must not remove a replacement owner.',
    );
    replacement.publish(null);
    check(
      (await sdk.displays.list()).single == display,
      'Clearing a source removes only that source\'s failure.',
    );
    replacement.dispose();
    Object? disposedFailure;
    try {
      first.publish(sourceFailure);
    } catch (error) {
      disposedFailure = error;
    }
    check(
      disposedFailure is DeviceReadoutCancelled,
      'A disposed failure source cannot publish into a new owner\'s lifetime.',
    );
    sdk.dispose();
    replacement.dispose();
  } finally {
    await stream.cancel();
    first.dispose();
    second.dispose();
    sdk.dispose();
  }
}

Future<void> registerSensorWhileBlocked() async {
  final sdk = DeviceAccess.isolated(forbiddenNativeFactory);
  final target = sdk.observers.target(Entities.accelerometer, 'blocked-input');
  const denied = DeviceReadoutException(
    ErrorCode.permissionDenied,
    'The application has not enabled collection.',
  );
  var starts = 0;
  void Function()? unregister;
  sdk.observers.failure(Entities.accelerometer, denied);
  try {
    unregister = sdk.observers.sensorSource(
      target,
      SensorObserverSource<AccelerometerSnapshot>(
        subscribe: (session) {
          starts++;
          session.publish(AccelerometerSnapshot(value: const Vector3(1, 2, 3)));
          return null;
        },
      ),
    );
    check(
      starts == 0 && identical(await errorOf(sdk.get(target)), denied),
      'Installing an observer is inert and cannot bypass application policy.',
    );
    check(
      identical(await errorOf(sdk.watch(target).first), denied) && starts == 0,
      'A denied watch cannot start the prepared sensor source.',
    );
    sdk.observers.failure(Entities.accelerometer, null);
    check(
      (await sdk.get(target)).value?.x == 1 && starts == 1,
      'Only an application policy change permits fresh sensor collection.',
    );
  } finally {
    unregister?.call();
    sdk.dispose();
  }
}

Future<void> scopedFailureInvalidatesPendingRead() async {
  final probe = ReceivePort();
  final entered = Completer<void>(), disposed = Completer<void>();
  final listener = probe.listen((Object? event) {
    if (event == 'entered') entered.complete();
    if (event == 'disposed') disposed.complete();
  });
  final sdk = DeviceAccess.isolated(
    heldRamFactory,
    initialData: probe.sendPort,
  );
  final source = sdk.observers.failureSource(Entities.ram);
  const failure = DeviceReadoutException(
    ErrorCode.readFailed,
    'The provider failed while a native read was in flight.',
  );
  try {
    await sdk.get(Entities.runtime);
    final pending = errorOf(sdk.get(Entities.ram));
    await entered.future.timeout(const Duration(seconds: 2));
    source.publish(failure);
    source.publish(null);
    source.dispose();
    check(
      identical(
        await pending.timeout(const Duration(milliseconds: 100)),
        failure,
      ),
      'Immediate source recovery and disposal cannot revive an in-flight result.',
    );
    sdk.dispose();
    await disposed.future.timeout(const Duration(seconds: 2));
  } finally {
    source.dispose();
    sdk.dispose();
    await listener.cancel();
    probe.close();
  }
}

final checks = <String, Future<void> Function()>{
  'scoped observer failures preserve app policy and independent source lifetimes':
      independentFailuresAndAppPolicy,
  'sensor observer registration is inert while app policy blocks collection':
      registerSensorWhileBlocked,
  'scoped failure recovery and disposal reject an in-flight native result':
      scopedFailureInvalidatesPendingRead,
};
