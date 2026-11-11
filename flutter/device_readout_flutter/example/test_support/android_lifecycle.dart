import 'dart:async';

import 'package:device_readout_flutter/device_readout_flutter.dart';
import 'package:flutter/widgets.dart';

// This observer records real framework notifications only. The test runner moves
// this fixture's Android Activity to the background and brings it back.
final class _LifecycleProbe with WidgetsBindingObserver {
  final states = <String>[];
  final paused = Completer<void>(), resumed = Completer<void>();
  bool active = true;
  DateTime? resumedAt;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    states.add(state.name);
    active = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.paused && !paused.isCompleted) {
      paused.complete();
    }
    if (active && paused.isCompleted && !resumed.isCompleted) {
      resumedAt = DateTime.now().toUtc();
      resumed.complete();
    }
  }
}

Future<List<String>> verifyAndroidLifecycle(
  DeviceAccess access,
  Entity<AccelerometerSnapshot> target, {
  Future<void> Function()? whilePaused,
}) async {
  final binding = WidgetsBinding.instance;
  if (binding.lifecycleState != AppLifecycleState.resumed) {
    throw StateError('Start the lifecycle fixture in a resumed Activity.');
  }
  final probe = _LifecycleProbe();
  binding.addObserver(probe);
  final first = Completer<void>();
  final resumedSample = Completer<AccelerometerSnapshot>();
  final failures = <Object>[];
  var inactiveSamples = 0, ended = false;
  final subscription = access
      .withReadTimeout(const Duration(milliseconds: 300))
      .withSensorSamplingRate(SensorSamplingRate.atHertz(60))
      .watch(target)
      .listen(
        (sample) {
          if (!first.isCompleted) first.complete();
          if (!probe.active) inactiveSamples++;
          if (probe.resumed.isCompleted && !resumedSample.isCompleted) {
            resumedSample.complete(sample);
          }
        },
        onError: (Object error) {
          failures.add(error);
        },
        onDone: () {
          ended = true;
        },
      );
  try {
    await first.future.timeout(const Duration(seconds: 5));
    print('DEVICE_READOUT_ANDROID_LIFECYCLE_READY');
    await probe.paused.future.timeout(const Duration(seconds: 15));
    try {
      await access
          .withReadTimeout(const Duration(milliseconds: 150))
          .get(target);
      throw StateError('An inactive sensor get must not fabricate a sample.');
    } on DeviceReadoutException catch (error) {
      if (error.code != ErrorCode.readTimeout) rethrow;
    }
    await whilePaused?.call();
    print('DEVICE_READOUT_ANDROID_LIFECYCLE_PAUSED');
    await probe.resumed.future.timeout(const Duration(seconds: 15));
    final sample = await resumedSample.future.timeout(
      const Duration(seconds: 5),
    );
    if (failures.isNotEmpty ||
        ended ||
        inactiveSamples != 0 ||
        sample.value == null ||
        sample.collectedAt.isBefore(probe.resumedAt!)) {
      throw StateError(
        'The existing watch must resume fresh samples without inactive delivery: '
        'errors=$failures, ended=$ended, inactiveSamples=$inactiveSamples.',
      );
    }
    print('DEVICE_READOUT_ANDROID_LIFECYCLE_RESUMED');
    // Let the runner inspect the restored native SensorManager registration.
    await Future<void>.delayed(const Duration(seconds: 2));
    return List.unmodifiable(probe.states);
  } finally {
    await subscription.cancel();
    binding.removeObserver(probe);
  }
}
