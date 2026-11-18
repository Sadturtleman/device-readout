import 'dart:async';

import 'package:device_readout_flutter/device_readout_flutter.dart' as readout;

import 'windows_cpu_core_reference.dart';

Future<Map<String, Object?>> verifyCpuCores(
  readout.DeviceAccess access,
  String probePath,
) async {
  final probe = WindowsCpuCoreReference(probePath);
  void require(bool value, String reason) {
    if (!value) throw StateError(reason);
  }

  try {
    final expected = probe.read();
    var ticks = 0;
    final timer = Timer.periodic(
      const Duration(milliseconds: 5),
      (_) => ticks++,
    );
    try {
      final targets = await access.cpuCores.list();
      require(
        targets.length == expected.length,
        'CPU-core inventory differs from independent native relations.',
      );
      final values = <readout.CpuCoreSnapshot>[];
      for (final target in targets) {
        values.add(await access.get(target));
      }
      final byIndex = {for (final value in values) value.logicalIndex: value};
      require(
        byIndex.length == expected.length,
        'Logical CPU indices are unique.',
      );
      for (final first in expected) {
        final value = byIndex[first.logical];
        require(
          value != null &&
              value.online == true &&
              value.coreIndex != null &&
              value.packageIndex != null,
          'CPU-core membership and online fields are available.',
        );
        if (first.maximumMhz != null) {
          require(
            value!.maximumClockHz == first.maximumMhz! * 1000000.0 &&
                value.currentClockHz != null &&
                value.currentClockHz!.isFinite &&
                value.currentClockHz! >= 0 &&
                value.currentClockHz! % 1000000 == 0,
            'Core clock fields preserve native MHz units; live current readings can change.',
          );
        }
        for (final second in expected) {
          require(
            (value!.coreIndex == byIndex[second.logical]!.coreIndex) ==
                (first.coreMinimum == second.coreMinimum),
            'Physical-core membership differs from the native reference.',
          );
          require(
            (value.packageIndex == byIndex[second.logical]!.packageIndex) ==
                (first.packageMinimum == second.packageMinimum),
            'Processor-package membership differs from the native reference.',
          );
        }
      }
      final again = await access.cpuCores.list();
      require(
        targets.every(again.contains),
        'Unchanged CPUs keep their handles.',
      );
      require(
        await access.cpuCores.current() == null,
        'A collector-thread CPU is not an application current target.',
      );
      access.observers.current(readout.Entities.cpuCore, targets.first);
      require(
        await access.cpuCores.current() == targets.first,
        'Explicit current CPU selection is retained.',
      );
      final support = await access.capabilities.get(targets.first);
      require(
        support.readable == true && support.watchable == true,
        'Core get/watch capabilities are advertised.',
      );
      final snapshots = await access
          .withPollInterval(const Duration(milliseconds: 25))
          .watch(targets.first)
          .take(3)
          .toList();
      require(
        snapshots.every(
          (value) =>
              value.logicalIndex == values.first.logicalIndex &&
              value.coreIndex == values.first.coreIndex,
        ),
        'Polling keeps the selected logical CPU.',
      );
      for (var i = 1; i < snapshots.length; i++) {
        require(
          snapshots[i].collectedAt.isAfter(snapshots[i - 1].collectedAt),
          'Polling uses fresh collection timestamps.',
        );
      }
      require(
        ticks > 0,
        'The host timer progresses while CPU-core queries run.',
      );
      return {
        'name': 'native CPU-core discovery, topology and clocks',
        'logicalCount': targets.length,
        'coreCount': values.map((value) => value.coreIndex).toSet().length,
        'packageCount': values
            .map((value) => value.packageIndex)
            .toSet()
            .length,
        'sample': values.first.toJson(),
        'snapshots': snapshots.map((value) => value.toJson()).toList(),
        'heartbeatTicks': ticks,
      };
    } finally {
      timer.cancel();
    }
  } finally {
    probe.dispose();
  }
}
