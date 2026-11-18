import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:isolate';

import 'package:device_readout_flutter/device_readout_flutter.dart' as readout;

final class _Probe extends ffi.Struct {
  @ffi.Int32()
  external int status;
  @ffi.Int32()
  external int mask;
  @ffi.Int32()
  external int rate;
  @ffi.Int32()
  external int design;
  @ffi.Int32()
  external int full;
  @ffi.Int32()
  external int remaining;
  @ffi.Int32()
  external int state;
  @ffi.Uint32()
  external int time;
}

Map<String, Object?> _reference(String path) {
  final library = ffi.DynamicLibrary.open(path);
  try {
    final v = library.lookupFunction<_Probe Function(), _Probe Function()>(
      'readout_probe_battery',
    )();
    if (v.status != 0)
      throw StateError('Independent aggregate battery projection failed.');
    if (v.state == 0)
      return {
        'present': false,
        'state': null,
        'level': null,
        'chargeRateMilliwatts': null,
        'designEnergyMilliwattHours': null,
        'fullChargeEnergyMilliwattHours': null,
        'remainingEnergyMilliwattHours': null,
        'timeToEmpty': null,
      };
    return {
      'present': v.state >= 1 && v.state <= 3 ? true : null,
      'state': switch (v.state) {
        1 => readout.BatteryState.discharging,
        2 => readout.BatteryState.idle,
        3 => readout.BatteryState.charging,
        _ => null,
      },
      'level':
          v.mask & 12 == 12 &&
              v.full > 0 &&
              v.remaining >= 0 &&
              v.remaining <= v.full
          ? v.remaining / v.full
          : null,
      'chargeRateMilliwatts': v.mask & 1 != 0 ? v.rate : null,
      'designEnergyMilliwattHours': v.mask & 2 != 0 && v.design >= 0
          ? v.design
          : null,
      'fullChargeEnergyMilliwattHours': v.mask & 4 != 0 && v.full >= 0
          ? v.full
          : null,
      'remainingEnergyMilliwattHours': v.mask & 8 != 0 && v.remaining >= 0
          ? v.remaining
          : null,
      'timeToEmpty': v.mask & 32 != 0 ? Duration(seconds: v.time) : null,
    };
  } finally {
    library.close();
  }
}

// These closures capture only a path. Keeping them outside the verification
// scope avoids Dart's shared closure context also retaining SDK target handles.
Future<Map<String, Object?>> _aggregateReference(String path) =>
    Isolate.run(() => _reference(path));
Future<int> _packReference(String path) => Isolate.run(() {
  final library = ffi.DynamicLibrary.open(path);
  try {
    return library.lookupFunction<ffi.Int64 Function(), int Function()>(
      'readout_probe_battery_pack_count',
    )();
  } finally {
    library.close();
  }
});

Future<Map<String, Object?>> verifyAggregateBattery(
  readout.DeviceAccess access,
  String probePath,
) async {
  final target = await access.current(readout.Entities.battery);
  if (target == null)
    throw StateError('The Windows aggregate endpoint is missing.');
  final packCount = await _packReference(probePath);
  final discovered = await access.list(readout.Entities.battery);
  if (packCount < 0 ||
      !discovered.contains(target) ||
      discovered.length != packCount + 1)
    throw StateError(
      'Individual battery discovery disagrees with independent native enumeration.',
    );
  for (final pack in discovered.where((p) => p != target)) {
    if ((await access.get(pack)).present != true)
      throw StateError('A present individual pack is unreadable.');
  }
  final before = await _aggregateReference(probePath);
  final snapshot = await access.get(target);
  final after = await _aggregateReference(probePath);
  final actual = <String, Object?>{
    'present': snapshot.present,
    'state': snapshot.state,
    'level': snapshot.level,
    'chargeRateMilliwatts': snapshot.chargeRateMilliwatts,
    'designEnergyMilliwattHours': snapshot.designEnergyMilliwattHours,
    'fullChargeEnergyMilliwattHours': snapshot.fullChargeEnergyMilliwattHours,
    'remainingEnergyMilliwattHours': snapshot.remainingEnergyMilliwattHours,
    'timeToEmpty': snapshot.timeToEmpty,
  };
  var matched = 0;
  for (final key in before.keys) {
    if (before[key] != after[key]) continue;
    if (actual[key] != before[key])
      throw StateError(
        'Aggregate field $key differs from the native reference.',
      );
    matched++;
  }
  if (matched == 0)
    throw StateError('No stable native field could be compared.');
  if (snapshot.voltageMillivolts != null ||
      snapshot.currentMicroamps != null ||
      snapshot.timeToFull != null)
    throw StateError(
      'Aggregate data must not fabricate pack measurements or charging time.',
    );
  var ticks = 0;
  final timer = Timer.periodic(const Duration(milliseconds: 5), (_) => ticks++);
  try {
    final values = await access
        .withPollInterval(const Duration(milliseconds: 25))
        .watch(target)
        .take(3)
        .toList();
    if (ticks < 2 ||
        values.length != 3 ||
        target != await access.current(readout.Entities.battery))
      throw StateError(
        'Aggregate watch must retain UI progress and endpoint identity.',
      );
    for (var i = 1; i < values.length; i++) {
      if (!values[i].collectedAt.isAfter(values[i - 1].collectedAt))
        throw StateError('Fresh completion time required.');
    }
    return {
      'name': 'native Windows aggregate battery agrees with C++/WinRT',
      'snapshot': snapshot.toJson(),
      'matchedReferenceFields': matched,
      'individualPackCount': packCount,
      'listedCount': discovered.length,
      'polls': values.length,
      'heartbeatTicks': ticks,
    };
  } finally {
    timer.cancel();
  }
}
