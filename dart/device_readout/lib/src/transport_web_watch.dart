part of 'transport_web.dart';

final class _WebReading {
  final clock = Stopwatch()..start();
  late final Timer deadline;
  _WebReading(Duration timeout, void Function() expire) {
    deadline = Timer(timeout, expire);
  }
  void finish() => deadline.cancel();
}

final class _WebDelivery {
  final JSAny? value;
  final _WebReading reading;
  _WebDelivery(this.value, this.reading);
}

final class _WebWatch {
  final _WebChannel owner;
  final int id;
  final EntityAddress entity;
  final Duration pollInterval, readTimeout;
  final CancellationToken cancellation;
  final _pending = Queue<DeviceSnapshot>();
  final _incoming = Queue<_WebDelivery>();
  final _readings = <_WebReading>{};
  late final StreamController<DeviceSnapshot?> _controller;
  _WebReading? _currentRead;
  bool get expired =>
      _readings.any((read) => read.clock.elapsed >= readTimeout);
  void Function()? _detach;
  bool _closed = false, _paused = false, _scheduled = false;
  bool _processing = false, _ended = false;

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

  _WebReading _reading() {
    // Initial registration already owns a deadline. A duplicate reading header
    // cannot extend it, and a later read cannot reset a queued value's deadline.
    if (_currentRead != null) return _currentRead!;
    final read = _WebReading(readTimeout, () => fail(_readTimeout));
    _readings.add(read);
    return _currentRead = read;
  }

  void receive(JSObject message) {
    if (_closed || _ended) return;
    if (expired) {
      fail(_readTimeout);
      return;
    }
    try {
      switch (message.getProperty<JSAny?>('type'.toJS).dartify()) {
        case 'reading':
          _reading();
        case 'snapshot':
          if (_pending.length + _incoming.length + (_processing ? 1 : 0) >=
              2048) {
            fail(
              const DeviceReadoutException(
                ErrorCode.readFailed,
                'The worker delivery queue is full.',
              ),
            );
            return;
          }
          final reading = _reading();
          _currentRead = null;
          _incoming.add(
            _WebDelivery(message.getProperty<JSAny?>('value'.toJS), reading),
          );
          unawaited(_process());
        case 'error':
          final raw = message.getProperty<JSAny?>('error'.toJS);
          if (raw == null || !raw.isA<JSObject>())
            throw const FormatException('Invalid worker error.');
          final error = raw as JSObject;
          fail(
            _workerError({
              'code': error.getProperty<JSAny?>('code'.toJS).dartify(),
              'message': error.getProperty<JSAny?>('message'.toJS).dartify(),
            }),
          );
        case 'end':
          _ended = true;
          _currentRead?.finish();
          _readings.remove(_currentRead);
          _currentRead = null;
          _finishIfEnded();
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

  Future<void> _process() async {
    if (_processing || _closed) return;
    _processing = true;
    try {
      while (!_closed && _incoming.isNotEmpty) {
        final item = _incoming.removeFirst();
        final budget = WorkerTransferBudget(() {
          if (_closed) throw const DeviceReadoutCancelled();
          if (item.reading.clock.elapsed >= readTimeout) throw _readTimeout;
        });
        final raw = await _decodeJs(item.value, budget) as Map<String, Object?>;
        final snapshot = await hydrateWorkerSnapshot(
          entity.kind,
          raw,
          budget: budget,
        );
        budget.check();
        item.reading.finish();
        _readings.remove(item.reading);
        _pending.add(snapshot);
        _drain();
      }
    } catch (error) {
      if (!_closed)
        fail(
          error is DeviceReadoutException
              ? error
              : const DeviceReadoutException(
                  ErrorCode.readFailed,
                  'Invalid worker stream response.',
                ),
        );
    } finally {
      _processing = false;
      _finishIfEnded();
    }
  }

  void _drain() {
    if (_closed || _paused || _scheduled || _pending.isEmpty) return;
    _scheduled = true;
    Timer.run(() {
      _scheduled = false;
      if (_closed || _paused || _pending.isEmpty) return;
      _controller.add(_pending.removeFirst());
      _drain();
      _finishIfEnded();
    });
  }

  void _finishIfEnded() {
    if (_closed ||
        !_ended ||
        _processing ||
        _incoming.isNotEmpty ||
        _pending.isNotEmpty)
      return;
    _stop();
    unawaited(_controller.close());
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
    for (final reading in _readings) {
      reading.finish();
    }
    _readings.clear();
    _currentRead = null;
    _detach?.call();
    _pending.clear();
    _incoming.clear();
    owner._watches.remove(id);
    try {
      owner._worker?.postMessage({'id': id, 'operation': 'cancel'}.jsify());
    } catch (_) {}
  }
}
