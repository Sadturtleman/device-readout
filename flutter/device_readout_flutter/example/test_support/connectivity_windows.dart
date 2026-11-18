import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:isolate';

import 'package:device_readout_flutter/device_readout_flutter.dart' as readout;

int _reference(String path) {
  final probe = ffi.DynamicLibrary.open(path);
  try {
    return probe.lookupFunction<ffi.Uint64 Function(), int Function()>(
      'readout_probe_connectivity',
    )();
  } finally {
    probe.close();
  }
}

Future<Map<String, Object?>> verifyConnectivity(
  readout.DeviceAccess access,
  String probePath,
) async {
  final native = await Isolate.run(() => _reference(probePath));
  if (native < 0 || native == 0xffffffffffffffff)
    throw StateError('Independent WinRT path/reference subscription failed.');
  final level = native & 1 == 0 ? 0 : (native >> 8) & 255;
  final cost = (native >> 16) & 255;
  final expected = switch (level) {
    0 => readout.ConnectionState.disconnected,
    1 || 2 || 3 => readout.ConnectionState.connected,
    _ => null,
  };
  final validated = switch (level) {
    0 || 1 || 2 => false,
    3 => true,
    _ => null,
  };
  final metered = switch (cost) {
    1 => false,
    2 || 3 => true,
    _ => null,
  };
  bool matches(readout.NetworkPathSnapshot value) =>
      value.connectionState == expected &&
      value.internetValidated == validated &&
      value.metered == metered &&
      value.transports == null &&
      value.expensive == null &&
      value.constrained == null &&
      value.saveData == null &&
      value.supportsIpv4 == null &&
      value.supportsIpv6 == null &&
      value.supportsDns == null &&
      value.captivePortal == null;
  final snapshot = await access.get(readout.Entities.networkPath);
  if (!matches(snapshot))
    throw StateError(
      'Flutter path differs from independent C++/WinRT: ${snapshot.toJson()} / $native',
    );
  final support = await access.capabilities.get(readout.Entities.networkPath);
  if (support.readable != true || support.watchable != true)
    throw StateError('Native path get/watch must be available.');
  var ticks = 0;
  final timer = Timer.periodic(const Duration(milliseconds: 5), (_) => ticks++);
  try {
    final values = await access
        .withPollInterval(const Duration(milliseconds: 25))
        .watch(readout.Entities.networkPath)
        .take(3)
        .toList();
    if (!values.every(matches) || ticks < 2)
      throw StateError(
        'Path polling must preserve independent values and Flutter timer progress.',
      );
    for (var i = 1; i < values.length; i++) {
      if (!values[i].collectedAt.isAfter(values[i - 1].collectedAt))
        throw StateError('Equal snapshots retain fresh timestamps.');
    }
    return {
      'name': 'native Windows preferred path get/watch agrees with C++/WinRT',
      'snapshot': snapshot.toJson(),
      'reference': native,
      'referenceEventRegistration': true,
      'polls': values.length,
      'heartbeatTicks': ticks,
    };
  } finally {
    timer.cancel();
  }
}
