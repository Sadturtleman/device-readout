import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:device_readout/device_readout.dart';

/// App-owned observation of the displays that Flutter exposes to this engine.
/// Use one owner for the Display collection in a DeviceAccess context.
final class FlutterDisplayObserver with WidgetsBindingObserver {
  static int _nextTarget = 0;
  final DeviceAccess _access;
  final ObserverFailureSource _failure;
  final WidgetsBinding _binding;
  final _targets = <int, Entity<DisplaySnapshot>>{};
  ui.FlutterView? _selectedView;
  ui.FlutterView? _registeredView;
  bool _disposed = false;
  bool _failed = false;

  FlutterDisplayObserver.attach(DeviceAccess access, {WidgetsBinding? binding})
    : _access = access,
      _failure = access.observers.failureSource(Entities.display),
      _binding = binding ?? WidgetsBinding.instance {
    _access.observers.current(Entities.display, null);
    _binding.addObserver(this);
    _publish();
  }

  /// Select an application view whose display becomes `access.displays.current()`.
  /// Pass null to clear selection; no primary/focused view is chosen implicitly.
  void selectView(ui.FlutterView? view) {
    if (_disposed) throw const DeviceReadoutCancelled();
    ui.FlutterView? registered;
    if (view != null) {
      if (!identical(view.platformDispatcher, _binding.platformDispatcher)) {
        throw const DeviceReadoutException(
          ErrorCode.invalidConfiguration,
          'The selected view must belong to the observed Flutter binding.',
        );
      }
      registered = _binding.platformDispatcher.view(id: view.viewId);
      if (registered == null || !identical(registered, view)) {
        throw const DeviceReadoutException(
          ErrorCode.entityRemoved,
          'The selected Flutter view is no longer registered.',
        );
      }
    }
    _selectedView = view;
    _registeredView = registered;
    _publish();
  }

  @override
  void didChangeMetrics() => _publish();

  void _publish() {
    if (_disposed) return;
    try {
      // Validate the inventory before retiring targets. Flutter replaces Display
      // value objects on updates, so object identity is not a removal signal.
      final displays = <int, ui.Display>{};
      for (final display in _binding.platformDispatcher.displays) {
        final id = display.id;
        if (displays.containsKey(id))
          throw StateError('Duplicate Flutter display ID.');
        displays[id] = display;
      }
      for (final id in _targets.keys.toList()) {
        if (!displays.containsKey(id)) {
          _access.observers.remove(_targets.remove(id)!);
        }
      }
      for (final entry in displays.entries) {
        final entity = _targets.putIfAbsent(
          entry.key,
          () => _access.observers.target(
            Entities.display,
            'flutter-display-${entry.key}-${++_nextTarget}',
          ),
        );
        final display = entry.value;
        final size = _read(() => display.size);
        final width = _pixel(size?.width), height = _pixel(size?.height);
        final pixels = width == null || height == null
            ? null
            : Size(width, height);
        final ratio = _positive(_read(() => display.devicePixelRatio));
        // Pinned Windows engine source uses EnumDisplaySettings(CURRENT_SETTINGS).
        // Other engines can report a render cadence; don't call that a mode rate.
        final rate = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows
            ? _positive(_read(() => display.refreshRate))
            : null;
        final mode = rate != null && rate > 1
            ? DisplayMode(pixelSize: pixels, refreshRateHz: rate)
            : null;
        _access.observers.publish(
          entity,
          DisplaySnapshot(
            pixelSize: pixels,
            scaleFactor: ratio,
            currentMode: mode,
          ),
        );
      }
      final selected = _selectedView;
      int? currentId;
      if (selected != null) {
        if (!identical(
          _binding.platformDispatcher.view(id: selected.viewId),
          _registeredView,
        )) {
          _selectedView = null;
          _registeredView = null;
        } else {
          currentId = _read(() => selected.display.id);
        }
      }
      _access.observers.current(Entities.display, _targets[currentId]);
      if (_failed) {
        _failure.publish(null);
        _failed = false;
      }
    } on DeviceReadoutCancelled {
      dispose();
    } catch (error) {
      _failed = true;
      try {
        _failure.publish(
          DeviceReadoutException(
            ErrorCode.readFailed,
            'Flutter display inventory observation failed: $error',
          ),
        );
      } on DeviceReadoutCancelled {
        dispose();
      }
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _binding.removeObserver(this);
    try {
      for (final target in _targets.values) {
        _access.observers.remove(target);
      }
    } on DeviceReadoutCancelled {
      /* Context already closed. */
    }
    _failure.dispose();
    _targets.clear();
    _selectedView = null;
    _registeredView = null;
  }
}

T? _read<T>(T Function() read) {
  try {
    return read();
  } catch (_) {
    return null;
  }
}

double? _positive(double? value) =>
    value != null && value.isFinite && value > 0 ? value : null;

int? _pixel(double? value) =>
    value != null &&
        value.isFinite &&
        value > 0 &&
        value < 9223372036854775808.0 &&
        value.truncateToDouble() == value
    ? value.toInt()
    : null;
