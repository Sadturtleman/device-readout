import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';

import 'package:device_readout/device_readout.dart';

import 'observers.dart' show check;

Future<int> _packReference() => Isolate.run(() {
  final library = ffi.DynamicLibrary.open(
    File('.tools/windows-memory-probe/Release/device_readout_memory_probe.dll')
        .absolute
        .path,
  );
  try {
    return library.lookupFunction<ffi.Int64 Function(), int Function()>(
      'readout_probe_battery_pack_count',
    )();
  } finally {
    library.close();
  }
});

Future<void> nativeWindowsAggregateBattery() async {
  if (!Platform.isWindows) return;
  final access = DeviceAccess.native();
  var ticks = 0;
  final timer = Timer.periodic(const Duration(milliseconds: 5), (_) => ticks++);
  try {
    final target = await access.current(Entities.battery);
    check(
      target != null,
      'Windows exposes its logical aggregate battery endpoint.',
    );
    final same = await access
        .withPollInterval(const Duration(milliseconds: 30))
        .current(Entities.battery);
    check(
      target == same,
      'Aggregate handles retain identity across configuration views.',
    );
    final support = await access.capabilities.get(target!);
    check(
      support.readable == true && support.watchable == true,
      'The aggregate endpoint supports get and watch.',
    );
    final packCount = await _packReference();
    final discovered = await access.list(Entities.battery);
    check(
      packCount >= 0 &&
          discovered.contains(target) &&
          discovered.length == packCount + 1,
      'Battery discovery agrees with independent native pack enumeration and includes the logical aggregate.',
    );
    for (final pack in discovered.where((p) => p != target)) {
      check(
        (await access.get(pack)).present == true,
        'Each independently enumerated present pack is readable.',
      );
    }
    final reference = await Process.run('powershell.exe', [
      '-NoProfile',
      '-File',
      'tools/verify-windows-battery.ps1',
    ]);
    check(
      reference.exitCode == 0,
      'Independent battery projection: ${reference.stderr}',
    );
    final expected = jsonDecode(reference.stdout as String) as Map;
    final snapshot = await access.get(target);
    if (expected['Status'] == 0) {
      check(
        snapshot.present == false &&
            snapshot.level == null &&
            snapshot.charging == null &&
            snapshot.state == null &&
            snapshot.chargeRateMilliwatts == null &&
            snapshot.remainingEnergyMilliwattHours == null,
        'A batteryless host preserves the endpoint without fabricated battery values.',
      );
    } else {
      check(
        snapshot.present == true,
        'The OS reports a present aggregate battery.',
      );
    }
    check(
      snapshot.voltageMillivolts == null &&
          snapshot.currentMicroamps == null &&
          snapshot.temperatureCelsius == null &&
          snapshot.timeToFull == null,
      'The aggregate never fabricates pack-specific measurements or charging time.',
    );
    final values = await access
        .withPollInterval(const Duration(milliseconds: 30))
        .watch(target)
        .take(3)
        .toList();
    check(
      values.length == 3 &&
          values.last.collectedAt.isAfter(values.first.collectedAt),
      'State watch retains equal values and fresh completion times.',
    );
    check(
      ticks > 2 && target == await access.current(Entities.battery),
      'Caller progress and the logical aggregate lifetime survive watch cancellation.',
    );
    print(
      'WINDOWS_BATTERY ${jsonEncode({'snapshot': snapshot.toJson(), 'reference': expected, 'individualPackCount': packCount, 'listedCount': discovered.length, 'polls': values.length, 'heartbeat': ticks})}',
    );
  } finally {
    timer.cancel();
    access.dispose();
  }
}

final checks = <String, Future<void> Function()>{
  'native Windows aggregate battery agrees with an independent projection':
      nativeWindowsAggregateBattery,
};
Future<void> main() => nativeWindowsAggregateBattery();
