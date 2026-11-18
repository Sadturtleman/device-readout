import 'dart:ffi' as ffi;

final class WindowsPackContext extends ffi.Struct {
  @ffi.Uint32()
  external int error;
  external ffi.Pointer<ffi.Void> owner;
}

final class WindowsPackInventory extends ffi.Struct {
  @ffi.Uint32()
  external int error;
  @ffi.Uint32()
  external int count;
  external ffi.Pointer<ffi.Uint64> ids;
}

final class WindowsPackReport extends ffi.Struct {
  @ffi.Uint32()
  external int error;
  @ffi.Uint32()
  external int mask;
  @ffi.Uint32()
  external int capabilities;
  @ffi.Uint32()
  external int design;
  @ffi.Uint32()
  external int full;
  @ffi.Uint32()
  external int cycles;
  @ffi.Uint32()
  external int flags;
  @ffi.Uint32()
  external int remaining;
  @ffi.Uint32()
  external int voltage;
  @ffi.Int32()
  external int rate;
  @ffi.Uint32()
  external int temperature;
  @ffi.Uint32()
  external int seconds;
  @ffi.Array(4)
  external ffi.Array<ffi.Uint8> chemistry;
}

@ffi.Native<
  WindowsPackContext Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>,
    ffi.Uint64,
  )
>(
  symbol: 'readout_pack_context_create',
  assetId: 'package:device_readout/src/windows_calls.dart',
)
external WindowsPackContext createWindowsPackContext(
  ffi.Pointer<ffi.Void> module,
  ffi.Pointer<ffi.Void> dispatch,
  int token,
);
@ffi.Native<ffi.Uint32 Function(ffi.Pointer<ffi.Void>)>(
  symbol: 'readout_pack_context_close',
  assetId: 'package:device_readout/src/windows_calls.dart',
)
external int closeWindowsPackContext(ffi.Pointer<ffi.Void> owner);
@ffi.Native<WindowsPackInventory Function(ffi.Pointer<ffi.Void>)>(
  symbol: 'readout_pack_inventory',
  assetId: 'package:device_readout/src/windows_calls.dart',
)
external WindowsPackInventory readWindowsPackInventory(
  ffi.Pointer<ffi.Void> owner,
);
@ffi.Native<WindowsPackReport Function(ffi.Pointer<ffi.Void>, ffi.Uint64)>(
  symbol: 'readout_pack_report',
  assetId: 'package:device_readout/src/windows_calls.dart',
)
external WindowsPackReport readWindowsPackReport(
  ffi.Pointer<ffi.Void> owner,
  int id,
);
@ffi.Native<ffi.Void Function(ffi.Pointer<ffi.Void>)>(
  symbol: 'readout_pack_free',
  assetId: 'package:device_readout/src/windows_calls.dart',
)
external void freeWindowsPackBuffer(ffi.Pointer<ffi.Void> buffer);

final class WindowsBatteryReport extends ffi.Struct {
  @ffi.Int32()
  external int status;
  @ffi.Uint32()
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
  external int timeToEmpty;
}

@ffi.Native<ffi.Int32 Function(ffi.Pointer<ffi.Void>)>(
  symbol: 'readout_battery_available',
  assetId: 'package:device_readout/src/windows_calls.dart',
)
external int windowsBatteryAvailable(ffi.Pointer<ffi.Void> module);

@ffi.Native<WindowsBatteryReport Function(ffi.Pointer<ffi.Void>)>(
  symbol: 'readout_battery_aggregate',
  assetId: 'package:device_readout/src/windows_calls.dart',
)
external WindowsBatteryReport readWindowsAggregateBattery(
  ffi.Pointer<ffi.Void> module,
);

final class WindowsBatteryObservation extends ffi.Struct {
  @ffi.Int32()
  external int status;
  external ffi.Pointer<ffi.Void> owner;
}

@ffi.Native<
  WindowsBatteryObservation Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>,
    ffi.Uint64,
  )
>(
  symbol: 'readout_battery_subscribe',
  assetId: 'package:device_readout/src/windows_calls.dart',
)
external WindowsBatteryObservation subscribeWindowsBattery(
  ffi.Pointer<ffi.Void> module,
  ffi.Pointer<ffi.Void> dispatch,
  int token,
);

