part of 'transport_native.dart';

final class _WindowsBatteryPacks {
  final _WindowsBattery battery;
  ffi.Pointer<ffi.Void> _owner = ffi.nullptr;
  ffi.NativeCallable<WindowsNetworkCallback>? _callback;
  int? _token;
  Object? _failure;
  final _listeners = <_WindowsBatteryWatch>{};
  _WindowsBatteryPacks(this.battery);
  bool get released => _owner == ffi.nullptr;

  void _ensure(ReadContext context) {
    context.cancellation.throwIfCancelled();
    if (_failure case final failure?) throw failure;
    if (_owner != ffi.nullptr) return;
    _callback = ffi.NativeCallable<WindowsNetworkCallback>.listener(_changed);
    try {
      final token = createNetworkCallback(_callback!.nativeFunction);
      if (token == 0) throw _error(8);
      _token = token;
      final result = createWindowsPackContext(
        battery._module,
        networkCallbackFunction(),
        token,
      );
      _owner = result.owner;
      if (result.error != 0) throw _error(result.error);
      if (_owner == ffi.nullptr) throw _error(13);
      context.cancellation.throwIfCancelled();
    } catch (error) {
      _failure = error;
      _detach();
      rethrow;
    }
  }

  List<String> list(ReadContext context) {
    _ensure(context);
    final result = readWindowsPackInventory(_owner);
    try {
      context.cancellation.throwIfCancelled();
      if (result.error != 0) throw _error(result.error);
      return [for (var i = 0; i < result.count; i++) 'pack-${result.ids[i]}'];
    } finally {
      freeWindowsPackBuffer(result.ids.cast());
    }
  }

  BatterySnapshot read(String? target, ReadContext context) {
    _ensure(context);
    final id = target != null && target.startsWith('pack-')
        ? int.tryParse(target.substring(5))
        : null;
    if (id == null || id <= 0) throw _error(1167);
    final value = readWindowsPackReport(_owner, id);
    context.cancellation.throwIfCancelled();
    if (value.error != 0) throw _error(value.error);
    final info = value.mask & 1 != 0, status = value.mask & 2 != 0;
    int? available(bool present, int amount) =>
        present && amount != 0xffffffff ? amount : null;
    final full = available(info, value.full),
        remaining = available(status, value.remaining);
    final level = full != null && full > 0 && remaining != null
        ? remaining / full
        : null;
    final knownState =
        status && value.flags & ~0xf == 0 && value.flags & 6 != 6;
    final absolute = info && value.capabilities & 0x40000000 == 0;
    final rate = absolute && status && value.rate != -2147483648
        ? value.rate.toDouble()
        : null;
    final voltage = available(status, value.voltage);
    final temperature = available(value.mask & 4 != 0, value.temperature);
    final seconds = available(value.mask & 8 != 0, value.seconds);
    final chemistry = <int>[];
    var validChemistry = info;
    if (info)
      for (var i = 0; i < 4 && value.chemistry[i] != 0; i++) {
        final char = value.chemistry[i];
        if (char < 32 || char > 126) validChemistry = false;
        chemistry.add(char);
      }
    return BatterySnapshot(
      present: true,
      level: level,
      charging: knownState ? value.flags & 4 != 0 : null,
      state: !knownState
          ? null
          : value.flags & 4 != 0
          ? BatteryState.charging
          : value.flags & 2 != 0
          ? BatteryState.discharging
          : level == 1
          ? BatteryState.full
          : value.flags & 1 != 0
          ? BatteryState.notCharging
          : BatteryState.idle,
      voltageMillivolts: voltage?.toDouble(),
      chargeRateMilliwatts: rate,
      currentMicroamps: voltage != null && voltage > 0 && rate != null
          ? rate / voltage * 1000000
          : null,
      remainingEnergyMilliwattHours: absolute ? remaining?.toDouble() : null,
      fullChargeEnergyMilliwattHours: absolute ? full?.toDouble() : null,
      designEnergyMilliwattHours: absolute
          ? available(info, value.design)?.toDouble()
          : null,
      temperatureCelsius: temperature != null
          ? temperature / 10 - 273.15
          : null,
      timeToEmpty: seconds != null ? Duration(seconds: seconds) : null,
      technology: validChemistry && chemistry.isNotEmpty
          ? String.fromCharCodes(chemistry)
          : null,
      cycleCount: info && value.cycles != 0 && value.cycles != 0xffffffff
          ? BigInt.from(value.cycles)
          : null,
    );
  }

  void add(_WindowsBatteryWatch listener) {
    _ensure(listener.readContext);
    _listeners.add(listener);
  }

  void remove(_WindowsBatteryWatch listener) {
    _listeners.remove(listener);
  }

  void _changed(int token, int valid, int type) {
    acknowledgeNetworkCallback(token);
    if (_token != token) return;
    if (valid != 1 || type != 0) _failure = _error(13);
    for (final listener in _listeners.toList()) {
      if (_failure case final failure?) {
        listener.fail(failure);
      } else {
        listener.changed();
      }
    }
  }

  void _detach() {
    if (_token case final token?) removeNetworkCallback(token);
    _token = null;
    _callback?.close();
    _callback = null;
  }

  void dispose() {
    _detach();
    _listeners.clear();
    if (_owner == ffi.nullptr) return;
    final error = closeWindowsPackContext(_owner);
    if (error != 0) throw _error(error);
    _owner = ffi.nullptr;
  }

  static DeviceReadoutException _error(int code) =>
      DeviceReadoutException(switch (code) {
        5 => ErrorCode.permissionDenied,
        2 || 433 || 1167 => ErrorCode.entityRemoved,
        _ => ErrorCode.readFailed,
      }, 'Windows battery device operation failed (Win32 $code).');
}
