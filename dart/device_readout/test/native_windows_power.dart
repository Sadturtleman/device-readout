import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:device_readout/device_readout.dart';

import 'observers.dart' show check;

Future<void> nativeWindowsPower() async {
  if (!Platform.isWindows) return;
  final probe = ffi.DynamicLibrary.open(
    File('.tools/windows-memory-probe/Release/device_readout_memory_probe.dll')
        .absolute
        .path,
  );
  final sdk = DeviceAccess.native();
  try {
    final query = probe.lookupFunction<ffi.Uint32 Function(), int Function()>(
      'readout_probe_power_status',
    );
    final structureSize = probe
        .lookupFunction<ffi.Uint32 Function(), int Function()>(
          'readout_probe_power_status_size',
        )();
    check(
      structureSize == 12,
      'The Windows SDK power structure ABI must be 12 bytes.',
    );
    final native = query();
    check(native != 0xffffffff, 'The independent native power query failed.');
    final reference = await Process.run('powershell.exe', [
      '-NoProfile',
      '-File',
      'tools/verify-windows-power.ps1',
    ]);
    check(
      reference.exitCode == 0,
      'Independent Windows Forms query failed: ${reference.stderr}',
    );
    final forms = jsonDecode(reference.stdout as String) as Map;
    check(
      forms['powerLineStatus'] == (native & 255),
      'Windows SDK and Windows Forms power-line readings must agree on this stable host.',
    );
    final batteryClass = probe
        .lookupFunction<ffi.Uint32 Function(), int Function()>(
          'readout_probe_battery_class',
        )();
    final layout = probe.lookupFunction<ffi.Uint32 Function(), int Function()>(
      'readout_probe_power_capabilities_layout',
    )();
    check(
      layout == (76 | (12 << 8) | (30 << 16) | (31 << 24)),
      'The Windows SDK must corroborate capability structure size and field offsets.',
    );
    final expectedSource = switch (native & 255) {
      0 => batteryClass == 1 ? PowerSource.battery : null,
      1 => PowerSource.external,
      _ => null,
    };
    final expectedSaving = switch ((native >> 8) & 255) {
      0 => false,
      1 => true,
      _ => null,
    };
    final started = DateTime.now().toUtc();
    final value = await sdk.get(Entities.power);
    check(
      value.powerSource == expectedSource &&
          value.powerSaveMode == expectedSaving,
      'Power fields must match independent native status, preserving false as a value.',
    );
    check(
      value.thermalState == null,
      'Windows must not invent an Android or Apple thermal stage.',
    );
    check(
      value.collectedAt.isUtc && !value.collectedAt.isBefore(started),
      'Power collection must stamp completion in UTC.',
    );
    final support = await sdk.capabilities.get(Entities.power);
    check(
      support.readable == true && support.watchable == true,
      'The native Windows power collector must advertise get/watch.',
    );
    final values = await sdk
        .withPollInterval(const Duration(milliseconds: 20))
        .watch(Entities.power)
        .take(3)
        .toList();
    check(
      values.every(
        (item) =>
            item.powerSource == expectedSource &&
            item.powerSaveMode == expectedSaving &&
            item.thermalState == null,
      ),
      'Unchanged power values must still be delivered on each poll.',
    );
    for (var i = 1; i < values.length; i++) {
      check(
        values[i].collectedAt.isAfter(values[i - 1].collectedAt),
        'Each power poll must have a fresh completion time.',
      );
    }
    final sibling = DeviceAccess.native();
    try {
      check(
        (await sibling.get(Entities.power)).powerSource == expectedSource,
        'Another context must own a usable native power binding.',
      );
    } finally {
      sibling.dispose();
    }
    check(
      (await sdk.get(Entities.power)).powerSource == expectedSource &&
          (await sdk.get(Entities.locale)).currentLanguageTag != null &&
          (await sdk.get(Entities.ram)).physicalBytes != null,
      'Disposing another context must preserve live power and other collectors.',
    );
    print(
      'WINDOWS_POWER ${jsonEncode({'snapshot': value.toJson(), 'nativeStatus': native, 'structureSize': structureSize, 'batteryClass': batteryClass, 'capabilityLayout': layout, 'forms': forms, 'polls': values.length})}',
    );
  } finally {
    sdk.dispose();
    probe.close();
  }
}

final checks = <String, Future<void> Function()>{
  'native Windows power matches Windows SDK and Forms references':
      nativeWindowsPower,
};

Future<void> main() => nativeWindowsPower();
