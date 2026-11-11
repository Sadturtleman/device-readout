import 'dart:async';
import 'dart:convert';

import 'package:device_readout_flutter/device_readout_flutter.dart';

import 'android_discovery.dart';
import 'android_mixed.dart';

void _require(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<Map<String, Object?>> verifyAndroidState(List<String> checks) async {
  final access = FlutterAndroidDeviceAccess.create();
  try {
    var permissionRequests = 0;
    access.observers.onPermissionRequest((_) {
      permissionRequests++;
    });
    access.observers.permission(
      Entities.hardwareSerial,
      PermissionStatus.denied,
    );
    for (final entity in [
      Entities.ram,
      Entities.hardwareSerial,
      Entities.cpuCore,
    ]) {
      final support = await access.capabilities.get(entity);
      _require(
        support.readable == true && support.watchable == true,
        'Connected operation support is independent of denied permission.',
      );
    }
    for (final entity in <Entity<DeviceSnapshot>>[
      Entities.processMemory,
      Entities.display,
      Entities.accelerometer,
    ]) {
      final support = await access.capabilities.get(entity);
      _require(
        support.readable == false && support.watchable == false,
        'Unconnected native collectors and app-owned sources cannot claim support.',
      );
    }
    _require(
      permissionRequests == 0,
      'Support queries must not request permission.',
    );
    checks.add(
      'native capabilities distinguish support from permission and source registration',
    );
    final ram = await access.get(Entities.ram);
    final build = await access.get(Entities.androidBuild);
    final runtime = await access.get(Entities.runtime);
    final device = await access.get(Entities.deviceInfo);
    final os = await access.get(Entities.os);
    _require(
      ram.kernelAccessibleBytes != null &&
          ram.kernelAccessibleBytes! > BigInt.zero,
      'Native Android RAM must expose kernel-accessible memory.',
    );
    _require(
      os.family == OsFamily.android &&
          runtime.processArchitecture == Architecture.x64 &&
          runtime.processBitness == 64,
      'The Android x86_64 APK must report the running process and OS.',
    );
    for (final entity in <Entity<DeviceSnapshot>>[
      Entities.cpu,
      Entities.locale,
      Entities.timeZone,
      Entities.androidIdentity,
      Entities.power,
      Entities.networkPath,
      Entities.networkPerformance,
    ]) {
      final snapshot = await access.get(entity);
      _require(
        snapshot.entityKind == entity.kind && snapshot.collectedAt.isUtc,
        'Every connected singleton must retain its snapshot type and timestamp.',
      );
    }
    checks.add('native Android singleton state snapshots');
    try {
      await access.get(Entities.hardwareSerial);
      throw StateError(
        'This ordinary test app has no serial-reading permission.',
      );
    } on DeviceReadoutException catch (error) {
      _require(
        error.code == ErrorCode.permissionDenied,
        'Native serial denial must remain typed.',
      );
    }
    try {
      await access.get(Entities.processMemory);
      throw StateError(
        'Unimplemented Android process memory must not be fabricated.',
      );
    } on DeviceReadoutException catch (error) {
      _require(
        error.code == ErrorCode.unsupportedEntity,
        'Expected UnsupportedEntity for an unconnected collector.',
      );
    }
    checks.add('state bridge preserves permission and unsupported errors');

    final discovery = await verifyAndroidDiscovery(access, checks);

    final polled = await access
        .withPollInterval(const Duration(milliseconds: 40))
        .watch(Entities.os)
        .take(3)
        .toList()
        .timeout(const Duration(seconds: 5));
    _require(
      polled.every((value) => value.version == os.version) &&
          polled.last.collectedAt.isAfter(polled.first.collectedAt),
      'Native polling must retain equal OS values and fresh collection times.',
    );
    checks.add('native state polling retains equal values');

    final initial = Completer<PowerSnapshot>(),
        changed = Completer<PowerSnapshot>();
    PowerSource? original;
    final watch = access
        .withReadTimeout(const Duration(milliseconds: 500))
        .withPollInterval(const Duration(minutes: 1))
        .watch(Entities.power)
        .listen(
          (value) {
            if (!initial.isCompleted) {
              original = value.powerSource;
              initial.complete(value);
            } else if (value.powerSource != original && !changed.isCompleted) {
              changed.complete(value);
            }
          },
          onError: (Object error) {
            if (!initial.isCompleted) initial.completeError(error);
            if (!changed.isCompleted) changed.completeError(error);
          },
        );
    // Install the error handler before the host can trigger a power transition.
    final outcome = changed.future.then<Object>(
      (value) => value,
      onError: (Object error) => error,
    );
    try {
      final first = await initial.future.timeout(const Duration(seconds: 5));
      _require(
        first.powerSource == PowerSource.external ||
            first.powerSource == PowerSource.battery,
        'The owned emulator must expose a known power source.',
      );
      print(
        'DEVICE_READOUT_ANDROID_STATE_POWER_READY:${jsonEncode({'source': first.powerSource!.name})}',
      );
      final result = await outcome.timeout(const Duration(seconds: 15));
      if (result is! PowerSnapshot) throw result;
      _require(
        result.powerSource != null && result.powerSource != original,
        'A native power event must arrive before the one-minute poll interval.',
      );
      checks.add(
        'native power events do not wait for polling or idle timeouts',
      );
    } finally {
      await watch.cancel();
    }
    final mixedLifecycle = await verifyAndroidMixed(access, checks);
    return {
      ...discovery,
      'mixedLifecycle': mixedLifecycle,
      'apiLevel': build.apiLevel,
      'modelName': device.modelName,
      'kernelAccessibleBytes': ram.kernelAccessibleBytes.toString(),
      'processArchitecture': runtime.processArchitecture?.name,
    };
  } finally {
    access.dispose();
  }
}
