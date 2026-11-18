part of 'transport_native.dart';

final class _WindowsBattery {
  static const aggregateId = 'os-aggregate';
  final ffi.DynamicLibrary? _fixture;
  ffi.Pointer<ffi.Void> _mta = ffi.nullptr;
  ffi.Pointer<ffi.Void> _owner = ffi.nullptr;
  ffi.NativeCallable<WindowsNetworkCallback>? _callback;
  final _listeners = <_WindowsBatteryWatch>{};
  int? _token;
  Object? _failure;
  bool _unsupportedEvents = false;
  _WindowsBattery(String? library)
    : _fixture = library == null ? null : ffi.DynamicLibrary.open(library);
  ffi.Pointer<ffi.Void> get _module => _fixture?.handle ?? ffi.nullptr;

  void _ensureContext(ReadContext context) {
    context.cancellation.throwIfCancelled();
    if (_mta != ffi.nullptr) return;
    final value = createWindowsConnectivityContext();
    if (value.status < 0) throw _error(value.status);
    _mta = value.owner;
    if (_mta == ffi.nullptr) throw _error(0x80004005);
  }

  String? current(ReadContext context) {
    _ensureContext(context);
    final status = windowsBatteryAvailable(_module);
    context.cancellation.throwIfCancelled();
    if (status < 0) throw _error(status);
    return status == 1 ? null : aggregateId;
  }

  BatterySnapshot read(String? target, ReadContext context) {
    if (target != aggregateId) {
      throw const DeviceReadoutException(
        ErrorCode.unsupportedEntity,
        'This native battery target is not implemented.',
      );
    }
    _ensureContext(context);
    final value = readWindowsAggregateBattery(_module);
    context.cancellation.throwIfCancelled();
    if (value.status < 0) throw _error(value.status);
    final state = value.mask & 16 != 0 ? value.state : null;
    if (state == 0) return BatterySnapshot(present: false);
    int? capacity(int bit, int amount) =>
        value.mask & bit != 0 && amount >= 0 ? amount : null;
    final full = capacity(4, value.full);
    final remaining = capacity(8, value.remaining);
    return BatterySnapshot(
      present: switch (state) {
        1 || 2 || 3 => true,
        _ => null,
      },
      charging: switch (state) {
        1 || 2 => false,
        3 => true,
        _ => null,
      },
      state: switch (state) {
        1 => BatteryState.discharging,
        2 => BatteryState.idle,
        3 => BatteryState.charging,
        _ => null,
      },
      level: full != null && full > 0 && remaining != null
          ? remaining / full
          : null,
      chargeRateMilliwatts: value.mask & 1 != 0 ? value.rate.toDouble() : null,
      designEnergyMilliwattHours: capacity(2, value.design)?.toDouble(),
      fullChargeEnergyMilliwattHours: full?.toDouble(),
      remainingEnergyMilliwattHours: remaining?.toDouble(),
      timeToEmpty: value.mask & 32 != 0
          ? Duration(seconds: value.timeToEmpty)
          : null,
    );
  }

  Stream<SnapshotRead> watch(String? target, StateWatchContext context) =>
      _WindowsBatteryWatch(this, target, context).stream;

  void _add(_WindowsBatteryWatch listener) {
    _ensureContext(listener.readContext);
    if (_listeners.isEmpty && _owner != ffi.nullptr) _release();
    _listeners.add(listener);
    if (_failure != null) throw _failure!;
    if (_owner != ffi.nullptr || _unsupportedEvents) return;
    _callback = ffi.NativeCallable<WindowsNetworkCallback>.listener(_changed);
    try {
      final token = createNetworkCallback(_callback!.nativeFunction);
      if (token == 0) throw _error(0x8007000e);
      _token = token;
      final result = subscribeWindowsBattery(
        _module,
        networkCallbackFunction(),
        token,
      );
      if (result.status < 0) {
        if ((result.status & 0xffffffff) == 0x80004001) {
          _unsupportedEvents = true;
          _detach();
          return;
        }
        throw _error(result.status);
      }
      _owner = result.owner;
      if (_owner == ffi.nullptr) throw _error(0x80004005);
    } catch (error) {
      _detach();
      _failure = error;
      rethrow;
    }
  }

