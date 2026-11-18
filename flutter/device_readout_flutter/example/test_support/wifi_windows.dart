import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:isolate';

import 'package:device_readout_flutter/device_readout_flutter.dart' as readout;

(int, bool) _reference(String path) {
  final library = ffi.DynamicLibrary.open(path);
  try {
    final value = library.lookupFunction<ffi.Uint64 Function(), int Function()>(
      'readout_probe_wifi',
    )();
    if (value == -1)
      throw StateError('Independent native Wi-Fi inventory failed.');
    return (value & 0xffffffff, value >> 32 != 0);
  } finally {
    library.close();
  }
}

Future<Map<String, Object?>> verifyWifi(
  readout.DeviceAccess access,
  String probePath,
) async {
  final reference = await Isolate.run(() => _reference(probePath));
  var ticks = 0, reads = 0;
  final timer = Timer.periodic(const Duration(milliseconds: 5), (_) => ticks++);
  try {
    final targets = await access.list(readout.Entities.wifiConnection);
    final current = await access.current(readout.Entities.wifiConnection);
    if (targets.length != reference.$1 || (current != null) != reference.$2)
      throw StateError('Wi-Fi inventory differs from independent C++/WinRT.');
    for (final target in targets) {
      final value = await access.get(target);
      reads++;
      if (value.bssid != null ||
          value.frequencyHz != null ||
          value.receiveLinkSpeedBps != null ||
          value.transmitLinkSpeedBps != null)
        throw StateError('Unmapped Wi-Fi fields must remain null.');
      final values = await access
          .withPollInterval(const Duration(milliseconds: 25))
          .watch(target)
          .take(3)
          .toList();
      if (!values.last.collectedAt.isAfter(values.first.collectedAt))
        throw StateError('Wi-Fi snapshots require fresh timestamps.');
    }
    for (var i = 0; i < 3; i++) {
      final again = await access.list(readout.Entities.wifiConnection);
      if (again.length != targets.length || !targets.every(again.contains))
        throw StateError('Stable inventory must preserve typed handles.');
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    if (ticks < 2)
      throw StateError('Flutter event loop must progress during collection.');
    return {
      'name': 'native Windows Wi-Fi discovery agrees with C++/WinRT',
      'targets': targets.length,
      'current': current != null,
      'fieldReads': reads,
      'referenceCount': reference.$1,
      'referenceCurrent': reference.$2,
      'heartbeatTicks': ticks,
    };
  } finally {
    timer.cancel();
  }
}
