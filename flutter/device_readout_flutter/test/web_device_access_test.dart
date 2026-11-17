import 'package:device_readout_flutter/device_readout_flutter.dart' as readout;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('web factory rejects native use before resolving a package asset', () {
    expect(
      () => readout.FlutterWebDeviceAccess.create(),
      throwsA(
        isA<readout.DeviceReadoutException>().having(
          (error) => error.code,
          'code',
          readout.ErrorCode.unsupportedEntity,
        ),
      ),
    );
  });

  test('an explicit worker URL does not enable web collection on native', () {
    expect(
      () => readout.FlutterWebDeviceAccess.create(
        workerUri: Uri.parse('https://example.invalid/readout-worker.js'),
      ),
      throwsA(
        isA<readout.DeviceReadoutException>().having(
          (error) => error.code,
          'code',
          readout.ErrorCode.unsupportedEntity,
        ),
      ),
    );
  });
}
