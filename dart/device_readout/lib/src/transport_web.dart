import 'dart:async';
import 'dart:collection';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'core.dart';
import 'transport_api.dart';
import 'transport_stub.dart' as unsupported;

part 'transport_web_watch.dart';

// Closures cannot be transferred into browser workers. Keep the explicit
// isolate factory unsupported; web() supplies a separately built module asset.
CollectionChannel createChannel(
  CollectorFactory factory,
  Object? initialData,
) => unsupported.createChannel(factory, initialData);
DeviceCollector createNativeCollector(Object? data) =>
    unsupported.createNativeCollector(data);
CollectionChannel createWebChannel(Uri workerUri) => _WebChannel(workerUri);

@JS('Worker')
extension type _Worker._(JSObject _) implements JSObject {
  external factory _Worker(String url, JSObject options);
  external void postMessage(JSAny? value);
  external void addEventListener(String type, JSFunction listener);
  external void removeEventListener(String type, JSFunction listener);
  external void terminate();
}

extension type _Event._(JSObject _) implements JSObject {
  external JSAny? get data;
  external String? get message;
  external void preventDefault();
}

final class _Pending {
  final Duration timeout;
  final elapsed = Stopwatch()..start();
  _Pending(this.timeout);
  bool get expired => elapsed.elapsed >= timeout;
  final result = Completer<Object?>();
  Timer? timer;
  void Function()? detach;
  void finish() {
    timer?.cancel();
    detach?.call();
  }
}

final class _WebChannel implements CollectionChannel {
  final Uri uri;
  final _pending = <int, _Pending>{};
  final _watches = <int, _WebWatch>{};
  _Worker? _worker;
  late final JSFunction _message = ((JSObject event) {
    _receive(_Event._(event));
  }).toJS;
  late final JSFunction _error = ((JSObject event) {
    final error = _Event._(event);
    error.preventDefault();
    _fail(
      DeviceReadoutException(
        ErrorCode.readFailed,
        error.message ?? 'Browser worker failed.',
      ),
    );
  }).toJS;
  late final JSFunction _messageError = ((JSObject event) {
    _fail(
      const DeviceReadoutException(
        ErrorCode.readFailed,
        'Cannot decode worker response.',
      ),
    );
  }).toJS;
  int _nextId = 0;
  bool _closed = false;
  DeviceReadoutException? _failure;
  _WebChannel(this.uri);

  @override
  bool get available => globalContext.has('Worker');

  void _start() {
    if (_worker != null) return;
    if (!available)
      throw const DeviceReadoutException(
        ErrorCode.unsupportedEntity,
        'Browser workers are unavailable.',
      );
    final worker = _Worker(
      Uri.base.resolveUri(uri).toString(),
      {'type': 'module', 'name': 'DeviceReadout Dart'}.jsify() as JSObject,
    );
    _worker = worker;
    worker.addEventListener('message', _message);
    worker.addEventListener('error', _error);
    worker.addEventListener('messageerror', _messageError);
  }

  Future<Object?> _request(
    String operation,
    EntityAddress entity,
    Duration timeout,
    CancellationToken? cancellation, {
    Object? value,
    SensorSamplingRate rate = SensorSamplingRate.platformDefault,
  }) {
    if (_closed || cancellation?.isCancelled == true)
      return Future.error(const DeviceReadoutCancelled());
    if (_failure != null) return Future.error(_failure!);
    if (_pending.length >= 128)
      return Future.error(
        const DeviceReadoutException(
          ErrorCode.readFailed,
          'The bounded worker request queue is full.',
        ),
      );
    final id = ++_nextId, pending = _Pending(timeout);
    _pending[id] = pending;
    pending.timer = Timer(
      timeout,
      () => _cancel(
        id,
        const DeviceReadoutException(
          ErrorCode.readTimeout,
          'Collection exceeded its read timeout.',
        ),
      ),
    );
    pending.detach = cancellation?.listen(
      () => _cancel(id, const DeviceReadoutCancelled()),
    );
    try {
      _start();
      final name = entity.kind.name;
      _worker!.postMessage(
        {
          'id': id,
          'operation': operation,
          'entity': {
            'kind': '${name[0].toUpperCase()}${name.substring(1)}',
            if (entity.targetId != null) 'targetId': entity.targetId,
          },
          'settings': {
            'pollIntervalMs': 1000,
            'readTimeoutMs': timeout.inMicroseconds / 1000,
            'sensorHertz': rate.hertz,
          },
          if (value != null) 'value': value,
        }.jsify(),
      );
    } catch (error) {
      _fail(
        error is DeviceReadoutException
            ? error
            : DeviceReadoutException(ErrorCode.readFailed, '$error'),
      );
    }
    return pending.result.future;
  }

