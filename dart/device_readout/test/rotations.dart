import 'package:device_readout/device_readout.dart';

import 'observers.dart' show check, forbiddenNativeFactory;

Future<void> unitRotations() async {
  await _checkRotations(
    Entities.relativeOrientation,
    (value) => RelativeOrientationSnapshot(value: value),
    (snapshot) => snapshot.value,
  );
  await _checkRotations(
    Entities.absoluteOrientation,
    (value) => AbsoluteOrientationSnapshot(value: value),
    (snapshot) => snapshot.value,
  );
}

Future<void> _checkRotations<S extends DeviceSnapshot>(
  Entity<S> kind,
  S Function(Quaternion?) make,
  Quaternion? Function(S) rotation,
) async {
  final samples = <Quaternion?>[
    const Quaternion(double.nan, 0, 0, 1),
    const Quaternion(0, double.infinity, 0, 1),
    const Quaternion(0, 0, double.negativeInfinity, 1),
    const Quaternion(0, 0, 0, double.nan),
    null,
    const Quaternion(0, 0, 0, 0),
    const Quaternion(0, 0, 0, 1),
    const Quaternion(0, 0, 0, -1),
    const Quaternion(0, 0, 3, 4),
    const Quaternion(0, 0, -3, -4),
    const Quaternion(double.maxFinite, double.maxFinite, 0, 0),
    const Quaternion(double.minPositive, 0, 0, 0),
  ];
  final expected = <Quaternion?>[
    null,
    null,
    null,
    null,
    null,
    null,
    const Quaternion(0, 0, 0, 1),
    const Quaternion(0, 0, 0, -1),
    const Quaternion(0, 0, 0.6, 0.8),
    const Quaternion(0, 0, -0.6, -0.8),
    const Quaternion(0.7071067811865475, 0.7071067811865475, 0, 0),
    const Quaternion(1, 0, 0, 0),
  ];
  final sdk = DeviceAccess.isolated(forbiddenNativeFactory);
  final target = sdk.observers.target(kind, 'rotation');
  var initialSample = 0;
  sdk.observers.sensorSource(
    target,
    SensorObserverSource<S>(
      subscribe: (session) {
        for (final value in samples.skip(initialSample)) {
          session.publish(make(value));
        }
        return null;
      },
    ),
  );
  try {
    final snapshots = await sdk.watch(target).take(samples.length).toList();
    for (var i = 0; i < expected.length; i++) {
      initialSample = i;
      final fromGet = rotation(await sdk.get(target));
      for (final actual in [fromGet, rotation(snapshots[i])]) {
        final wanted = expected[i];
        if (wanted == null) {
          check(
            actual == null,
            '${kind.kind}: zero or nonfinite rotation is null at $i.',
          );
        } else {
          check(
            actual != null,
            '${kind.kind}: finite rotation is present at $i.',
          );
          final components = [actual!.x, actual.y, actual.z, actual.w];
          final values = [wanted.x, wanted.y, wanted.z, wanted.w];
          for (var axis = 0; axis < 4; axis++) {
            check(
              (components[axis] - values[axis]).abs() <= 1e-15,
              '${kind.kind}: unit rotation preserves axis $axis at $i.',
            );
          }
        }
      }
    }
  } finally {
    sdk.dispose();
  }
}

final checks = <String, Future<void> Function()>{
  'orientation get/watch normalize unit quaternions with finite extremes and preserved signs':
      unitRotations,
};

Future<void> main() async {
  await unitRotations().timeout(const Duration(seconds: 12));
  print('PASS orientation get/watch unit rotations');
}
