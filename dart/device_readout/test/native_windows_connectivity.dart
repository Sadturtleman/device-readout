import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_readout/device_readout.dart';

import 'observers.dart' show check;

Future<void> nativeWindowsConnectivity() async {
  if (!Platform.isWindows) return;
  final sdk = DeviceAccess.native();
  var heartbeat = 0;
  final timer = Timer.periodic(
    const Duration(milliseconds: 5),
    (_) => heartbeat++,
  );
  try {
    final support = await sdk.capabilities.get(Entities.networkPath);
    check(
      support.readable == true && support.watchable == true,
      'Windows must expose NetworkPath get/watch.',
    );
    final reference = await Process.run('powershell.exe', [
      '-NoProfile',
      '-File',
      'tools/verify-windows-connectivity.ps1',
    ]);
    check(
      reference.exitCode == 0,
      'Independent WinRT projection failed: ${reference.stderr}',
    );
    final expected = jsonDecode(reference.stdout as String) as Map;
    final level = expected['HasProfile'] == false
        ? 0
        : expected['Connectivity'];
    final connection = switch (level) {
      0 => ConnectionState.disconnected,
      1 || 2 || 3 => ConnectionState.connected,
      _ => null,
    };
    final validated = switch (level) {
      0 || 1 || 2 => false,
      3 => true,
      _ => null,
    };
    final metered = switch (expected['Cost']) {
      1 => false,
      2 || 3 => true,
      _ => null,
    };
    void verify(NetworkPathSnapshot value) {
      check(
        value.connectionState == connection &&
            value.internetValidated == validated &&
            value.metered == metered,
        'Preferred-path fields must agree with an independent WinRT projection on this stable host.',
      );
      check(
        value.transports == null &&
            value.expensive == null &&
            value.constrained == null &&
            value.saveData == null &&
            value.supportsIpv4 == null &&
            value.supportsIpv6 == null &&
            value.supportsDns == null &&
            value.captivePortal == null,
        'Unavailable path meanings must remain null.',
      );
    }

    final start = DateTime.now().toUtc();
    final snapshot = await sdk.get(Entities.networkPath);
    verify(snapshot);
    check(
      !snapshot.collectedAt.isBefore(start),
      'Read completion must be fresh.',
    );
    final stream = sdk.withPollInterval(const Duration(milliseconds: 25));
    final values = await stream.watch(Entities.networkPath).take(3).toList();
    for (var index = 0; index < values.length; index++) {
      verify(values[index]);
      if (index > 0)
        check(
          values[index].collectedAt.isAfter(values[index - 1].collectedAt),
          'Equal values must still receive fresh completion timestamps.',
        );
    }
    final sibling = DeviceAccess.native();
    try {
      verify(await sibling.get(Entities.networkPath));
    } finally {
      sibling.dispose();
    }
    verify(await sdk.get(Entities.networkPath));
    check(
      (await sdk.get(Entities.ram)).physicalBytes != null && heartbeat > 2,
      'Other collectors and the caller event loop must remain usable.',
    );
    print(
      'WINDOWS_CONNECTIVITY ${jsonEncode({'snapshot': snapshot.toJson(), 'reference': expected, 'polls': values.length, 'heartbeat': heartbeat})}',
    );
  } finally {
    timer.cancel();
    sdk.dispose();
  }
}

final checks = <String, Future<void> Function()>{
  'native Windows preferred path matches an independent WinRT projection':
      nativeWindowsConnectivity,
};
Future<void> main() => nativeWindowsConnectivity();
