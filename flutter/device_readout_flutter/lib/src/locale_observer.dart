import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:device_readout/device_readout.dart';

/// App-captured locale state. The application selects its Localizations scope
/// and supplies only the language lists and formatting preferences it knows.
/// No system/app list is inferred from Flutter's resolved locale.
final class FlutterLocaleState {
  final ui.Locale? currentLocale;
  final List<ui.Locale>? preferredLocales;
  final List<ui.Locale>? systemLocales;
  final List<ui.Locale>? appLocales;
  final String? calendar;
  final String? numberingSystem;
  final HourCycle? hourCycle;
  final Weekday? firstWeekday;
  final MeasurementSystem? measurementSystem;

  FlutterLocaleState({
    required this.currentLocale,
    List<ui.Locale>? preferredLocales,
    List<ui.Locale>? systemLocales,
    List<ui.Locale>? appLocales,
    this.calendar,
    this.numberingSystem,
    this.hourCycle,
    this.firstWeekday,
    this.measurementSystem,
  }) : preferredLocales = preferredLocales == null
           ? null
           : List.unmodifiable(preferredLocales),
       systemLocales = systemLocales == null
           ? null
           : List.unmodifiable(systemLocales),
       appLocales = appLocales == null ? null : List.unmodifiable(appLocales);

  LocaleSnapshot _snapshot() => LocaleSnapshot(
    currentLanguageTag: currentLocale?.toLanguageTag(),
    preferredLanguageTags: preferredLocales
        ?.map((locale) => locale.toLanguageTag())
        .toList(),
    systemLanguageTags: systemLocales
        ?.map((locale) => locale.toLanguageTag())
        .toList(),
    appLanguageTags: appLocales
        ?.map((locale) => locale.toLanguageTag())
        .toList(),
    regionCode: _nonempty(currentLocale?.countryCode),
    scriptCode: _nonempty(currentLocale?.scriptCode),
    calendar: calendar,
    numberingSystem: numberingSystem,
    hourCycle: hourCycle,
    firstWeekday: firstWeekday,
    measurementSystem: measurementSystem,
  );

  static String? _nonempty(String? value) => value == '' ? null : value;
}

/// Explicitly observes app-owned state, without querying Localizations or
/// PlatformDispatcher from SDK get/watch. One owner per DeviceAccess context.
/// Dispose before the app's listenable; existing watches end with ReadFailed,
/// while subsequent operations may use the underlying native collector.
final class FlutterLocaleObserver {
  final ValueListenable<FlutterLocaleState> _state;
  final ObserverStateSource<LocaleSnapshot> _source;
  final ObserverFailureSource _failure;
  bool _disposed = false;
  bool _failed = false;

  factory FlutterLocaleObserver.attach(
    DeviceAccess access, {
    required ValueListenable<FlutterLocaleState> state,
  }) {
    final source = access.observers.stateSource(Entities.locale);
    final failure = access.observers.failureSource(Entities.locale);
    final observer = FlutterLocaleObserver._(state, source, failure);
    try {
      state.addListener(observer._publish);
      observer._publish();
      return observer;
    } catch (_) {
      observer.dispose();
      rethrow;
    }
  }

  FlutterLocaleObserver._(this._state, this._source, this._failure);

  void _publish() {
    if (_disposed) return;
    try {
      _source.publish(_state.value._snapshot());
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
            'Flutter locale observation failed: $error',
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
    try {
      _state.removeListener(_publish);
    } catch (_) {
      // App-owned cleanup may fail. Retained callbacks are inert after disposal.
    } finally {
      _source.dispose();
      _failure.dispose();
    }
  }
}
