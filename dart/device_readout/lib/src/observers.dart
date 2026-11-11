part of 'core.dart';

/// App-owned state inputs. These methods do not invoke platform UI APIs.
final class ObserverInputs {
  final _AccessContext _context;
  ObserverInputs._(this._context);

  /// Feed application foreground/visibility policy. Desktop focus loss alone
  /// should not be reported as inactivity.
  void sensorActivity(bool active) {
    if (_context.closed) throw const DeviceReadoutCancelled();
    if (_context.sensorsActive == active) return;
    _context.sensorsActive = active;
    final generation = ++_context.sensorActivityGeneration;
    for (final listener in _context.sensorActivityListeners.toList()) {
      if (_context.sensorActivityGeneration != generation) break;
      listener(active);
    }
  }

  /// The application owns nonblocking native listener setup and cleanup.
  /// Unregistering retires the target; reuse requires a fresh target identity.
  void Function() sensorSource<S extends DeviceSnapshot>(
    Entity<S> entity,
    SensorObserverSource<S> source,
  ) {
    final address = entity._address(_context);
    _context.assertLive(address);
    if (entity.mode == EntityMode.state) {
      throw const DeviceReadoutException(
        ErrorCode.invalidConfiguration,
        'Expected a sensor target and observation source.',
      );
    }
    final key = _key(address);
    if (_context.sensorSources.containsKey(key)) {
      throw const DeviceReadoutException(
        ErrorCode.invalidConfiguration,
        'A sensor source is already registered for this target.',
      );
    }
    final registration = _SensorRegistration(
      (rate, timeout, cancellation, publish, fail) => source.subscribe(
        SensorObserverSession<S>._(rate, timeout, cancellation, publish, fail),
      ),
      source.description,
    );
    _context.sensorSources[key] = registration;
    return () {
      if (!identical(_context.sensorSources[key], registration)) return;
      _context.sensorSources.remove(key);
      if (!_context.closed) remove(entity);
    };
  }

  void permission<S extends DeviceSnapshot>(
    Entity<S> entity,
    PermissionStatus? status,
  ) {
    if (_context.closed) throw const DeviceReadoutCancelled();
    final address = entity._address(_context, collection: true);
    _context.permissionStates[_key(address)] = status;
    _context.notify(_ObservedChange(address, permissionChanged: true));
  }

  /// Replace metadata without restarting a registered measurement source.
  /// describe() normalizes the captured description in the collection worker.
  void sensorDescription<S extends DeviceSnapshot>(
    Entity<S> entity,
    SensorDescription? description,
  ) {
    final address = entity._address(_context);
    _context.assertLive(address);
    final source = _context.sensorSources[_key(address)];
    if (entity.mode == EntityMode.state || source == null) {
      throw const DeviceReadoutException(
        ErrorCode.invalidConfiguration,
        'Register a sensor source before updating its description.',
      );
    }
    source.description = description;
  }

  void Function() onPermissionRequest(PermissionCoordinator coordinator) {
    if (_context.closed) throw const DeviceReadoutCancelled();
    if (_context.permissionCoordinator != null) {
      throw const DeviceReadoutException(
        ErrorCode.invalidConfiguration,
        'An application permission coordinator is already registered.',
      );
    }
    final registration = _PermissionCoordinatorRegistration(coordinator);
    _context.permissionCoordinator = registration;
    return () {
      if (identical(_context.permissionCoordinator, registration)) {
        _context.permissionCoordinator = null;
      }
    };
  }

  void remove<S extends DeviceSnapshot>(Entity<S> entity) {
    if (_context.closed) throw const DeviceReadoutCancelled();
    final address = entity._address(_context), key = _key(address);
    if (_context.nativeAddresses.containsKey(key)) {
      _context.retireNative(address);
      return;
    }
    if (!_context.removed.add(key)) return;
    _context.sensorSources.remove(key);
    _context.observed[key] = null;
    _context.notify(
      _ObservedChange(
        address,
        error: const DeviceReadoutException(
          ErrorCode.entityRemoved,
          'The observed target was removed.',
        ),
      ),
    );
  }

