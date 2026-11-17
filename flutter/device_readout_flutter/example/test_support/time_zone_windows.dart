import 'dart:async';
import 'dart:ffi' as ffi;

import 'package:device_readout_flutter/device_readout_flutter.dart' as readout;

Future<Map<String, Object?>> verifyTimeZone(
  readout.DeviceAccess access,
  String probePath,
) async {
  final probe = ffi.DynamicLibrary.open(probePath);
  try {
    final refreshed = probe
        .lookupFunction<ffi.Int32 Function(), int Function()>(
          'readout_probe_time_zone_refresh',
        )();
    if (refreshed != 1) throw StateError('Independent time-zone query failed.');
    String? string(String symbol) {
      final pointer = probe
          .lookupFunction<
            ffi.Pointer<ffi.Uint16> Function(),
            ffi.Pointer<ffi.Uint16> Function()
          >(symbol)();
      final units = <int>[];
      for (var i = 0; i < 256 && pointer[i] != 0; i++) {
        units.add(pointer[i]);
      }
      return units.isEmpty ? null : String.fromCharCodes(units);
    }

    final windows = string('readout_probe_time_zone_windows');
    final iana = string('readout_probe_time_zone_iana');
    final offset = probe.lookupFunction<ffi.Int32 Function(), int Function()>(
      'readout_probe_time_zone_offset',
    )();
    final daylight =
        probe.lookupFunction<ffi.Int32 Function(), int Function()>(
          'readout_probe_time_zone_daylight',
        )() !=
        0;
    bool matches(readout.TimeZoneSnapshot snapshot) =>
        snapshot.windowsId == windows &&
        snapshot.ianaId == iana &&
        snapshot.utcOffsetSeconds == offset &&
        snapshot.daylightSavingTime == daylight;
    final snapshot = await access.get(readout.Entities.timeZone);
    if (!matches(snapshot))
      throw StateError(
        'Time-zone fields differ from the independent native conversion.',
      );
    final support = await access.capabilities.get(readout.Entities.timeZone);
    if (support.readable != true || support.watchable != true) {
      throw StateError('Flutter must see native time-zone get/watch support.');
    }
    var ticks = 0;
    final heartbeat = Timer.periodic(
      const Duration(milliseconds: 5),
      (_) => ticks++,
    );
    try {
      final values = await access
          .withPollInterval(const Duration(milliseconds: 20))
          .watch(readout.Entities.timeZone)
          .take(3)
          .toList();
      if (!values.every(matches))
        throw StateError('Every time-zone poll must preserve current fields.');
      for (var i = 1; i < values.length; i++) {
        if (!values[i].collectedAt.isAfter(values[i - 1].collectedAt)) {
          throw StateError(
            'Time-zone polling must carry fresh completion times.',
          );
        }
      }
      if (ticks < 2)
        throw StateError(
          'Flutter timers must progress during time-zone polling.',
        );
      return {
        'name': 'native Windows time zone with Flutter host timer progress',
        'snapshot': snapshot.toJson(),
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
