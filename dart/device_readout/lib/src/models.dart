part of 'core.dart';

enum ErrorCode {
  unsupportedEntity,
  permissionDenied,
  entityRemoved,
  readTimeout,
  readFailed,
  invalidConfiguration,
}

final class DeviceReadoutException implements Exception {
  final ErrorCode code;
  final String message;
  const DeviceReadoutException(this.code, this.message);
  @override
  String toString() => 'DeviceReadoutException(${code.name}): $message';
}

final class DeviceReadoutCancelled implements Exception {
  const DeviceReadoutCancelled();
  @override
  String toString() => 'DeviceReadout operation cancelled.';
}

/// Explicit cancellation for Dart futures, which do not have built-in cancel.
final class CancellationToken {
  bool _cancelled = false;
  final Set<void Function()> _listeners = {};
  bool get isCancelled => _cancelled;
  void throwIfCancelled() {
    if (_cancelled) throw const DeviceReadoutCancelled();
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    final listeners = _listeners.toList();
    _listeners.clear();
    for (final listener in listeners) {
      _notify(listener);
    }
  }

  static void _notify(void Function() listener) {
    try {
      listener();
    } catch (_) {
      // Cancellation is terminal. One failed cleanup cannot skip the other
      // owners or escape into the application/collection isolate's event loop.
    }
  }

  /// Returns a detach function. Callbacks must be nonblocking; their synchronous
  /// errors are contained so that all owners still receive cancellation.
  void Function() listen(void Function() listener) {
    if (_cancelled) {
      _notify(listener);
      return () {};
    }
    _listeners.add(listener);
    return () {
      _listeners.remove(listener);
    };
  }
}

enum EntityMode { state, sample, event }

final class EntityAddress {
  final EntityKind kind;
  final String? targetId;
  final Object? _targetKey;
  const EntityAddress(this.kind, [this.targetId]) : _targetKey = null;
  const EntityAddress._(this.kind, this.targetId, this._targetKey);
}

final class Entity<S extends DeviceSnapshot> {
  final EntityKind kind;
  final EntityMode mode;
  final bool _targeted;
  final Object? _owner;
  final String? _targetId;
  final Object? _targetKey;
  const Entity._(
    this.kind,
    this.mode,
    this._targeted, [
    this._owner,
    this._targetId,
    this._targetKey,
  ]);
  EntityAddress _address(Object owner, {bool collection = false}) {
    if (_owner != null && !identical(_owner, owner)) {
      throw const DeviceReadoutException(
        ErrorCode.invalidConfiguration,
        'This entity belongs to another DeviceAccess context.',
      );
    }
    if (_targeted && _targetId == null && !collection) {
      throw const DeviceReadoutException(
        ErrorCode.invalidConfiguration,
        'Discover or observe a target before reading this entity.',
      );
    }
    return EntityAddress._(kind, _targetId, _targetKey);
  }

  EntityAddress _collectionAddress(Object owner) {
    final address = _address(owner, collection: true);
    if (!_targeted || _targetId != null) {
      throw const DeviceReadoutException(
        ErrorCode.invalidConfiguration,
        'Expected a multi-target entity kind.',
      );
    }
    return address;
  }
}

final class SensorSamplingRate {
  final double? hertz;
  const SensorSamplingRate._(this.hertz);
  static const platformDefault = SensorSamplingRate._(null);
  factory SensorSamplingRate.atHertz(double hertz) {
    if (!hertz.isFinite || hertz <= 0) {
      throw const DeviceReadoutException(
        ErrorCode.invalidConfiguration,
        'Sampling frequency must be positive and finite.',
      );
    }
    return SensorSamplingRate._(hertz);
  }
}

