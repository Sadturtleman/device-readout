import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:device_readout/device_readout.dart';

import 'observers.dart' show check;

Future<void> nativeWindowsTimeZone() async {
  if (!Platform.isWindows) return;
  final probe = ffi.DynamicLibrary.open(
    File('.tools/windows-memory-probe/Release/device_readout_memory_probe.dll')
        .absolute
        .path,
  );
  final sdk = DeviceAccess.native();
  try {
    final refresh = probe.lookupFunction<ffi.Int32 Function(), int Function()>(
      'readout_probe_time_zone_refresh',
    );
    check(refresh() == 1, 'The independent native time-zone query failed.');
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
    final reference = await Process.run('powershell.exe', [
      '-NoProfile',
      '-File',
      'tools/verify-windows-time-zone.ps1',
    ]);
    check(
      reference.exitCode == 0,
      'Independent time-zone query failed: ${reference.stderr}',
    );
    final dotnet = jsonDecode(reference.stdout as String) as Map;
    check(
      dotnet['windowsId'] == windows &&
          dotnet['utcOffsetSeconds'] == offset &&
          dotnet['daylightSavingTime'] == daylight,
      'Independent Windows conversion and .NET time-zone data must agree.',
    );
    final started = DateTime.now().toUtc();
    final snapshot = await sdk.get(Entities.timeZone);
    check(
      snapshot.windowsId == windows &&
          snapshot.ianaId == iana &&
          snapshot.utcOffsetSeconds == offset &&
          snapshot.daylightSavingTime == daylight,
      'Time-zone fields must match independent native conversion and ICU mapping.',
    );
    check(
      !snapshot.collectedAt.isBefore(started),
      'Time-zone reads must stamp completion.',
    );
    final support = await sdk.capabilities.get(Entities.timeZone);
    check(
      support.readable == true && support.watchable == true,
      'TimeZone must advertise native get/watch.',
    );
    final values = await sdk
        .withPollInterval(const Duration(milliseconds: 20))
        .watch(Entities.timeZone)
        .take(3)
        .toList();
    check(
      values.every(
        (value) =>
            value.windowsId == windows &&
            value.ianaId == iana &&
            value.utcOffsetSeconds == offset &&
            value.daylightSavingTime == daylight,
      ),
      'Unchanged time-zone values must be delivered on every poll.',
    );
    for (var i = 1; i < values.length; i++) {
      check(
        values[i].collectedAt.isAfter(values[i - 1].collectedAt),
        'Time-zone polls must carry fresh completion times.',
      );
    }
    final other = DeviceAccess.native();
    try {
      check(
        (await other.get(Entities.timeZone)).ianaId == iana,
        'Each context must own its native time-zone binding.',
      );
    } finally {
      other.dispose();
    }
    check(
      (await sdk.get(Entities.timeZone)).windowsId == windows &&
          (await sdk.get(Entities.deviceInfo)).deviceName != null,
      'Closing a sibling must preserve live time-zone and device reads.',
    );
    print(
      'WINDOWS_TIME_ZONE ${jsonEncode({'snapshot': snapshot.toJson(), 'reference': dotnet, 'nativeIana': iana, 'polls': values.length})}',
    );
  } finally {
    sdk.dispose();
    probe.close();
  }
}

final checks = <String, Future<void> Function()>{
  'native Windows time zone agrees with independent local-time conversion and ICU':
      nativeWindowsTimeZone,
};

Future<void> main() => nativeWindowsTimeZone();
