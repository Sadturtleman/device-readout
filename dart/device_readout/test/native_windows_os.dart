import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:device_readout/device_readout.dart';

import 'observers.dart' show check;

Future<void> nativeWindowsOs() async {
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
        >('readout_probe_os_version');
    final pointer = query();
    check(pointer != ffi.nullptr, 'The independent native OS query failed.');
    final bytes = <int>[];
    for (var offset = 0; offset < 64 && pointer[offset] != 0; offset++) {
      bytes.add(pointer[offset]);
    }
    final nativeVersion = ascii.decode(bytes);
    final nativeBuild = probe
        .lookupFunction<ffi.Uint32 Function(), int Function()>(
          'readout_probe_os_build',
        )();
    check(nativeBuild != 0xffffffff, 'The native build query failed.');
    final reference = await Process.run('powershell.exe', [
      '-NoProfile',
      '-File',
      'tools/verify-windows-os.ps1',
    ]);
    check(
      reference.exitCode == 0,
      'Independent CIM query failed: ${reference.stderr}',
    );
    final cim = jsonDecode(reference.stdout as String) as Map;
    check(
      cim['version'] == nativeVersion && cim['build'] == nativeBuild.toString(),
      'Independent CIM and native Windows version sources must agree.',
    );

    final started = DateTime.now().toUtc();
    final snapshot = await sdk.get(Entities.os);
    check(
      snapshot.family == OsFamily.windows &&
          snapshot.name == 'Windows' &&
          snapshot.kernelName == 'Windows NT',
      'OS identity must retain Windows/NT semantics.',
    );
    check(
      snapshot.version == nativeVersion &&
          snapshot.build == cim['build'] &&
          snapshot.kernelVersion == nativeVersion,
      'OS version/build must match the independent native and CIM readings.',
    );
    check(
      !snapshot.collectedAt.isBefore(started),
      'OS collection must stamp completion.',
    );
    final support = await sdk.capabilities.get(Entities.os);
    check(
      support.readable == true && support.watchable == true,
      'Native Windows OS must advertise get/watch support.',
    );
    final values = await sdk
        .withPollInterval(const Duration(milliseconds: 20))
        .watch(Entities.os)
        .take(3)
        .toList();
    check(
      values.every(
        (value) =>
            value.version == snapshot.version && value.build == snapshot.build,
      ),
      'Unchanged OS values must still be delivered on every poll.',
    );
    for (var i = 1; i < values.length; i++) {
      check(
        values[i].collectedAt.isAfter(values[i - 1].collectedAt),
        'OS polling must carry fresh completion times.',
      );
    }
    final other = DeviceAccess.native();
    try {
      check(
        (await other.get(Entities.os)).version == nativeVersion,
        'Independent contexts must read the same running OS.',
      );
    } finally {
      other.dispose();
    }
    check(
      (await sdk.get(Entities.os)).version == nativeVersion &&
          (await sdk.get(Entities.runtime)).hostArchitecture != null &&
          (await sdk.get(Entities.ram)).physicalBytes != null,
      'Native OS cleanup must preserve the live OS, runtime and RAM context.',
    );
    print(
      'WINDOWS_OS ${jsonEncode({'snapshot': snapshot.toJson(), 'nativeVersion': nativeVersion, 'nativeBuild': nativeBuild, 'cim': cim, 'polls': values.length})}',
    );
  } finally {
    sdk.dispose();
    probe.close();
  }
}

final checks = <String, Future<void> Function()>{
  'native Windows OS agrees with native version and CIM providers':
      nativeWindowsOs,
};

Future<void> main() => nativeWindowsOs();