sealed class DeviceSnapshot {
  final DateTime collectedAt;
  DeviceSnapshot({DateTime? collectedAt})
    : collectedAt =
          (collectedAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true))
              .toUtc();
  DeviceSnapshot._completed() : collectedAt = DateTime.now().toUtc();
  DeviceSnapshot _collected();
  EntityKind? get entityKind;
  Map<String, Object?> _fields();
  Map<String, Object?> toJson() => {
    'collectedAt': collectedAt.toIso8601String(),
    for (final entry in _fields().entries) entry.key: _jsonValue(entry.value),
  };
  String toJsonString() => jsonEncode(toJson());
}

abstract interface class ThermalState {}

final class Size<T extends num> {
  final T width, height;
  const Size(this.width, this.height);
}

final class Rect {
  final double x, y, width, height;
  const Rect(this.x, this.y, this.width, this.height);
}

final class Insets {
  final double top, right, bottom, left;
  const Insets(this.top, this.right, this.bottom, this.left);
}

final class Vector3 {
  final double x, y, z;
  const Vector3(this.x, this.y, this.z);
}

final class Quaternion {
  final double x, y, z, w;
  const Quaternion(this.x, this.y, this.z, this.w);
}

final class DisplayMode {
  final Size<int>? pixelSize;
  final double? refreshRateHz;
  const DisplayMode({this.pixelSize, this.refreshRateHz});
}

final class IpAddressInfo {
  final String address;
  final int? prefixLength;
  const IpAddressInfo(this.address, {this.prefixLength});
}

final class NetworkRoute {
  final String destination;
  final int? prefixLength;
  final String? gateway;
  const NetworkRoute(this.destination, {this.prefixLength, this.gateway});
}

Object? _jsonValue(Object? value) => switch (value) {
  BigInt v => v.toString(),
  DateTime v => v.toUtc().toIso8601String(),
  Duration v => v.inMicroseconds / Duration.microsecondsPerMillisecond,
  AndroidThermalState v => 'AndroidThermalState.${v.wireName}',
  AppleThermalState v => 'AppleThermalState.${v.wireName}',
  _WireEnum v => v.wireName,
  Size v => {'width': v.width, 'height': v.height},
  Rect v => {'x': v.x, 'y': v.y, 'width': v.width, 'height': v.height},
  Insets v => {
    'top': v.top,
    'right': v.right,
    'bottom': v.bottom,
    'left': v.left,
  },
  Vector3 v => {'x': v.x, 'y': v.y, 'z': v.z},
  Quaternion v => {'x': v.x, 'y': v.y, 'z': v.z, 'w': v.w},
  DisplayMode v => {
    'pixelSize': _jsonValue(v.pixelSize),
    'refreshRateHz': v.refreshRateHz,
  },
  IpAddressInfo v => {'address': v.address, 'prefixLength': v.prefixLength},
  NetworkRoute v => {
    'destination': v.destination,
    'prefixLength': v.prefixLength,
    'gateway': v.gateway,
  },
  Iterable<Object?> v => v.map(_jsonValue).toList(growable: false),
  Map<Object?, Object?> v => {
    for (final e in v.entries)
      _jsonValue(e.key).toString(): _jsonValue(e.value),
  },
  _ => value,
};

abstract interface class _WireEnum {
  String get wireName;
}

T? _enumValue<T extends _WireEnum>(Object? raw, List<T> values) {
  for (final value in values) {
    if (identical(raw, value) || raw == value.wireName) return value;
  }
  return null;
}

double? _number(Object? v) => v is num && v.isFinite ? v.toDouble() : null;
double? _ratio(Object? v) {
  final n = _number(v);
  return n != null && n >= 0 && n <= 1 ? n : null;
}

int? _integer(Object? v) => v is int ? v : null;
BigInt? _counter(Object? v, {bool signed = false}) {
  final n = v is BigInt
      ? v
      : v is int
      ? BigInt.from(v)
      : v is String
      ? BigInt.tryParse(v)
      : null;
  final min = signed ? -(BigInt.one << 63) : BigInt.zero;
  final max = (BigInt.one << (signed ? 63 : 64)) - BigInt.one;
  return n != null && n >= min && n <= max ? n : null;
}

