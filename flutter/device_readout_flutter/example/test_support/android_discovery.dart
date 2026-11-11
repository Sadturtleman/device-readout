import 'package:device_readout_flutter/device_readout_flutter.dart';

void _require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<Map<String, Object?>> verifyAndroidDiscovery(
  DeviceAccess access,
  List<String> checks,
) async {
  final cores = await access.cpuCores.list();
  final again = await access.cpuCores.list();
  _require(
    cores.isNotEmpty &&
        cores.length == again.length &&
        cores.asMap().entries.every(
          (entry) => identical(entry.value, again[entry.key]),
        ),
    'Native CPU inventories must preserve live typed handles.',
  );
  final indices = <int>[];
  for (final core in cores) {
    final value = await access.get(core);
    _require(
      value.logicalIndex != null,
      'The native CPU fixture must expose each logical index.',
    );
    indices.add(value.logicalIndex!);
  }
  _require(
    await access.cpuCores.current() == null,
    'CPU current selection must not invent a default core.',
  );
  final updates = await access
      .withPollInterval(const Duration(milliseconds: 40))
      .watch(cores.first)
      .take(2)
      .toList();
  _require(
    updates.every((value) => value.logicalIndex == indices.first),
    'Selected CPU handles must be usable by native watch.',
  );
  checks.add('native CPU discovery preserves handles and selected polling');

  final support = await access.capabilities.get(cores.first);
  _require(
    support.readable == true && support.watchable == true,
    'Selected native handles preserve operation support.',
  );
  access.observers.remove(cores.first);
  final retired = await access.capabilities.get(cores.first);
  _require(
    retired.readable == false && retired.watchable == false,
    'Explicit observer removal retires capability support.',
  );
  final replacement = (await access.cpuCores.list()).first;
  _require(
    !identical(replacement, cores.first) &&
        (await access.capabilities.get(replacement)).readable == true,
    'Rediscovery creates a new supported handle without reviving the retired one.',
  );
  checks.add(
    'selected capabilities preserve native and retired target generations',
  );

  final volumes = await access.storageVolumes.list();
  final selected = await access.storageVolumes.current();
  _require(
    selected != null && volumes.any((value) => identical(value, selected)),
    'The current app-data volume must be one of the discovered native targets.',
  );
  final storage = await access.get(selected!);
  _require(
    storage.totalBytes != null && storage.totalBytes! > BigInt.zero,
    'The app-data volume must expose a positive native capacity.',
  );
  checks.add('native storage current resolves the discovered app volume');

  final batteries = await access.batteries.list();
  _require(batteries.isNotEmpty, 'The owned AVD has a simulated battery.');
  final battery = await access.get(batteries.first);
  _require(
    battery.present == true,
    'Selected battery state must come from the native reader.',
  );
  final interfaces = await access.networkInterfaces.list();
  _require(
    interfaces.isNotEmpty,
    'The owned AVD has native network interfaces.',
  );
  final interfaceNames = <String>[];
  for (final target in interfaces) {
    final value = await access.get(target);
    _require(
      value.name != null && value.name!.isNotEmpty,
      'Native interface names must be readable.',
    );
    interfaceNames.add(value.name!);
  }
  checks.add('native battery and network interfaces use typed target reads');

  // Ordinary-app queries only. No permission prompt is opened and no identifier
  // or Wi-Fi value is copied into the report.
  final outcomes = <String, String>{};
  for (final kind in <Entity<DeviceSnapshot>>[
    Entities.wifiConnection,
    Entities.cellularSubscription,
    Entities.telephonyIdentity,
  ]) {
    try {
      final targets = await access.list(kind);
      var readable = 0, denied = 0;
      for (final target in targets) {
        try {
          final value = await access.get(target);
          _require(
            value.entityKind == kind.kind,
            'Selected wireless/identity reads must retain their snapshot type.',
          );
          readable++;
        } on DeviceReadoutException catch (error) {
          _require(
            error.code == ErrorCode.permissionDenied,
            'Selected ordinary-app reads must retain native permission denials.',
          );
          denied++;
        }
      }
      outcomes[kind.kind.name] =
          'count:${targets.length},readable:$readable,denied:$denied';
    } on DeviceReadoutException catch (error) {
      _require(
        error.code == ErrorCode.permissionDenied,
        'Connected wireless/identity discovery must retain native permission errors.',
      );
      outcomes[kind.kind.name] = 'permissionDenied';
    }
  }
  checks.add('wireless and slot discovery retain native permission outcomes');

  final other = FlutterAndroidDeviceAccess.create();
  try {
    try {
      await other.get(cores.first);
      throw StateError('A foreign native target was accepted.');
    } on DeviceReadoutException catch (error) {
      _require(
        error.code == ErrorCode.invalidConfiguration,
        'Native handles remain context-scoped.',
      );
    }
  } finally {
    other.dispose();
  }
  return {
    'cpuIndices': indices,
    'interfaceNames': interfaceNames,
    'storageTotalBytes': storage.totalBytes.toString(),
    'collectionOutcomes': outcomes,
  };
}
