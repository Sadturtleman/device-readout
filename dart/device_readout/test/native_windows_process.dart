import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:device_readout/device_readout.dart';

import 'observers.dart' show check;

Future<void> nativeProcessMemory() async {
  if (!Platform.isWindows) return;
  final probe = ffi.DynamicLibrary.open(
    File('.tools/windows-memory-probe/Release/device_readout_memory_probe.dll')
        .absolute
        .path,
  );
  final available = probe.lookupFunction<ffi.Uint64 Function(), int Function()>(
    'readout_probe_available_commit',
  );
  final processId = probe.lookupFunction<ffi.Uint32 Function(), int Function()>(
    'readout_probe_process_id',
  );
  BigInt readReference() {
    final bytes = BigInt.from(available()).toUnsigned(64);
    check(
      bytes != (BigInt.one << 64) - BigInt.one,
      'The independently compiled Win32 query failed.',
    );
    return bytes;
  }

  final access = DeviceAccess.native();
  try {
    check(
      processId() == pid,
      'The OS reference must query the SDK consumer process.',
    );
    await access.get(Entities.runtime);
    final before = readReference();
    final started = DateTime.now().toUtc();
    final snapshot = await access.get(Entities.processMemory);
    final after = readReference();
    final bytes = snapshot.allocationRemainingBytes;
    check(
      bytes != null && bytes >= BigInt.zero,
      'The process allocation budget must be an exact nonnegative byte count.',
    );
    final tolerance = BigInt.from(1024 * 1024 * 1024);
    check(
      (bytes! - before).abs() <= tolerance ||
          (bytes - after).abs() <= tolerance,
      'The SDK must read the process commit budget, not physical available RAM.',
    );
    check(
      !snapshot.collectedAt.isBefore(started),
      'The process read must have a completion timestamp.',
    );
    final support = await access.capabilities.get(Entities.processMemory);
    check(
      support.readable == true && support.watchable == true,
      'Process memory must support get/watch.',
    );
    final values = await access
        .withPollInterval(const Duration(milliseconds: 20))
        .watch(Entities.processMemory)
        .take(3)
        .toList();
    check(
      values.every((value) => value.allocationRemainingBytes != null),
      'Every native process poll returns its typed budget.',
    );
    for (var i = 1; i < values.length; i++) {
      check(
        values[i].collectedAt.isAfter(values[i - 1].collectedAt),
        'Process polling must produce fresh snapshots.',
      );
    }
    final ram = await access.get(Entities.ram);
    check(
      ram.physicalBytes != null,
      'Process reads must preserve the shared RAM collector.',
    );
    print(
      'WINDOWS_PROCESS_MEMORY ${jsonEncode({'processId': pid, 'snapshot': snapshot.toJson(), 'before': before.toString(), 'after': after.toString(), 'ramAvailableBytes': ram.availableBytes?.toString(), 'polls': values.length})}',
    );
  } finally {
    access.dispose();
    probe.close();
  }
}

final checks = <String, Future<void> Function()>{
  'native Windows process memory matches an independent same-process OS query':
      nativeProcessMemory,
};
