import 'dart:async';

import 'package:device_readout/device_readout.dart';

import 'observers.dart' show check, errorOf, forbiddenNativeFactory;
import 'sensors.dart' show until;

Future<void> metadataUpdatesKeepLiveSources() async {
  final sdk = DeviceAccess.isolated(forbiddenNativeFactory);
  final other = DeviceAccess.isolated(forbiddenNativeFactory);
  final target = sdk.observers.target(Entities.pressure, 'pressure');
  SensorObserverSession<PressureSnapshot>? session;
  var starts = 0, stops = 0;
  sdk.observers.sensorSource(
    target,
    SensorObserverSource<PressureSnapshot>(
      description: SensorDescription(name: 'first'),
      subscribe: (value) {
        starts++;
        session = value;
        value.publish(PressureSnapshot(value: 100000));
        return () {
          stops++;
        };
      },
    ),
  );
  final values = <double?>[], errors = <Object>[];
  final watch = sdk.watch(target).listen((value) {
    values.add(value.value);
  }, onError: errors.add);
  try {
    await until(() => values.length == 1);
    final before = await sdk.describe(target);
    sdk.observers.sensorDescription(
      target,
      SensorDescription(
        kind: SensorKind.accelerometer,
        name: 'updated',
        maximumRange: double.nan,
      ),
    );
    final updated = await sdk.describe(target);
    check(
      before.name == 'first' &&
          updated.name == 'updated' &&
          updated.kind == SensorKind.pressure &&
          updated.maximumRange == null,
      'Metadata updates normalize in the worker without mutating prior snapshots.',
    );
    session!.publish(PressureSnapshot(value: 100001));
    await until(() => values.length == 2);
    check(
      starts == 1 && stops == 0 && errors.isEmpty,
      'A description update must preserve the active source and sensor watch.',
    );
    sdk.observers.sensorDescription(target, null);
    check(
      (await sdk.describe(target)).name == null,
      'An unavailable replacement description clears old metadata.',
    );
    final foreign = await errorOf(
      Future<void>.sync(() {
        other.observers.sensorDescription(target, SensorDescription());
      }),
    );
    check(
      foreign is DeviceReadoutException &&
          foreign.code == ErrorCode.invalidConfiguration,
      'Description updates reject foreign handles.',
    );
    final unbound = sdk.observers.target(Entities.pressure, 'unbound');
    final missing = await errorOf(
      Future<void>.sync(() {
        sdk.observers.sensorDescription(unbound, SensorDescription());
      }),
    );
    check(
      missing is DeviceReadoutException &&
          missing.code == ErrorCode.invalidConfiguration,
      'Metadata alone cannot create a readable sensor source.',
    );
    await watch.cancel();
    sdk.observers.remove(target);
    final removed = await errorOf(
      Future<void>.sync(() {
        sdk.observers.sensorDescription(target, SensorDescription());
      }),
    );
    check(
      removed is DeviceReadoutException &&
          removed.code == ErrorCode.entityRemoved,
      'Metadata updates cannot revive a retired sensor.',
    );
  } finally {
    await watch.cancel();
    sdk.dispose();
    other.dispose();
  }
}

final checks = <String, Future<void> Function()>{
  'sensor description updates preserve handles, samples and source lifetime':
      metadataUpdatesKeepLiveSources,
};
