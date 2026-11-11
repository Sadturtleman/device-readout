part of 'core.dart';

extension _NativeDiscovery on DeviceAccess {
  Future<Object?> _discover<S extends DeviceSnapshot>(
    Entity<S> kind, {
    bool current = false,
    CancellationToken? cancellation,
  }) async {
    final address = kind._collectionAddress(_context);
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
      final result = current
          ? await _context.channel.current(kind.kind, readTimeout, operation)
          : await _context.channel.list(kind.kind, readTimeout, operation);
      operation.throwIfCancelled();
      _context.assertAvailable(address);
      return result;
    } catch (_) {
      if (invalidated != null) throw invalidated!;
      rethrow;
    } finally {
      detachFailure();
      detachCaller?.call();
      detachLifetime();
    }
  }
}

extension _NativeTargets on _AccessContext {
  EntityAddress nativeAddress(EntityAddress address) =>
      nativeAddresses[_key(address)] ?? address;

  Entity<S> bindNative<S extends DeviceSnapshot>(
    Entity<S> kind,
    String identity,
  ) {
    final sourceKey = (kind.kind, identity);
    final existing = nativeTargets[sourceKey];
    if (existing != null) return existing as Entity<S>;
    final opaque = Object();
    final target = Entity<S>._(
      kind.kind,
      kind.mode,
      true,
      this,
      identity,
      opaque,
    );
    final key = (kind.kind, opaque);
    targets[key] = target;
    nativeAddresses[key] = EntityAddress(kind.kind, identity);
    nativeTargets[sourceKey] = target;
    return target;
  }

  void retireNative(EntityAddress address) {
    final key = _key(address), native = nativeAddresses[_key(address)];
    if (native == null || !removed.add(key)) return;
    final sourceKey = _key(native);
    if (identical(nativeTargets[sourceKey], targets[key]))
      nativeTargets.remove(sourceKey);
    observed.remove(key);
    notify(
      _ObservedChange(
        address,
        error: const DeviceReadoutException(
          ErrorCode.entityRemoved,
          'The native target was removed.',
        ),
      ),
    );
  }
}
