import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_readout/device_readout.dart';

import 'observers.dart' show check;

Future<Map<String, Object?>> memoryProbe() async {
  final result = await Process.run('powershell.exe', [
    '-NoProfile',
    '-File',
    'tools/verify-windows-memory.ps1',
  ]);
  check(result.exitCode == 0, 'Independent OS probe failed: ${result.stderr}');
  return (jsonDecode(result.stdout as String) as Map).cast<String, Object?>();
}

Future<void> nativeWindowsRam() async {
  if (!Platform.isWindows) return;
  final access = DeviceAccess.native();
  try {
    final before = await memoryProbe();
    final started = DateTime.now().toUtc();
    final snapshot = await access.get(Entities.ram);
    final after = await memoryProbe();
    check(
      snapshot.physicalBytes?.toString() == before['physicalBytes'],
      'Installed bytes must agree with the independent firmware-backed API.',
    );
    check(
      snapshot.kernelAccessibleBytes?.toString() ==
          before['kernelAccessibleBytes'],
      'Kernel-accessible RAM must agree with the independent OS query.',
    );
    final available = snapshot.availableBytes;
    final total = snapshot.kernelAccessibleBytes;
    check(
      available != null &&
          total != null &&
          available >= BigInt.zero &&
          available <= total,
      'Available memory must retain its independent, bounded byte value.',
    );
    final first = BigInt.parse(before['availableBytes']! as String);
    final last = BigInt.parse(after['availableBytes']! as String);
    // These are separate processes and memory changes between observations.
    final tolerance = BigInt.from(1024 * 1024 * 1024);
    check(
      (available! - first).abs() <= tolerance ||
          (available - last).abs() <= tolerance,
      'Available bytes must remain near an independent before/after OS sample.',
    );
    if (before['lowMemory'] == after['lowMemory']) {
      check(
        snapshot.lowMemory == before['lowMemory'],
        'Low-memory state comes from the OS notification.',
      );
    }
    check(
      snapshot.advertisedBytes == null &&
          snapshot.freeBytes == null &&
          snapshot.lowMemoryThresholdBytes == null,
      'Unavailable RAM meanings must not be fabricated from another field.',
    );
    check(
      !snapshot.collectedAt.isBefore(started),
      'Timestamp records this completed read.',
    );
    final support = await access.capabilities.get(Entities.ram);
    check(
      support.readable == true && support.watchable == true,
      'Native RAM supports reads and state polling.',
    );
    print(
      'WINDOWS_RAM ${jsonEncode({'snapshot': snapshot.toJson(), 'before': before, 'after': after})}',
    );
  } finally {
    access.dispose();
  }
}

Future<int> ownHandleCount() async {
  final result = await Process.run('powershell.exe', [
    '-NoProfile',
    '-Command',
    '(Get-Process -Id $pid).HandleCount',
  ]);
  check(result.exitCode == 0, 'The independent process handle probe failed.');
  return int.parse((result.stdout as String).trim());
}

Future<void> nativeWindowsRamLifetime() async {
  if (!Platform.isWindows) return;
  final access = DeviceAccess.native();
  final polling = access.withPollInterval(const Duration(milliseconds: 10));
  var ticks = 0;
  final timer = Timer.periodic(const Duration(milliseconds: 1), (_) => ticks++);
  try {
    final initial = await access.get(Entities.ram);
    // Warm both paths before taking the process-level resource baseline.
    await polling.watch(Entities.ram).take(2).drain<void>();
    final beforeHandles = await ownHandleCount();
    final beforeTicks = ticks;
    final values = await polling.watch(Entities.ram).take(4).toList();
    check(
      values.every(
        (snapshot) => snapshot.physicalBytes == initial.physicalBytes,
      ),
      'Native polling retains equal physical RAM values.',
    );
    for (var i = 1; i < values.length; i++) {
      check(
        values[i].collectedAt.isAfter(values[i - 1].collectedAt),
        'Every native poll has a new completion timestamp.',
      );
    }
    for (var i = 0; i < 100; i++) {
      await access.get(Entities.ram);
    }
    final collectedTicks = ticks - beforeTicks;
    check(
      collectedTicks >= 3,
      'Host timers continue across native reads and polling.',
    );
    final afterHandles = await ownHandleCount();
    check(
      afterHandles <= beforeHandles + 8,
      'Repeated reads must release their notification handles: $beforeHandles -> $afterHandles.',
    );
    final runtime = await access.get(Entities.runtime);
    check(
      runtime.processBitness == 64 &&
          access.pollInterval == const Duration(seconds: 1),
      'Ending RAM watches preserves other native reads and the original configuration.',
    );
    print(
      'WINDOWS_RAM_LIFETIME ${jsonEncode({'beforeHandles': beforeHandles, 'afterHandles': afterHandles, 'hostTicks': collectedTicks, 'polls': values.length, 'reads': 100})}',
    );
  } finally {
    timer.cancel();
    access.dispose();
  }
}

Future<void> nativeWindowsRamContexts() async {
  if (!Platform.isWindows) return;
  final keeper = DeviceAccess.native();
  try {
    final baseline = await keeper.get(Entities.ram);
    for (var i = 0; i < 8; i++) {
      final sibling = DeviceAccess.native();
      try {
        final value = await sibling.get(Entities.ram);
        check(
          value.physicalBytes == baseline.physicalBytes,
          'Independent native contexts must read the same installed RAM.',
        );
      } finally {
        sibling.dispose();
      }
      final retained = await keeper.get(Entities.ram);
      check(
        retained.physicalBytes == baseline.physicalBytes,
        'Closing another native context must preserve live library bindings.',
      );
    }
  } finally {
    keeper.dispose();
  }
}

final checks = <String, Future<void> Function()>{
  'native Windows RAM agrees with independent OS memory queries':
      nativeWindowsRam,
  'native Windows RAM polling keeps host timers and releases notification handles':
      nativeWindowsRamLifetime,
  'closing native Windows RAM contexts preserves independent consumers':
      nativeWindowsRamContexts,
};
