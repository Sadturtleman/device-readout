import 'core.dart';

abstract interface class CollectionChannel {
  bool get available;
  Future<EntityCapabilities> capabilities(
    EntityAddress entity,
    Duration timeout,
    CancellationToken cancellation,
  );
  Future<List<String>> list(
    EntityKind kind,
    Duration timeout,
    CancellationToken cancellation,
  );
  Future<String?> current(
    EntityKind kind,
    Duration timeout,
    CancellationToken cancellation,
  );

  /// A single null update selects common polling; it is never public SDK data.
  /// onCollected reports a completed non-null snapshot before consumer delivery.
  Stream<DeviceSnapshot?> watch(
    EntityAddress entity,
    Duration pollInterval,
    Duration readTimeout,
    CancellationToken cancellation, {
    void Function()? onCollected,
  });
  Future<DeviceSnapshot> read(
    EntityAddress entity,
    SensorSamplingRate rate,
    Duration timeout,
    CancellationToken? cancellation, {
    DeviceSnapshot? observed,
    bool description = false,
  });
  void close();
}
