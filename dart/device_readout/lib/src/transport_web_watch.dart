part of 'transport_web.dart';

final class _WebWatch {
  final _WebChannel owner;
  final int id;
  final EntityAddress entity;
  final Duration pollInterval, readTimeout;
  final CancellationToken cancellation;
  final _pending = Queue<DeviceSnapshot>();
  late final StreamController<DeviceSnapshot?> _controller;
  Timer? _deadline;
  Stopwatch? _readingClock;
  bool get expired =>
      _readingClock != null && _readingClock!.elapsed >= readTimeout;
  void Function()? _detach;
  bool _closed = false, _paused = false, _scheduled = false;

  _WebWatch(
    this.owner,
    this.id,
    this.entity,
    this.pollInterval,
    this.readTimeout,
    this.cancellation,
  ) {
    _controller = StreamController<DeviceSnapshot?>(
      onListen: _start,
      onCancel: _stop,
      onPause: () => _paused = true,
      onResume: () {
        _paused = false;
        _drain();
      },
    );
  }
  Stream<DeviceSnapshot?> get stream => _controller.stream;

  void _start() {
    if (owner._closed || cancellation.isCancelled) {
      fail(const DeviceReadoutCancelled());
      return;
    }
    if (owner._failure != null) {
      fail(owner._failure!);
      return;
    }
    if (owner._watches.length >= 128) {
      fail(
        const DeviceReadoutException(
          ErrorCode.readFailed,
          'The bounded worker watch queue is full.',
        ),
      );
      return;
    }
    owner._watches[id] = this;
    _detach = cancellation.listen(() => fail(const DeviceReadoutCancelled()));
    _reading();
    try {
      owner._start();
      final name = entity.kind.name;
      owner._worker!.postMessage(
        {
          'id': id,
          'operation': 'watch',
          'entity': {
            'kind': '${name[0].toUpperCase()}${name.substring(1)}',
            if (entity.targetId != null) 'targetId': entity.targetId,
          },
          'settings': {
            'pollIntervalMs': pollInterval.inMicroseconds / 1000,
            'readTimeoutMs': readTimeout.inMicroseconds / 1000,
            'sensorHertz': null,
          },
        }.jsify(),
      );
    } catch (error) {
      owner._fail(
        error is DeviceReadoutException
            ? error
            : DeviceReadoutException(ErrorCode.readFailed, '$error'),
      );
    }
  }

  void _reading() {
    _readingClock = Stopwatch()..start();
    _deadline?.cancel();
    _deadline = Timer(
      readTimeout,
      () => fail(
        const DeviceReadoutException(
          ErrorCode.readTimeout,
          'A worker state read exceeded its deadline.',
        ),
      ),
    );
  }

  void receive(Map<String, Object?> message) {
    if (_closed) return;
    if (expired) {
      fail(_readTimeout);
      return;
    }
    try {
      switch (message['type']) {
        case 'reading':
          _reading();
        case 'snapshot':
          if (_pending.length >= 2048) {
            fail(
              const DeviceReadoutException(
                ErrorCode.readFailed,
                'The worker delivery queue is full.',
              ),
            );
            return;
          }
          final raw = (message['value'] as Map<Object?, Object?>)
              .cast<String, Object?>();
          final snapshot = hydrateWorkerSnapshot(entity.kind, raw);
          if (expired) {
            fail(_readTimeout);
            return;
          }
          _deadline?.cancel();
          _readingClock = null;
          _pending.add(snapshot);
          _drain();
        case 'error':
          fail(_workerError(message['error']));
        case 'end':
          _stop();
          unawaited(_controller.close());
        default:
          fail(
            const DeviceReadoutException(
              ErrorCode.readFailed,
              'Unexpected worker stream response.',
            ),
          );
      }
    } catch (_) {
      fail(
        const DeviceReadoutException(
          ErrorCode.readFailed,
          'Invalid worker stream response.',
        ),
      );
    }
  }

  void _drain() {
    if (_closed || _paused || _scheduled || _pending.isEmpty) return;
    _scheduled = true;
    scheduleMicrotask(() {
      _scheduled = false;
      if (_closed || _paused || _pending.isEmpty) return;
      _controller.add(_pending.removeFirst());
      _drain();
    });
  }

  void fail(Object error) {
    if (_closed) return;
    _stop();
    _controller.addError(error);
    unawaited(_controller.close());
  }

  void _stop() {
    if (_closed) return;
    _closed = true;
    _deadline?.cancel();
    _detach?.call();
    _pending.clear();
    owner._watches.remove(id);
    try {
      owner._worker?.postMessage({'id': id, 'operation': 'cancel'}.jsify());
    } catch (_) {}
  }
}
