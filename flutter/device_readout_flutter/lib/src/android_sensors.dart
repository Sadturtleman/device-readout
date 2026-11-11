import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:device_readout/device_readout.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'sensor_inventory.dart';

/// Explicit owner of Android sensor sources in an existing DeviceAccess context.
/// Attach the app lifecycle observer first. Dispose before the owning SDK.
final class FlutterAndroidSensors {
  final SensorInventoryOwner _inventory;
  FlutterAndroidSensors._(this._inventory);

  static Future<FlutterAndroidSensors> attach(DeviceAccess access) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw const DeviceReadoutException(
        ErrorCode.unsupportedEntity,
        'The Android sensor adapter requires Android.',
      );
    }
    final token = ui.RootIsolateToken.instance;
    if (token == null) {
      throw const DeviceReadoutException(
        ErrorCode.invalidConfiguration,
        'Attach from the application root isolate.',
      );
    }
    final worker = _AndroidSensorWorker();
    final owner = SensorInventoryOwner(access, worker);
    worker.onInventoryChange = owner.changed;
    worker.onInventoryFailure = owner.failed;
    try {
      await worker.start(token).timeout(access.readTimeout);
      await owner.initialize();
      return FlutterAndroidSensors._(owner);
    } catch (error) {
      owner.dispose();
      throw _failure(error);
    }
  }

  /// Explicit refresh remains available alongside native connection notifications.
  Future<void> refresh<S extends DeviceSnapshot>(Entity<S> kind) =>
      _inventory.refresh(kind);
  void dispose() => _inventory.dispose();
}

typedef _Inventory = SensorInventoryRows;

final class _Sink {
  final void Function(DeviceSnapshot) publish;
  final void Function(DeviceReadoutException) fail;
  _Sink(this.publish, this.fail);
}

final class _AndroidSensorWorker implements SensorInventoryTransport {
  late final Future<void> Function(EntityKind) onInventoryChange;
  late final void Function(DeviceReadoutException) onInventoryFailure;
  final _messages = ReceivePort();
  final _ready = Completer<void>();
  final _pending = <int, Completer<_Inventory>>{};
  final _streams = <int, _Sink>{};
  SendPort? _commands;
  int _sequence = 0;
  bool _closed = false;

  Future<void> start(ui.RootIsolateToken token) async {
    _messages.listen((Object? raw) {
      if (raw == null) {
        _broken(
          const DeviceReadoutException(
            ErrorCode.readFailed,
            'Android sensor worker exited.',
          ),
        );
        _messages.close();
        return;
      }
      if (raw is! List<Object?> || raw.isEmpty) return;
      switch (raw[0]) {
        case 'port':
          _commands = raw[1] as SendPort;
          if (_closed) _commands!.send(['dispose']);
        case 'ready':
          if (!_ready.isCompleted) _ready.complete();
        case 'inventory':
          _pending.remove(raw[1])?.complete(raw[2] as _Inventory);
        case 'inventoryError':
          _pending.remove(raw[1])?.completeError(raw[2]!);
        case 'inventoryChanged':
          if (!_closed) unawaited(_changed(raw[1] as EntityKind));
        case 'inventoryChangesError':
          if (!_closed) _inventoryFailed(raw[1] as DeviceReadoutException);
        case 'sample':
          try {
            _streams[raw[1]]?.publish(raw[2] as DeviceSnapshot);
          } catch (error) {
            _streams.remove(raw[1])?.fail(_failure(error));
            if (!_closed) _commands?.send(['close', raw[1]]);
          } finally {
            // One unacknowledged message per session bounds the root-isolate
            // mailbox even when application code temporarily stops servicing it.
            if (!_closed) _commands?.send(['ack', raw[1]]);
          }
        case 'error':
          _streams.remove(raw[1])?.fail(raw[2] as DeviceReadoutException);
        case 'fatal':
          _broken(raw[1] as DeviceReadoutException);
        default:
          _broken(
            const DeviceReadoutException(
              ErrorCode.readFailed,
              'Android sensor worker failed.',
            ),
          );
      }
    });
    try {
      await Isolate.spawn(
        _androidWorker,
        [token, _messages.sendPort],
        onExit: _messages.sendPort,
        onError: _messages.sendPort,
      );
      await _ready.future;
    } catch (error) {
      close();
      rethrow;
    }
  }

  Future<void> _changed(EntityKind kind) async {
    try {
      await onInventoryChange(kind);
    } catch (error) {
      _inventoryFailed(_failure(error));
    } finally {
      if (!_closed) _commands?.send(['inventoryAck']);
    }
  }

