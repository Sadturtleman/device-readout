library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;

import 'transport_api.dart';
import 'transport_stub.dart'
    if (dart.library.io) 'transport_native.dart'
    if (dart.library.js_interop) 'transport_web.dart'
    as platform;

part 'models.dart';
part 'wire.dart';
part 'generated.dart';
part 'access.dart';
part 'discovery.dart';
part 'capabilities.dart';
part 'observers.dart';
part 'state_watch.dart';
part 'permissions.dart';
part 'sensor_sources.dart';

/// The factory runs inside the collection isolate. Use a top-level or static
/// function and sendable initial data; do not capture UI objects or open handles.
typedef CollectorFactory = FutureOr<DeviceCollector> Function(
  Object? initialData,
);

abstract interface class DeviceCollector {
  FutureOr<DeviceSnapshot> read(EntityAddress entity, ReadContext context);
  FutureOr<void> dispose();
}

/// Optional support probe. Do not read snapshots, subscribe to sources or
/// request permission. Unknown support is null, independent of permission.
abstract interface class DeviceCapabilityCollector {
  FutureOr<EntityCapabilities> capabilities(
    EntityAddress entity,
    ReadContext context,
  );
}

/// Optional native inventory. Identities are adapter-local and must remain
/// stable while a target lives. Return an empty list only after a successful
/// enumeration; current returns the platform-selected identity or null.
abstract interface class DeviceDiscoveryCollector {
  FutureOr<List<String>> list(EntityKind kind, ReadContext context);
  FutureOr<String?> current(EntityKind kind, ReadContext context);
}

/// Deferred collection work, executed and normalized in the owning isolate.
typedef SnapshotRead = FutureOr<DeviceSnapshot> Function();

/// Optional native state stream. Include its initial read; null selects the
/// common polling implementation. Observation setup and teardown stay worker-owned.
abstract interface class DeviceStateCollector {
  Stream<SnapshotRead>? watch(EntityAddress entity, StateWatchContext context);
}

final class StateWatchContext {
  final CancellationToken cancellation;
  final Duration pollInterval;
  final Duration readTimeout;
  StateWatchContext(this.cancellation, this.pollInterval, this.readTimeout);
}

final class ReadContext {
  final CancellationToken cancellation;
  final SensorSamplingRate sensorSamplingRate;
  final Duration readTimeout;
  ReadContext(
    this.cancellation,
    this.sensorSamplingRate, {
    this.readTimeout = const Duration(seconds: 5),
  });
}

/// Internal transport boundary. Normalization and stamping run in the worker.
DeviceSnapshot prepareSnapshot(EntityKind kind, DeviceSnapshot snapshot) {
  if (snapshot is SensorDescription || snapshot.entityKind != kind) {
    throw const DeviceReadoutException(
      ErrorCode.readFailed,
      'The collector returned a different snapshot type.',
    );
  }
  if ((snapshot is StepDetectedSnapshot && snapshot.value != true) ||
      (snapshot is SignificantMotionSnapshot && snapshot.value != true)) {
    throw const DeviceReadoutException(
      ErrorCode.readFailed,
      'An occurrence sensor must publish an actual true event.',
    );
  }
  return SnapshotCodec.decode(kind, snapshot._fields())._collected();
}

SensorDescription prepareDescription(
  EntityKind kind,
  SensorDescription description,
) {
  final sensor = _sensorKind(kind);
  if (sensor == null) {
    throw const DeviceReadoutException(
      ErrorCode.unsupportedEntity,
      'Metadata is available only for sensor entities.',
    );
  }
  return SnapshotCodec.describe({...description._fields(), 'kind': sensor})
      ._collected();
}
