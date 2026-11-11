part of 'core.dart';

/// Operation support, independent of permission and individual field coverage.
/// False means unavailable; null means the adapter cannot determine support.
final class EntityCapabilities {
  final bool? readable;
  final bool? watchable;
  const EntityCapabilities({required this.readable, required this.watchable});
}

const _unavailableCapabilities = EntityCapabilities(
  readable: false,
  watchable: false,
);

final class CapabilityAccess {
  final DeviceAccess _access;
  CapabilityAccess._(this._access);

  Future<EntityCapabilities> get<S extends DeviceSnapshot>(
    Entity<S> entity, {
    CancellationToken? cancellation,
  }) async {
    final context = _access._context;
    if (context.closed) throw const DeviceReadoutCancelled();
    cancellation?.throwIfCancelled();
    final address = entity._address(context, collection: true);
    final known = _known(entity, address);
    if (known != null) return known;
    final operation = CancellationToken();
    final detachCaller = cancellation?.listen(operation.cancel);
    final detachLifetime = context.lifetime.listen(operation.cancel);
    final detachRemoval = context.listen((change) {
      if (change.affects(address) && context.removed.contains(_key(address))) {
        operation.cancel();
      }
    });
    try {
      final answer = await context.channel.capabilities(
        context.nativeAddress(address),
        _access.readTimeout,
        operation,
      );
      cancellation?.throwIfCancelled();
      context.lifetime.throwIfCancelled();
      return _known(entity, address) ?? answer;
    } catch (error) {
      cancellation?.throwIfCancelled();
      context.lifetime.throwIfCancelled();
      if (error is DeviceReadoutException &&
          error.code == ErrorCode.entityRemoved) {
        context.retireNative(address);
      }
      if (context.removed.contains(_key(address)))
        return _unavailableCapabilities;
      rethrow;
    } finally {
      detachCaller?.call();
      detachLifetime();
      detachRemoval();
    }
  }

  EntityCapabilities? _known<S extends DeviceSnapshot>(
    Entity<S> entity,
    EntityAddress address,
  ) {
    final context = _access._context, key = _key(address);
    if (!platform.hasCollectionWorker || context.removed.contains(key)) {
      return _unavailableCapabilities;
    }
    bool registered(EntityAddress target) =>
        !context.removed.contains(_key(target)) &&
        (entity.mode == EntityMode.state
            ? context.observed.containsKey(_key(target))
            : context.sensorSources.containsKey(_key(target)));
    if (entity._targeted &&
        address.targetId == null &&
        (context.knownCollections.contains(entity.kind) ||
            entity.mode != EntityMode.state)) {
      final available = context.targets.values.any(
        (target) =>
            target.kind == entity.kind && registered(target._address(context)),
      );
      return EntityCapabilities(readable: available, watchable: available);
    }
    if (context.observed.containsKey(key) ||
        context.sensorSources.containsKey(key)) {
      final available = registered(address);
      return EntityCapabilities(readable: available, watchable: available);
    }
    // Sensor get/watch currently consume explicit observer sources only. Native
    // metadata must not advertise a path that this runtime cannot execute.
    return entity.mode == EntityMode.state ? null : _unavailableCapabilities;
  }
}