  void _changed(int token, int valid, int type) {
    acknowledgeNetworkCallback(token);
    if (_token != token || _failure != null) return;
    if (valid != 1 || type != 0) _failure = _error(0x80004005);
    for (final listener in _listeners.toList()) {
      if (_failure != null) {
        listener.fail(_failure!);
      } else {
        listener.changed();
      }
    }
  }

  void _remove(_WindowsBatteryWatch listener) {
    _listeners.remove(listener);
    if (_listeners.isEmpty) _release();
  }

  void _detach() {
    if (_token case final token?) removeNetworkCallback(token);
    _token = null;
    _callback?.close();
    _callback = null;
  }

  void _release() {
    _detach();
    _failure = null;
    if (_owner != ffi.nullptr) {
      final status = unsubscribeWindowsBattery(_owner);
      if (status < 0) throw _error(status);
      _owner = ffi.nullptr;
    }
  }

  void dispose() {
    try {
      _release();
    } finally {
      if (_mta != ffi.nullptr) {
        closeWindowsConnectivityContext(_mta);
        _mta = ffi.nullptr;
      }
      if (_owner == ffi.nullptr) _fixture?.close();
    }
  }

  static DeviceReadoutException _error(int hr) => DeviceReadoutException(
    switch (hr & 0xffffffff) {
      0x80070005 => ErrorCode.permissionDenied,
      0x80040154 || 0x80004002 => ErrorCode.unsupportedEntity,
      _ => ErrorCode.readFailed,
    },
    'Windows battery query failed (HRESULT 0x${(hr & 0xffffffff).toRadixString(16)}).',
  );
}

final class _WindowsBatteryWatch {
  final _WindowsBattery owner;
  final String? target;
  final StateWatchContext context;
  late final StreamController<SnapshotRead> _controller;
  Timer? _timer;
  void Function()? _detach;
  Future<void>? _stopped;
  bool _closed = false, _attached = false, _pollQueued = false;
  _WindowsBatteryWatch(this.owner, this.target, this.context) {
    _controller = StreamController<SnapshotRead>(
      onListen: _start,
      onCancel: _stop,
    );
  }
  Stream<SnapshotRead> get stream => _controller.stream;
  ReadContext get readContext => ReadContext(
    context.cancellation,
    SensorSamplingRate.platformDefault,
    readTimeout: context.readTimeout,
  );
  void _start() {
    _detach = context.cancellation.listen(() => unawaited(_stop()));
    if (_closed) return;
    _controller.add(() {
      context.cancellation.throwIfCancelled();
      _attached = true;
      owner._add(this);
      return _read();
    });
  }

  DeviceSnapshot _read() {
    context.cancellation.throwIfCancelled();
    try {
      return owner.read(target, readContext);
    } finally {
      _timer?.cancel();
      if (!_closed && !context.cancellation.isCancelled && !_pollQueued) {
        _timer = Timer(context.pollInterval, () {
          if (_closed || _pollQueued) return;
          _pollQueued = true;
          _controller.add(() {
            _pollQueued = false;
            return _read();
          });
        });
      }
    }
  }

  void changed() {
    if (!_closed) _controller.add(_read);
  }

  void fail(Object error) {
    if (!_closed) _controller.add(() => throw error);
  }

  Future<void> _stop() {
    if (_stopped != null) return _stopped!;
    _closed = true;
    _timer?.cancel();
    _detach?.call();
    unawaited(_controller.close());
    return _stopped = Future<void>.microtask(() {
      if (_attached) {
        _attached = false;
        owner._remove(this);
      }
    });
  }
}
