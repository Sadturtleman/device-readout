part of 'core.dart';

typedef SensorObserverCleanup = FutureOr<void> Function();
typedef SensorObserverSubscribe<S extends DeviceSnapshot> =
    FutureOr<SensorObserverCleanup?> Function(SensorObserverSession<S> session);

/// An application-owned source. Setup/cleanup must be nonblocking and must not
/// request permission. Heavy collection belongs in a native worker or isolate.
final class SensorObserverSource<S extends DeviceSnapshot> {
  final SensorObserverSubscribe<S> subscribe;
  final SensorDescription? description;
  const SensorObserverSource({required this.subscribe, this.description});
}

/// A single get/watch demand. Publish actual samples in the schema's units.
final class SensorObserverSession<S extends DeviceSnapshot> {
  final SensorSamplingRate samplingRate;
  final Duration readTimeout;
  final CancellationToken cancellation;
  final void Function(DeviceSnapshot) _publish;
  final void Function(DeviceReadoutException) _fail;
  SensorObserverSession._(
    this.samplingRate,
    this.readTimeout,
    this.cancellation,
    this._publish,
    this._fail,
  );
  void publish(S snapshot) => _publish(snapshot);
  void fail(DeviceReadoutException error) => _fail(error);
}

final class _SensorRegistration {
  SensorDescription? description;
  final FutureOr<SensorObserverCleanup?> Function(
    SensorSamplingRate,
    Duration,
    CancellationToken,
    void Function(DeviceSnapshot),
    void Function(DeviceReadoutException),
  )
  open;
  _SensorRegistration(this.open, this.description);
}

final class _SensorCapture {
  final cancellation = CancellationToken();
  SensorObserverCleanup? _cleanup;
  bool _closed = false;

  void start(
    _SensorRegistration registration,
    SensorSamplingRate rate,
    Duration timeout,
    void Function(DeviceSnapshot) publish,
    void Function(Object) fail,
  ) {
    unawaited(
      Future<SensorObserverCleanup?>.sync(
        () => registration.open(
          rate,
          timeout,
          cancellation,
          (value) {
            if (!_closed) publish(value);
          },
          (error) {
            if (!_closed) fail(error);
          },
        ),
      ).then<void>(
        (cleanup) {
          _cleanup = cleanup;
          if (_closed) _dispose();
        },
        onError: (Object error, StackTrace stack) {
          if (!_closed) fail(_sensorError(error));
        },
      ),
    );
  }

  void close() {
    if (_closed) return;
    _closed = true;
    try {
      cancellation.cancel();
    } catch (_) {
      /* Contain app cancellation hooks. */
    }
    _dispose();
  }

  void _dispose() {
    final cleanup = _cleanup;
    _cleanup = null;
    if (cleanup != null) {
      unawaited(
        Future<void>.sync(cleanup).then<void>(
          (_) {},
          onError: (Object error, StackTrace stack) {
            /* The session is already closed. */
          },
        ),
      );
    }
  }
}

final class _SensorStream<S extends DeviceSnapshot> {
  final DeviceAccess sdk;
  final Entity<S> entity;
  final bool oneShot;
  final CancellationToken? caller;
  final _pending = Queue<DeviceSnapshot>();
  S? _ready;
  var _readCancellation = CancellationToken();
  late final StreamController<S> _controller;
  _SensorCapture? _capture;
  late final _SensorRegistration _source;
  bool _active = false;
  int _epoch = 0;
  void Function()? _detachFailure, _detachLifetime, _detachCaller;
  Timer? _deadline;
  bool _stopped = false, _paused = false, _reading = false, _scheduled = false;

  _SensorStream(this.sdk, this.entity, {this.oneShot = false, this.caller}) {
    _controller = StreamController<S>(
      onListen: _start,
      onCancel: _stop,
      onPause: () {
        _paused = true;
      },
      onResume: () {
        _paused = false;
        _schedule();
      },
    );
  }
  Stream<S> get stream => _controller.stream;