Duration? _duration(Object? v) {
  if (v is Duration) return v.isNegative ? null : v;
  final ms = _number(v);
  // Preserve exact microsecond conversion and reject overflow before toInt.
  if (ms == null || ms < 0 || ms > 9007199254740) return null;
  return Duration(microseconds: (ms * 1000).round());
}

List<T>? _list<T>(Object? v, T? Function(Object?) read) {
  if (v is! Iterable<Object?>) return null;
  final result = <T>[];
  for (final raw in v) {
    final item = read(raw);
    if (item == null) return null;
    result.add(item);
  }
  return List.unmodifiable(result);
}

Set<T>? _set<T>(Object? v, T? Function(Object?) read) {
  final items = _list(v, read);
  return items == null ? null : Set.unmodifiable(items);
}

Map<K, V>? _map<K, V>(
  Object? raw,
  K? Function(Object?) key,
  V? Function(Object?) value,
) {
  if (raw is! Map<Object?, Object?>) return null;
  final result = <K, V>{};
  for (final entry in raw.entries) {
    final k = key(entry.key), v = value(entry.value);
    if (k == null || v == null || result.containsKey(k)) return null;
    result[k] = v;
  }
  return Map.unmodifiable(result);
}

Map<String, Object?>? _object(Object? v) {
  final raw = _jsonValue(v);
  return raw is Map<String, Object?> ? raw : null;
}

T? _components<T>(
  Object? value,
  List<String> keys,
  T Function(List<double>) create,
) {
  final raw = _object(value);
  if (raw == null) return null;
  final numbers = keys.map((k) => _number(raw[k])).toList();
  return numbers.any((n) => n == null) ? null : create(numbers.cast<double>());
}

Size<int>? _pixelSize(Object? v) {
  final o = _object(v);
  final w = _integer(o?['width']), h = _integer(o?['height']);
  return w == null || h == null ? null : Size(w, h);
}

Quaternion? _rotation(Object? value) {
  final q = _components(value, [
    'x',
    'y',
    'z',
    'w',
  ], (n) => Quaternion(n[0], n[1], n[2], n[3]));
  if (q == null) return null;
  final scale = math.max(
    math.max(q.x.abs(), q.y.abs()),
    math.max(q.z.abs(), q.w.abs()),
  );
  if (scale == 0) return null;
  final x = q.x / scale, y = q.y / scale, z = q.z / scale, w = q.w / scale;
  final length = math.sqrt(x * x + y * y + z * z + w * w);
  return Quaternion(x / length, y / length, z / length, w / length);
}

DisplayMode? _displayMode(Object? v) {
  final o = _object(v);
  return o == null
      ? null
      : DisplayMode(
          pixelSize: _pixelSize(o['pixelSize']),
          refreshRateHz: _number(o['refreshRateHz']),
        );
}

IpAddressInfo? _addressInfo(Object? v) {
  final o = _object(v), address = o?['address'];
  return address is String
      ? IpAddressInfo(address, prefixLength: _integer(o?['prefixLength']))
      : null;
}

NetworkRoute? _route(Object? v) {
  final o = _object(v), destination = o?['destination'];
  return destination is String
      ? NetworkRoute(
          destination,
          prefixLength: _integer(o?['prefixLength']),
          gateway: o?['gateway'] is String ? o!['gateway'] as String : null,
        )
      : null;
}

ThermalState? _thermal(Object? v) {
  if (v is AndroidThermalState || v is AppleThermalState)
    return v as ThermalState;
  if (v is! String) return null;
  if (v.startsWith('AndroidThermalState.')) {
    return _enumValue<AndroidThermalState>(
      v.substring(20),
      AndroidThermalState.values,
    );
  }
  if (v.startsWith('AppleThermalState.')) {
    return _enumValue<AppleThermalState>(
      v.substring(18),
      AppleThermalState.values,
    );
  }
  return null;
}
