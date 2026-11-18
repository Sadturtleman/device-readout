part of 'transport_native.dart';

/// Native WinRT values are collected and released on one worker OS thread.
final class _WindowsConnectivity {
  final ffi.DynamicLibrary? _fixture;
  _WindowsConnectivity(String? library)
    : _fixture = library == null ? null : ffi.DynamicLibrary.open(library);
  late final _activation =
      _fixture?.lookup<ffi.Void>('readout_connectivity_activate') ??
      ffi.nullptr;
  final _listeners = <_WindowsConnectivityWatch>{};
  ffi.Pointer<ffi.Void> _owner = ffi.nullptr;
  ffi.Pointer<ffi.Void> _mta = ffi.nullptr;
  ffi.NativeCallable<WindowsNetworkCallback>? _callback;
  int? _token;
  bool _unsupportedEvents = false;
  Object? _failure;
  _WindowsWifi? _wifi;
  _WindowsWifi get wifi => _wifi ??= _WindowsWifi(this);
  Stream<SnapshotRead> watch(
    EntityKind kind,
    StateWatchContext context, {
    SnapshotRead? read,
  }) => _WindowsConnectivityWatch(this, kind, context, read).stream;

  void _add(_WindowsConnectivityWatch listener) {
    _ensureContext();
    if (_listeners.isEmpty && _owner != ffi.nullptr) _release();
    _listeners.add(listener);
    if (_failure != null) throw _failure!;
    if (_owner != ffi.nullptr || _unsupportedEvents) return;
    _callback = ffi.NativeCallable<WindowsNetworkCallback>.listener(_changed);
    try {
      final token = createNetworkCallback(_callback!.nativeFunction);
      if (token == 0) throw _error(0x8007000e);
      _token = token;
      final result = subscribeWindowsConnectivity(
        _activation,
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

  void _remove(_WindowsConnectivityWatch listener) {
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
      final status = unsubscribeWindowsConnectivity(_owner);
      if (status < 0) throw _error(status);
      _owner = ffi.nullptr;
    }
  }

  NetworkPathSnapshot read(ReadContext context) {
    context.cancellation.throwIfCancelled();
    _ensureContext();
    final result = readWindowsConnectivity(_activation);
    context.cancellation.throwIfCancelled();
    if (result.status < 0) throw _error(result.status);
    if (result.hasProfile == 0)
      return NetworkPathSnapshot(
        connectionState: ConnectionState.disconnected,
        internetValidated: false,
      );
    final level = result.levelStatus >= 0 ? result.level : null;
    final cost = result.costStatus >= 0 ? result.cost : null;
    return NetworkPathSnapshot(
      connectionState: switch (level) {
        0 => ConnectionState.disconnected,
        1 || 2 || 3 => ConnectionState.connected,
        _ => null,
      },
      internetValidated: switch (level) {
        0 || 1 || 2 => false,
        3 => true,
        _ => null,
      },
      metered: switch (cost) {
        1 => false,
        2 || 3 => true,
        _ => null,
      },
    );
  }

  static DeviceReadoutException _error(int hr) => DeviceReadoutException(
    switch (hr & 0xffffffff) {
      0x80070005 => ErrorCode.permissionDenied,
      0x80040154 || 0x80004002 => ErrorCode.unsupportedEntity,
      _ => ErrorCode.readFailed,
    },
    'Windows connectivity query failed (HRESULT 0x${(hr & 0xffffffff).toRadixString(16)}).',
  );
  NetworkPerformanceSnapshot readPerformance(ReadContext context) {
    context.cancellation.throwIfCancelled();
    _ensureContext();
    final result = readWindowsPerformance(_activation);
    context.cancellation.throwIfCancelled();
    if (result.status < 0) throw _error(result.status);
    return NetworkPerformanceSnapshot(
      downlinkBps: result.present & 1 != 0 ? result.inbound : null,
      uplinkBps: result.present & 2 != 0 ? result.outbound : null,
    );
  }

  void _ensureContext() {
    if (_mta != ffi.nullptr) return;
    final result = createWindowsConnectivityContext();
    if (result.status < 0) throw _error(result.status);
    _mta = result.owner;
    if (_mta == ffi.nullptr) throw _error(0x80004005);
  }

  void dispose() {
    try {
      try {
        _wifi?.dispose();
      } finally {
        _release();
      }
    } finally {
      if (_mta != ffi.nullptr) {
        closeWindowsConnectivityContext(_mta);
        _mta = ffi.nullptr;
      }
      // Failed native unregister still owns COM objects from this module.
      if (_owner == ffi.nullptr && (_wifi?._pendingClients.isEmpty ?? true))
        _fixture?.close();
    }
  }
}

final class _WindowsConnectivityWatch {
  final _WindowsConnectivity owner;
  final EntityKind kind;
  final StateWatchContext context;
  final SnapshotRead? readOverride;
  late final StreamController<SnapshotRead> _controller;
  Timer? _timer;
  void Function()? _detach;
  Future<void>? _stopped;
  bool _closed = false, _attached = false, _pollQueued = false;
  _WindowsConnectivityWatch(
    this.owner,
    this.kind,
    this.context,
    this.readOverride,
  ) {
    _controller = StreamController<SnapshotRead>(
      onListen: _start,
      onCancel: _stop,
    );
  }
  Stream<SnapshotRead> get stream => _controller.stream;
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

  FutureOr<DeviceSnapshot> _read() {
    context.cancellation.throwIfCancelled();
    try {
      if (readOverride != null) return readOverride!();
      final readContext = ReadContext(
        context.cancellation,
        SensorSamplingRate.platformDefault,
        readTimeout: context.readTimeout,
      );
      return kind == EntityKind.networkPerformance
          ? owner.readPerformance(readContext)
          : owner.read(readContext);
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
