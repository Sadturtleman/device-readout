import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:device_readout/device_readout.dart';

import 'observers.dart' show check;

Future<void> nativeWindowsCpu() async {
  if (!Platform.isWindows) return;
  final probe = ffi.DynamicLibrary.open(
    File('.tools/windows-memory-probe/Release/device_readout_memory_probe.dll')
        .absolute
        .path,
  );
  final sdk = DeviceAccess.native();
  try {
    probe.lookupFunction<ffi.Void Function(), void Function()>(
      'readout_probe_cpu_refresh',
    )();
    final count = probe
        .lookupFunction<ffi.Uint32 Function(ffi.Uint32), int Function(int)>(
          'readout_probe_cpu_count',
        );
    final native = [for (var field = 0; field < 4; field++) count(field)];
    check(
      native.every((value) => value > 0 && value != 0xffffffff),
      'The current host needs readable independent CPU references.',
    );
    final result = await Process.run('powershell.exe', [
      '-NoProfile',
      '-File',
      'tools/verify-windows-cpu.ps1',
    ]);
    check(
      result.exitCode == 0,
      'CIM/registry CPU reference failed: ${result.stderr}',
    );
    final reference =
        jsonDecode(result.stdout as String) as Map<String, dynamic>;
    const fields = [
      'logicalProcessorCount',
      'physicalCoreCount',
      'processorPackageCount',
    ];
    for (var i = 0; i < fields.length; i++) {
      check(
        native[i] == reference[fields[i]],
        'Native and CIM ${fields[i]} must agree.',
      );
    }
    reference['availableLogicalProcessorCount'] = native[3];
    final value = await sdk.get(Entities.cpu);
    void matches(CpuSnapshot snapshot) {
      final json = snapshot.toJson();
      for (final entry in reference.entries) {
        check(
          json[entry.key] == entry.value,
          'CPU ${entry.key}: ${json[entry.key]} != ${entry.value}',
        );
      }
      check(
        snapshot.socModel == null && snapshot.socManufacturer == null,
        'CPU identity is not a SoC identity.',
      );
    }

    matches(value);
    final samples = await sdk
        .withPollInterval(const Duration(milliseconds: 25))
        .watch(Entities.cpu)
        .take(3)
        .toList();
    for (final sample in samples) {
      matches(sample);
    }
    for (var i = 1; i < samples.length; i++) {
      check(
        samples[i].collectedAt.isAfter(samples[i - 1].collectedAt),
        'Each CPU poll has a fresh completion time.',
      );
    }
    final support = await sdk.capabilities.get(Entities.cpu);
    check(
      support.readable == true && support.watchable == true,
      'CPU get/watch must be advertised.',
    );
    print(
      'WINDOWS_CPU ${jsonEncode({'reference': reference, 'snapshot': value.toJson(), 'samples': samples.length})}',
    );
  } finally {
    sdk.dispose();
    probe.close();
  }
}

final checks = <String, Future<void> Function()>{
  'native Windows CPU separates topology and process-default availability':
      nativeWindowsCpu,
};
Future<void> main() => nativeWindowsCpu();