@ffi.Native<ffi.Int32 Function(ffi.Pointer<ffi.Void>)>(
  symbol: 'readout_battery_unsubscribe',
  assetId: 'package:device_readout/src/windows_calls.dart',
)
external int unsubscribeWindowsBattery(ffi.Pointer<ffi.Void> owner);

final class WindowsWifiRecord extends ffi.Struct {
  @ffi.Array(32)
  external ffi.Array<ffi.Uint8> identity;
  @ffi.Int32()
  external int ssidStatus;
  @ffi.Int32()
  external int securityStatus;
  @ffi.Int32()
  external int rssiStatus;
  @ffi.Uint32()
  external int ssidLength;
  external ffi.Pointer<ffi.Uint16> ssid;
  @ffi.Int32()
  external int authentication;
  @ffi.Int32()
  external int encryption;
  @ffi.Int32()
  external int rssi;
  @ffi.Int32()
  external int removed;
  external ffi.Pointer<ffi.Void> retainedClient;
}

final class WindowsWifiInventory extends ffi.Struct {
  @ffi.Int32()
  external int status;
  @ffi.Uint32()
  external int count;
  external ffi.Pointer<WindowsWifiRecord> records;
  @ffi.Int32()
  external int current;
}

@ffi.Native<WindowsWifiInventory Function(ffi.Pointer<ffi.Void>, ffi.Int32)>(
  symbol: 'readout_wifi_inventory',
  assetId: 'package:device_readout/src/windows_calls.dart',
)
external WindowsWifiInventory readWindowsWifiInventory(
  ffi.Pointer<ffi.Void> activate,
  int current,
);
@ffi.Native<
  ffi.Int32 Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<WindowsWifiRecord>,
    ffi.Int32,
  )
>(
  symbol: 'readout_wifi_fields',
  assetId: 'package:device_readout/src/windows_calls.dart',
)
external int readWindowsWifiFields(
  ffi.Pointer<ffi.Void> activate,
  ffi.Pointer<ffi.Void> module,
  ffi.Pointer<WindowsWifiRecord> record,
  int wlanStatus,
);
@ffi.Native<ffi.Void Function(ffi.Pointer<WindowsWifiRecord>, ffi.Uint32)>(
  symbol: 'readout_wifi_free',
  assetId: 'package:device_readout/src/windows_calls.dart',
)
external void freeWindowsWifiInventory(
  ffi.Pointer<WindowsWifiRecord> records,
  int count,
);
@ffi.Native<ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>)>(
  symbol: 'readout_wifi_close',
  assetId: 'package:device_readout/src/windows_calls.dart',
)
external int closeWindowsWifiClient(
  ffi.Pointer<ffi.Void> module,
  ffi.Pointer<ffi.Void> client,
);

final class WindowsPerformanceResult extends ffi.Struct {
  @ffi.Int32()
  external int status;
  @ffi.Int32()
  external int present;
  @ffi.Int32()
  external int inboundStatus;
  @ffi.Int32()
  external int outboundStatus;
  @ffi.Double()
  external double inbound;
  @ffi.Double()
  external double outbound;
}

@ffi.Native<WindowsPerformanceResult Function(ffi.Pointer<ffi.Void>)>(
  symbol: 'readout_connectivity_performance',
  assetId: 'package:device_readout/src/windows_calls.dart',
)
external WindowsPerformanceResult readWindowsPerformance(
  ffi.Pointer<ffi.Void> activation,
);

final class WindowsConnectivityResult extends ffi.Struct {
  @ffi.Int32()
  external int status;
  @ffi.Int32()
  external int hasProfile;
  @ffi.Int32()
  external int levelStatus;
  @ffi.Int32()
  external int level;
  @ffi.Int32()
  external int costStatus;
  @ffi.Int32()
  external int cost;
}

@ffi.Native<WindowsConnectivityResult Function(ffi.Pointer<ffi.Void>)>(
  symbol: 'readout_connectivity_read',
  assetId: 'package:device_readout/src/windows_calls.dart',
)
external WindowsConnectivityResult readWindowsConnectivity(
  ffi.Pointer<ffi.Void> activation,
);

final class WindowsConnectivitySubscription extends ffi.Struct {
  @ffi.Int32()
  external int status;
  external ffi.Pointer<ffi.Void> owner;
}

@ffi.Native<
  WindowsConnectivitySubscription Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>,
    ffi.Uint64,
  )
