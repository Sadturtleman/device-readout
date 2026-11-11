part of 'core.dart';

enum PermissionStatus {
  granted,
  denied,
  notDetermined,
  restricted,
  unavailable,
}

final class PermissionRequest {
  final EntityKind kind;
  final String? targetId;
  final CancellationToken cancellation;
  PermissionRequest(this.kind, this.targetId, this.cancellation);
}

typedef PermissionCoordinator = FutureOr<void> Function(
  PermissionRequest request,
);

final class PermissionAccess {
  final _AccessContext _context;
  PermissionAccess._(this._context);
  Future<PermissionStatus?> check<S extends DeviceSnapshot>(
    Entity<S> entity, {
    CancellationToken? cancellation,
  }) async {
    if (_context.closed) throw const DeviceReadoutCancelled();
    cancellation?.throwIfCancelled();
    return _context.permissionFor(entity._address(_context, collection: true));
  }

  Future<PermissionStatus?> request<S extends DeviceSnapshot>(
    Entity<S> entity, {
    CancellationToken? cancellation,
  }) async {
    if (_context.closed) throw const DeviceReadoutCancelled();
    cancellation?.throwIfCancelled();
    final address = entity._address(_context, collection: true);
    if (_context.permissionFor(address) == PermissionStatus.granted) {
      return PermissionStatus.granted;
    }
    final coordinator = _context.permissionCoordinator;
    if (coordinator == null) {
      throw const DeviceReadoutException(
        ErrorCode.unsupportedEntity,
        'Register an application permission coordinator before requesting permission.',
      );
    }
    final result = Completer<PermissionStatus?>();
    final operation = CancellationToken();
    void fail(Object error) {
      if (!result.isCompleted) result.completeError(error);
    }

    final detachChanges = _context.listen((change) {
      if (!change.permissionChanged || !change.affects(address)) return;
      final exact = _key(change.entity) == _key(address);
      if (exact || !_context.permissionStates.containsKey(_key(address))) {
        if (!result.isCompleted)
          result.complete(_context.permissionFor(address));
      }
    });
    final detachOperation = operation.listen(
      () => fail(const DeviceReadoutCancelled()),
    );
    final detachCaller = cancellation?.listen(operation.cancel);
    final detachLifetime = _context.lifetime.listen(operation.cancel);
    // The explicit app-owned coordinator may dispatch UI work. Schedule it after
    // returning to the caller, and always observe its asynchronous failures.
    unawaited(
      Future<void>(() async {
        if (operation.isCancelled) return;
        try {
          await coordinator.callback(
            PermissionRequest(address.kind, address.targetId, operation),
          );
        } catch (error) {
          fail(
            error is DeviceReadoutException || error is DeviceReadoutCancelled
                ? error
                : DeviceReadoutException(
                    ErrorCode.readFailed,
                    'The application permission coordinator failed: $error',
                  ),
          );
        }
      }),
    );
    try {
      return await result.future;
    } finally {
      detachChanges();
      detachCaller?.call();
      detachLifetime();
      detachOperation();
      operation.cancel();
    }
  }
}

final class _PermissionCoordinatorRegistration {
  final PermissionCoordinator callback;
  _PermissionCoordinatorRegistration(this.callback);
}
