import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;

import 'package:device_readout_flutter/device_readout_flutter.dart' as readout;

Future<Map<String, Object?>> verifyOs(
  readout.DeviceAccess access,
  String probePath,
) async {
  final probe = ffi.DynamicLibrary.open(probePath);
  try {
    final query = probe
        .lookupFunction<
          ffi.Pointer<ffi.Uint8> Function(),
          ffi.Pointer<ffi.Uint8> Function()
        >('readout_probe_os_version');
    final pointer = query();
    if (pointer == ffi.nullptr) {
      throw StateError('Independent Windows version query failed.');
    }
    final bytes = <int>[];
    for (var offset = 0; offset < 64 && pointer[offset] != 0; offset++) {
      bytes.add(pointer[offset]);
    }
    final expectedVersion = ascii.decode(bytes);
    final expectedBuild = probe
        .lookupFunction<ffi.Uint32 Function(), int Function()>(
          'readout_probe_os_build',
        )();
    if (expectedBuild == 0xffffffff) {
      throw StateError('Independent Windows build query failed.');
    }
    final snapshot = await access.get(readout.Entities.os);
    if (snapshot.family != readout.OsFamily.windows ||
        snapshot.name != 'Windows' ||
        snapshot.version != expectedVersion ||
        snapshot.build != expectedBuild.toString() ||
        snapshot.kernelName != 'Windows NT' ||
        snapshot.kernelVersion != expectedVersion) {
      throw StateError(
        'The Windows OS snapshot must match the native version '
        'and build: ${snapshot.toJson()}, native=$expectedVersion/$expectedBuild.',
      );
    }
    final support = await access.capabilities.get(readout.Entities.os);
    if (support.readable != true || support.watchable != true) {
      throw StateError('The Flutter consumer must see OS get/watch support.');
    }
    var ticks = 0;
    final heartbeat = Timer.periodic(
      const Duration(milliseconds: 5),
      (_) => ticks++,
    );
    try {
      final values = await access
          .withPollInterval(const Duration(milliseconds: 20))
          .watch(readout.Entities.os)
          .take(3)
          .toList();
      if (!values.every(
        (value) =>
            value.version == expectedVersion &&
            value.build == expectedBuild.toString(),
      )) {
        throw StateError(
          'Unchanged native OS values must be delivered on each poll.',
        );
      }
      for (var index = 1; index < values.length; index++) {
        if (!values[index].collectedAt.isAfter(values[index - 1].collectedAt)) {
          throw StateError('OS snapshots must have fresh collection times.');
        }
      }
      if (ticks < 2)
        throw StateError('Flutter timers must progress during OS polling.');
      return {
        'name':
            'native Windows OS version/build with Flutter host timer progress',
        'snapshot': snapshot.toJson(),
        'nativeVersion': expectedVersion,
        'nativeBuild': expectedBuild,
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