  void current<S extends DeviceSnapshot>(Entity<S> kind, Entity<S>? target) {
    if (_context.closed) throw const DeviceReadoutCancelled();
    kind._collectionAddress(_context);
    if (target != null) {
      final address = target._address(_context);
      if (target.kind != kind.kind || address.targetId == null) {
        throw const DeviceReadoutException(
          ErrorCode.invalidConfiguration,
          'The current target must belong to the same entity kind.',
        );
      }
      if (_context.removed.contains(_key(address))) {
        throw const DeviceReadoutException(
          ErrorCode.entityRemoved,
          'A removed target cannot become current.',
        );
      }
    }
    if (!_context.nativeCollections.contains(kind.kind)) {
      _context.knownCollections.add(kind.kind);
    }
    _context.currentTargets[kind.kind] = target;
  }

  void failure<S extends DeviceSnapshot>(
    Entity<S> entity,
    DeviceReadoutException? error,
  ) {
    if (_context.closed) throw const DeviceReadoutCancelled();
    final address = entity._address(_context, collection: true);
    if (error == null) {
      _context.failures.remove(_key(address));
      return;
    }
    _context.failures[_key(address)] = error;
    _context.reportFailure(address, error);
  }

  /// A provider-owned failure slot, independent of application policy and other
  /// providers. Dispose this source when its adapter detaches.
  ObserverFailureSource failureSource<S extends DeviceSnapshot>(
    Entity<S> entity,
  ) {
    final address = entity._address(_context, collection: true);
    _context.assertLive(address);
    return ObserverFailureSource._(_context, address);
  }

  Entity<S> target<S extends DeviceSnapshot>(Entity<S> kind, String id) {
    if (_context.closed) throw const DeviceReadoutCancelled();
    kind._address(_context, collection: true);
    if (!kind._targeted || kind._targetId != null || id.isEmpty) {
      throw const DeviceReadoutException(
        ErrorCode.invalidConfiguration,
        'Expected a target kind and a nonempty observer identity.',
      );
    }
    final key = (kind.kind, id);
    final existing = _context.targets[key];
    if (existing != null) return existing as Entity<S>;
    final target = Entity<S>._(kind.kind, kind.mode, true, _context, id);
    _context.targets[key] = target;
    _context.knownCollections.add(kind.kind);
    _context.observed.putIfAbsent(key, () => null);
    return target;
  }

  void publish<S extends DeviceSnapshot>(Entity<S> entity, S snapshot) {
    if (_context.closed) throw const DeviceReadoutCancelled();
    final address = entity._address(_context);
    if (_context.removed.contains(_key(address))) return;
    if (snapshot.entityKind != entity.kind) {
      throw const DeviceReadoutException(
        ErrorCode.invalidConfiguration,
        'The published snapshot must match the entity.',
      );
    }
    if (entity.mode != EntityMode.state) {
      throw const DeviceReadoutException(
        ErrorCode.unsupportedEntity,
        'Register a sensor source and publish actual samples through its session.',
      );
    }
    _context.observed[_key(address)] = snapshot;
    _context.notify(_ObservedChange(address, snapshot: snapshot));
  }
}

/// Owns exactly one observer failure. Clearing or disposing this source cannot
/// clear an application's direct failure input or another source's failure.
final class ObserverFailureSource {
  final _AccessContext _context;
  final EntityAddress _address;
  final Object _owner = Object();
  bool _disposed = false;
  ObserverFailureSource._(this._context, this._address);

  void publish(DeviceReadoutException? error) {
    if (_disposed) throw const DeviceReadoutCancelled();
    _context.assertLive(_address);
    if (error == null) {
      _clear();
      return;
    }
    _context.scopedFailures.putIfAbsent(_key(_address), () => {})[_owner] =
        error;
    _context.reportFailure(_address, _context.failureFor(_address)!);
  }

  void _clear() {
    final key = _key(_address),
        sources = _context.scopedFailures[_key(_address)];
    sources?.remove(_owner);
    if (sources?.isEmpty ?? false) _context.scopedFailures.remove(key);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _clear();
  }
}

typedef _EntityKey = (EntityKind, Object?);
_EntityKey _key(EntityAddress entity) =>
    (entity.kind, entity._targetKey ?? entity.targetId);

final class _ObservedChange {
  final EntityAddress entity;
  final DeviceSnapshot? snapshot;
  final DeviceReadoutException? error;
  final bool permissionChanged;
  const _ObservedChange(
    this.entity, {
    this.snapshot,
    this.error,
    this.permissionChanged = false,
  });
  bool affects(EntityAddress address) =>
      entity.kind == address.kind &&
      (entity.targetId == null || _key(entity) == _key(address));
}
