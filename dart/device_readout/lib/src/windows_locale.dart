part of 'transport_native.dart';

enum _LocaleLanguageScope { user, system, process }

final class _WindowsLocale {
  static const _isoRegion = 0x005a;
  static const _firstWeekday = 0x100c;
  static const _measurement = 0x000d;
  static const _returnNumber = 0x20000000;
  static const _timeFormat = 0x1003;
  static const _calendarType = 0x1009;
  static const _nativeDigits = 0x0013;
  static const _digitSubstitution = 0x1014;
  final kernel = ffi.DynamicLibrary.open('kernel32.dll');
  _WindowsLocaleUnicode? unicode;
  late final heap = kernel
      .lookupFunction<
        ffi.Pointer<ffi.Void> Function(),
        ffi.Pointer<ffi.Void> Function()
      >('GetProcessHeap');
  late final allocate = kernel
      .lookupFunction<
        ffi.Pointer<ffi.Void> Function(
          ffi.Pointer<ffi.Void>,
          ffi.Uint32,
          ffi.UintPtr,
        ),
        ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>, int, int)
      >('HeapAlloc');
  late final free = kernel
      .lookupFunction<
        ffi.Int32 Function(
          ffi.Pointer<ffi.Void>,
          ffi.Uint32,
          ffi.Pointer<ffi.Void>,
        ),
        int Function(ffi.Pointer<ffi.Void>, int, ffi.Pointer<ffi.Void>)
      >('HeapFree');
  late final userName = kernel
      .lookupFunction<
        ffi.Int32 Function(ffi.Pointer<ffi.Uint16>, ffi.Int32),
        int Function(ffi.Pointer<ffi.Uint16>, int)
      >('GetUserDefaultLocaleName');
  late final info = kernel
      .lookupFunction<
        ffi.Int32 Function(
          ffi.Pointer<ffi.Uint16>,
          ffi.Uint32,
          ffi.Pointer<ffi.Uint16>,
          ffi.Int32,
        ),
        int Function(ffi.Pointer<ffi.Uint16>, int, ffi.Pointer<ffi.Uint16>, int)
      >('GetLocaleInfoEx');

  static String? text(ffi.Pointer<ffi.Uint16> source, int count) {
    final units = <int>[];
    for (var i = 0; i < count; i++) {
      final value = source[i];
      if (value == 0) return String.fromCharCodes(units);
      if (value >= 0xd800 && value <= 0xdbff) {
        if (++i >= count) return null;
        final next = source[i];
        if (next < 0xdc00 || next > 0xdfff) return null;
        units.addAll([value, next]);
      } else {
        if (value >= 0xdc00 && value <= 0xdfff) return null;
        units.add(value);
      }
    }
    return null;
  }

  static HourCycle? hourCycle(String? pattern) {
    if (pattern == null) return null;
    var quoted = false;
    HourCycle? result;
    for (var i = 0; i < pattern.length; i++) {
      final char = pattern.codeUnitAt(i);
      if (char == 0x27) {
        if (i + 1 < pattern.length && pattern.codeUnitAt(i + 1) == 0x27) {
          i++;
        } else {
          quoted = !quoted;
        }
      } else if (!quoted) {
        final hour = switch (char) {
          0x68 => HourCycle.h12,
          0x48 => HourCycle.h23,
          _ => null,
        };
        if (hour != null) {
          if (result != null && result != hour) return null;
          result = hour;
        }
      }
    }
    return quoted ? null : result;
  }

  List<String>? languages(
    _LocaleLanguageScope scope,
    ffi.Pointer<ffi.Void> owner,
  ) {
    final counts = allocate(owner, 0x00000008, 8);
    if (counts == ffi.nullptr) return null;
    try {
      final query = kernel
          .lookupFunction<
            ffi.Int32 Function(
              ffi.Uint32,
              ffi.Pointer<ffi.Uint32>,
              ffi.Pointer<ffi.Uint16>,
              ffi.Pointer<ffi.Uint32>,
            ),
            int Function(
              int,
              ffi.Pointer<ffi.Uint32>,
              ffi.Pointer<ffi.Uint16>,
              ffi.Pointer<ffi.Uint32>,
            )
          >(switch (scope) {
            _LocaleLanguageScope.user => 'GetUserPreferredUILanguages',
            _LocaleLanguageScope.system => 'GetSystemPreferredUILanguages',
            _LocaleLanguageScope.process => 'GetProcessPreferredUILanguages',
          });
      final count = counts.cast<ffi.Uint32>();
      final size = count + 1;
      const languageName = 0x00000008;
      for (var attempt = 0; attempt < 3; attempt++) {
        count.value = 0;
        size.value = 0;
        if (query(languageName, count, ffi.nullptr, size) == 0) return null;
        final capacity = size.value;
        if (capacity < 2 || capacity > 32768) return null;
        final buffer = allocate(owner, 0x00000008, capacity * 2);
        if (buffer == ffi.nullptr) return null;
        try {
          final chars = buffer.cast<ffi.Uint16>();
          // Re-size from a fresh successful query after a race. A failed call's
          // count/size outputs are undefined and are never used for allocation.
          if (query(languageName, count, chars, size) == 0) continue;
          final used = size.value, number = count.value;
          if (used < 2 || used > capacity || number > used ~/ 2) return null;
          if (number == 0) {
            return used == 2 && chars[0] == 0 && chars[1] == 0
                ? <String>[]
                : null;
          }
          final result = <String>[];
          var offset = 0;
          for (var index = 0; index < number; index++) {
            if (offset >= used) return null;
            final language = text(chars + offset, used - offset);
            if (language == null || language.isEmpty) return null;
            result.add(language);
            offset += language.length + 1;
          }
          if (offset != used - 1 || chars[offset] != 0) return null;
          return result;
        } finally {
          free(owner, 0, buffer);
        }
      }
      return null;
    } on ArgumentError {
      return null;
    } finally {
      free(owner, 0, counts);
    }
  }

  LocaleSnapshot read() {
    final owner = heap();
    if (owner == ffi.nullptr) throw unavailable();
    const nameCapacity = 85, textCapacity = 256;
    final nameStorage = allocate(owner, 0x00000008, nameCapacity * 2);
    final valueStorage = allocate(owner, 0x00000008, textCapacity * 2);
    try {
      if (nameStorage == ffi.nullptr || valueStorage == ffi.nullptr)
        throw unavailable();
      final nameBuffer = nameStorage.cast<ffi.Uint16>();
      final values = valueStorage.cast<ffi.Uint16>();
      String? language;
      try {
        final count = userName(nameBuffer, nameCapacity);
        if (count > 0 && count <= nameCapacity)
          language = text(nameBuffer, count);
      } on ArgumentError {
        /* Other locale sources remain independent. */
      }
      // A null name is the native LOCALE_NAME_USER_DEFAULT selector.
      final name = language == null
          ? ffi.nullptr.cast<ffi.Uint16>()
          : nameBuffer;
      String? string(int type) {
        try {
          final count = info(name, type, values, textCapacity);
          return count > 0 && count <= textCapacity
              ? text(values, count)
              : null;
        } on ArgumentError {
          return null;
        }
      }

      int? number(int type) {
        try {
          return info(name, type | _returnNumber, values, 2) == 2
              ? valueStorage.cast<ffi.Uint32>().value
              : null;
        } on ArgumentError {
          return null;
        }
      }

      final region = string(_isoRegion);
      final weekday = number(_firstWeekday);
      final measure = number(_measurement);
      final calendar = number(_calendarType);
      final pattern = string(_timeFormat);
      final digits = string(_nativeDigits);
      final substitution = number(_digitSubstitution);
      final preferred = languages(_LocaleLanguageScope.user, owner);
      final system = languages(_LocaleLanguageScope.system, owner);
      final app = languages(_LocaleLanguageScope.process, owner);
      if (language == null &&
          region == null &&
          weekday == null &&
          measure == null &&
          preferred == null &&
          system == null &&
          app == null &&
          calendar == null &&
          pattern == null &&
          digits == null &&
          substitution == null) {
        throw unavailable();
      }
      return LocaleSnapshot(
        currentLanguageTag: language,
        preferredLanguageTags: preferred,
        systemLanguageTags: system,
        appLanguageTags: app,
        regionCode: region,
        scriptCode: (unicode ??= _WindowsLocaleUnicode(
          this,
        )).script(language, owner),
        numberingSystem: (unicode ??= _WindowsLocaleUnicode(
          this,
        )).numbering(digits, substitution, owner),
        hourCycle: hourCycle(pattern),
        calendar: switch (calendar) {
          1 || 2 || 9 || 10 || 11 || 12 => 'gregory',
          3 => 'japanese',
          4 => 'roc',
          6 => 'islamic',
          7 => 'buddhist',
          8 => 'hebrew',
          22 => 'persian',
          23 => 'islamic-umalqura',
          // Korean Tangun solar chronology is not the Unicode dangi calendar.
          _ => null,
        },
        firstWeekday: switch (weekday) {
          0 => Weekday.monday,
          1 => Weekday.tuesday,
          2 => Weekday.wednesday,
          3 => Weekday.thursday,
          4 => Weekday.friday,
          5 => Weekday.saturday,
          6 => Weekday.sunday,
          _ => null,
        },
        measurementSystem: switch (measure) {
          0 => MeasurementSystem.metric,
          1 => MeasurementSystem.uS,
          _ => null,
        },
      );
    } finally {
      if (valueStorage != ffi.nullptr) free(owner, 0, valueStorage);
      if (nameStorage != ffi.nullptr) free(owner, 0, nameStorage);
    }
  }

  static DeviceReadoutException unavailable() => const DeviceReadoutException(
    ErrorCode.readFailed,
    'Windows locale information is unavailable.',
  );

  void dispose() {
    try {
      unicode?.dispose();
    } finally {
      unicode = null;
      kernel.close();
    }
  }
}
