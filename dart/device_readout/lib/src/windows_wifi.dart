part of 'transport_native.dart';

final class _WindowsWifi {
  final _WindowsConnectivity owner;
  final _pendingClients = <ffi.Pointer<ffi.Void>>[];
  _WindowsWifi(this.owner);
  ffi.Pointer<ffi.Void> get _module => owner._fixture?.handle ?? ffi.nullptr;

  String _key(WindowsWifiRecord record) => List.generate(
    32,
    (index) => record.identity[index].toRadixString(16).padLeft(2, '0'),
  ).join();
  T _inventory<T>(
    ReadContext context,
    T Function(WindowsWifiInventory) read, {
    bool current = false,
  }) {
    context.cancellation.throwIfCancelled();
    owner._ensureContext();
    final result = readWindowsWifiInventory(owner._activation, current ? 1 : 0);
    try {
      context.cancellation.throwIfCancelled();
      if (result.status < 0) throw _error(result.status);
      return read(result);
    } finally {
      freeWindowsWifiInventory(result.records, result.count);
    }
  }

  List<String> list(ReadContext context) => _inventory(
    context,
    (result) => [
      for (var i = 0; i < result.count; i++) _key(result.records[i]),
    ],
  );
  String? current(ReadContext context) => _inventory(
    context,
    (result) =>
        result.current < 0 ? null : _key(result.records[result.current]),
    current: true,
  );

  WifiConnectionSnapshot read(
    String? target,
    ReadContext context,
  ) => _inventory(context, (result) {
    final wlanStatus = _cleanup();
    context.cancellation.throwIfCancelled();
    ffi.Pointer<WindowsWifiRecord>? selected;
    for (var i = 0; i < result.count; i++) {
      if (_key(result.records[i]) == target) selected = result.records + i;
    }
    if (selected == null) throw _removed;
    final status = readWindowsWifiFields(
      owner._activation,
      _module,
      selected,
      wlanStatus,
    );
    final value = selected.ref;
    if (value.retainedClient != ffi.nullptr)
      _pendingClients.add(value.retainedClient);
    context.cancellation.throwIfCancelled();
    if (status < 0) throw value.removed != 0 ? _removed : _error(status);
    // Native profile objects are snapshots. Confirm the selected lifetime still
    // exists after the separate field and WLAN reads.
    if (!list(context).contains(target)) throw _removed;
    return WifiConnectionSnapshot(
      ssid: value.ssidStatus >= 0 && value.ssid != ffi.nullptr
          ? String.fromCharCodes(value.ssid.asTypedList(value.ssidLength))
          : null,
      security: value.securityStatus < 0
          ? null
          : switch (value.authentication) {
              0 || 2 => switch (value.encryption) {
                0 => WifiSecurity.open,
                2 || 3 || 4 => WifiSecurity.wep,
                _ => null,
              },
              3 => WifiSecurity.wep,
              4 || 7 => WifiSecurity.eap,
              5 || 8 => WifiSecurity.psk,
              10 => WifiSecurity.eapWpa3Enterprise192Bit,
              11 => WifiSecurity.sae,
              12 => WifiSecurity.owe,
              13 => WifiSecurity.eapWpa3Enterprise,
              _ => null,
            },
      rssiDbm: value.rssiStatus >= 0 ? value.rssi.toDouble() : null,
    );
  });
  Stream<SnapshotRead> watch(String? target, StateWatchContext context) =>
      owner.watch(
        EntityKind.wifiConnection,
        context,
        read: () => this.read(
          target,
          ReadContext(
            context.cancellation,
            SensorSamplingRate.platformDefault,
            readTimeout: context.readTimeout,
          ),
        ),
      );
  int _cleanup() {
    var error = 0;
    for (final client in _pendingClients.toList()) {
      final status = closeWindowsWifiClient(_module, client);
      if (status >= 0) {
        _pendingClients.remove(client);
      } else {
        if (error == 0) error = status;
      }
    }
    return error;
  }

  void dispose() {
    final status = _cleanup();
    if (status < 0) throw _error(status);
  }

  static const _removed = DeviceReadoutException(
    ErrorCode.entityRemoved,
    'The Wi-Fi connection was removed.',
  );
  static DeviceReadoutException _error(int hr) =>
      _WindowsConnectivity._error(hr);
}
