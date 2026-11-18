import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_readout/device_readout.dart';

import 'observers.dart' show check, errorOf;
import '../../../flutter/device_readout_flutter/example/test_support/windows_network_reference.dart';

Future<void> nativeNetworkInterfaces() async {
  if (!Platform.isWindows) return;
  final elapsed = Stopwatch()..start();
  final referenceProbe = WindowsNetworkReference(
    File('.tools/windows-memory-probe/Release/device_readout_memory_probe.dll')
        .absolute
        .path,
  );
  final expected = referenceProbe.read();
  final dotnet = await windowsNetworkReference();
  final referenceMillis = elapsed.elapsedMilliseconds;
  final access = DeviceAccess.native(), other = DeviceAccess.native();
  var ticks = 0;
  final timer = Timer.periodic(const Duration(milliseconds: 5), (_) => ticks++);
  try {
    final targets = await access.networkInterfaces.list();
    check(
      targets.length == expected.length,
      'Full NDIS inventory agrees with the independent Windows SDK reference (${targets.length}/${expected.length}).',
    );
    final again = await access.networkInterfaces.list();
    check(
      targets.every(again.contains),
      'Inventory retains stable typed handles.',
    );
    check(
      await access.networkInterfaces.current() == null,
      'Network interface selection belongs to the application.',
    );
    final values = <NetworkInterfaceSnapshot>[];
    for (final target in targets) {
      values.add(await access.get(target));
    }
    for (final reference in [...expected, ...dotnet]) {
      final value = values.singleWhere(
        (value) => value.name == reference['name'],
      );
      check(
        value.mtuBytes == BigInt.from(reference['mtu'] as int),
        'MTU agrees with independent reference (${value.mtuBytes}/${reference['mtu']}, native=${expected.contains(reference)}).',
      );
      check(
        value.hardwareAddress == reference['hardware'],
        'Hardware address agrees with .NET.',
      );
      const types = {
        6: NetworkInterfaceType.ethernet,
        26: NetworkInterfaceType.ethernet,
        62: NetworkInterfaceType.ethernet,
        69: NetworkInterfaceType.ethernet,
        117: NetworkInterfaceType.ethernet,
        71: NetworkInterfaceType.wifi,
        24: NetworkInterfaceType.loopback,
        131: NetworkInterfaceType.tunnel,
        23: NetworkInterfaceType.ppp,
        243: NetworkInterfaceType.cellular,
        244: NetworkInterfaceType.cellular,
        209: NetworkInterfaceType.bridge,
      };
      const states = {
        1: NetworkOperationalState.up,
        2: NetworkOperationalState.down,
        3: NetworkOperationalState.testing,
        5: NetworkOperationalState.dormant,
        6: NetworkOperationalState.notPresent,
        7: NetworkOperationalState.lowerLayerDown,
      };
      check(
        value.interfaceType == types[reference['type']],
        'Interface type preserves native meaning.',
      );
      check(
        value.operationalState == states[reference['state']],
        'Operational state agrees with .NET.',
      );
      String ordered(Iterable<Object?> values) =>
          (values.map((v) => '$v').toList()..sort()).join('|');
      check(
        value.ipAddresses != null &&
            ordered(
                  value.ipAddresses!.map(
                    (ip) => '${ip.address}/${ip.prefixLength}',
                  ),
                ) ==
                ordered(
                  (reference['ips'] as List).map(
                    (ip) => '${ip['address']}/${ip['prefix']}',
                  ),
                ),
        'Unicast addresses and prefixes agree with .NET.',
      );
      check(
        value.dnsServers != null &&
            ordered(value.dnsServers!) == ordered(reference['dns'] as List),
        'DNS servers agree with .NET.',
      );
      check(
        value.gateways != null &&
            ordered(value.gateways!) == ordered(reference['gateways'] as List),
        'Gateways agree with .NET.',
      );
      if (reference.containsKey('routes')) {
        final routes = (reference['routes'] as List).map((route) {
          final gateway = route['gateway'];
          return '${route['destination']}/${route['prefix']}=>${gateway == '::' || gateway == '0.0.0.0' ? null : gateway}';
        });
        check(
          value.routes != null &&
              ordered(
                    value.routes!.map(
                      (route) =>
                          '${route.destination}/${route.prefixLength}=>${route.gateway}',
                    ),
                  ) ==
                  ordered(routes),
          'Routes agree with native destinations, prefixes and on-link next hops.',
        );
      }
    }
    check(
      expected.isNotEmpty,
      'The Windows acceptance host has a network interface.',
    );
    access.observers.current(Entities.networkInterface, targets.first);
    check(
      await access.networkInterfaces.current() == targets.first,
      'Application selection is preserved.',
    );
    final foreign = await errorOf(other.get(targets.first));
    check(
      foreign is DeviceReadoutException &&
          foreign.code == ErrorCode.invalidConfiguration,
      'Foreign-context handles are rejected.',
    );
    final capabilities = await access.capabilities.get(targets.first);
    check(
      capabilities.readable == true && capabilities.watchable == true,
      'Native target supports get/watch.',
    );
    final samples = await access
        .withPollInterval(const Duration(milliseconds: 30))
        .watch(targets.first)
        .take(3)
        .toList();
    check(
      samples.every((s) => s.name == values.first.name),
      'Watch retains its selected interface.',
    );
    check(
      samples[2].collectedAt.isAfter(samples[1].collectedAt) && ticks > 0,
      'Snapshots have fresh timestamps while host timers continue.',
    );
    print(
      'WINDOWS_NETWORK ${jsonEncode({'interfaces': targets.length, 'polls': samples.length, 'heartbeat': ticks, 'referenceMillis': referenceMillis, 'elapsedMillis': elapsed.elapsedMilliseconds})}',
    );
  } finally {
    referenceProbe.dispose();
    timer.cancel();
    access.dispose();
    other.dispose();
  }
}

final checks = <String, Future<void> Function()>{
  'Windows native network interfaces match independent OS properties':
      nativeNetworkInterfaces,
};

Future<void> main() => nativeNetworkInterfaces();
