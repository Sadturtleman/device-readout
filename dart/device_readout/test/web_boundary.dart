import 'package:device_readout/device_readout.dart';

DeviceCollector mustNotRunOnHost(Object? _) =>
    throw StateError('A native collector must not run on the web host.');

Future<void> main() async {
  final web = DeviceAccess.web(
    workerUri: Uri.parse('https://example.invalid/worker.js'),
  );
  try {
    if ((await web.capabilities.get(Entities.cpu)).readable != false) {
      throw StateError(
        'An absent browser Worker cannot claim collection support.',
      );
    }
    try {
      await web.get(Entities.cpu);
      throw StateError('A missing browser Worker must fail explicitly.');
    } on DeviceReadoutException catch (error) {
      if (error.code != ErrorCode.unsupportedEntity) rethrow;
    }
  } finally {
    web.dispose();
  }
  final sdk = DeviceAccess.isolated(mustNotRunOnHost);
  try {
    final nativeSupport = await sdk.capabilities.get(Entities.runtime);
    if (nativeSupport.readable != false || nativeSupport.watchable != false) {
      throw StateError('An absent worker bridge cannot claim native support.');
    }
    for (final operation in [
      sdk.storageVolumes.list(),
      sdk.storageVolumes.current(),
    ]) {
      try {
        await operation;
        throw StateError('Native discovery requires a Web Worker bridge.');
      } on DeviceReadoutException catch (error) {
        if (error.code != ErrorCode.unsupportedEntity) rethrow;
      }
    }
    Object? failure;
    try {
      await sdk.get(Entities.runtime);
    } catch (error) {
      failure = error;
    }
    if (failure is! DeviceReadoutException ||
        failure.code != ErrorCode.unsupportedEntity) {
      throw StateError(
        'An absent Web Worker bridge must fail without host collection.',
      );
    }
    final screen = sdk.observers.target(Entities.display, 'web-screen');
    sdk.observers.publish(screen, DisplaySnapshot(label: 'app-observed'));
    if ((await sdk.capabilities.get(screen)).readable != false) {
      throw StateError('Observed state still requires a normalization worker.');
    }
    Object? observedFailure;
    try {
      await sdk.get(screen);
    } catch (error) {
      observedFailure = error;
    }
    if (observedFailure is! DeviceReadoutException ||
        observedFailure.code != ErrorCode.unsupportedEntity) {
      throw StateError(
        'Observed normalization must also wait for a Web Worker bridge.',
      );
    }
    var sensorStarts = 0;
    final sensor = sdk.observers.target(Entities.accelerometer, 'web-sensor');
    sdk.observers.sensorSource(
      sensor,
      SensorObserverSource<AccelerometerSnapshot>(
        subscribe: (_) {
          sensorStarts++;
          return null;
        },
      ),
    );
    if ((await sdk.capabilities.get(sensor)).watchable != false) {
      throw StateError('A sensor registration cannot bypass an absent worker.');
    }
    for (final operation in [
      sdk.get(sensor),
      sdk.watch(sensor).first,
      sdk.describe(sensor),
    ]) {
      Object? failure;
      try {
        await operation;
      } catch (error) {
        failure = error;
      }
      if (failure is! DeviceReadoutException ||
          failure.code != ErrorCode.unsupportedEntity) {
        throw StateError(
          'Sensor APIs must reject an absent web worker bridge.',
        );
      }
    }
    if (sensorStarts != 0)
      throw StateError(
        'Unsupported web sensor queries must not start host sources.',
      );
    print(
      'PASS Dart web boundary rejects unsupported collection without invoking the host factory.',
    );
  } finally {
    sdk.dispose();
  }
}
