import 'dart:async';

import 'package:device_readout_flutter/device_readout_flutter.dart' as readout;

import 'windows_storage_reference.dart';

Future<Map<String, Object?>> verifyStorage(
  readout.DeviceAccess access,
  String probePath,
) async {
  final probe = WindowsStorageReference(probePath);
  try {
    final reference = probe.read();
    final volumes = await access.storageVolumes.list();
    if (volumes.length != probe.count() || reference['structureSize'] != 96) {
      throw StateError(
        'Flutter volume inventory/native ABI reference differs.',
      );
    }
    final again = await access.storageVolumes.list();
    if (volumes.length != again.length || !volumes.every(again.contains)) {
      throw StateError(
        'Repeated discovery must retain unchanged volume handles.',
      );
    }
    if (await access.storageVolumes.current() != null) {
      throw StateError('No application storage volume has been selected.');
    }
    readout.Entity<readout.StorageVolumeSnapshot>? target;
    readout.StorageVolumeSnapshot? initial;
    for (final volume in volumes) {
      try {
        final value = await access.get(volume);
        if (value.totalBytes == reference['totalBytes'] &&
            value.name == reference['name'] &&
            value.fileSystem == reference['fileSystem']) {
          initial = value;
          target = volume;
          break;
        }
      } on readout.DeviceReadoutException catch (error) {
        if (error.code != readout.ErrorCode.permissionDenied) rethrow;
      }
    }
    if (target == null || initial == null) {
      throw StateError('The independently queried Windows volume is missing.');
    }
    bool matches(readout.StorageVolumeSnapshot value) =>
        value.totalBytes == reference['totalBytes'] &&
        value.totalBytesForCaller == reference['totalBytesForCaller'] &&
        value.name == reference['name'] &&
        value.fileSystem == reference['fileSystem'] &&
        value.readOnly == reference['readOnly'] &&
        value.removable == reference['removable'] &&
        value.freeBytes != null &&
        value.availableToCallerBytes != null &&
        value.encrypted == null &&
        value.caseSensitive == null;
    if (!matches(initial)) throw StateError('Native storage fields differ.');
    access.observers.current(readout.Entities.storageVolume, target);
    if (await access.storageVolumes.current() != target) {
      throw StateError(
        'Explicit app storage selection must retain its handle.',
      );
    }
    final support = await access.capabilities.get(target);
    if (support.readable != true || support.watchable != true) {
      throw StateError('Flutter Windows storage must advertise get/watch.');
    }
    var ticks = 0;
    final heartbeat = Timer.periodic(
      const Duration(milliseconds: 5),
      (_) => ticks++,
    );
    try {
      final values = await access
          .withPollInterval(const Duration(milliseconds: 25))
          .watch(target)
          .take(3)
          .toList();
      if (!values.every(matches) || ticks == 0) {
        throw StateError('Storage polling fields or host heartbeat failed.');
      }
      for (var i = 1; i < values.length; i++) {
        if (!values[i].collectedAt.isAfter(values[i - 1].collectedAt)) {
          throw StateError(
            'Equal storage values still require fresh snapshots.',
          );
        }
      }
      return {
        'name': 'native storage discovery, explicit current volume and polling',
        'passed': true,
        'volumeCount': volumes.length,
        'reference': reference.map(
          (key, value) =>
              MapEntry(key, value is BigInt ? value.toString() : value),
        ),
        'initial': initial.toJson(),
        'snapshots': values.map((value) => value.toJson()).toList(),
        'heartbeatTicks': ticks,
      };
    } finally {
      heartbeat.cancel();
    }
  } finally {
    probe.dispose();
  }
}
