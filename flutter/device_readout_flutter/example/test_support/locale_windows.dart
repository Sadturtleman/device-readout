import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;

import 'package:device_readout_flutter/device_readout_flutter.dart' as readout;

Future<Map<String, Object?>> verifyLocale(
  readout.DeviceAccess access,
  String probePath,
) async {
  final probe = ffi.DynamicLibrary.open(probePath);
  try {
    int integer(String symbol) =>
        probe.lookupFunction<ffi.Uint32 Function(), int Function()>(symbol)();
    if (integer('readout_probe_locale_refresh') != 1 ||
        integer('readout_probe_locale_formats') != 1) {
      throw StateError('Independent locale references failed.');
    }
    String? wide(ffi.Pointer<ffi.Uint16> pointer) {
      final units = <int>[];
      for (var i = 0; i < 85 && pointer[i] != 0; i++) {
        units.add(pointer[i]);
      }
      return units.isEmpty ? null : String.fromCharCodes(units);
    }

    String? string(String symbol) => wide(
      probe.lookupFunction<
        ffi.Pointer<ffi.Uint16> Function(),
        ffi.Pointer<ffi.Uint16> Function()
      >(symbol)(),
    );
    String? asciiString(String symbol) {
      final pointer = probe
          .lookupFunction<
            ffi.Pointer<ffi.Uint8> Function(),
            ffi.Pointer<ffi.Uint8> Function()
          >(symbol)();
      final bytes = <int>[];
      for (var i = 0; i < 64 && pointer[i] != 0; i++) {
        bytes.add(pointer[i]);
      }
      return bytes.isEmpty ? null : ascii.decode(bytes);
    }

    final queryLanguages = probe
        .lookupFunction<ffi.Int32 Function(ffi.Int32), int Function(int)>(
          'readout_probe_locale_languages',
        );
    final language = probe
        .lookupFunction<
          ffi.Pointer<ffi.Uint16> Function(ffi.Int32),
          ffi.Pointer<ffi.Uint16> Function(int)
        >('readout_probe_locale_language');
    List<String> languageList(int kind) {
      final count = queryLanguages(kind);
      if (count < 0) throw StateError('Native language-list query failed.');
      return List.generate(count, (index) => wide(language(index))!);
    }

    final expected = <String, Object?>{
      'currentLanguageTag': string('readout_probe_locale_name'),
      'regionCode': string('readout_probe_locale_region'),
      'preferredLanguageTags': languageList(0),
      'systemLanguageTags': languageList(1),
      'appLanguageTags': languageList(2),
      'scriptCode': asciiString('readout_probe_locale_script'),
      'numberingSystem': asciiString('readout_probe_locale_numbering'),
      'hourCycle': switch (integer('readout_probe_locale_hour_cycle')) {
        0 => 'H12',
        1 => 'H23',
        _ => null,
      },
      'measurementSystem': switch (integer(
        'readout_probe_locale_measurement',
      )) {
        0 => 'Metric',
        1 => 'US',
        _ => null,
      },
      'firstWeekday': switch (integer('readout_probe_locale_weekday')) {
        0 => 'Monday',
        1 => 'Tuesday',
        2 => 'Wednesday',
        3 => 'Thursday',
        4 => 'Friday',
        5 => 'Saturday',
        6 => 'Sunday',
        _ => null,
      },
      'calendar': switch (integer('readout_probe_locale_calendar')) {
        1 || 2 || 9 || 10 || 11 || 12 => 'gregory',
        3 => 'japanese',
        4 => 'roc',
        6 => 'islamic',
        7 => 'buddhist',
        8 => 'hebrew',
        22 => 'persian',
        23 => 'islamic-umalqura',
        _ => null,
      },
    };
    bool matches(readout.LocaleSnapshot value) {
      final fields = value.toJson();
      return expected.entries.every(
        (entry) => jsonEncode(fields[entry.key]) == jsonEncode(entry.value),
      );
    }

    final snapshot = await access.get(readout.Entities.locale);
    if (!matches(snapshot))
      throw StateError(
        'Locale fields differ from independent native sources: ${snapshot.toJson()} / $expected',
      );
    final support = await access.capabilities.get(readout.Entities.locale);
    if (support.readable != true || support.watchable != true)
      throw StateError('Locale get/watch support missing.');
    var ticks = 0;
    final heartbeat = Timer.periodic(
      const Duration(milliseconds: 5),
      (_) => ticks++,
    );
    try {
      final values = await access
          .withPollInterval(const Duration(milliseconds: 20))
          .watch(readout.Entities.locale)
          .take(3)
          .toList();
      if (!values.every(matches))
        throw StateError(
          'Locale polls must preserve all current preference fields.',
        );
      for (var i = 1; i < values.length; i++) {
        if (!values[i].collectedAt.isAfter(values[i - 1].collectedAt))
          throw StateError('Locale timestamps must advance.');
      }
      if (ticks < 2)
        throw StateError('Flutter timers must progress during locale polling.');
      return {
        'name': 'native Windows locale with Flutter host timer progress',
        'snapshot': snapshot.toJson(),
        'polls': values.length,
        'heartbeatTicks': ticks,
      };
    } finally {
      heartbeat.cancel();
    }
  } finally {
    probe.close();
  }
}
