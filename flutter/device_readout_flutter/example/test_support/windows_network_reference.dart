import 'dart:convert';
import 'dart:io';
import 'dart:ffi' as ffi;

final class WindowsNetworkReference {
  final ffi.DynamicLibrary library;
  WindowsNetworkReference(String path)
    : library = ffi.DynamicLibrary.open(path);
  late final refresh = library
      .lookupFunction<ffi.Uint32 Function(), int Function()>(
        'readout_probe_network_refresh',
      );
  late final count = library
      .lookupFunction<ffi.Uint32 Function(), int Function()>(
        'readout_probe_network_count',
      );
  late final free = library
      .lookupFunction<ffi.Void Function(), void Function()>(
        'readout_probe_network_free',
      );
  late final number = library
      .lookupFunction<
        ffi.Uint64 Function(ffi.Uint32, ffi.Uint32, ffi.Uint32),
        int Function(int, int, int)
      >('readout_probe_network_number');
  late final text = library
      .lookupFunction<
        ffi.Pointer<ffi.Uint16> Function(ffi.Uint32, ffi.Uint32, ffi.Uint32),
        ffi.Pointer<ffi.Uint16> Function(int, int, int)
      >('readout_probe_network_text');
  String? string(int item, int field, int index) {
    final pointer = text(item, field, index);
    if (pointer == ffi.nullptr) return null;
    final units = <int>[];
    for (var i = 0; i < 32768; i++) {
      if (pointer[i] == 0) return String.fromCharCodes(units);
      units.add(pointer[i]);
    }
    throw StateError('Unterminated native reference string.');
  }

  List<Map<String, dynamic>> read() {
    final error = refresh();
    if (error != 0) throw StateError('Native network reference failed: $error');
    return [
      for (var item = 0; item < count(); item++)
        {
          'name': string(item, 0, 0),
          'hardware': string(item, 1, 0),
          'type': number(item, 0, 0),
          'state': number(item, 1, 0),
          'mtu': number(item, 2, 0),
          'ips': [
            for (var i = 0; i < number(item, 3, 0); i++)
              {'address': string(item, 2, i), 'prefix': number(item, 7, i)},
          ],
          'dns': [
            for (var i = 0; i < number(item, 4, 0); i++) string(item, 3, i),
          ],
          'gateways': [
            for (var i = 0; i < number(item, 5, 0); i++) string(item, 4, i),
          ],
          'routes': [
            for (var i = 0; i < number(item, 6, 0); i++)
              {
                'destination': string(item, 5, i),
                'prefix': number(item, 8, i),
                'gateway': string(item, 6, i),
              },
          ],
        },
    ];
  }

  void dispose() {
    try {
      free();
    } finally {
      library.close();
    }
  }
}

/// Test-only independent .NET networking view. No SDK collector code is used.
Future<List<Map<String, dynamic>>> windowsNetworkReference() async {
  final child = await Process.start('powershell.exe', [
    '-NoProfile',
    '-NonInteractive',
    '-WindowStyle',
    'Hidden',
    '-Command',
    r'''
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$rows = @([System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() | ForEach-Object {
  $adapter = $_
  $properties = $adapter.GetIPProperties()
  $hardware = $adapter.GetPhysicalAddress().GetAddressBytes()
  $mtu = if ($adapter.Supports([System.Net.NetworkInformation.NetworkInterfaceComponent]::IPv4)) {
    $properties.GetIPv4Properties().Mtu
  } else { $properties.GetIPv6Properties().Mtu }
  @{
    name = $adapter.Name
    type = [int]$adapter.NetworkInterfaceType
    state = [int]$adapter.OperationalStatus
    # .NET Framework exposes the native ULONG through a signed Int32 property.
    mtu = [BitConverter]::ToUInt32([BitConverter]::GetBytes([int]$mtu), 0)
    hardware = if ($hardware.Length) { ($hardware | ForEach-Object { $_.ToString('X2') }) -join ':' } else { $null }
    ips = @($properties.UnicastAddresses | ForEach-Object { @{ address = $_.Address.ToString(); prefix = $_.PrefixLength } })
    dns = @($properties.DnsAddresses | ForEach-Object { $_.ToString() })
    gateways = @($properties.GatewayAddresses | ForEach-Object { $_.Address.ToString() })
  }
})
ConvertTo-Json -InputObject $rows -Depth 6 -Compress
''',
  ]);
  var terminal = false;
  final output = child.stdout.transform(utf8.decoder).join();
  final errors = child.stderr.transform(utf8.decoder).join();
  try {
    final code = await child.exitCode.timeout(const Duration(seconds: 20));
    terminal = true;
    final stdout = await output, stderr = await errors;
    if (code != 0)
      throw StateError('Independent .NET network reference failed: $stderr');
    return (jsonDecode(stdout) as List).cast<Map<String, dynamic>>();
  } finally {
    if (!terminal) {
      child.kill();
      await child.exitCode;
    }
  }
}