  void _cancel(int id, Object error) {
    final pending = _pending.remove(id);
    if (pending == null) return;
    pending.finish();
    pending.result.completeError(error);
    try {
      _worker?.postMessage({'id': id, 'operation': 'cancel'}.jsify());
    } catch (_) {}
  }

  void _receive(_Event event) {
    try {
      final data = event.data;
      if (data == null || !data.isA<JSObject>())
        throw const FormatException('Missing response object.');
      final rawId = (data as JSObject).getProperty<JSAny?>('id'.toJS);
      if (rawId == null || !rawId.isA<JSNumber>())
        throw const FormatException('Missing response identity.');
      final number = (rawId as JSNumber).toDartDouble;
      if (!number.isFinite || number != number.truncateToDouble())
        throw const FormatException('Invalid response identity.');
      final id = number.toInt();
      // Retired operations must not traverse a potentially large late payload.
      if (!_pending.containsKey(id) && !_watches.containsKey(id)) return;
      if (_pending[id]?.expired == true) {
        _cancel(id, _readTimeout);
        return;
      }
      if (_watches[id]?.expired == true) {
        _watches[id]!.fail(_readTimeout);
        return;
      }
      final message = (event.data.dartify() as Map<Object?, Object?>)
          .cast<String, Object?>();
      final watch = _watches[id];
      if (watch != null) {
        watch.receive(message);
        return;
      }
      final pending = _pending[id];
      if (pending == null) return;
      if (pending.expired) {
        _cancel(id, _readTimeout);
        return;
      }
      if (message['type'] == 'result') {
        _pending.remove(id);
        pending.finish();
        pending.result.complete(message['value']);
      } else if (message['type'] == 'error') {
        final error = _workerError(message['error']);
        _pending.remove(id);
        pending.finish();
        pending.result.completeError(error);
      } else {
        _pending.remove(id);
        pending.finish();
        pending.result.completeError(
          const DeviceReadoutException(
            ErrorCode.readFailed,
            'Unexpected worker response.',
          ),
        );
      }
    } catch (error) {
      _fail(
        DeviceReadoutException(
          ErrorCode.readFailed,
          'Invalid worker response: $error',
        ),
      );
    }
  }

  void _fail(DeviceReadoutException error) {
    _failure ??= error;
    final pending = _pending.values.toList();
    _pending.clear();
    for (final request in pending) {
      request.finish();
      request.result.completeError(_failure!);
    }
    for (final watch in _watches.values.toList()) {
      watch.fail(_failure!);
    }
    _disposeWorker();
  }

  void _disposeWorker() {
    final worker = _worker;
    _worker = null;
    if (worker == null) return;
    worker.removeEventListener('message', _message);
    worker.removeEventListener('error', _error);
    worker.removeEventListener('messageerror', _messageError);
    worker.terminate();
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    final pending = _pending.values.toList();
    _pending.clear();
    for (final request in pending) {
      request.finish();
      request.result.completeError(const DeviceReadoutCancelled());
    }
    for (final watch in _watches.values.toList()) {
      watch.fail(const DeviceReadoutCancelled());
    }
    _disposeWorker();
  }

