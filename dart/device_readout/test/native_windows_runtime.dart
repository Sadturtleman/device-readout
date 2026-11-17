import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:device_readout/device_readout.dart';

import 'observers.dart' show check;

Future<void> nativeWindowsRuntime() async {
  if (!Platform.isWindows) return;
  final probe = ffi.DynamicLibrary.open(
    File('.tools/windows-memory-probe/Release/device_readout_memory_probe.dll')
        .absolute
        .path,
  );
  final sdk = DeviceAccess.native();
  try {
    final query = probe
        .lookupFunction<
          ffi.Pointer<ffi.Uint8> Function(),
          ffi.Pointer<ffi.Uint8> Function()
        >('readout_probe_host_architecture');
    final pointer = query();
    check(pointer != ffi.nullptr, 'The native host-architecture query failed.');
    final bytes = <int>[];
    for (var offset = 0; offset < 16 && pointer[offset] != 0; offset++) {
      bytes.add(pointer[offset]);
    }
    final expected = ascii.decode(bytes);
    final started = DateTime.now().toUtc();
    final snapshot = await sdk.get(Entities.runtime);
    check(
      snapshot.hostArchitecture?.wireName == expected,
      'Host architecture must match the OS native-machine report: '
      '$expected != ${snapshot.hostArchitecture}.',
    );
    check(
      snapshot.processArchitecture == Architecture.x64 &&
          snapshot.processBitness == 64 &&
          snapshot.supportedAbis == null,
      'The x64 test consumer must preserve its process ABI without guessing supported ABIs.',
    );
    check(
      !snapshot.collectedAt.isBefore(started),
      'Native runtime queries must retain their completion timestamp.',
    );
    final values = await sdk
        .withPollInterval(const Duration(milliseconds: 20))
        .watch(Entities.runtime)
        .take(3)
        .toList();
    check(
      values.every(
        (value) => value.hostArchitecture == snapshot.hostArchitecture,
      ),
      'Runtime polling must retain equal host-architecture readings.',
    );
    for (var i = 1; i < values.length; i++) {
      check(
        values[i].collectedAt.isAfter(values[i - 1].collectedAt),
        'Runtime polling must create fresh snapshots.',
      );
    }
    final other = DeviceAccess.native();
    try {
      check(
        (await other.get(Entities.runtime)).hostArchitecture ==
            snapshot.hostArchitecture,
        'Independent contexts must agree on the host.',
      );
      await other.get(Entities.ram);
    } finally {
      other.dispose();
    }
    check(
      (await sdk.get(Entities.runtime)).hostArchitecture ==
          snapshot.hostArchitecture,
      'Disposing another context must preserve native runtime bindings.',
    );
    print(
      'WINDOWS_RUNTIME ${jsonEncode({'snapshot': snapshot.toJson(), 'nativeReference': expected, 'polls': values.length})}',
    );
  } finally {
    sdk.dispose();
    probe.close();
  }
}

final checks = <String, Future<void> Function()>{
  'native Windows runtime distinguishes host and process architecture':
      nativeWindowsRuntime,
};

Future<void> main() => nativeWindowsRuntime();
