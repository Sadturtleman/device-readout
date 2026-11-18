import 'dart:async';
import 'dart:ffi' as ffi;

import 'package:device_readout_flutter/device_readout_flutter.dart' as readout;

Future<Map<String, Object?>> verifyPower(
  readout.DeviceAccess access,
  String probePath,
) async {
  final probe = ffi.DynamicLibrary.open(probePath);
  try {
    final query = probe.lookupFunction<ffi.Uint32 Function(), int Function()>(
      'readout_probe_power_status',
    );
    final native = query();
    if (native == 0xffffffff)
      throw StateError('Independent native power query failed.');
    final batteryClass = probe
        .lookupFunction<ffi.Uint32 Function(), int Function()>(
          'readout_probe_battery_class',
        )();
    final expectedSource = switch (native & 255) {
      0 => batteryClass == 1 ? readout.PowerSource.battery : null,
      1 => readout.PowerSource.external,
      _ => null,
    };
    final expectedSaving = switch ((native >> 8) & 255) {
      0 => false,
      1 => true,
      _ => null,
    };
    bool matches(readout.PowerSnapshot value) =>
        value.powerSource == expectedSource &&
        value.powerSaveMode == expectedSaving &&
        value.thermalState == null;
    final snapshot = await access.get(readout.Entities.power);
    if (!matches(snapshot))
      throw StateError(
        'Power differs from the native reference: ${snapshot.toJson()} / $native',
      );
    final support = await access.capabilities.get(readout.Entities.power);
    if (support.readable != true || support.watchable != true) {
      throw StateError('Flutter Windows must advertise Power get/watch.');
    }
    var ticks = 0;
    final heartbeat = Timer.periodic(
      const Duration(milliseconds: 5),
      (_) => ticks++,
    );
    try {
      final values = await access
          .withPollInterval(const Duration(milliseconds: 20))
          .watch(readout.Entities.power)
          .take(3)
          .toList();
      if (!values.every(matches))
        throw StateError(
          'Every power poll must match the stable native status.',
        );
      for (var i = 1; i < values.length; i++) {
        if (!values[i].collectedAt.isAfter(values[i - 1].collectedAt)) {
          throw StateError(
            'Equal power values must retain fresh completion timestamps.',
          );
        }
      }
      if (ticks < 2)
        throw StateError(
          'Flutter host timer did not advance during power polling.',
        );
      return {
        'name':
            'native Windows power get/watch with Flutter host timer progress',
        'snapshot': snapshot.toJson(),
        'nativeStatus': native,
        'batteryClass': batteryClass,
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
