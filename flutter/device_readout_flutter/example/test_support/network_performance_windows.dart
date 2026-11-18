import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:isolate';

import 'package:device_readout_flutter/device_readout_flutter.dart' as readout;

final class _Probe extends ffi.Struct {
  @ffi.Int32()
  external int status;
  @ffi.Int32()
  external int present;
  @ffi.Double()
  external double inbound;
  @ffi.Double()
  external double outbound;
}

(double?, double?) _reference(String path) {
  final probe = ffi.DynamicLibrary.open(path);
  try {
    final value = probe.lookupFunction<_Probe Function(), _Probe Function()>(
      'readout_probe_network_performance',
    )();
    if (value.status != 0)
      throw StateError('Independent C++/WinRT plan reference failed.');
    return (
      value.present & 1 != 0 ? value.inbound : null,
      value.present & 2 != 0 ? value.outbound : null,
    );
  } finally {
    probe.close();
  }
}

Future<Map<String, Object?>> verifyNetworkPerformance(
  readout.DeviceAccess access,
  String probePath,
) async {
  final reference = await Isolate.run(() => _reference(probePath));
  final support = await access.capabilities.get(
    readout.Entities.networkPerformance,
  );
  if (support.readable != true || support.watchable != true)
    throw StateError(
      'Flutter Windows performance get/watch must be available.',
    );
  bool matches(readout.NetworkPerformanceSnapshot value) =>
      value.downlinkBps == reference.$1 &&
      value.uplinkBps == reference.$2 &&
      value.roundTripTime == null &&
      value.effectiveType == null &&
      value.browserOnline == null;
  final value = await access.get(readout.Entities.networkPerformance);
  if (!matches(value))
    throw StateError(
      'Flutter rates differ from independent WinRT: ${value.toJson()} / $reference',
    );
  var ticks = 0;
  final timer = Timer.periodic(const Duration(milliseconds: 5), (_) => ticks++);
  try {
    final values = await access
        .withPollInterval(const Duration(milliseconds: 25))
        .watch(readout.Entities.networkPerformance)
        .take(3)
        .toList();
    if (!values.every(matches) || ticks < 2)
      throw StateError(
        'Performance polling must preserve values and Flutter event-loop progress.',
      );
    for (var i = 1; i < values.length; i++) {
      if (!values[i].collectedAt.isAfter(values[i - 1].collectedAt))
        throw StateError(
          'Equal/null-rate snapshots need fresh completion timestamps.',
        );
    }
    if ((await access.get(readout.Entities.networkPath)).connectionState ==
        null)
      throw StateError('The shared path collector must remain usable.');
    return {
      'name': 'native Windows performance get/watch agrees with C++/WinRT',
      'snapshot': value.toJson(),
      'referenceInbound': reference.$1,
      'referenceOutbound': reference.$2,
      'polls': values.length,
      'heartbeatTicks': ticks,
    };
  } finally {
    timer.cancel();
  }
}
