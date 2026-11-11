import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:device_readout/device_readout.dart';

/// Explicit app lifecycle owner for one DeviceAccess context, including its
/// configured views. Attach before opening sensors and dispose before the SDK.
final class FlutterSensorActivityObserver with WidgetsBindingObserver {
  final DeviceAccess _access;
  final WidgetsBinding _binding;
  final bool _desktop;
  bool _disposed = false;

  FlutterSensorActivityObserver.attach(
    DeviceAccess access, {
    WidgetsBinding? binding,
  }) : _access = access,
       _binding = binding ?? WidgetsBinding.instance,
       _desktop =
           !kIsWeb &&
           switch (defaultTargetPlatform) {
             TargetPlatform.windows ||
             TargetPlatform.macOS ||
             TargetPlatform.linux => true,
             _ => false,
           } {
    _binding.addObserver(this);
    _publish(_binding.lifecycleState);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _publish(state);

  void _publish(AppLifecycleState? state) {
    if (_disposed) return;
    final active =
        state == AppLifecycleState.resumed ||
        (_desktop && state == AppLifecycleState.inactive);
    try {
      _access.observers.sensorActivity(active);
    } on DeviceReadoutCancelled {
      dispose();
    }
  }

  /// Detach the framework observer and suspend this context's sensor sources.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _binding.removeObserver(this);
    try {
      _access.observers.sensorActivity(false);
    } on DeviceReadoutCancelled {
      // SDK lifetime already ended.
    }
  }
}
