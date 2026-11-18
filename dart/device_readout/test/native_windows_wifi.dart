import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_readout/device_readout.dart';

import 'observers.dart' show check;

Future<void> nativeWindowsWifi() async {
  if (!Platform.isWindows) return;
  final access = DeviceAccess.native();
  try {
    final targets = await access.list(Entities.wifiConnection);
    final reference = await Process.run('powershell.exe', [
      '-NoProfile',
      '-File',
      'tools/verify-windows-wifi.ps1',
    ]);
    check(
      reference.exitCode == 0,
      'Independent Wi-Fi reference: ${reference.stderr}',
    );
    final expected = jsonDecode(reference.stdout as String) as Map;
    check(
      targets.length == expected['ConnectedWifi'],
      'Only active Wi-Fi connections are listed.',
    );
    final again = await access.list(Entities.wifiConnection);
    check(
      targets.every(again.contains),
      'Repeated discovery preserves typed handles.',
    );
    final current = await access.current(Entities.wifiConnection);
    check(
      (current != null) == expected['PreferredWifi'],
      'Current selects the preferred Wi-Fi profile only.',
    );
    for (final target in targets) {
      final support = await access.capabilities.get(target);
      check(
        support.readable == true && support.watchable == true,
        'Wi-Fi supports typed get/watch.',
      );
      final value = await access.get(target);
      check(
        value.bssid == null &&
            value.frequencyHz == null &&
            value.receiveLinkSpeedBps == null &&
            value.transmitLinkSpeedBps == null,
        'Unmapped fields are not filled with adapter capacity or location-sensitive queries.',
      );
      final values = await access
          .withPollInterval(const Duration(milliseconds: 30))
          .watch(target)
          .take(3)
          .toList();
      check(
        values.length == 3 &&
            values.last.collectedAt.isAfter(values.first.collectedAt),
        'Watch emits fresh polling snapshots.',
      );
    }
    print(
      'WINDOWS_WIFI ${jsonEncode({'targets': targets.length, 'current': current != null, 'reference': expected})}',
    );
  } finally {
    access.dispose();
  }
}

final checks = <String, Future<void> Function()>{
  'native Windows Wi-Fi discovery agrees with independent WinRT profiles':
      nativeWindowsWifi,
};
Future<void> main() => nativeWindowsWifi();
