import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:device_readout/device_readout.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android state collection through the common worker-owned DeviceAccess.
/// Screen, permission and sensor lifecycle observations remain app-owned.
abstract final class FlutterAndroidDeviceAccess {
  static DeviceAccess create() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw const DeviceReadoutException(
        ErrorCode.unsupportedEntity,
        'The Android state collector requires Android.',
      );
    }
    final token = ui.RootIsolateToken.instance;
    if (token == null) {
      throw const DeviceReadoutException(
        ErrorCode.invalidConfiguration,
        'Create access from the existing root isolate.',
      );
    }
    return DeviceAccess.isolated(_androidStateCollector, initialData: token);
  }
}

Future<DeviceCollector> _androidStateCollector(Object? initial) async {
  BackgroundIsolateBinaryMessenger.ensureInitialized(
    initial! as ui.RootIsolateToken,
  );
  final collector = _AndroidStateCollector();
  try {
    if ((await collector.context) case final int id when id > 0)
      return collector;
    throw const FormatException('Missing native state context.');
  } catch (error) {
    await collector.dispose();
    throw _stateFailure(error);
  }
}

final class _AndroidStateCollector
    implements
        DeviceCollector,
        DeviceStateCollector,
        DeviceDiscoveryCollector,
        DeviceCapabilityCollector {
  static const _channel = MethodChannel('dev.devicereadout/state.v1');
  final Future<int?> context = _channel.invokeMethod<int>('create');
  final _replies = <Future<void>>{};
  int _request = 0;
  bool _closed = false;

  Future<T?> _invoke<T>(
    String method, [
    Map<String, Object?> args = const {},
  ]) async {
    final settled = Completer<void>();
    _replies.add(settled.future);
    try {
      return await _channel.invokeMethod<T>(method, {
        'context': await context,
        ...args,
      });
    } catch (error) {
      throw _stateFailure(error);
    } finally {
      _replies.remove(settled.future);
      settled.complete();
    }
  }

  Future<void> _release(String method, Map<String, Object?> args) async {
    try {
      await _invoke<void>(method, args);
    } catch (_) {}
  }

  void _check(EntityAddress entity) {
    if (_closed) throw const DeviceReadoutCancelled();
    if (entity.targetId != null && (int.tryParse(entity.targetId!) ?? 0) <= 0)
      throw const FormatException('Invalid native state target.');
  }

  Map<String, Object?> _address(EntityAddress entity) => {
    'entity': _nativeStateName(entity.kind),
    if (entity.targetId != null) 'target': int.parse(entity.targetId!),
  };

  DeviceSnapshot _decode(EntityKind kind, String? json) {
    if (json == null)
      throw const FormatException('Missing native state snapshot.');
    return SnapshotCodec.decode(kind, jsonDecode(json) as Map<String, Object?>);
  }

  @override
  Future<DeviceSnapshot> read(EntityAddress entity, ReadContext read) async {
    return _decode(entity.kind, await _query<String>('read', entity, read));
  }

  @override
  Future<EntityCapabilities> capabilities(
    EntityAddress entity,
    ReadContext read,
  ) async {
    final result = await _query<Map<Object?, Object?>>(
      'capabilities',
      entity,
      read,
    );
    bool? flag(String key) {
      if (result == null ||
          !result.containsKey(key) ||
          (result[key] != null && result[key] is! bool)) {
        throw const FormatException('Invalid native capability response.');
      }
      return result[key] as bool?;
    }

    return EntityCapabilities(
      readable: flag('readable'),
      watchable: flag('watchable'),
    );
  }

  String _identity(Object? value) {
    if (value is! int || value <= 0)
      throw const FormatException('Invalid native state identity.');
    return value.toString();
  }

  @override
  Future<List<String>> list(EntityKind kind, ReadContext read) async {
    final result = await _query<List<Object?>>(
      'list',
      EntityAddress(kind),
      read,
    );
    if (result == null)
      throw const FormatException('Missing native state inventory.');
    return result.map(_identity).toList(growable: false);
  }

  @override
  Future<String?> current(EntityKind kind, ReadContext read) async {
    final result = await _query<int>('current', EntityAddress(kind), read);
    return result == null ? null : _identity(result);
  }

  Future<T?> _query<T>(
    String method,
    EntityAddress entity,
    ReadContext read,
  ) async {
    _check(entity);
    read.cancellation.throwIfCancelled();
    final request = ++_request;
    final detach = read.cancellation.listen(() {
      unawaited(_release('cancelRead', {'request': request}));
    });
    try {
      final result = await _invoke<T>(method, {
        'request': request,
        ..._address(entity),
        'timeoutMicros': read.readTimeout.inMicroseconds,
      });
      read.cancellation.throwIfCancelled();
      return result;
    } finally {
      detach();
    }
  }

  @override
  Stream<SnapshotRead> watch(
    EntityAddress entity,
    StateWatchContext settings,
  ) async* {
    _check(entity);
    settings.cancellation.throwIfCancelled();
    int? session;
    Future<void> release() async {
      if (session != null) await _release('close', {'session': session});
    }

    final detach = settings.cancellation.listen(() {
      unawaited(release());
    });
    try {
      session = await _invoke<int>('open', {
        ..._address(entity),
        'timeoutMicros': settings.readTimeout.inMicroseconds,
        'pollMicros': settings.pollInterval.inMicroseconds,
      });
      if (session == null)
        throw const FormatException('Missing native state session.');
      while (!_closed && !settings.cancellation.isCancelled) {
        final json = await _invoke<String>('next', {'session': session});
        if (settings.cancellation.isCancelled) return;
        yield () => _decode(entity.kind, json);
      }
    } finally {
      detach();
      await release();
    }
  }

  @override
  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    await _release('dispose', const {});
    // The common collection isolate exits only after disposal finishes. Keep
    // its messenger alive until late native replies have all been received.
    while (_replies.isNotEmpty) {
      await Future.wait(_replies.toList());
    }
  }
}

String _nativeStateName(Enum value) =>
    value.name[0].toUpperCase() + value.name.substring(1);

DeviceReadoutException _stateFailure(Object error) {
  if (error is DeviceReadoutException) return error;
  if (error is MissingPluginException) {
    return const DeviceReadoutException(
      ErrorCode.unsupportedEntity,
      'The Android state plugin is unavailable.',
    );
  }
  if (error is PlatformException) {
    final code = ErrorCode.values
        .where((code) => _nativeStateName(code) == error.code)
        .firstOrNull;
    return DeviceReadoutException(
      code ?? ErrorCode.readFailed,
      error.message ?? 'Android state collection failed.',
    );
  }
  return DeviceReadoutException(ErrorCode.readFailed, error.toString());
}
