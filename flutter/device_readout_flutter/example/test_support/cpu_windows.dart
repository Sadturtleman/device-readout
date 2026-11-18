import 'dart:async';

import 'package:device_readout_flutter/device_readout_flutter.dart' as readout;

import 'windows_cpu_reference.dart';

Future<Map<String, Object?>> verifyCpu(
  readout.DeviceAccess access,
  String probePath,
) async {
  final probe = WindowsCpuReference(probePath);
  try {
    final reference = probe.read();
    void matches(readout.CpuSnapshot value) {
      final json = value.toJson();
      for (final entry in reference.entries) {
        if (json[entry.key] != entry.value)
          throw StateError('CPU ${entry.key} differs from native reference.');
      }
      if (value.socModel != null || value.socManufacturer != null)
        throw StateError('CPU identity must not be relabeled as SoC identity.');
    }

    final initial = await access.get(readout.Entities.cpu);
    matches(initial);
    final support = await access.capabilities.get(readout.Entities.cpu);
    if (support.readable != true || support.watchable != true)
      throw StateError('Windows CPU get/watch is not advertised.');
    var ticks = 0;
    final heartbeat = Timer.periodic(
      const Duration(milliseconds: 5),
      (_) => ticks++,
    );
    try {
      final samples = await access
          .withPollInterval(const Duration(milliseconds: 25))
          .watch(readout.Entities.cpu)
          .take(3)
          .toList();
      for (final value in samples) {
        matches(value);
      }
      if (ticks == 0)
        throw StateError('Host timer did not progress during CPU polling.');
      for (var i = 1; i < samples.length; i++) {
        if (!samples[i].collectedAt.isAfter(samples[i - 1].collectedAt))
          throw StateError('CPU snapshot completion time was reused.');
      }
      return {
        'name':
            'native CPU topology, identity and process-default availability',
        'reference': reference,
        'initial': initial.toJson(),
        'snapshots': samples.map((value) => value.toJson()).toList(),
        'heartbeatTicks': ticks,
      };
    } finally {
      heartbeat.cancel();
    }
  } finally {
    probe.dispose();
  }
}
