import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:device_readout/device_readout.dart';

/// Attach explicitly from the application's Flutter view lifecycle.
final class FlutterViewportObserver with WidgetsBindingObserver {
  static int _nextRegistration = 0;
  final DeviceAccess _access;
  final ui.FlutterView _view;
  final ui.FlutterView _registeredView;
  final int _viewId;
  final WidgetsBinding _binding;
  final Entity<ViewportSnapshot> entity;
  late final ObserverFailureSource _failure;
  bool _disposed = false;
  bool _failed = false;

  factory FlutterViewportObserver.attach(
    DeviceAccess access, {
    required ui.FlutterView view,
    WidgetsBinding? binding,
  }) {
    final activeBinding = binding ?? WidgetsBinding.instance;
    if (!identical(view.platformDispatcher, activeBinding.platformDispatcher)) {
      throw const DeviceReadoutException(
        ErrorCode.invalidConfiguration,
        'The Flutter view must belong to the supplied binding.',
      );
    }
    final viewId = view.viewId;
    final registered = activeBinding.platformDispatcher.view(id: viewId);
    if (registered == null || !identical(registered, view)) {
      throw const DeviceReadoutException(
        ErrorCode.entityRemoved,
        'The Flutter view is no longer registered.',
      );
    }
    return FlutterViewportObserver._(
      access,
      view,
      activeBinding,
      registered,
      viewId,
    );
  }

  FlutterViewportObserver._(
    DeviceAccess access,
    ui.FlutterView view,
    this._binding,
    this._registeredView,
    this._viewId,
  ) : _access = access,
      _view = view,
      entity = access.observers.target(
        Entities.viewport,
        'flutter-viewport-$_viewId-${++_nextRegistration}',
      ) {
    _failure = access.observers.failureSource(entity);
    _binding.addObserver(this);
    _publish();
  }

  @override
  void didChangeMetrics() => _publish();

  @override
  void didChangeTextScaleFactor() => _publish();

  void _publish() {
    if (_disposed) return;
    try {
      if (!identical(
        _binding.platformDispatcher.view(id: _viewId),
        _registeredView,
      )) {
        dispose();
        return;
      }
      final ratio = _view.devicePixelRatio;
      final physical = _view.physicalSize;
      final padding = _view.viewPadding;
      final scale = _binding.platformDispatcher.textScaleFactor;
      final validRatio = ratio.isFinite && ratio > 0;
      _access.observers.publish(
        entity,
        ViewportSnapshot(
          size: validRatio
              ? Size(physical.width / ratio, physical.height / ratio)
              : null,
          safeAreaInsets: validRatio
              ? Insets(
                  padding.top / ratio,
                  padding.right / ratio,
                  padding.bottom / ratio,
                  padding.left / ratio,
                )
              : null,
          textScaleFactor: scale,
        ),
      );
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
            'Flutter viewport observation failed: $error',
          ),
        );
      } on DeviceReadoutCancelled {
        dispose();
      } on DeviceReadoutException catch (failure) {
        if (failure.code == ErrorCode.entityRemoved) {
          dispose();
        } else {
          rethrow;
        }
      }
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _binding.removeObserver(this);
    try {
      _access.observers.remove(entity);
    } on DeviceReadoutCancelled {
      /* Context already closed. */
    }
    _failure.dispose();
  }
}
