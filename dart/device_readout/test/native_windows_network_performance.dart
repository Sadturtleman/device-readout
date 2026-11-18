import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_readout/device_readout.dart';

import 'observers.dart' show check;

Future<void> nativeWindowsNetworkPerformance() async {
  if (!Platform.isWindows) return;
  final access = DeviceAccess.native();
  var ticks = 0;
  final timer = Timer.periodic(const Duration(milliseconds: 5), (_) => ticks++);
  try {
    final support = await access.capabilities.get(Entities.networkPerformance);
    check(
      support.readable == true && support.watchable == true,
      'Native Windows NetworkPerformance must expose get/watch.',
    );
    final reference = await Process.run('powershell.exe', [
      '-NoProfile',
      '-File',
      'tools/verify-windows-network-performance.ps1',
    ]);
    check(
      reference.exitCode == 0,
      'Independent WinRT projection failed: ${reference.stderr}',
    );
    final expected = jsonDecode(reference.stdout as String) as Map;
    double? rate(Object? value) =>
        value == null ? null : double.parse(value as String);
    void verify(NetworkPerformanceSnapshot value) {
      check(
        value.downlinkBps == rate(expected['InboundBps']) &&
            value.uplinkBps == rate(expected['OutboundBps']),
        'Native plan rates must agree with an independent projection, including unavailable rates.',
      );
      check(
        value.roundTripTime == null &&
            value.effectiveType == null &&
            value.browserOnline == null,
        'Other performance meanings must remain null.',
      );
    }

    final start = DateTime.now().toUtc();
    final value = await access.get(Entities.networkPerformance);
    verify(value);
    check(!value.collectedAt.isBefore(start), 'Read completion is fresh.');
    final values = await access
        .withPollInterval(const Duration(milliseconds: 25))
        .watch(Entities.networkPerformance)
        .take(3)
        .toList();
    for (var i = 0; i < values.length; i++) {
      verify(values[i]);
      if (i > 0)
        check(
          values[i].collectedAt.isAfter(values[i - 1].collectedAt),
          'Equal and null-rate snapshots retain fresh timestamps.',
        );
    }
    check(
      (await access.get(Entities.networkPath)).connectionState != null &&
          ticks > 2,
      'The shared connectivity context and caller event loop remain usable.',
    );
    print(
      'WINDOWS_NETWORK_PERFORMANCE ${jsonEncode({'snapshot': value.toJson(), 'reference': expected, 'polls': values.length, 'heartbeat': ticks})}',
    );
  } finally {
    timer.cancel();
    access.dispose();
  }
}

final checks = <String, Future<void> Function()>{
  'native Windows performance rates match an independent WinRT projection':
      nativeWindowsNetworkPerformance,
};
Future<void> main() => nativeWindowsNetworkPerformance();
