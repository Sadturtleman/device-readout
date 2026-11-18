import 'dart:async';
import 'dart:convert';

import 'package:device_readout_flutter/device_readout_flutter.dart' as readout;

import 'windows_network_reference.dart';

Future<Map<String, Object?>> verifyNetworkInterfaces(
  readout.DeviceAccess access,
  String probePath,
) async {
  final probe = WindowsNetworkReference(probePath);
  void require(bool value, String reason) {
    if (!value) throw StateError(reason);
  }

  String ordered(Iterable<Object?> values) =>
      (values.map(jsonEncode).toList()..sort()).join('|');
  try {
    final expected = probe.read();
    var ticks = 0;
    final timer = Timer.periodic(
      const Duration(milliseconds: 5),
      (_) => ticks++,
    );
    try {
      final targets = await access.networkInterfaces.list();
      require(
        targets.length == expected.length && targets.isNotEmpty,
        'NDIS inventory agrees with the independent Windows SDK reference.',
      );
      final values = <readout.NetworkInterfaceSnapshot>[];
      for (final target in targets) {
        values.add(await access.get(target));
      }
      const types = {
        6: 'Ethernet',
        26: 'Ethernet',
        62: 'Ethernet',
        69: 'Ethernet',
        117: 'Ethernet',
        71: 'Wifi',
        24: 'Loopback',
        131: 'Tunnel',
        23: 'Ppp',
        243: 'Cellular',
        244: 'Cellular',
        209: 'Bridge',
      };
      const states = {
        1: 'Up',
        2: 'Down',
        3: 'Testing',
        5: 'Dormant',
        6: 'NotPresent',
        7: 'LowerLayerDown',
      };
      var routeCount = 0;
      for (final item in expected) {
        final value = values.singleWhere((v) => v.name == item['name']);
        final json = value.toJson();
        require(
          json['interfaceType'] == types[item['type']] &&
              json['operationalState'] == states[item['state']],
          'Type and state agree with the native reference.',
        );
        require(
          value.hardwareAddress == item['hardware'] &&
              value.mtuBytes == BigInt.from(item['mtu'] as int),
          'Hardware and MTU agree with the native reference.',
        );
        final addresses = (item['ips'] as List).map(
          (ip) => {'address': ip['address'], 'prefixLength': ip['prefix']},
        );
        require(
          value.ipAddresses != null &&
              ordered(json['ipAddresses'] as List) == ordered(addresses),
          'Unicast addresses and prefixes agree.',
        );
        require(
          value.dnsServers != null &&
              ordered(value.dnsServers!) == ordered(item['dns'] as List),
          'DNS addresses agree.',
        );
        require(
          value.gateways != null &&
              ordered(value.gateways!) == ordered(item['gateways'] as List),
          'Gateway addresses agree.',
        );
        final routes = (item['routes'] as List).map(
          (r) => {
            'destination': r['destination'],
            'prefixLength': r['prefix'],
            'gateway': r['gateway'] == '::' || r['gateway'] == '0.0.0.0'
                ? null
                : r['gateway'],
          },
        );
        require(
          value.routes != null &&
              ordered(json['routes'] as List) == ordered(routes),
          'Routes preserve destination, prefix and on-link null gateways.',
        );
        routeCount += value.routes!.length;
      }
      require(
        await access.networkInterfaces.current() == null,
        'Native collection does not choose an application network interface.',
      );
      access.observers.current(
        readout.Entities.networkInterface,
        targets.first,
      );
      require(
        await access.networkInterfaces.current() == targets.first,
        'Application current selection is preserved.',
      );
      final samples = await access
          .withPollInterval(const Duration(milliseconds: 25))
          .watch(targets.first)
          .take(3)
          .toList();
      require(
        samples.every((s) => s.name == values.first.name) &&
            samples.last.collectedAt.isAfter(samples.first.collectedAt),
        'Polling retains the selected interface and emits fresh snapshots.',
      );
      require(
        ticks > 0,
        'The UI isolate timer progresses during network collection.',
      );
      return {
        'name': 'native network-interface discovery, addresses and routes',
        'interfaceCount': targets.length,
        'routeCount': routeCount,
        'fieldsCompared': 9,
        'polls': samples.length,
        'heartbeatTicks': ticks,
      };
    } finally {
      timer.cancel();
    }
  } finally {
    probe.dispose();
  }
}
