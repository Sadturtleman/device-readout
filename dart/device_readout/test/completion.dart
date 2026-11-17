import 'package:device_readout/device_readout.dart';

import 'observers.dart' show check, forbiddenNativeFactory;

Future<void> completedSnapshotsRetainValues() async {
  final suppliedAt = DateTime.utc(2000, 1, 2, 3, 4, 5);
  final decoded = SnapshotCodec.decode(EntityKind.display, {
    'brightness': 0.5,
  }, collectedAt: suppliedAt);
  final decodedDescription = SnapshotCodec.describe({
    'name': 'decoded',
  }, collectedAt: suppliedAt);
  check(
    decoded.collectedAt == suppliedAt &&
        decodedDescription.collectedAt == suppliedAt,
    'The low-level decoder preserves explicit source timestamps.',
  );
  check(
    SnapshotCodec.decode(
              EntityKind.ram,
              {},
            ).collectedAt.millisecondsSinceEpoch ==
            0 &&
        SnapshotCodec.describe({}).collectedAt.millisecondsSinceEpoch == 0,
    'Decoding without an explicit timestamp retains the epoch default.',
  );

  final sdk = DeviceAccess.isolated(forbiddenNativeFactory);
  try {
    final target = sdk.observers.target(Entities.display, 'observed');
    final supplied = DisplaySnapshot(
      collectedAt: suppliedAt,
      label: 'External',
      primary: false,
      brightness: double.nan,
      logicalBounds: const Rect(-1280, 0, 1280, 720),
      scaleFactor: 2,
      supportedModes: const [
        DisplayMode(pixelSize: Size(1920, 1080), refreshRateHz: double.nan),
        DisplayMode(refreshRateHz: 60),
      ],
      hdrFormats: {},
    );
    sdk.observers.publish(target, supplied);
    final beforeRead = DateTime.now().toUtc();
    final read = await sdk.get(target);
    final beforeWatch = DateTime.now().toUtc();
    final watched = await sdk.watch(target).first;
    check(
      !read.collectedAt.isBefore(beforeRead) &&
          !watched.collectedAt.isBefore(beforeWatch) &&
          !watched.collectedAt.isAfter(DateTime.now().toUtc()) &&
          read.collectedAt.isUtc &&
          watched.collectedAt.isUtc,
      'get and watch supply fresh worker completion timestamps.',
    );
    for (final value in [read, watched]) {
      check(
        value.label == 'External' &&
            value.primary == false &&
            value.brightness == null &&
            value.logicalBounds?.x == -1280 &&
            value.scaleFactor == 2 &&
            value.hdrFormats?.isEmpty == true &&
            value.supportedModes?.length == 2 &&
            value.supportedModes?[0].pixelSize?.width == 1920 &&
            value.supportedModes?[0].refreshRateHz == null &&
            value.supportedModes?[1].pixelSize == null &&
            value.supportedModes?[1].refreshRateHz == 60,
        'Completion preserves independent normalized fields and empty collections.',
      );
      Object? failure;
      try {
        value.supportedModes!.clear();
      } catch (error) {
        failure = error;
      }
      check(
        failure is UnsupportedError,
        'Completed mode collections stay immutable.',
      );
    }
    check(
      supplied.collectedAt == suppliedAt &&
          supplied.brightness!.isNaN &&
          supplied.supportedModes![0].refreshRateHz!.isNaN,
      'Completion must not mutate the source snapshot.',
    );

    final sensor = sdk.observers.target(Entities.pressure, 'pressure');
    final description = SensorDescription(
      collectedAt: suppliedAt,
      kind: SensorKind.accelerometer,
      name: 'Barometer',
      vendor: 'Fixture',
      version: '2',
      reportingMode: SensorReportingMode.continuous,
      minimumInterval: const Duration(milliseconds: -1),
      maximumInterval: const Duration(seconds: 1),
      maximumRange: double.infinity,
      resolution: 0.01,
      powerMilliamps: 0,
      fifoCapacity: 64,
    );
    sdk.observers.sensorSource(
      sensor,
      SensorObserverSource<PressureSnapshot>(
        description: description,
        subscribe: (_) =>
            throw StateError('Metadata must not start a measurement.'),
      ),
    );
    final beforeDescription = DateTime.now().toUtc();
    final metadata = await sdk.describe(sensor);
    check(
      !metadata.collectedAt.isBefore(beforeDescription) &&
          metadata.collectedAt.isUtc &&
          !metadata.collectedAt.isAfter(DateTime.now().toUtc()),
      'Descriptions receive fresh completion timestamps in UTC.',
    );
    check(
      metadata.kind == SensorKind.pressure &&
          metadata.name == 'Barometer' &&
          metadata.vendor == 'Fixture' &&
          metadata.version == '2' &&
          metadata.reportingMode == SensorReportingMode.continuous &&
          metadata.minimumInterval == null &&
          metadata.maximumInterval == const Duration(seconds: 1) &&
          metadata.maximumRange == null &&
          metadata.resolution == 0.01 &&
          metadata.powerMilliamps == 0 &&
          metadata.fifoCapacity == 64,
      'Description completion preserves normalized metadata and the requested kind.',
    );
    check(
      description.collectedAt == suppliedAt &&
          description.kind == SensorKind.accelerometer &&
          description.maximumRange!.isInfinite,
      'Description completion leaves supplied metadata unchanged.',
    );
  } finally {
    sdk.dispose();
  }
}

final checks = <String, Future<void> Function()>{
  'completion preserves normalized state and metadata without changing decoder timestamps':
      completedSnapshotsRetainValues,
};

Future<void> main() async {
  await completedSnapshotsRetainValues().timeout(const Duration(seconds: 12));
  print(
    'PASS completed snapshots preserve normalized values and timestamp ownership',
  );
}