  void _start() {
    try {
      caller?.throwIfCancelled();
      final address = entity._address(sdk._context);
      sdk._context.assertAvailable(address);
      if (!platform.supportsSensorSources) {
        throw const DeviceReadoutException(
          ErrorCode.unsupportedEntity,
          'Sensor observation requires the Dart Web Worker bridge.',
        );
      }
      final source = sdk._context.sensorSources[_key(address)];
      if (source == null) {
        throw const DeviceReadoutException(
          ErrorCode.unsupportedEntity,
          'No sensor observation source is registered for this target.',
        );
      }
      _source = source;
      _detachFailure = sdk._context.listen((change) {
        if (change.affects(address) && change.error != null)
          _fail(change.error!);
      });
      _detachLifetime = sdk._context.lifetime.listen(
        () => _fail(const DeviceReadoutCancelled()),
      );
      _detachCaller = caller?.listen(
        () => _fail(const DeviceReadoutCancelled()),
      );
      if (oneShot) {
        _deadline = Timer(
          sdk.readTimeout,
          () => _fail(
            const DeviceReadoutException(
              ErrorCode.readTimeout,
              'The first sensor sample exceeded its read timeout.',
            ),
          ),
        );
      }
      sdk._context.sensorActivityListeners.add(_activity);
      _activity(sdk._context.sensorsActive);
    } catch (error) {
      _fail(_sensorError(error));
    }
  }

  void _activity(bool active) {
    if (_stopped) return;
    final epoch = ++_epoch;
    _active = active;
    _pending.clear();
    _ready = null;
    _readCancellation.cancel();
    final previous = _capture;
    _capture = null;
    if (!oneShot) _deadline?.cancel();
    previous?.close();
    if (_stopped || !active || epoch != _epoch) return;
    _readCancellation = CancellationToken();
    if (!oneShot && entity.mode == EntityMode.sample) {
      _deadline = Timer(
        sdk.readTimeout,
        () => _fail(
          const DeviceReadoutException(
            ErrorCode.readTimeout,
            'The first active sensor sample exceeded its read timeout.',
          ),
        ),
      );
    }
    final capture = _capture = _SensorCapture();
    capture.start(
      _source,
      !oneShot && entity.mode == EntityMode.sample
          ? sdk.sensorSamplingRate
          : SensorSamplingRate.platformDefault,
      sdk.readTimeout,
      _enqueue,
      _fail,
    );
  }

  void _enqueue(DeviceSnapshot value) {
    if (_stopped || !_active) return;
    if (value.entityKind != entity.kind) {
      _fail(
        const DeviceReadoutException(
          ErrorCode.readFailed,
          'The sensor source published a different snapshot type.',
        ),
      );
      return;
    }
    if (_pending.length >= 2048) {
      _fail(
        const DeviceReadoutException(
          ErrorCode.readFailed,
          'The sensor delivery queue is full.',
        ),
      );
      return;
    }
    _pending.add(value);
    if (oneShot) _capture?.close();
    _schedule();
  }

  void _schedule() {
    if (_stopped ||
        !_active ||
        _paused ||
        _reading ||
        _scheduled ||
        (_pending.isEmpty && _ready == null))
      return;
    _scheduled = true;
    scheduleMicrotask(() {
      _scheduled = false;
      unawaited(_drain());
    });
  }

  Future<void> _drain() async {
    if (_stopped || !_active || _paused || _reading) return;
    final ready = _ready;
    if (ready != null) {
      _ready = null;
      _deliver(ready);
      _schedule();
      return;
    }
    if (_pending.isEmpty) return;
    final epoch = _epoch;
    _reading = true;
    try {
      final value = await sdk._read(
        entity,
        cancellation: _readCancellation,
        captured: _pending.removeFirst(),
      );
      if (!_stopped && epoch == _epoch) {
        _deadline?.cancel();
        // Keep normalized-but-undelivered data inside the lifecycle-owned
        // queue. StreamController's paused buffer cannot be invalidated later.
        if (_paused) {
          _ready = value;
        } else {
          _deliver(value);
        }
      }
    } catch (error) {
      if (epoch == _epoch) _fail(_sensorError(error));
    } finally {
      _reading = false;
    }
    _schedule();
  }

  void _deliver(S value) {
    if (oneShot) _stop();
    _controller.add(value);
    if (oneShot) unawaited(_controller.close());
  }

  void _fail(Object error) {
    if (_stopped) return;
    _stop();
    _controller.addError(_sensorError(error));
    unawaited(_controller.close());
  }

  void _stop() {
    if (_stopped) return;
    _stopped = true;
    _active = false;
    _epoch++;
    _deadline?.cancel();
    _detachFailure?.call();
    _detachLifetime?.call();
    _detachCaller?.call();
    sdk._context.sensorActivityListeners.remove(_activity);
    _capture?.close();
    _pending.clear();
    _ready = null;
    _readCancellation.cancel();
  }
}

Object _sensorError(Object error) =>
    error is DeviceReadoutException || error is DeviceReadoutCancelled
    ? error
    : DeviceReadoutException(ErrorCode.readFailed, error.toString());
