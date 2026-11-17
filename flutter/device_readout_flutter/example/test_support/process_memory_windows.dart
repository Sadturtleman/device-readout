import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:device_readout_flutter/device_readout_flutter.dart' as readout;

void require(bool condition, String reason) {
  if (!condition) throw StateError(reason);
}

Future<Map<String, Object?>> verifyProcessMemory(
  readout.DeviceAccess access,
  String probePath,
) async {
  final probe = ffi.DynamicLibrary.open(probePath);
  try {
    final processId = probe
        .lookupFunction<ffi.Uint32 Function(), int Function()>(
          'readout_probe_process_id',
        );
    final available = probe
        .lookupFunction<ffi.Uint64 Function(), int Function()>(
          'readout_probe_available_commit',
        );
    BigInt reference() {
      final value = BigInt.from(available()).toUnsigned(64);
      require(
        value != (BigInt.one << 64) - BigInt.one,
        'The independent native process-memory query failed.',
      );
      return value;
    }

    require(
      processId() == pid,
      'The native reference must run inside the Flutter consumer process.',
    );
    final before = reference();
    final started = DateTime.now().toUtc();
    final snapshot = await access.get(readout.Entities.processMemory);
    final after = reference();
    final budget = snapshot.allocationRemainingBytes;
    require(
      budget != null && budget >= BigInt.zero,
      'The native process commit budget must be available and nonnegative.',
    );
    final tolerance = BigInt.from(1024 * 1024 * 1024);
    require(
      (budget! - before).abs() <= tolerance ||
          (budget - after).abs() <= tolerance,
      'ProcessMemory must agree with the same-process native commit query.',
    );
    require(
      !snapshot.collectedAt.isBefore(started),
      'Process memory must carry the completed read timestamp.',
    );
    final support = await access.capabilities.get(
      readout.Entities.processMemory,
    );
    require(
      support.readable == true && support.watchable == true,
      'The Flutter consumer must see native process-memory get/watch support.',
    );
    var ticks = 0;
    final heartbeat = Timer.periodic(
      const Duration(milliseconds: 5),
      (_) => ticks++,
    );
    try {
      final values = await access
          .withPollInterval(const Duration(milliseconds: 20))
          .watch(readout.Entities.processMemory)
          .take(3)
          .toList();
      require(
        values.every((value) => value.allocationRemainingBytes != null),
        'Every process-memory poll must return a budget.',
      );
      for (var index = 1; index < values.length; index++) {
        require(
          values[index].collectedAt.isAfter(values[index - 1].collectedAt),
          'Each process-memory poll must have a fresh timestamp.',
        );
      }
      require(
        ticks >= 2,
        'The Flutter host timer must progress during polling.',
      );
      require(
        (await access.get(readout.Entities.ram)).physicalBytes != null,
        'Ending process-memory polling must preserve the shared RAM collector.',
      );
      return {
        'name':
            'real Windows process memory agrees with same-process native query',
        'processId': pid,
        'snapshot': snapshot.toJson(),
        'before': before.toString(),
        'after': after.toString(),
        'polls': values.length,
        'heartbeatTicks': ticks,
      };
    } finally {
      heartbeat.cancel();
    }
  } finally {
    probe.close();
  }
}