  void _inventoryFailed(DeviceReadoutException error) {
    try {
      onInventoryFailure(error);
    } catch (_) {
      /* The owner may already have ended its SDK context. */
    }
  }

  @override
  Future<_Inventory> inventory(EntityKind kind, Duration timeout) {
    if (_closed) return Future.error(const DeviceReadoutCancelled());
    if (_pending.length >= 128)
      return Future.error(
        const DeviceReadoutException(
          ErrorCode.readFailed,
          'Android inventory queue is full.',
        ),
      );
    final id = ++_sequence;
    final result = _pending[id] = Completer<_Inventory>();
    _commands!.send(['list', id, kind, timeout.inMicroseconds]);
    return result.future;
  }

  @override
  void Function() observe<S extends DeviceSnapshot>(
    int target,
    EntityKind kind,
    SensorObserverSession<S> session,
    void Function() removed,
  ) {
    if (_closed) throw const DeviceReadoutCancelled();
    final id = ++_sequence;
    _streams[id] = _Sink((value) => session.publish(value as S), (error) {
      if (error.code == ErrorCode.entityRemoved)
        removed();
      else
        session.fail(error);
    });
    _commands!.send([
      'open',
      id,
      target,
      kind,
      session.samplingRate.hertz,
      session.readTimeout.inMicroseconds,
    ]);
    return () {
      _streams.remove(id);
      if (!_closed) _commands?.send(['close', id]);
    };
  }

  void _broken(DeviceReadoutException error) {
    if (!_ready.isCompleted) _ready.completeError(error);
    for (final pending in _pending.values) {
      pending.completeError(error);
    }
    _pending.clear();
    for (final stream in _streams.values.toList()) {
      stream.fail(error);
    }
    _streams.clear();
    _inventoryFailed(error);
    close();
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    for (final pending in _pending.values) {
      pending.completeError(const DeviceReadoutCancelled());
    }
    _pending.clear();
    _streams.clear();
    _commands?.send(['dispose']);
  }
}

