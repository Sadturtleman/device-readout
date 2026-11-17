import 'package:device_readout/device_readout.dart';

Uri packagedWorkerUri() => throw const DeviceReadoutException(
  ErrorCode.unsupportedEntity,
  'The Flutter web collector requires a browser.',
);
