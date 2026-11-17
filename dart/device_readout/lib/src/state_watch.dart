part of 'core.dart';

final class _StateWatch<S extends DeviceSnapshot> {
  final DeviceAccess sdk;
  final Entity<S> entity;
  final _pending = Queue<DeviceSnapshot>();
  final _cancellation = CancellationToken();
  late final StreamController<S> _controller;
  Timer? _pollTimer, _initialDeadline;
  void Function()? _detachChanges, _detachLifetime;
  StreamSubscription<DeviceSnapshot?>? _nativeSubscription;
  final _nativeCancellation = CancellationToken();
  bool _native = false;
  bool _observed = false, _reading = false, _paused = false;
  bool _stopped = false, _scheduled = false;

  _StateWatch(this.sdk, this.entity) {
    _controller = StreamController<S>(
      onListen: _start,
      onCancel: _stop,
      onPause: () {
        _paused = true;
        _pollTimer?.cancel();
        _nativeSubscription?.pause();
      },
      onResume: () {
        _paused = false;
        _nativeSubscription?.resume();
        _schedule();
      },
    );
  }
  Stream<S> get stream => _controller.stream;

  void _start() {
    try {
      if (sdk._context.closed) throw const DeviceReadoutCancelled();
      final address = entity._address(sdk._context);
      sdk._context.assertAvailable(address);
      if (entity.mode != EntityMode.state) {
        throw const DeviceReadoutException(
          ErrorCode.unsupportedEntity,
          'The Dart sensor stream adapter is not implemented.',
        );
      }
      _observed = sdk._context.observed.containsKey(_key(address));
      _detachChanges = sdk._context.listen((change) {
        if (!change.affects(address)) return;
        if (change.error != null) {
          _fail(change.error!);
          return;
        }
        if (change.snapshot != null) _enqueue(change.snapshot!);
      });
      _detachLifetime = sdk._context.lifetime.listen(
        () => _fail(const DeviceReadoutCancelled()),
      );
      _initialDeadline = Timer(
        sdk.readTimeout,
        () => _fail(
          const DeviceReadoutException(
            ErrorCode.readTimeout,
            'The initial snapshot exceeded its read timeout.',
          ),
        ),
      );
      final initial = sdk._context.observed[_key(address)];
      if (initial != null) {
        _enqueue(initial);
      } else if (!_observed) {
        _native = true;
        _nativeSubscription = sdk._context.channel
            .watch(
              sdk._context.nativeAddress(address),
              sdk.pollInterval,
              sdk.readTimeout,
              _nativeCancellation,
              onCollected: () => _initialDeadline?.cancel(),
            )
            .listen(
              (value) {
                if (_stopped || _observed) return;
                if (value == null) {
                  _native = false;
                  _schedule();
                } else {
                  _initialDeadline?.cancel();
                  _controller.add(value as S);
                }
              },
              onError: (Object error, StackTrace stack) {
                if (error is DeviceReadoutException &&
                    error.code == ErrorCode.entityRemoved) {
                  sdk._context.retireNative(address);
                }
                if (!_observed) _fail(error, stack);
              },
              onDone: () {
                if (!_stopped && _native && !_observed) {
                  _stop();
                  unawaited(_controller.close());
                }
              },
            );
        if (_paused) _nativeSubscription!.pause();
      } else {
        _schedule();
      }
    } catch (error, stack) {
      _fail(error, stack);
    }
  }

  void _enqueue(DeviceSnapshot snapshot) {
    if (_stopped) return;
    _nativeCancellation.cancel();
    _native = false;
    _observed = true;
    _pollTimer?.cancel();
    if (_pending.length >= 2048) {
      _fail(
        const DeviceReadoutException(
          ErrorCode.readFailed,
          'The observer delivery queue is full.',
        ),
      );
      return;
    }
    _pending.add(snapshot);
    _schedule();
  }

  void _schedule() {
    if (_stopped || _paused || _reading || _scheduled || _native) return;
    if (_observed && _pending.isEmpty) return;
    _scheduled = true;
    scheduleMicrotask(() {
      _scheduled = false;
      unawaited(_drain());
    });
  }

  Future<void> _drain() async {
    if (_stopped || _paused || _reading) return;
    if (_observed && _pending.isEmpty) return;
    _reading = true;
    try {
      final captured = _pending.isEmpty ? null : _pending.removeFirst();
      final value = await sdk._read(
        entity,
        cancellation: _cancellation,
        captured: captured,
      );
      if (!_stopped) {
        _initialDeadline?.cancel();
        _controller.add(value);
      }
    } catch (error, stack) {
      _fail(error, stack);
    } finally {
      _reading = false;
    }
    if (_stopped || _paused) return;
    if (_pending.isNotEmpty) {
      _schedule();
    } else if (!_observed) {
      _pollTimer = Timer(sdk.pollInterval, _schedule);
    }
  }

  void _fail(Object error, [StackTrace? stack]) {
    if (_stopped) return;
    _stop();
    _controller.addError(error, stack);
    unawaited(_controller.close());
  }

  void _stop() {
    if (_stopped) return;
    _stopped = true;
    _pollTimer?.cancel();
    _initialDeadline?.cancel();
    _detachChanges?.call();
    _detachLifetime?.call();
    _pending.clear();
    _cancellation.cancel();
    _nativeCancellation.cancel();
    unawaited(_nativeSubscription?.cancel());
  }
}