>(
  symbol: 'readout_connectivity_subscribe',
  assetId: 'package:device_readout/src/windows_calls.dart',
)
external WindowsConnectivitySubscription subscribeWindowsConnectivity(
  ffi.Pointer<ffi.Void> activation,
  ffi.Pointer<ffi.Void> dispatch,
  int token,
);
@ffi.Native<ffi.Int32 Function(ffi.Pointer<ffi.Void>)>(
  symbol: 'readout_connectivity_unsubscribe',
  assetId: 'package:device_readout/src/windows_calls.dart',
)
external int unsubscribeWindowsConnectivity(ffi.Pointer<ffi.Void> owner);

@ffi.Native<WindowsConnectivitySubscription Function()>(
  symbol: 'readout_connectivity_context_create',
  assetId: 'package:device_readout/src/windows_calls.dart',
)
external WindowsConnectivitySubscription createWindowsConnectivityContext();
@ffi.Native<ffi.Int32 Function(ffi.Pointer<ffi.Void>)>(
  symbol: 'readout_connectivity_context_close',
  assetId: 'package:device_readout/src/windows_calls.dart',
)
external int closeWindowsConnectivityContext(ffi.Pointer<ffi.Void> cookie);

typedef WindowsNetworkCallback = ffi.Void Function(
  ffi.Uint64,
  ffi.Int32,
  ffi.Uint32,
);

@ffi.Native<
  ffi.Uint64 Function(ffi.Pointer<ffi.NativeFunction<WindowsNetworkCallback>>)
>(
  symbol: 'readout_network_callback_create',
  assetId: 'package:device_readout/src/windows_calls.dart',
)
external int createNetworkCallback(
  ffi.Pointer<ffi.NativeFunction<WindowsNetworkCallback>> listener,
);
@ffi.Native<ffi.Pointer<ffi.Void> Function()>(
  symbol: 'readout_network_callback_function',
  assetId: 'package:device_readout/src/windows_calls.dart',
)
external ffi.Pointer<ffi.Void> networkCallbackFunction();
@ffi.Native<ffi.Void Function(ffi.Uint64)>(
  symbol: 'readout_network_callback_ack',
  assetId: 'package:device_readout/src/windows_calls.dart',
)
external void acknowledgeNetworkCallback(int token);
@ffi.Native<ffi.Void Function(ffi.Uint64)>(
  symbol: 'readout_network_callback_remove',
  assetId: 'package:device_readout/src/windows_calls.dart',
)
external void removeNetworkCallback(int token);

// Ordinals correspond to the internal C ABI; never exposed as entity options.
enum WindowsCall {
  firstVolume,
  nextVolume,
  freeSpace,
  openFile,
  volumeInformation,
  processorTopology,
  processAffinity,
  processCpuSets,
  systemCpuSets,
}

final class WindowsCallResult extends ffi.Struct {
  @ffi.IntPtr()
  external int value;
  @ffi.Uint32()
  external int error;
}

@ffi.Native<
  ffi.Void Function(
    ffi.Int32,
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.UintPtr>,
    ffi.Pointer<WindowsCallResult>,
  )
>(
  symbol: 'readout_win32_call',
  assetId: 'package:device_readout/src/windows_calls.dart',
)
external void _call(
  int kind,
  ffi.Pointer<ffi.Void> function,
  ffi.Pointer<ffi.UintPtr> arguments,
  ffi.Pointer<WindowsCallResult> result,
);

/// Buffer lifetime belongs to the enclosing collection operation.
final class WindowsCalls {
  final ffi.Pointer<ffi.UintPtr> _arguments;
  final ffi.Pointer<WindowsCallResult> _result;
  WindowsCalls(ffi.Pointer<ffi.Void> Function(int) reserve)
    : _arguments = reserve(8 * ffi.sizeOf<ffi.UintPtr>()).cast(),
      _result = reserve(ffi.sizeOf<WindowsCallResult>()).cast();

  int get error => _result.ref.error;
  int invoke(
    WindowsCall kind,
    ffi.Pointer<ffi.Void> function,
    List<int> arguments,
  ) {
    for (var i = 0; i < arguments.length; i++) {
      _arguments[i] = arguments[i];
    }
    _call(kind.index, function, _arguments, _result);
    return _result.ref.value;
  }
}