void _androidWorker(List<Object?> initial) async {
  final host = initial[1] as SendPort;
  final commands = ReceivePort();
  Future<void> Function()? cleanup;
  try {
    BackgroundIsolateBinaryMessenger.ensureInitialized(
      initial[0] as ui.RootIsolateToken,
    );
    const channel = MethodChannel('dev.devicereadout/sensors.v1');
    final context = channel.invokeMethod<int>('create');
    final sessions = <int, int?>{};
    final acknowledgements = <int, Completer<void>>{};
    final pendingReplies = <Future<void>>{};
    Completer<void>? inventoryAck;
    bool closing = false;
    Future<T?> invoke<T>(
      String method, [
      Map<String, Object?> args = const {},
    ]) async {
      final settled = Completer<void>();
      pendingReplies.add(settled.future);
      try {
        return await channel.invokeMethod<T>(method, {
          'context': await context,
          ...args,
        });
      } finally {
        pendingReplies.remove(settled.future);
        settled.complete();
      }
    }

    Future<void> stop(int id) async {
      final native = sessions.remove(id);
      acknowledgements.remove(id)?.complete();
      if (native != null) {
        try {
          await invoke<void>('close', {'session': native});
        } catch (_) {}
      }
    }

    Future<void> observe(List<Object?> message) async {
      final id = message[1] as int;
      final kind = message[3] as EntityKind;
      sessions[id] = null;
      int? native;
      try {
        native = await invoke<int>('open', {
          'target': message[2],
          'hertz': message[4],
          'timeoutMicros': message[5],
        });
        if (native == null)
          throw const FormatException('Missing native sensor session.');
        if (closing || !sessions.containsKey(id)) return;
        sessions[id] = native;
        while (!closing && sessions.containsKey(id)) {
          final json = await invoke<String>('next', {'session': native});
          if (closing || !sessions.containsKey(id)) break;
          final fields = jsonDecode(json!) as Map<String, Object?>;
          final acknowledged = acknowledgements[id] = Completer<void>();
          host.send(['sample', id, SnapshotCodec.decode(kind, fields)]);
          await acknowledged.future;
        }
      } catch (error) {
        if (!closing && sessions.containsKey(id))
          host.send(['error', id, _failure(error)]);
      } finally {
        sessions.remove(id);
        acknowledgements.remove(id)?.complete();
        if (native != null && !closing) {
          try {
            await invoke<void>('close', {'session': native});
          } catch (_) {}
        }
      }
    }

    Future<void> inventory(List<Object?> message) async {
      try {
        final kind = message[2] as EntityKind;
        final rows = await invoke<List<Object?>>('list', {
          'kind': _nativeName(kind),
          'timeoutMicros': message[3],
        });
        if (rows == null || rows.length > 1024)
          throw const FormatException('Invalid sensor inventory.');
        final result = <(int, SensorDescription)>[];
        final seen = <int>{};
        for (final raw in rows) {
          final row = raw as Map<Object?, Object?>;
          final id = row['target'] as int;
          if (id <= 0 || !seen.add(id))
            throw const FormatException('Invalid sensor target.');
          final fields =
              jsonDecode(row['description'] as String) as Map<String, Object?>;
          result.add((id, SnapshotCodec.describe(fields)));
        }
        if (!closing) host.send(['inventory', message[1], result]);
      } catch (error) {
        if (!closing)
          host.send(['inventoryError', message[1], _failure(error)]);
      }
    }

    Future<void> inventoryChanges() async {
      try {
        while (!closing) {
          final name = await invoke<String>('nextInventory');
          if (closing) return;
          final kind = EntityKind.values
              .where((kind) => _nativeName(kind) == name)
              .firstOrNull;
          if (kind == null)
            throw const FormatException('Unknown inventory entity kind.');
          final acknowledged = inventoryAck = Completer<void>();
          host.send(['inventoryChanged', kind]);
          await acknowledged.future;
          inventoryAck = null;
        }
      } catch (error) {
        if (!closing) host.send(['inventoryChangesError', _failure(error)]);
      }
    }

    Future<void> close() async {
      if (closing) return;
      closing = true;
      if (inventoryAck case final pending? when !pending.isCompleted)
        pending.complete();
      sessions.clear();
      for (final acknowledged in acknowledgements.values) {
        acknowledged.complete();
      }
      acknowledgements.clear();
      try {
        await invoke<void>('dispose');
      } catch (_) {}
      // Context disposal cancels native work but does not order other channel
      // replies. Keep their Dart port alive until every issued call settles.
      // This drain is worker-owned; the application's dispose never waits for it.
      while (pendingReplies.isNotEmpty) {
        await Future.wait(pendingReplies.toList());
      }
      commands.close();
      Isolate.exit();
    }

    cleanup = close;

    commands.listen((Object? raw) {
      final message = raw as List<Object?>;
      switch (message[0]) {
        case 'list':
          if (!closing) unawaited(inventory(message));
        case 'open':
          if (!closing) unawaited(observe(message));
        case 'close':
          if (!closing) unawaited(stop(message[1] as int));
        case 'ack':
          acknowledgements.remove(message[1])?.complete();
        case 'inventoryAck':
          if (inventoryAck case final pending? when !pending.isCompleted)
            pending.complete();
        case 'dispose':
          unawaited(close());
      }
    });
    host.send(['port', commands.sendPort]);
    if (await context == null)
      throw const FormatException('Missing native sensor context.');
    if (!closing && await invoke<bool>('startInventory') == true && !closing) {
      unawaited(inventoryChanges());
    }
    if (!closing) host.send(['ready']);
  } catch (error) {
    host.send(['fatal', _failure(error)]);
    if (cleanup != null) await cleanup();
    commands.close();
    Isolate.exit();
  }
}

DeviceReadoutException _failure(Object error) {
  if (error is DeviceReadoutException) return error;
  if (error is TimeoutException)
    return const DeviceReadoutException(
      ErrorCode.readTimeout,
      'Android sensor request exceeded its timeout.',
    );
  if (error is MissingPluginException)
    return const DeviceReadoutException(
      ErrorCode.unsupportedEntity,
      'The Android native sensor plugin is unavailable.',
    );
  if (error is PlatformException) {
    final code = ErrorCode.values
        .where((code) => _nativeName(code) == error.code)
        .firstOrNull;
    return DeviceReadoutException(
      code ?? ErrorCode.readFailed,
      error.message ?? 'Android sensor operation failed.',
    );
  }
  return DeviceReadoutException(ErrorCode.readFailed, error.toString());
}

// Kotlin enum names use PascalCase; Dart uses lowerCamelCase. This is confined
// to the versioned native protocol; application queries remain typed entities.
String _nativeName(Enum value) =>
    value.name[0].toUpperCase() + value.name.substring(1);
