import 'dart:async';
import 'dart:ffi' as ffi;

import 'package:device_readout_flutter/device_readout_flutter.dart' as readout;

Future<Map<String, Object?>> verifyDeviceInfo(
  readout.DeviceAccess access,
  String probePath,
) async {
  final probe = ffi.DynamicLibrary.open(probePath);
  try {
    final query = probe
        .lookupFunction<
          ffi.Pointer<ffi.Uint16> Function(ffi.Int32),
          ffi.Pointer<ffi.Uint16> Function(int)
        >('readout_probe_device_info');
    String? native(int field) {
      final value = query(field);
      if (value == ffi.nullptr) return null;
      final units = <int>[];
      for (var i = 0; i < 32768; i++) {
        if (value[i] == 0) return String.fromCharCodes(units);
        units.add(value[i]);
      }
      throw StateError('The native reference string must be terminated.');
    }

    final manufacturer = native(0),
        model = native(1),
        board = native(2),
        name = native(3);
    if (name == null || name.isEmpty)
      throw StateError('The native name query failed.');
    bool matches(readout.DeviceInfoSnapshot value) =>
        value.manufacturer == manufacturer &&
        value.modelName == model &&
        value.board == board &&
        value.deviceName == name;
    final snapshot = await access.get(readout.Entities.deviceInfo);
    if (!matches(snapshot))
      throw StateError(
        'DeviceInfo must match its native BIOS and name sources.',
      );
    if (snapshot.brand != null ||
        snapshot.modelCode != null ||
        snapshot.product != null ||
        snapshot.formFactor != null) {
      throw StateError('Unmapped DeviceInfo meanings must remain null.');
    }
    final support = await access.capabilities.get(readout.Entities.deviceInfo);
    if (support.readable != true || support.watchable != true) {
      throw StateError(
        'The native DeviceInfo adapter must advertise get/watch.',
      );
    }
    var ticks = 0;
    final heartbeat = Timer.periodic(
      const Duration(milliseconds: 5),
      (_) => ticks++,
    );
    try {
      final values = await access
          .withPollInterval(const Duration(milliseconds: 20))
          .watch(readout.Entities.deviceInfo)
          .take(3)
          .toList();
      if (!values.every(matches))
        throw StateError('Repeated device values must be preserved.');
      for (var i = 1; i < values.length; i++) {
        if (!values[i].collectedAt.isAfter(values[i - 1].collectedAt)) {
          throw StateError(
            'Each DeviceInfo poll must have a fresh completion time.',
          );
        }
      }
      if (ticks < 2)
        throw StateError('Flutter timers must progress during device polling.');
      final redacted = snapshot.toJson()..remove('deviceName');
      return {
        'name': 'native Windows device information with Flutter host timer progress',
        'snapshot': redacted,
        'deviceNameMatches': true,
        'polls': values.length,
        'heartbeatTicks': ticks,
      };
    } finally {
      heartbeat.cancel();
    }
  } finally {
    probe.close();
  }
}
