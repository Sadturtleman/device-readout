part of 'transport_native.dart';

final class _NativeStateWatch {
  final _IsolateChannel owner;
  final int id;
  final EntityAddress entity;
  final Duration pollInterval, readTimeout;
  final CancellationToken cancellation;
  final _pending = Queue<DeviceSnapshot?>();
  late final StreamController<DeviceSnapshot?> _controller;
  Timer? _deadline;
  void Function()? _detach;
  bool _sent = false, _closed = false, _paused = false;
  bool _scheduled = false, _ended = false;

  _NativeStateWatch(
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
          'The native watch queue is full.',
        ),
      );
      return;
    }
    owner._watches[id] = this;
    _detach = cancellation.listen(() => fail(const DeviceReadoutCancelled()));
    if (!owner._started) owner._start();
    send();
  }

  void send() {
    if (_closed || _sent || owner._worker == null) return;
    _sent = true;
    owner._worker!.send(['watch', id, entity, pollInterval, readTimeout]);
  }

  void reading() {
    if (_closed) return;
    _deadline?.cancel();
    _deadline = Timer(readTimeout, () {
      fail(
        const DeviceReadoutException(
          ErrorCode.readTimeout,
          'A native state update exceeded its read timeout.',
        ),
      );
    });
  }

  void value(DeviceSnapshot? snapshot) {
    if (_closed) return;
    _deadline?.cancel();
    if (_pending.length >= 2048) {
      fail(
        const DeviceReadoutException(
          ErrorCode.readFailed,
          'The native state delivery queue is full.',
        ),
      );
      return;
    }
    _pending.add(snapshot);
    _drain();
  }

  void done() {
    if (_closed) return;
    _deadline?.cancel();
    _ended = true;
    _drain();
  }

  void _drain() {
    if (_closed || _paused || _scheduled) return;
    _scheduled = true;
    scheduleMicrotask(() {
      _scheduled = false;
      if (_closed || _paused) return;
      if (_pending.isNotEmpty) {
        _controller.add(_pending.removeFirst());
        _drain();
      } else if (_ended) {
        _stop();
        unawaited(_controller.close());
      }
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
    _pending.clear();
    _deadline?.cancel();
    _detach?.call();
    owner._watches.remove(id);
    if (_sent) owner._worker?.send(['unwatch', id]);
  }
}

final class _WorkerStateWatch {
  final int id;
  final EntityAddress entity;
  final StateWatchContext context;
  final SendPort host;
  final Future<DeviceCollector> Function() collector;
  final void Function() finished;
  final _pending = Queue<SnapshotRead>();
  StreamSubscription<SnapshotRead>? _subscription;
  bool _starting = true, _stopping = false, _settled = false;
  bool _reading = false, _scheduled = false, _awaitingAck = false;
  bool _sourceEnded = false, _cancelling = false;

  _WorkerStateWatch(
    this.id,
    this.entity,
    this.context,
    this.host,
    this.collector,
    this.finished,
  );

  Future<void> start() async {
    try {
      final source = await collector();
      if (_stopping) return;
      final updates = source is DeviceStateCollector
          ? (source as DeviceStateCollector).watch(entity, context)
          : null;
      if (updates == null) {
        host.send(['watchFallback', id]);
        stop();
        return;
      }
      _subscription = updates.listen(
        (read) {
          if (_stopping) return;
          if (_pending.length >= 2048) {
            _fail(
              const DeviceReadoutException(
                ErrorCode.readFailed,
                'The native state collection queue is full.',
              ),
            );
            return;
          }
          _pending.add(read);
          _drain();
        },
        onError: (Object error) => _fail(error),
        onDone: () {
          _sourceEnded = true;
          _settle();
        },
      );
    } catch (error) {
      _fail(error);
    } finally {
      _starting = false;
      _drain();
      _settle();
    }
  }

  void acknowledge() {
    _awaitingAck = false;
    _drain();
    _settle();
  }

  void _drain() {
    if (_stopping ||
        _starting ||
        _reading ||
        _scheduled ||
        _awaitingAck ||
        _pending.isEmpty)
      return;
    _scheduled = true;
    scheduleMicrotask(() {
      _scheduled = false;
      if (_stopping || _reading || _awaitingAck || _pending.isEmpty) return;
      unawaited(_read(_pending.removeFirst()));
    });
  }

  Future<void> _read(SnapshotRead read) async {
    _reading = true;
    host.send(['watchReading', id]);
    try {
      final raw = await read();
      if (_stopping) return;
      final snapshot = prepareSnapshot(entity.kind, raw);
      if (_stopping) return;
      _awaitingAck = true;
      host.send(['watchValue', id, snapshot]);
    } catch (error) {
      _fail(error);
    } finally {
      _reading = false;
      _settle();
    }
  }

  void _fail(Object error) {
    if (_stopping) return;
    host.send([
      'watchError',
      id,
      error is DeviceReadoutCancelled ? error : _failure(error),
    ]);
    stop();
  }

  void stop() {
    if (_stopping) return;
    _stopping = true;
    context.cancellation.cancel();
    _pending.clear();
    _awaitingAck = false;
    final subscription = _subscription;
    if (subscription != null) {
      _cancelling = true;
      unawaited(
        Future<void>.sync(subscription.cancel)
            .then<void>((_) {}, onError: (Object _) {})
            .whenComplete(() {
              _cancelling = false;
              _settle();
            }),
      );
    }
    _settle();
  }

  void _settle() {
    if (_settled || _starting || _reading || _cancelling) return;
    if (!_stopping) {
      if (!_sourceEnded || _pending.isNotEmpty || _awaitingAck) return;
      host.send(['watchDone', id]);
      stop();
      return;
    }
    _settled = true;
    finished();
  }
}
