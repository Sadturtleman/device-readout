import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:device_readout/device_readout.dart';

import 'observers.dart' show check;

Future<void> nativeWindowsLocale() async {
  if (!Platform.isWindows) return;
  final probe = ffi.DynamicLibrary.open(
    File('.tools/windows-memory-probe/Release/device_readout_memory_probe.dll')
        .absolute
        .path,
  );
  final sdk = DeviceAccess.native();
  try {
    final refresh = probe.lookupFunction<ffi.Int32 Function(), int Function()>(
      'readout_probe_locale_refresh',
    );
    check(refresh() == 1, 'Independent locale query failed.');
    String? string(String symbol) {
      final pointer = probe
          .lookupFunction<
            ffi.Pointer<ffi.Uint16> Function(),
            ffi.Pointer<ffi.Uint16> Function()
          >(symbol)();
      final units = <int>[];
      for (var i = 0; i < 85 && pointer[i] != 0; i++) {
        units.add(pointer[i]);
      }
      return units.isEmpty ? null : String.fromCharCodes(units);
    }

    final language = string('readout_probe_locale_name');
    final region = string('readout_probe_locale_region');
    final measure = probe.lookupFunction<ffi.Uint32 Function(), int Function()>(
      'readout_probe_locale_measurement',
    )();
    final queryLanguages = probe
        .lookupFunction<ffi.Int32 Function(ffi.Int32), int Function(int)>(
          'readout_probe_locale_languages',
        );
    final queryLanguage = probe
        .lookupFunction<
          ffi.Pointer<ffi.Uint16> Function(ffi.Int32),
          ffi.Pointer<ffi.Uint16> Function(int)
        >('readout_probe_locale_language');
    List<String> languageList(int kind) {
      final count = queryLanguages(kind);
      check(count >= 0, 'Independent language-list query failed.');
      return List.generate(count, (index) {
        final pointer = queryLanguage(index);
        check(pointer != ffi.nullptr, 'Native reference language missing.');
        final units = <int>[];
        for (var i = 0; i < 85 && pointer[i] != 0; i++) {
          units.add(pointer[i]);
        }
        return String.fromCharCodes(units);
      });
    }

    final preferred = languageList(0),
        system = languageList(1),
        app = languageList(2);
    check(
      probe.lookupFunction<ffi.Int32 Function(), int Function()>(
            'readout_probe_locale_formats',
          )() ==
          1,
      'Independent locale-format query failed.',
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

    final script = asciiString('readout_probe_locale_script');
    final numbering = asciiString('readout_probe_locale_numbering');
    final clock = probe.lookupFunction<ffi.Uint32 Function(), int Function()>(
      'readout_probe_locale_hour_cycle',
    )();
    final reference = await Process.run('powershell.exe', [
      '-NoProfile',
      '-File',
      'tools/verify-windows-locale.ps1',
    ]);
    check(
      reference.exitCode == 0,
      'Independent culture query failed: ${reference.stderr}',
    );
    final culture = jsonDecode(reference.stdout as String) as Map;
    check(
      culture['currentLanguageTag'] == language &&
          culture['regionCode'] == region,
      'Native and .NET default user locale sources must agree on this host.',
    );
    final started = DateTime.now().toUtc();
    final snapshot = await sdk.get(Entities.locale);
    final expectedCalendar = switch (culture['calendarType']) {
      'GregorianCalendar' => 'gregory',
      'JapaneseCalendar' => 'japanese',
      'TaiwanCalendar' => 'roc',
      'HijriCalendar' => 'islamic',
      'ThaiBuddhistCalendar' => 'buddhist',
      'HebrewCalendar' => 'hebrew',
      'PersianCalendar' => 'persian',
      'UmAlQuraCalendar' => 'islamic-umalqura',
      _ => null,
    };
    check(
      snapshot.scriptCode == script &&
          snapshot.numberingSystem == numbering &&
          snapshot.calendar == expectedCalendar &&
          snapshot.hourCycle ==
              switch (clock) {
                0 => HourCycle.h12,
                1 => HourCycle.h23,
                _ => null,
              },
      'Calendar, script, numbering and hour cycle must match independent platform data.',
    );
    check(
      snapshot.currentLanguageTag == language &&
          snapshot.regionCode == region &&
          snapshot.toJson()['firstWeekday'] == culture['firstWeekday'],
      'Locale fields must match independent native and .NET sources.',
    );
    check(
      snapshot.measurementSystem ==
          switch (measure) {
            0 => MeasurementSystem.metric,
            1 => MeasurementSystem.uS,
            _ => null,
          },
      'The native measurement preference must be preserved.',
    );
    check(
      jsonEncode(snapshot.preferredLanguageTags) == jsonEncode(preferred) &&
          jsonEncode(snapshot.systemLanguageTags) == jsonEncode(system) &&
          jsonEncode(snapshot.appLanguageTags) == jsonEncode(app),
      'User, system and process language lists must stay separate and preserve native ordering, including a known empty list.',
    );
    check(
      !snapshot.collectedAt.isBefore(started),
      'Locale reads must stamp completion.',
    );
    final support = await sdk.capabilities.get(Entities.locale);
    check(
      support.readable == true && support.watchable == true,
      'Locale must advertise native get/watch.',
    );
    final values = await sdk
        .withPollInterval(const Duration(milliseconds: 20))
        .watch(Entities.locale)
        .take(3)
        .toList();
    String fields(LocaleSnapshot value) =>
        jsonEncode({...value.toJson()}..remove('collectedAt'));
    check(
      values.every((value) => fields(value) == fields(snapshot)),
      'Equal locale preferences must still be delivered on each poll.',
    );
    for (var i = 1; i < values.length; i++) {
      check(
        values[i].collectedAt.isAfter(values[i - 1].collectedAt),
        'Locale polling must carry fresh completion times.',
      );
    }
    final other = DeviceAccess.native();
    try {
      check(
        (await other.get(Entities.locale)).currentLanguageTag == language,
        'Independent contexts must read the default user locale.',
      );
    } finally {
      other.dispose();
    }
    check(
      (await sdk.get(Entities.locale)).currentLanguageTag == language &&
          (await sdk.get(Entities.timeZone)).windowsId != null,
      'Closing another context must preserve locale and time-zone reads.',
    );
    print(
      'WINDOWS_LOCALE ${jsonEncode({'snapshot': snapshot.toJson(), 'reference': culture, 'nativeMeasurement': measure, 'preferred': preferred, 'system': system, 'app': app, 'script': script, 'numbering': numbering, 'nativeClock': clock, 'polls': values.length})}',
    );
  } finally {
    sdk.dispose();
    probe.close();
  }
}

final checks = <String, Future<void> Function()>{
  'native Windows locale agrees with independent user preferences':
      nativeWindowsLocale,
};

Future<void> main() => nativeWindowsLocale();
