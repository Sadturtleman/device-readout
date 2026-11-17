import 'dart:convert';
import 'dart:ffi' as ffi;

import 'package:device_readout_flutter/device_readout_flutter.dart' as readout;

Future<Map<String, Object?>> verifyRuntime(
  readout.DeviceAccess access,
  String probePath,
) async {
  final probe = ffi.DynamicLibrary.open(probePath);
  try {
    final query = probe
        .lookupFunction<
          ffi.Pointer<ffi.Uint8> Function(),
          ffi.Pointer<ffi.Uint8> Function()
        >('readout_probe_host_architecture');
    final pointer = query();
    if (pointer == ffi.nullptr) {
      throw StateError('Independent native host-architecture query failed.');
    }
    final bytes = <int>[];
    for (var offset = 0; offset < 16 && pointer[offset] != 0; offset++) {
      bytes.add(pointer[offset]);
    }
    final expected = ascii.decode(bytes);
    final snapshot = await access.get(readout.Entities.runtime);
    if (snapshot.hostArchitecture?.wireName != expected ||
        snapshot.processArchitecture != readout.Architecture.x64 ||
        snapshot.processBitness != 64 ||
        snapshot.supportedAbis != null) {
      throw StateError(
        'The x64 Flutter consumer must retain distinct native host '
        'and process values without fabricating supported ABIs: '
        '${snapshot.toJson()}, native=$expected.',
      );
    }
    final values = await access
        .withPollInterval(const Duration(milliseconds: 20))
        .watch(readout.Entities.runtime)
        .take(2)
        .toList();
    if (!values.every(
          (value) => value.hostArchitecture == snapshot.hostArchitecture,
        ) ||
        !values.last.collectedAt.isAfter(values.first.collectedAt)) {
      throw StateError(
        'Runtime watch must retain equal values with fresh timestamps.',
      );
    }
    return {
      'name': 'native host architecture and x64 Flutter process ABI',
      'snapshot': snapshot.toJson(),
      'nativeReference': expected,
      'polls': values.length,
    };
  } finally {
    probe.close();
  }
}
