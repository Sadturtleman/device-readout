import 'core.dart';
import 'transport_api.dart';

const hasCollectionWorker = false;
const supportsSensorSources = hasCollectionWorker;

CollectionChannel createChannel(
  CollectorFactory factory,
  Object? initialData,
) => _UnsupportedChannel();

DeviceCollector createNativeCollector(Object? _) =>
    throw const DeviceReadoutException(
      ErrorCode.unsupportedEntity,
      'The Dart Web Worker bridge is not implemented.',
    );

final class _UnsupportedChannel implements CollectionChannel {
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
      'The Dart Web Worker bridge is not implemented.',
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
      'The Dart Web Worker bridge is not implemented.',
    );
  }

  @override
  Stream<DeviceSnapshot?> watch(
    EntityAddress entity,
    Duration pollInterval,
    Duration readTimeout,
    CancellationToken cancellation,
  ) async* {
    cancellation.throwIfCancelled();
    throw const DeviceReadoutException(
      ErrorCode.unsupportedEntity,
      'The Dart Web Worker bridge is not implemented.',
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
      'The Dart Web Worker bridge is not implemented.',
    );
  }

  @override
  void close() {}
}
