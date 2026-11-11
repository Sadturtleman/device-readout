import 'dart:async';

import 'package:device_readout/device_readout.dart';

typedef SensorInventoryRows = List<(int, SensorDescription)>;

/// Internal platform boundary. Transport calls dispatch native work off the app isolate.
abstract interface class SensorInventoryTransport {
  Future<SensorInventoryRows> inventory(EntityKind kind, Duration timeout);
  void Function() observe<S extends DeviceSnapshot>(
    int target,
    EntityKind kind,
    SensorObserverSession<S> session,
    void Function() removed,
  );
  void close();
}

final class _InstalledSensor {
  final void Function() dispose;
  final void Function(SensorDescription) describe;
  _InstalledSensor(this.dispose, this.describe);
}

/// Owns the app-side registrations of one explicitly attached native provider.
/// It never queries UI or starts measurements while reconciling an inventory.
final class SensorInventoryOwner {
  static int _nextOwner = 0;
  final DeviceAccess _access;
  final SensorInventoryTransport _transport;
  final int _owner = ++_nextOwner;
  final _installed = <EntityKind, Map<int, _InstalledSensor>>{};
  final _refreshing = <EntityKind, Future<void>>{};
  final _failures = <EntityKind, ObserverFailureSource>{};
  final _kinds = <Entity<DeviceSnapshot>>{};
  final _refreshers = <EntityKind, Future<void> Function()>{};
  int _generation = 0;
  DeviceReadoutException? _observationFailure;
  bool _disposed = false;

  SensorInventoryOwner(this._access, this._transport) {
    // Concrete generic calls preserve each discovered handle's snapshot type.
    _register(Entities.accelerometer);
    _register(Entities.linearAcceleration);
    _register(Entities.gravity);
    _register(Entities.gyroscope);
    _register(Entities.magnetometer);
    _register(Entities.relativeOrientation);
    _register(Entities.absoluteOrientation);
    _register(Entities.illuminance);
    _register(Entities.pressure);
    _register(Entities.ambientTemperature);
    _register(Entities.relativeHumidity);
    _register(Entities.proximityNear);
    _register(Entities.proximityDistance);
    _register(Entities.relativeAltitude);
    _register(Entities.hingeAngle);
    _register(Entities.stepCountSinceBoot);
    _register(Entities.stepDetected);
    _register(Entities.significantMotion);
    _register(Entities.humanPresence);
  }

  void _register<S extends DeviceSnapshot>(Entity<S> kind) {
    _kinds.add(kind);
    _refreshers[kind.kind] = () => refresh(kind);
  }

  Future<void> initialize() async {
    for (final refresh in _refreshers.values) {
      try {
        await refresh();
      } on DeviceReadoutException catch (error) {
        if (error.code != ErrorCode.unsupportedEntity &&
            error.code != ErrorCode.permissionDenied)
          rethrow;
      }
    }
  }

  Future<void> refresh<S extends DeviceSnapshot>(Entity<S> kind) {
    if (_disposed) return Future.error(const DeviceReadoutCancelled());
    if (!_kinds.contains(kind)) {
      return Future.error(
        const DeviceReadoutException(
          ErrorCode.invalidConfiguration,
          'Expected a sensor collection.',
        ),
      );
    }
    return _refreshing.putIfAbsent(
      kind.kind,
      () => _refresh(kind).whenComplete(() {
        _refreshing.remove(kind.kind);
      }),
    );
  }

  /// A notification received during a read requires a fresh read afterward.
  /// The transport waits for completion before forwarding another notification.
  Future<void> changed(EntityKind kind) async {
    if (_disposed) return;
    final refresh = _refreshers[kind];
    if (refresh == null) return;
    final pending = _refreshing[kind];
    if (pending != null) {
      try {
        await pending;
      } catch (_) {
        /* Refresh again from the later event. */
      }
    }
    if (_disposed) return;
    try {
      await refresh();
    } catch (_) {
      /* The owning failure source already records this error. */
    }
  }

  void failed(DeviceReadoutException error) {
    if (_disposed) return;
    _observationFailure ??= error;
    for (final kind in _installed.keys) {
      try {
        _failures[kind]?.publish(error);
      } on DeviceReadoutCancelled {
        dispose();
        return;
      }
    }
  }

  Future<void> _refresh<S extends DeviceSnapshot>(Entity<S> kind) async {
    final failure = _failures.putIfAbsent(
      kind.kind,
      () => _access.observers.failureSource(kind),
    );
    try {
      if (_observationFailure case final error?) throw error;
      final rows = await _transport
          .inventory(kind.kind, _access.readTimeout)
          .timeout(_access.readTimeout);
      if (_disposed) throw const DeviceReadoutCancelled();
      if (_observationFailure case final error?) throw error;
      final entries = _installed.putIfAbsent(kind.kind, () => {});
      final live = rows.map((row) => row.$1).toSet();
      for (final id in entries.keys.toList()) {
        if (!live.contains(id)) entries.remove(id)!.dispose();
      }
      _access.observers.current(kind, null);
      for (final (id, description) in rows) {
        final existing = entries[id];
        if (existing != null) {
          try {
            existing.describe(description);
            continue;
          } on DeviceReadoutException catch (error) {
            if (error.code != ErrorCode.entityRemoved) rethrow;
            entries.remove(id)?.dispose();
          }
        }
        final target = _access.observers.target(
          kind,
          'flutter-android-$_owner-${kind.kind.name}-$id-${++_generation}',
        );
        late final _InstalledSensor installed;
        final stop = _access.observers.sensorSource(
          target,
          SensorObserverSource<S>(
            description: description,
            subscribe: (session) =>
                _transport.observe(id, kind.kind, session, () {
                  if (identical(entries[id], installed))
                    entries.remove(id)?.dispose();
                }),
          ),
        );
        installed = _InstalledSensor(
          stop,
          (description) =>
              _access.observers.sensorDescription(target, description),
        );
        entries[id] = installed;
      }
      failure.publish(null);
    } catch (error) {
      if (_disposed || error is DeviceReadoutCancelled) rethrow;
      final normalized = error is DeviceReadoutException
          ? error
          : DeviceReadoutException(
              error is TimeoutException
                  ? ErrorCode.readTimeout
                  : ErrorCode.readFailed,
              'Sensor inventory refresh failed: $error',
            );
      failure.publish(normalized);
      throw normalized;
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final entries in _installed.values) {
      for (final target in entries.values.toList()) {
        target.dispose();
      }
      entries.clear();
    }
    for (final failure in _failures.values) {
      failure.dispose();
    }
    _failures.clear();
    _transport.close();
  }
}
