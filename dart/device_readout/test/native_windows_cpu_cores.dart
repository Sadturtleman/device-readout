import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_readout/device_readout.dart';

import 'observers.dart' show check, errorOf;
import '../../../flutter/device_readout_flutter/example/test_support/windows_cpu_core_reference.dart';

Future<void> nativeCpuCores() async {
  if (!Platform.isWindows) return;
  final reference = WindowsCpuCoreReference(
    File('.tools/windows-memory-probe/Release/device_readout_memory_probe.dll')
        .absolute
        .path,
  );
  final sdk = DeviceAccess.native(), other = DeviceAccess.native();
  try {
    final expected = reference.read();
    final targets = await sdk.cpuCores.list();
    check(
      targets.length == expected.length,
      'The public inventory agrees with an independent native topology.',
    );
    final again = await sdk.cpuCores.list();
    check(
      targets.every(again.contains),
      'Unchanged logical CPUs preserve typed handles.',
    );
    check(
      await sdk.cpuCores.current() == null,
      'The collector thread does not choose an application CPU.',
    );
    final values = <CpuCoreSnapshot>[];
    for (final target in targets) {
      values.add(await sdk.get(target));
    }
    final indices = values.map((value) => value.logicalIndex).toSet();
    check(
      indices.length == targets.length &&
          indices.containsAll(expected.map((value) => value.logical)),
      'Logical indices preserve group-relative numbering without duplicates.',
    );
    final byIndex = {for (final value in values) value.logicalIndex!: value};
    for (final first in expected) {
      final value = byIndex[first.logical]!;
      if (first.maximumMhz != null) {
        check(
          value.maximumClockHz == first.maximumMhz! * 1000000.0 &&
              value.currentClockHz != null &&
              value.currentClockHz!.isFinite &&
              value.currentClockHz! >= 0 &&
              value.currentClockHz! % 1000000 == 0,
          'Clocks use native MHz values with distinct maximum/current fields; live current readings may change.',
        );
      }
      check(
        value.online == true &&
            value.coreIndex != null &&
            value.packageIndex != null,
        'Current native topology provides online and membership fields.',
      );
      for (final second in expected) {
        check(
          (value.coreIndex == byIndex[second.logical]!.coreIndex) ==
              (first.coreMinimum == second.coreMinimum),
          'Physical-core membership agrees with the separate native relation query.',
        );
        check(
          (value.packageIndex == byIndex[second.logical]!.packageIndex) ==
              (first.packageMinimum == second.packageMinimum),
          'Package membership agrees with the separate native relation query.',
        );
      }
    }
    final total = await sdk.get(Entities.cpu);
    check(
      total.logicalProcessorCount == values.length &&
          total.physicalCoreCount ==
              values.map((value) => value.coreIndex).toSet().length &&
          total.processorPackageCount ==
              values.map((value) => value.packageIndex).toSet().length,
      'The system snapshot and per-core membership describe the same topology.',
    );
    sdk.observers.current(Entities.cpuCore, targets.first);
    check(
      await sdk.cpuCores.current() == targets.first,
      'Current CPU selection is explicit application state.',
    );
    final foreign = await errorOf(other.get(targets.first));
    check(
      foreign is DeviceReadoutException &&
          foreign.code == ErrorCode.invalidConfiguration,
      'Typed CPU handles remain scoped to their context.',
    );
    final support = await sdk.capabilities.get(targets.first);
    check(
      support.readable == true && support.watchable == true,
      'CPU-core get/watch support is reported.',
    );
    final samples = await sdk
        .withPollInterval(const Duration(milliseconds: 25))
        .watch(targets.first)
        .take(3)
        .toList();
    check(
      samples.every(
        (value) =>
            value.logicalIndex == values.first.logicalIndex &&
            value.coreIndex == values.first.coreIndex,
      ),
      'Core polling keeps the selected CPU and retains equal values.',
    );
    for (var i = 1; i < samples.length; i++) {
      check(
        samples[i].collectedAt.isAfter(samples[i - 1].collectedAt),
        'Every polling snapshot has its completion timestamp.',
      );
    }
    print(
      'WINDOWS_CPU_CORES ${jsonEncode({'logicalCount': values.length, 'coreCount': total.physicalCoreCount, 'packageCount': total.processorPackageCount, 'sample': samples.first.toJson(), 'polls': samples.length})}',
    );
  } finally {
    reference.dispose();
    sdk.dispose();
    other.dispose();
  }
}

final checks = <String, Future<void> Function()>{
  'native Windows CPU-core handles and memberships match independent relations':
      nativeCpuCores,
};
Future<void> main() => nativeCpuCores();
