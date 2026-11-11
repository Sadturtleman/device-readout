part of 'core.dart';

final class DeviceAccess {
  final _AccessContext _context;
  final Duration pollInterval;
  final Duration readTimeout;
  final SensorSamplingRate sensorSamplingRate;
  ObserverInputs get observers => ObserverInputs._(_context);
  PermissionAccess get permissions => PermissionAccess._(_context);
  CapabilityAccess get capabilities => CapabilityAccess._(this);

  EntityCollection<DisplaySnapshot> get displays =>
      EntityCollection._(this, Entities.display);
  EntityCollection<ViewportSnapshot> get viewports =>
      EntityCollection._(this, Entities.viewport);
  EntityCollection<CpuCoreSnapshot> get cpuCores =>
      EntityCollection._(this, Entities.cpuCore);
  EntityCollection<BatterySnapshot> get batteries =>
      EntityCollection._(this, Entities.battery);
  EntityCollection<NetworkInterfaceSnapshot> get networkInterfaces =>
      EntityCollection._(this, Entities.networkInterface);
  EntityCollection<StorageVolumeSnapshot> get storageVolumes =>
      EntityCollection._(this, Entities.storageVolume);
  EntityCollection<CellularSubscriptionSnapshot> get cellularSubscriptions =>
      EntityCollection._(this, Entities.cellularSubscription);
  EntityCollection<TelephonyIdentitySnapshot> get telephonyIdentities =>
      EntityCollection._(this, Entities.telephonyIdentity);

