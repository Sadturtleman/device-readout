part of 'core.dart';

// Shallow projection for the browser encoder. Snapshot fields and collection
// elements are traversed only by the budgeted transport, never by toJson().
Object? workerWireValue(Object? value) => switch (value) {
  DeviceSnapshot snapshot => {
    'collectedAt': snapshot.collectedAt.toIso8601String(),
    ...snapshot._fields(),
  },
  Iterable<Object?> _ => value,
  Map<Object?, Object?> _ => value,
  _ => _jsonValue(value),
};

// Internal binding boundary: the owned worker has already normalized fields.
// This materializes Dart values without repeating unit/range normalization.
Future<DeviceSnapshot> hydrateWorkerSnapshot(
  EntityKind kind,
  Map<String, Object?> fields, {
  bool description = false,
  required WorkerTransferBudget budget,
}) {
  final collectedAt = DateTime.parse(fields['collectedAt'] as String).toUtc();
  return description
      ? SnapshotCodec._hydrateDescription(fields, collectedAt, budget)
      : SnapshotCodec._hydrate(kind, fields, collectedAt, budget);
}

// Internal browser binding helper. Each traversal shares a budget, including
// nested collections. Event-loop turns (not microtasks) admit host work.
final class WorkerTransferBudget {
  final void Function() check;
  final _slice = Stopwatch()..start();
  int _steps = 0;
  WorkerTransferBudget(this.check);
  Future<void>? checkpoint() {
    check();
    if (++_steps < 512 && _slice.elapsedMilliseconds < 4) return null;
    return _yield();
  }

  Future<void> _yield() async {
    await Future<void>.delayed(Duration.zero);
    check();
    _steps = 0;
    _slice.reset();
  }
}

Future<List<T>?> _wireList<T>(
  Object? value,
  T? Function(Object?) read,
  WorkerTransferBudget budget,
) async {
  if (value is! Iterable<Object?>) return null;
  final result = <T>[];
  for (final raw in value) {
    final pause = budget.checkpoint();
    if (pause != null) await pause;
    final item = read(raw);
    if (item == null) return null;
    result.add(item);
  }
  budget.check();
  // The mutable backing collection never escapes and is never changed again.
  return UnmodifiableListView(result);
}

Future<Set<T>?> _wireSet<T>(
  Object? value,
  T? Function(Object?) read,
  WorkerTransferBudget budget,
) async {
  if (value is! Iterable<Object?>) return null;
  final result = <T>{};
  for (final raw in value) {
    final pause = budget.checkpoint();
    if (pause != null) await pause;
    final item = read(raw);
    if (item == null) return null;
    result.add(item);
  }
  budget.check();
  return UnmodifiableSetView(result);
}

Future<Map<K, V>?> _wireMap<K, V>(
  Object? value,
  K? Function(Object?) key,
  V? Function(Object?) read,
  WorkerTransferBudget budget,
) async {
  if (value is! Map<Object?, Object?>) return null;
  final result = <K, V>{};
  for (final entry in value.entries) {
    final pause = budget.checkpoint();
    if (pause != null) await pause;
    final k = key(entry.key), v = read(entry.value);
    if (k == null || v == null || result.containsKey(k)) return null;
    result[k] = v;
  }
  budget.check();
  return UnmodifiableMapView(result);
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
