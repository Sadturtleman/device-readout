import 'core.dart';
import 'transport_api.dart';

CollectionChannel createWebChannel(Uri workerUri) => _UnsupportedChannel();

CollectionChannel createChannel(
  CollectorFactory factory,
  Object? initialData,
) => _UnsupportedChannel();

DeviceCollector createNativeCollector(Object? _) =>
    throw const DeviceReadoutException(
      ErrorCode.unsupportedEntity,
      'No collection worker is connected. Browser callers must use DeviceAccess.web with a worker asset.',
    );

final class _UnsupportedChannel implements CollectionChannel {
  @override
  bool get available => false;
  @override
  Future<EntityCapabilities> capabilities(
    EntityAddress entity,
    Duration timeout,
    CancellationToken cancellation,
  ) async {
    cancellation.throwIfCancelled();
    return const EntityCapabilities(readable: false, watchable: false);
  }

  @override
  Future<List<String>> list(
    EntityKind kind,
    Duration timeout,
    CancellationToken cancellation,
  ) async {
    cancellation.throwIfCancelled();
    throw const DeviceReadoutException(
      ErrorCode.unsupportedEntity,
      'No collection worker is connected. Browser callers must use DeviceAccess.web with a worker asset.',
    );
  }

  @override
  Future<String?> current(
    EntityKind kind,
    Duration timeout,
    CancellationToken cancellation,
  ) async {
    cancellation.throwIfCancelled();
    throw const DeviceReadoutException(
      ErrorCode.unsupportedEntity,
      'No collection worker is connected. Browser callers must use DeviceAccess.web with a worker asset.',
    );
  }

  @override
  Stream<DeviceSnapshot?> watch(
    EntityAddress entity,
    Duration pollInterval,
    Duration readTimeout,
    CancellationToken cancellation, {
    void Function()? onCollected,
  }) async* {
    cancellation.throwIfCancelled();
    throw const DeviceReadoutException(
      ErrorCode.unsupportedEntity,
      'No collection worker is connected. Browser callers must use DeviceAccess.web with a worker asset.',
    );
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
    cancellation?.throwIfCancelled();
    throw const DeviceReadoutException(
      ErrorCode.unsupportedEntity,
      'No collection worker is connected. Browser callers must use DeviceAccess.web with a worker asset.',
    );
  }

  @override
  void close() {}
}
