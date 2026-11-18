part of 'native_windows_connectivity_faults.dart';

Future<Map<String, Object?>> _wifiExercise(
  String scenario,
  DeviceAccess access,
  int Function(int) counter,
  int Function() emit,
  void Function(int) configure,
  void Function() release,
) async {
  void typed(Object? error, ErrorCode code) => check(
    error is DeviceReadoutException && error.code == code,
    'Expected Wi-Fi $code, got $error.',
  );
  configure(70);
  final targets = await access.list(Entities.wifiConnection);
  check(
    targets.length == 2 && counter(12) == 0,
    'Discovery includes active Wi-Fi only and never queries signal.',
  );
  final first = targets.first;
  if (scenario == 'wifi-permission-observers') {
    var prompts = 0;
    final detach = access.observers.onPermissionRequest((request) {
      prompts++;
    });
    try {
      access.observers.permission(first, PermissionStatus.denied);
      access.observers.failure(
        first,
        const DeviceReadoutException(
          ErrorCode.permissionDenied,
          'App-owned permission state.',
        ),
      );
      typed(await errorOf(access.get(first)), ErrorCode.permissionDenied);
      typed(
        await errorOf(access.watch(first).first),
        ErrorCode.permissionDenied,
      );
      check(
        counter(12) == 0 && prompts == 0,
        'Blocked collection never requests permission or starts WLAN reads.',
      );
      access.observers.permission(first, PermissionStatus.granted);
      access.observers.failure(first, null);
      check(
        (await access.get(first)).ssid == 'First 🚀' && prompts == 0,
        'Fresh app observation permits explicit recovery without UI.',
      );
      return {'implicitPrompts': prompts};
    } finally {
      detach();
    }
  }
  if (scenario.startsWith('wifi-held-') ||
      scenario == 'wifi-cancel' ||
      scenario == 'wifi-dispose') {
    var ticks = 0;
    final timer = Timer.periodic(
      const Duration(milliseconds: 5),
      (_) => ticks++,
    );
    final sibling = DeviceAccess.native(), cancellation = CancellationToken();
    try {
      await sibling.capabilities.get(Entities.ram);
      final phase = scenario.substring(5);
      configure(switch (phase) {
        'held-inventory' => 90,
        'held-identity' => 91,
        'held-ssid' => 92,
        'held-security' => 93,
        'held-open' => 94,
        'held-close' => 96,
        _ => 95,
      });
      final limited = access.withReadTimeout(const Duration(milliseconds: 250));
      final pending = errorOf(
        phase == 'held-inventory'
            ? limited.list(Entities.wifiConnection, cancellation: cancellation)
            : limited.get(first, cancellation: cancellation),
      );
      await _until(() => counter(8) == 1);
      final before = ticks, worker = counter(9), caller = counter(7);
      if (scenario == 'wifi-cancel') cancellation.cancel();
      if (scenario == 'wifi-dispose') access.dispose();
      final error = await pending.timeout(const Duration(seconds: 1));
      if (scenario == 'wifi-cancel' || scenario == 'wifi-dispose') {
        check(
          error is DeviceReadoutCancelled,
          'Cancellation settles while the native call is held.',
        );
      } else {
        typed(error, ErrorCode.readTimeout);
      }
      check(
        (await sibling.get(Entities.ram)).physicalBytes != null,
        'Other contexts remain usable.',
      );
      await _until(() => ticks > before + 2);
      check(
        counter(8) == 1 && worker != caller,
        'Caller progress occurs before native return.',
      );
      access.dispose();
      release();
      await _until(
        () =>
            counter(8) == 0 &&
            counter(0) == 0 &&
            counter(10) == 0 &&
            counter(11) == 0,
      );
      check(
        counter(6) == 0 && counter(15) == 0,
        'Late cleanup balances native ownership without forbidden WLAN queries.',
      );
      return {
        'completedBeforeNativeReturn': true,
        'worker': worker,
        'caller': caller,
        'progress': ticks - before,
        'siblingReadable': true,
        'wlanClients': counter(10),
        'wlanBuffers': counter(11),
      };
    } finally {
      release();
      sibling.dispose();
      timer.cancel();
    }
  }
  if (scenario == 'wifi-fields') {
    check(
      await access.current(Entities.wifiConnection) == first,
      'Current selects the preferred Wi-Fi profile.',
    );
    check(counter(12) == 0, 'Current performs no RSSI query.');
    final firstValue = await access.get(first),
        second = await access.get(targets.last);
    check(
      firstValue.ssid == 'First 🚀' &&
          firstValue.security == WifiSecurity.psk &&
          firstValue.rssiDbm == -47,
      'Selected native SSID, Unicode, authentication and signed RSSI.',
    );
    check(
      second.ssid == 'Second' && second.rssiDbm == -65,
      'Second adapter retains distinct fields.',
    );
    check(
      firstValue.bssid == null &&
          firstValue.frequencyHz == null &&
          firstValue.receiveLinkSpeedBps == null &&
          firstValue.transmitLinkSpeedBps == null,
      'Location-sensitive and unmapped fields remain null.',
    );
    final fixture = ffi.DynamicLibrary.open(
      File(
        '.tools/windows-memory-probe/Release/device_readout_connectivity_fixture.dll',
      ).absolute.path,
    );
    final auth = fixture
        .lookupFunction<
          ffi.Void Function(ffi.Int32, ffi.Int32),
          void Function(int, int)
        >('readout_wifi_auth');
    final authCases = <(int, int, WifiSecurity?)>[
      (0, 0, WifiSecurity.open),
      (2, 0, WifiSecurity.open),
      (2, 2, WifiSecurity.wep),
      (2, 3, WifiSecurity.wep),
      (2, 4, WifiSecurity.wep),
      (2, 1, null),
      (2, 6, null),
      (3, 2, WifiSecurity.wep),
      (4, 6, WifiSecurity.eap),
      (5, 5, WifiSecurity.psk),
      (7, 6, WifiSecurity.eap),
      (8, 6, WifiSecurity.psk),
      (10, 11, WifiSecurity.eapWpa3Enterprise192Bit),
      (11, 10, WifiSecurity.sae),
      (12, 6, WifiSecurity.owe),
      (13, 10, WifiSecurity.eapWpa3Enterprise),
      (1, 0, null),
      (6, 5, null),
      (9, 9, null),
      (99, 6, null),
    ];
    for (final row in authCases) {
      auth(row.$1, row.$2);
      check(
        (await access.get(first)).security == row.$3,
        'Authentication ${row.$1}/${row.$2}.',
      );
    }
    auth(-1, -1);
    for (final row in <(int, String?, WifiSecurity?, double?)>[
      (71, '', WifiSecurity.open, -47),
      (80, null, WifiSecurity.psk, -47),
      (81, 'First 🚀', null, -47),
      (82, 'First 🚀', WifiSecurity.psk, null),
      (84, 'First 🚀', null, -47),
      (85, null, WifiSecurity.psk, -47),
      (86, 'First 🚀', WifiSecurity.psk, 0),
      (88, 'First 🚀', WifiSecurity.psk, null),
      (98, 'First 🚀', WifiSecurity.psk, null),
      (99, 'First 🚀', WifiSecurity.psk, null),
    ]) {
      configure(row.$1);
      final value = await access.get(first);
      check(
        value.ssid == row.$2 &&
            value.security == row.$3 &&
            value.rssiDbm == row.$4,
        'Independent nullable Wi-Fi fields in native mode ${row.$1}.',
      );
    }
    configure(83);
    typed(await errorOf(access.get(first)), ErrorCode.permissionDenied);
    configure(70);
    check(
      (await access.get(first)).ssid == 'First 🚀',
      'Explicit read recovers after field errors.',
    );
    configure(76);
    check(
      await access.current(Entities.wifiConnection) == null,
      'Preferred Ethernet does not select arbitrary Wi-Fi.',
    );
    configure(70);
    final polls = await access
        .withPollInterval(const Duration(milliseconds: 25))
        .watch(first)
        .take(3)
        .toList();
    check(
      polls.every((v) => v.ssid == 'First 🚀') &&
          polls.last.collectedAt.isAfter(polls.first.collectedAt),
      'Equal polling snapshots remain visible.',
    );
    await _until(() => counter(0) == 0 && counter(2) == 0);
    check(
      counter(10) == 0 &&
          counter(11) == 0 &&
          counter(6) == 0 &&
          counter(15) == 0,
      'All field resources released.',
    );
    return {
      'authenticationFixtures': authCases.length,
      'partialFieldFixtures': 10,
      'polls': polls.length,
    };
  }
  if (scenario == 'wifi-lifetimes') {
    for (final mode in [77, 78, 79, 97]) {
      configure(mode);
      typed(
        await errorOf(access.list(Entities.wifiConnection)),
        mode == 77 ? ErrorCode.permissionDenied : ErrorCode.readFailed,
      );
      configure(70);
      check(
        (await access.get(first)).ssid == 'First 🚀',
        'Failed inventories do not retire known targets.',
      );
    }
    configure(73);
    final remaining = await access.list(Entities.wifiConnection);
    check(
      remaining.length == 1 && remaining.single == targets.last,
      'Only the disconnected target is removed.',
    );
    typed(await errorOf(access.get(first)), ErrorCode.entityRemoved);
    configure(70);
    final restored = await access.list(Entities.wifiConnection);
    check(restored.first != first, 'Rediscovery creates a new typed handle.');
    typed(await errorOf(access.get(first)), ErrorCode.entityRemoved);
    configure(74);
    typed(await errorOf(access.get(restored.first)), ErrorCode.entityRemoved);
    final replacement = (await access.list(Entities.wifiConnection)).first;
    check(
      replacement != restored.first,
      'Network replacement on one adapter changes identity.',
    );
    configure(70);
    final active = (await access.list(Entities.wifiConnection)).first;
    final queries = counter(13);
    configure(89);
    typed(await errorOf(access.get(active)), ErrorCode.entityRemoved);
    check(
      counter(13) == queries + 1,
      'Native WLAN removal is observed after selecting the same identity.',
    );
    configure(70);
    check(
      counter(0) == 0 && counter(10) == 0 && counter(11) == 0,
      'Removal and failed inventories release all resources.',
    );
    return {'invalidInventories': 4, 'retiredLifetimes': 3};
  }
  if (scenario == 'wifi-retained-close') {
    configure(87);
    final value = await access.get(first);
    check(
      value.ssid == 'First 🚀' && value.rssiDbm == null && counter(10) == 1,
      'Failed close retains the owned client.',
    );
    final partial = await access.get(first);
    check(
      partial.ssid == 'First 🚀' &&
          partial.security == WifiSecurity.psk &&
          partial.rssiDbm == null,
      'Retained WLAN cleanup failure must not discard independently readable Wi-Fi fields.',
    );
    check(
      counter(12) == 1 && counter(10) == 1,
      'Failed retained cleanup does not open additional clients.',
    );
    configure(70);
    check(
      (await access.get(first)).rssiDbm == -47,
      'A new explicit read retries retained cleanup.',
    );
    check(
      counter(10) == 0 && counter(11) == 0 && counter(14) == 4,
      'Only owned clients are closed, including recovery.',
    );
    return {'cleanupAttempts': counter(14), 'wlanClients': counter(10)};
  }
  final values = <WifiConnectionSnapshot>[],
      errors = <Object>[],
      paths = <NetworkPathSnapshot>[];
  final slow = access.withPollInterval(const Duration(hours: 1));
  final path = slow
      .watch(Entities.networkPath)
      .listen(paths.add, onError: errors.add);
  final wifi = slow.watch(first).listen(values.add, onError: errors.add);
  try {
    await _until(
      () => values.isNotEmpty && paths.isNotEmpty || errors.isNotEmpty,
    );
    check(
      errors.isEmpty && counter(1) == 1,
      'Wi-Fi and path share one status registration.',
    );
    if (scenario == 'wifi-shared-events') {
      configure(72);
      check(emit() == 0, 'Native update starts.');
      await _until(
        () => values.length == 2 && paths.length == 2 || errors.isNotEmpty,
      );
      check(
        errors.isEmpty &&
            values.last.ssid == 'Changed' &&
            values.last.security == WifiSecurity.sae &&
            values.last.rssiDbm == -61,
        'Native event refreshes the selected connection without waiting for polling.',
      );
      check(emit() == 0, 'Equal native event starts.');
      await _until(() => values.length == 3 || errors.isNotEmpty);
      check(
        errors.isEmpty &&
            values.last.collectedAt.isAfter(values[1].collectedAt),
        'Equal event values retain fresh timestamps.',
      );
      await wifi.cancel();
      check(counter(2) == 1, 'Path keeps observation after Wi-Fi closes.');
    } else {
      configure(83);
      check(emit() == 0, 'Failed read starts.');
      await _until(() => errors.isNotEmpty && paths.length == 2);
      typed(errors.single, ErrorCode.permissionDenied);
      configure(70);
      check(emit() == 0, 'Path continues.');
      await _until(() => paths.length == 3);
      check(
        values.length == 1,
        'Failed Wi-Fi stream never restarts implicitly.',
      );
      check(
        (await slow.watch(first).first).ssid == 'First 🚀',
        'Explicit subscription recovers using the shared source.',
      );
    }
  } finally {
    await wifi.cancel();
    await path.cancel();
  }
  await _until(() => counter(2) == 0 && counter(0) == 0);
  check(
    counter(10) == 0 && counter(11) == 0 && counter(6) == 0 && counter(15) == 0,
    'Stream cleanup balances native owners.',
  );
  return {
    'wifiUpdates': values.length,
    'pathUpdates': paths.length,
    'terminalErrors': errors.length,
  };
}