  @override
  Future<DeviceSnapshot> read(
    EntityAddress entity,
    SensorSamplingRate rate,
    Duration timeout,
    CancellationToken? cancellation, {
    DeviceSnapshot? observed,
    bool description = false,
  }) async {
    final elapsed = Stopwatch()..start();
    if (observed != null &&
        (description
            ? observed is! SensorDescription
            : observed.entityKind != entity.kind)) {
      throw const DeviceReadoutException(
        ErrorCode.readFailed,
        'Observed snapshot type does not match the entity.',
      );
    }
    final value = observed == null
        ? null
        : {'description': description, 'snapshot': observed.toJson()};
    final remaining = timeout - elapsed.elapsed;
    if (remaining <= Duration.zero) throw _readTimeout;
    final raw = await _request(
      observed != null
          ? 'normalize'
          : description
          ? 'describe'
          : 'get',
      entity,
      remaining,
      cancellation,
      rate: rate,
      value: value,
    );
    late final DeviceSnapshot snapshot;
    try {
      snapshot = hydrateWorkerSnapshot(
        entity.kind,
        (raw as Map<Object?, Object?>).cast<String, Object?>(),
        description: description,
      );
    } catch (_) {
      throw const DeviceReadoutException(
        ErrorCode.readFailed,
        'Invalid worker snapshot.',
      );
    }
    if (elapsed.elapsed >= timeout) throw _readTimeout;
    return snapshot;
  }

  @override
  Future<EntityCapabilities> capabilities(
    EntityAddress entity,
    Duration timeout,
    CancellationToken cancellation,
  ) async {
    final raw = await _request(
      'capabilities',
      entity,
      timeout,
      cancellation,
    ) as Map<Object?, Object?>;
    return EntityCapabilities(
      readable: raw['readable'] as bool?,
      watchable: raw['watchable'] as bool?,
    );
  }

  @override
  Future<List<String>> list(
    EntityKind kind,
    Duration timeout,
    CancellationToken cancellation,
  ) async {
    final raw = await _request(
      'list',
      EntityAddress(kind),
      timeout,
      cancellation,
    );
    if (raw is! List<Object?> ||
        raw.length > 4096 ||
        raw.any((id) => id is! String || id.isEmpty || id.length > 1024) ||
        raw.toSet().length != raw.length) {
      throw const DeviceReadoutException(
        ErrorCode.readFailed,
        'Invalid worker inventory.',
      );
    }
    return List<String>.unmodifiable(raw.cast<String>());
  }

  @override
  Future<String?> current(
    EntityKind kind,
    Duration timeout,
    CancellationToken cancellation,
  ) async {
    final raw = await _request(
      'current',
      EntityAddress(kind),
      timeout,
      cancellation,
    );
    if (raw != null && (raw is! String || raw.isEmpty || raw.length > 1024)) {
      throw const DeviceReadoutException(
        ErrorCode.readFailed,
        'Invalid worker current identity.',
      );
    }
    return raw as String?;
  }

  @override
  Stream<DeviceSnapshot?> watch(
    EntityAddress entity,
    Duration pollInterval,
    Duration readTimeout,
    CancellationToken cancellation,
  ) => _WebWatch(
    this,
    ++_nextId,
    entity,
    pollInterval,
    readTimeout,
    cancellation,
  ).stream;
}

DeviceReadoutException _workerError(Object? raw) {
  final error = raw as Map<Object?, Object?>;
  final code =
      ErrorCode.values
          .where(
            (code) =>
                '${code.name[0].toUpperCase()}${code.name.substring(1)}' ==
                error['code'],
          )
          .firstOrNull ??
      ErrorCode.readFailed;
  return DeviceReadoutException(
    code,
    error['message'] as String? ?? 'Worker collection failed.',
  );
}

const _readTimeout = DeviceReadoutException(
  ErrorCode.readTimeout,
  'Collection exceeded its read timeout.',
);
