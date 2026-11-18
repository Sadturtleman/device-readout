part of 'transport_native.dart';

/// Shared native registration per collection context; polling remains per watch.
final class _WindowsNetworkNotifications {
  final _WindowsNetwork owner;
  final _listeners = <_WindowsNetworkWatch>{};
  final _tokens = <int>{};
  final _handles = <ffi.Pointer<ffi.Void>>[];
  ffi.NativeCallable<WindowsNetworkCallback>? _callback;
  Object? _failure;
  _WindowsNetworkNotifications(this.owner);
  late final cancel = owner.ip
      .lookupFunction<
        ffi.Uint32 Function(ffi.Pointer<ffi.Void>),
        int Function(ffi.Pointer<ffi.Void>)
      >('CancelMibChangeNotify2');

  void add(_WindowsNetworkWatch listener) {
    // An explicit later subscription may retry failed cleanup, but must not
    // accumulate another set of OS handles while old ones remain registered.
    if (_listeners.isEmpty && _callback == null && _handles.isNotEmpty)
      dispose();
    _listeners.add(listener);
    if (_failure != null) throw _failure!;
    if (_callback != null) return;
    _callback = ffi.NativeCallable<WindowsNetworkCallback>.listener(_changed);
    try {
      owner._withMemory((reserve) {
        for (final name in [
          'NotifyIpInterfaceChange',
          'NotifyUnicastIpAddressChange',
          'NotifyRouteChange2',
        ]) {
          listener.context.cancellation.throwIfCancelled();
          if (!owner.ip.providesSymbol(name)) continue;
          final register = owner.ip
              .lookupFunction<
                ffi.Uint32 Function(
                  ffi.Uint16,
                  ffi.Pointer<ffi.Void>,
                  ffi.Pointer<ffi.Void>,
                  ffi.Uint8,
                  ffi.Pointer<ffi.Pointer<ffi.Void>>,
                ),
                int Function(
                  int,
                  ffi.Pointer<ffi.Void>,
                  ffi.Pointer<ffi.Void>,
                  int,
                  ffi.Pointer<ffi.Pointer<ffi.Void>>,
                )
              >(name);
          final token = createNetworkCallback(_callback!.nativeFunction);
          if (token == 0) throw _WindowsNetwork._invalid();
          _tokens.add(token);
          final handle = reserve(ffi.sizeOf<ffi.Pointer<ffi.Void>>())
              .cast<ffi.Pointer<ffi.Void>>();
          final error = register(
            0,
            networkCallbackFunction(),
            ffi.Pointer<ffi.Void>.fromAddress(token),
            1,
            handle,
          );
          if (handle.value != ffi.nullptr) _handles.add(handle.value);
          if (error == 50 && handle.value == ffi.nullptr) {
            removeNetworkCallback(token);
            _tokens.remove(token);
            continue;
          }
          if (error != 0) throw _WindowsNetwork._error(error);
          if (handle.value == ffi.nullptr) throw _WindowsNetwork._invalid();
        }
      });
    } catch (error) {
      _failure = error;
      rethrow;
    }
  }

  void _changed(int token, int hasRow, int type) {
    acknowledgeNetworkCallback(token);
    if (!_tokens.contains(token) || _failure != null || type == 3) return;
    if (type > 2 || hasRow == 0) {
      final error = const DeviceReadoutException(
        ErrorCode.readFailed,
        'Invalid or overflowing Windows network notification.',
      );
      _failure = error;
      for (final listener in _listeners.toList()) {
        listener.fail(error);
      }
      return;
    }
    // Partial, OS-owned rows are intentionally not retained or dereferenced.
    // A protocol row deletion is an invalidation, not proof of adapter removal.
    for (final listener in _listeners.toList()) {
      listener.changed();
    }
  }

  void remove(_WindowsNetworkWatch listener) {
    _listeners.remove(listener);
    if (_listeners.isEmpty) dispose();
  }

  void dispose() {
    for (final token in _tokens) {
      removeNetworkCallback(token);
    }
    _tokens.clear();
    _callback?.close();
    _callback = null;
    // Tokens are detached before unregister: no callback may enter a closed
    // Dart trampoline, including after an OS unregister failure.
    Object? failure;
    final remaining = <ffi.Pointer<ffi.Void>>[];
    for (final handle in _handles) {
      try {
        final error = cancel(handle);
        if (error != 0) {
          remaining.add(handle);
          failure ??= _WindowsNetwork._error(error);
        }
      } catch (error) {
        remaining.add(handle);
        failure ??= error;
      }
    }
    _handles
      ..clear()
      ..addAll(remaining);
    _failure = null;
    if (failure != null) throw failure;
  }
}

final class _WindowsNetworkWatch {
  final _WindowsNetwork owner;
  final String? target;
  final StateWatchContext context;
  late final StreamController<SnapshotRead> _controller;
  Timer? _timer;
  void Function()? _detach;
  Future<void>? _stopped;
  bool _closed = false, _attached = false, _pollQueued = false;
  _WindowsNetworkWatch(this.owner, this.target, this.context) {
    _controller = StreamController<SnapshotRead>(
      onListen: _start,
      onCancel: _stop,
    );
  }
  Stream<SnapshotRead> get stream => _controller.stream;
  void _start() {
    _detach = context.cancellation.listen(() {
      unawaited(_stop());
    });
    if (_closed) return;
    _controller.add(() {
      context.cancellation.throwIfCancelled();
      _attached = true;
      (owner._notifications ??= _WindowsNetworkNotifications(owner)).add(this);
      return _read();
    });
  }

  DeviceSnapshot _read() {
    context.cancellation.throwIfCancelled();
    try {
      return owner.read(
        target,
        ReadContext(
          context.cancellation,
          SensorSamplingRate.platformDefault,
          readTimeout: context.readTimeout,
        ),
      );
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
    // The cancellation listener only schedules teardown. Native unregister can
    // block, so the worker owns it and the host never joins it.
    return _stopped = Future<void>.microtask(() {
      if (_attached) {
        _attached = false;
        owner._notifications?.remove(this);
      }
    });
  }
}
