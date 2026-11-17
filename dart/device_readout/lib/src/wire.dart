part of 'core.dart';

// Internal binding boundary: the owned worker has already normalized fields.
// This materializes Dart values without repeating unit/range normalization.
DeviceSnapshot hydrateWorkerSnapshot(
  EntityKind kind,
  Map<String, Object?> fields, {
  bool description = false,
}) {
  final collectedAt = DateTime.parse(fields['collectedAt'] as String).toUtc();
  return description
      ? SnapshotCodec._hydrateDescription(fields, collectedAt)
      : SnapshotCodec._hydrate(kind, fields, collectedAt);
}

int? _wireInteger(Object? value) => value as int?;
double? _wireNumber(Object? value) => (value as num?)?.toDouble();
BigInt? _wireCounter(Object? value) =>
    value == null ? null : BigInt.parse(value as String);
Duration? _wireDuration(Object? value) => value == null
    ? null
    : Duration(
        microseconds: ((value as num) * Duration.microsecondsPerMillisecond)
            .round(),
      );
Map<String, Object?> _wireObject(Object value) =>
    (value as Map<Object?, Object?>).cast<String, Object?>();

T? _wireComponents<T>(
  Object? value,
  List<String> keys,
  T Function(List<double>) create,
) {
  if (value == null) return null;
  final raw = _wireObject(value);
  return create(
    keys.map((key) => (raw[key] as num).toDouble()).toList(growable: false),
  );
}

Quaternion? _wireRotation(Object? value) => _wireComponents(value, [
  'x',
  'y',
  'z',
  'w',
], (n) => Quaternion(n[0], n[1], n[2], n[3]));
Size<int>? _wirePixelSize(Object? value) {
  if (value == null) return null;
  final raw = _wireObject(value);
  return Size(raw['width'] as int, raw['height'] as int);
}

DisplayMode? _wireDisplayMode(Object? value) {
  if (value == null) return null;
  final raw = _wireObject(value);
  return DisplayMode(
    pixelSize: _wirePixelSize(raw['pixelSize']),
    refreshRateHz: _wireNumber(raw['refreshRateHz']),
  );
}

IpAddressInfo? _wireAddressInfo(Object? value) {
  if (value == null) return null;
  final raw = _wireObject(value);
  return IpAddressInfo(
    raw['address'] as String,
    prefixLength: raw['prefixLength'] as int?,
  );
}

NetworkRoute? _wireRoute(Object? value) {
  if (value == null) return null;
  final raw = _wireObject(value);
  return NetworkRoute(
    raw['destination'] as String,
    prefixLength: raw['prefixLength'] as int?,
    gateway: raw['gateway'] as String?,
  );
}
