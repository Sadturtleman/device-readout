import 'dart:async';
import 'dart:io';

import 'package:device_readout/device_readout.dart';

import 'observers.dart' show check, errorOf;

Future<void> nativeWindowsStorage() async {
  if (!Platform.isWindows) return;
  final sdk = DeviceAccess.native();
  final other = DeviceAccess.native();
  try {
    final volumes = await sdk.storageVolumes.list();
    check(volumes.isNotEmpty, 'Windows must expose its mounted local volumes.');
    final again = await sdk.storageVolumes.list();
    check(
      volumes.length == again.length && volumes.every(again.contains),
      'Unchanged native volumes must preserve their context-owned handles.',
    );
    check(
      await sdk.storageVolumes.current() == null,
      'Do not infer application storage from a drive letter or working directory.',
    );
    Entity<StorageVolumeSnapshot>? readable;
    for (final volume in volumes) {
      late StorageVolumeSnapshot snapshot;
      try {
        snapshot = await sdk.get(volume);
      } on DeviceReadoutException catch (error) {
        // Enumeration can expose system volumes whose contents this user cannot query.
        if (error.code == ErrorCode.permissionDenied) continue;
        rethrow;
      }
      if (snapshot.totalBytes != null && snapshot.fileSystem != null) {
        readable ??= volume;
        check(
          snapshot.totalBytes! > BigInt.zero,
          'The volume capacity is positive.',
        );
        check(
          snapshot.totalBytesForCaller != null,
          'Caller quota capacity is separate.',
        );
        check(
          snapshot.freeBytes != null && snapshot.availableToCallerBytes != null,
          'Both volume and caller free-space fields are collected.',
        );
      }
      check(
        snapshot.encrypted == null && snapshot.caseSensitive == null,
        'File-system feature support is not current encryption or case behavior.',
      );
    }
    check(
      readable != null,
      'At least one local volume is readable on this host.',
    );
    final target = readable!;
    sdk.observers.current(Entities.storageVolume, target);
    check(
      await sdk.storageVolumes.current() == target,
      'The app can select its storage volume explicitly.',
    );
    final foreign = await errorOf(other.get(target));
    check(
      foreign is DeviceReadoutException &&
          foreign.code == ErrorCode.invalidConfiguration,
      'A volume handle belongs to its own context.',
    );
    final snapshots = await sdk
        .withPollInterval(const Duration(milliseconds: 25))
        .watch(target)
        .take(3)
        .toList()
        .timeout(const Duration(seconds: 3));
    check(
      snapshots.length == 3,
      'Native storage watch supplies initial and polled snapshots.',
    );
    for (var i = 1; i < snapshots.length; i++) {
      check(
        snapshots[i].collectedAt.isAfter(snapshots[i - 1].collectedAt),
        'Every volume snapshot has its own completion timestamp.',
      );
      check(
        snapshots[i].totalBytes == snapshots.first.totalBytes,
        'Polling retains a stable volume capacity.',
      );
    }
    final support = await sdk.capabilities.get(target);
    check(
      support.readable == true && support.watchable == true,
      'Native volume support is advertised.',
    );
  } finally {
    other.dispose();
    sdk.dispose();
  }
}

final checks = <String, Future<void> Function()>{
  'native Windows storage exposes stable handles and separate volume/caller fields':
      nativeWindowsStorage,
};

Future<void> main() => nativeWindowsStorage();
