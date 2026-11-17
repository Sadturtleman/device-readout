import 'package:device_readout/device_readout.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'web_worker_uri_stub.dart'
    if (dart.library.js_interop) 'web_worker_uri.dart';

/// Browser collection using the worker asset included in this Flutter package.
/// Creation resolves configuration only; collection starts on the first operation.
abstract final class FlutterWebDeviceAccess {
  static DeviceAccess create({Uri? workerUri}) {
    if (!kIsWeb) {
      throw const DeviceReadoutException(
        ErrorCode.unsupportedEntity,
        'The Flutter web collector requires a browser.',
      );
    }
    return DeviceAccess.web(workerUri: workerUri ?? packagedWorkerUri());
  }
}