  Future<List<Entity<S>>> list<S extends DeviceSnapshot>(
    Entity<S> kind, {
    CancellationToken? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    _context.assertAvailable(kind._collectionAddress(_context));
    if (!_context.knownCollections.contains(kind.kind)) {
      final identities =
          await _discover(kind, cancellation: cancellation) as List<String>;
      // An app-owned inventory published during the native request takes over.
      if (!_context.knownCollections.contains(kind.kind)) {
        _context.nativeCollections.add(kind.kind);
        final live = identities.toSet();
        for (final entry in _context.nativeTargets.entries.toList()) {
          if (entry.key.$1 == kind.kind && !live.contains(entry.key.$2)) {
            _context.retireNative(entry.value._address(_context));
          }
        }
        return List.unmodifiable(
          identities.map((id) => _context.bindNative(kind, id)),
        );
      }
    }
    return List.unmodifiable(
      _context.targets.entries
          .where(
            (entry) =>
                entry.key.$1 == kind.kind &&
                !_context.nativeAddresses.containsKey(entry.key) &&
                !_context.removed.contains(entry.key),
          )
          .map((entry) => entry.value as Entity<S>),
    );
  }

  Future<Entity<S>?> current<S extends DeviceSnapshot>(
    Entity<S> kind, {
    CancellationToken? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    _context.assertAvailable(kind._collectionAddress(_context));
    if (!_context.knownCollections.contains(kind.kind) &&
        !_context.currentTargets.containsKey(kind.kind)) {
      final identity = await _discover(
        kind,
        current: true,
        cancellation: cancellation,
      ) as String?;
      if (!_context.knownCollections.contains(kind.kind) &&
          !_context.currentTargets.containsKey(kind.kind)) {
        _context.nativeCollections.add(kind.kind);
        return identity == null ? null : _context.bindNative(kind, identity);
      }
    }
    final current = _context.currentTargets[kind.kind];
    return current == null ||
            _context.removed.contains(_key(current._address(_context)))
        ? null
        : current as Entity<S>;
  }

  factory DeviceAccess.native() =>
      DeviceAccess.isolated(platform.createNativeCollector);

  factory DeviceAccess.isolated(
    CollectorFactory factory, {
    Object? initialData,
  }) => DeviceAccess._(
    _AccessContext(platform.createChannel(factory, initialData)),
    const Duration(seconds: 1),
    const Duration(seconds: 5),
    SensorSamplingRate.platformDefault,
  );

  DeviceAccess._(
    this._context,
    this.pollInterval,
    this.readTimeout,
    this.sensorSamplingRate,
  );

  DeviceAccess withPollInterval(Duration interval) => DeviceAccess._(
    _context,
    _positive(interval),
    readTimeout,
    sensorSamplingRate,
  );
  DeviceAccess withReadTimeout(Duration timeout) => DeviceAccess._(
    _context,
    pollInterval,
    _positive(timeout),
    sensorSamplingRate,
  );
  DeviceAccess withSensorSamplingRate(SensorSamplingRate rate) =>
      DeviceAccess._(_context, pollInterval, readTimeout, rate);

  Future<S> get<S extends DeviceSnapshot>(
    Entity<S> entity, {
    CancellationToken? cancellation,
  }) => entity.mode == EntityMode.state
      ? _read(entity, cancellation: cancellation)
      : _SensorStream<S>(
          this,
          entity,
          oneShot: true,
          caller: cancellation,
        ).stream.first;

  Future<S> _read<S extends DeviceSnapshot>(
    Entity<S> entity, {
    CancellationToken? cancellation,
    DeviceSnapshot? captured,
  }) async {
    if (_context.closed) throw const DeviceReadoutCancelled();
    cancellation?.throwIfCancelled();
    final address = entity._address(_context);
    _context.assertAvailable(address);
    final operation = CancellationToken();
    DeviceReadoutException? invalidated;
    final detachFailure = _context.listen((change) {
      if (change.affects(address) && change.error != null) {
        invalidated ??= change.error;
        operation.cancel();
      }
    });
    final detachCaller = cancellation?.listen(operation.cancel);
    final detachLifetime = _context.lifetime.listen(operation.cancel);
    try {
      final elapsed = Stopwatch()..start();
      var observed = captured ?? _context.observed[_key(address)];
      if (observed == null && _context.observed.containsKey(_key(address))) {
        observed = await _context.firstObserved(
          address,
          readTimeout,
          operation,
        );
      }
      operation.throwIfCancelled();
      final remaining = readTimeout - elapsed.elapsed;
      if (remaining <= Duration.zero) {
        throw const DeviceReadoutException(
          ErrorCode.readTimeout,
          'Collection exceeded its read timeout.',
        );
      }
      final snapshot = await _context.channel.read(
        _context.nativeAddress(address),
        SensorSamplingRate.platformDefault,
        remaining,
        operation,
        observed: observed,
      ) as S;
      operation.throwIfCancelled();
      _context.assertAvailable(address);
      return snapshot;
    } catch (error) {
      if (error is DeviceReadoutException &&
          error.code == ErrorCode.entityRemoved) {
        _context.retireNative(address);
      }
      if (invalidated != null) throw invalidated!;
      rethrow;
    } finally {
      detachFailure();
      detachCaller?.call();
      detachLifetime();
    }
  }

  Future<SensorDescription> describe<S extends DeviceSnapshot>(
    Entity<S> sensor, {
    CancellationToken? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    final address = sensor._address(_context);
    _context.assertAvailable(address);
    if (sensor.mode == EntityMode.state) {
      throw const DeviceReadoutException(
        ErrorCode.unsupportedEntity,
        'Metadata is available only for sensor entities.',
      );
    }
    final source = _context.sensorSources[_key(address)];
    if (source == null) {
      throw const DeviceReadoutException(
        ErrorCode.unsupportedEntity,
        'No sensor description source is registered for this target.',
      );
    }
    final operation = CancellationToken();
    DeviceReadoutException? invalidated;
    final detachFailure = _context.listen((change) {
      if (change.affects(address) && change.error != null) {
        invalidated ??= change.error;
        operation.cancel();
      }
    });
    final detachCaller = cancellation?.listen(operation.cancel);
    final detachLifetime = _context.lifetime.listen(operation.cancel);
    try {
      final value = await _context.channel.read(
        address,
        SensorSamplingRate.platformDefault,
        readTimeout,
        operation,
        observed: source.description ?? SensorDescription(),
        description: true,
      );
      operation.throwIfCancelled();
      _context.assertAvailable(address);
      return value as SensorDescription;
    } catch (error) {
      if (invalidated != null) throw invalidated!;
      rethrow;
    } finally {
      detachFailure();
      detachCaller?.call();
      detachLifetime();
    }
  }

  Stream<S> watch<S extends DeviceSnapshot>(Entity<S> entity) =>
      entity.mode == EntityMode.state
      ? _StateWatch<S>(this, entity).stream
      : _SensorStream<S>(this, entity).stream;

  /// Signals cancellation immediately. Native resources are disposed in their
  /// owning isolate after any already-running native call has returned.
  void dispose() {
    if (_context.closed) return;
    _context.closed = true;
    _context.lifetime.cancel();
    _context.sensorSources.clear();
    _context.scopedFailures.clear();
    _context.channel.close();
  }
}

Duration _positive(Duration duration) {
  if (duration <= Duration.zero) {
    throw const DeviceReadoutException(
      ErrorCode.invalidConfiguration,
      'The duration must be positive.',
    );
  }
  return duration;
}

final class EntityCollection<S extends DeviceSnapshot> {
  final DeviceAccess _access;
  final Entity<S> _kind;
  EntityCollection._(this._access, this._kind);
  Future<List<Entity<S>>> list({CancellationToken? cancellation}) =>
      _access.list(_kind, cancellation: cancellation);
  Future<Entity<S>?> current({CancellationToken? cancellation}) =>
      _access.current(_kind, cancellation: cancellation);
}

final class _AccessContext {
  final CollectionChannel channel;
  final lifetime = CancellationToken();
  final observed = <_EntityKey, DeviceSnapshot?>{};
  final targets = <_EntityKey, Entity<DeviceSnapshot>>{};
  final nativeAddresses = <_EntityKey, EntityAddress>{};
  final nativeTargets = <_EntityKey, Entity<DeviceSnapshot>>{};
  final failures = <_EntityKey, DeviceReadoutException>{};
  final scopedFailures = <_EntityKey, Map<Object, DeviceReadoutException>>{};
  final removed = <_EntityKey>{};
  final knownCollections = <EntityKind>{};
  final nativeCollections = <EntityKind>{};
  final currentTargets = <EntityKind, Entity<DeviceSnapshot>?>{};
  final permissionStates = <_EntityKey, PermissionStatus?>{};
  final sensorSources = <_EntityKey, _SensorRegistration>{};
  bool sensorsActive = true;
  int sensorActivityGeneration = 0;
  final sensorActivityListeners = <void Function(bool)>{};
  _PermissionCoordinatorRegistration? permissionCoordinator;
  final _listeners = <void Function(_ObservedChange)>{};
  bool closed = false;
  _AccessContext(this.channel);
  PermissionStatus? permissionFor(EntityAddress address) =>
      permissionStates[permissionStates.containsKey(_key(address))
          ? _key(address)
          : (address.kind, null)];
  void assertLive(EntityAddress entity) {
    if (closed) throw const DeviceReadoutCancelled();
    if (removed.contains(_key(entity))) {
      throw const DeviceReadoutException(
        ErrorCode.entityRemoved,
        'The observed target was removed.',
      );
    }
  }

  DeviceReadoutException? failureFor(EntityAddress entity) {
    DeviceReadoutException? at(_EntityKey key) =>
        failures[key] ?? scopedFailures[key]?.values.firstOrNull;
    return at(_key(entity)) ?? at((entity.kind, null));
  }

  void reportFailure(EntityAddress address, DeviceReadoutException error) {
    final change = _ObservedChange(address, error: error);
    for (final key in observed.keys.toList()) {
      final address =
          targets[key]?._address(this) ??
          EntityAddress(key.$1, key.$2 as String?);
      if (change.affects(address)) observed[key] = null;
    }
    notify(change);
  }

  void assertAvailable(EntityAddress entity) {
    assertLive(entity);
    final error = failureFor(entity);
    if (error != null) throw error;
  }

  void Function() listen(void Function(_ObservedChange) listener) {
    _listeners.add(listener);
    return () {
      _listeners.remove(listener);
    };
  }

  void notify(_ObservedChange change) {
    for (final listener in _listeners.toList()) {
      listener(change);
    }
  }

  Future<DeviceSnapshot> firstObserved(
    EntityAddress address,
    Duration timeout,
    CancellationToken? cancellation,
  ) async {
    final result = Completer<DeviceSnapshot>();
    void fail(Object error) {
      if (!result.isCompleted) result.completeError(error);
    }

    final detach = listen((change) {
      if (change.affects(address) &&
          change.snapshot != null &&
          !result.isCompleted) {
        result.complete(change.snapshot!);
      }
    });
    final detachCaller = cancellation?.listen(
      () => fail(const DeviceReadoutCancelled()),
    );
    final detachLifetime = lifetime.listen(
      () => fail(const DeviceReadoutCancelled()),
    );
    final timer = Timer(
      timeout,
      () => fail(
        const DeviceReadoutException(
          ErrorCode.readTimeout,
          'No initial observed state arrived before the deadline.',
        ),
      ),
    );
    try {
      return await result.future;
    } finally {
      timer.cancel();
      detach();
      detachCaller?.call();
      detachLifetime();
    }
  }
}
