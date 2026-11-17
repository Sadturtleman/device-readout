import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:device_readout/device_readout.dart';

import 'observers.dart' show check;

Future<void> nativeWindowsDeviceInfo() async {
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
          ffi.Pointer<ffi.Uint16> Function(ffi.Int32),
          ffi.Pointer<ffi.Uint16> Function(int)
        >('readout_probe_device_info');
    String? native(int field) {
      final value = query(field);
      if (value == ffi.nullptr) return null;
      final units = <int>[];
      for (var offset = 0; offset < 32768; offset++) {
        if (value[offset] == 0) return String.fromCharCodes(units);
        units.add(value[offset]);
      }
      throw StateError('Native reference returned an unterminated string.');
    }

    final manufacturer = native(0),
        modelName = native(1),
        board = native(2),
        deviceName = native(3);
    check(
      deviceName != null && deviceName.isNotEmpty,
      'The native computer name must be readable.',
    );
    final reference = await Process.run('powershell.exe', [
      '-NoProfile',
      '-File',
      'tools/verify-windows-device-info.ps1',
    ]);
    check(
      reference.exitCode == 0,
      'Independent device CIM query failed: ${reference.stderr}',
    );
    final cim = jsonDecode(reference.stdout as String) as Map;
    check(
      manufacturer == cim['manufacturer'] && modelName == cim['modelName'],
      'Native BIOS and independent system-provider readings must agree.',
    );
    if (cim['boardCount'] == 1) {
      check(
        board == cim['board'],
        'The single baseboard must agree with the native BIOS product.',
      );
    }
    final started = DateTime.now().toUtc();
    final snapshot = await sdk.get(Entities.deviceInfo);
    check(
      snapshot.manufacturer == manufacturer &&
          snapshot.modelName == modelName &&
          snapshot.board == board &&
          snapshot.deviceName == deviceName,
      'DeviceInfo fields must match their independent native sources.',
    );
    check(
      snapshot.brand == null &&
          snapshot.modelCode == null &&
          snapshot.product == null &&
          snapshot.formFactor == null,
      'Unmapped meanings must stay null instead of borrowing another field.',
    );
    check(
      !snapshot.collectedAt.isBefore(started),
      'DeviceInfo must stamp read completion.',
    );
    final support = await sdk.capabilities.get(Entities.deviceInfo);
    check(
      support.readable == true && support.watchable == true,
      'DeviceInfo must support get/watch.',
    );
    final values = await sdk
        .withPollInterval(const Duration(milliseconds: 20))
        .watch(Entities.deviceInfo)
        .take(3)
        .toList();
    check(
      values.every(
        (value) =>
            value.manufacturer == manufacturer &&
            value.modelName == modelName &&
            value.board == board &&
            value.deviceName == deviceName,
      ),
      'Polling must retain equal device information.',
    );
    for (var i = 1; i < values.length; i++) {
      check(
        values[i].collectedAt.isAfter(values[i - 1].collectedAt),
        'DeviceInfo polling must stamp each read.',
      );
    }
    final sibling = DeviceAccess.native();
    try {
      check(
        (await sibling.get(Entities.deviceInfo)).modelName == modelName,
        'Independent contexts must read the same model.',
      );
    } finally {
      sibling.dispose();
    }
    check(
      (await sdk.get(Entities.deviceInfo)).deviceName == deviceName &&
          (await sdk.get(Entities.os)).family == OsFamily.windows,
      'Closing a sibling must preserve live device/OS collection.',
    );
    final redacted = snapshot.toJson()..remove('deviceName');
    print(
      'WINDOWS_DEVICE_INFO ${jsonEncode({'snapshot': redacted, 'deviceNameMatches': true, 'cim': cim, 'polls': values.length})}',
    );
  } finally {
    sdk.dispose();
    probe.close();
  }
}

final checks = <String, Future<void> Function()>{
  'native Windows DeviceInfo agrees with independent BIOS, name and CIM queries':
      nativeWindowsDeviceInfo,
};

Future<void> main() => nativeWindowsDeviceInfo();
