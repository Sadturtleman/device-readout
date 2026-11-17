part of 'transport_native.dart';

/// Optional OS ICU conversion for the Windows locale collector.
final class _WindowsLocaleUnicode {
  final _WindowsLocale owner;
  ffi.DynamicLibrary? library;
  final _numberingCache = <String, String?>{};
  _WindowsLocaleUnicode(this.owner);

  ffi.DynamicLibrary? load(ffi.Pointer<ffi.Void> heap) {
    if (library != null) return library;
    const capacity = 32768;
    final buffer = owner.allocate(heap, 0x00000008, capacity * 2);
    if (buffer == ffi.nullptr) return null;
    try {
      final directory = owner.kernel
          .lookupFunction<
            ffi.Uint32 Function(ffi.Pointer<ffi.Uint16>, ffi.Uint32),
            int Function(ffi.Pointer<ffi.Uint16>, int)
          >('GetSystemDirectoryW');
      final chars = buffer.cast<ffi.Uint16>();
      final count = directory(chars, capacity);
      if (count == 0 || count >= capacity) return null;
      final path = _WindowsLocale.text(chars, count + 1);
      if (path == null || path.isEmpty) return null;
      return library = ffi.DynamicLibrary.open('$path\\icu.dll');
    } on ArgumentError {
      return null;
    } finally {
      owner.free(heap, 0, buffer);
    }
  }

  static String? ascii(ffi.Pointer<ffi.Uint8> input, int count) {
    final bytes = <int>[];
    for (var i = 0; i < count; i++) {
      final value = input[i];
      if (value == 0 || value > 127) return null;
      bytes.add(value);
    }
    return String.fromCharCodes(bytes);
  }

  String? script(String? tag, ffi.Pointer<ffi.Void> heap) {
    if (tag == null || tag.isEmpty || tag.codeUnits.any((value) => value > 127))
      return null;
    const localeCapacity = 256, scriptCapacity = 16;
    final inputBytes = tag.length + 1;
    final buffer = owner.allocate(
      heap,
      0x00000008,
      8 + inputBytes + 2 * localeCapacity + scriptCapacity,
    );
    if (buffer == ffi.nullptr) return null;
    try {
      final icu = load(heap);
      if (icu == null) return null;
      final fromTag = icu
          .lookupFunction<
            ffi.Int32 Function(
              ffi.Pointer<ffi.Uint8>,
              ffi.Pointer<ffi.Uint8>,
              ffi.Int32,
              ffi.Pointer<ffi.Int32>,
              ffi.Pointer<ffi.Int32>,
            ),
            int Function(
              ffi.Pointer<ffi.Uint8>,
              ffi.Pointer<ffi.Uint8>,
              int,
              ffi.Pointer<ffi.Int32>,
              ffi.Pointer<ffi.Int32>,
            )
          >('uloc_forLanguageTag');
      final maximize = icu
          .lookupFunction<
            ffi.Int32 Function(
              ffi.Pointer<ffi.Uint8>,
              ffi.Pointer<ffi.Uint8>,
              ffi.Int32,
              ffi.Pointer<ffi.Int32>,
            ),
            int Function(
              ffi.Pointer<ffi.Uint8>,
              ffi.Pointer<ffi.Uint8>,
              int,
              ffi.Pointer<ffi.Int32>,
            )
          >('uloc_addLikelySubtags');
      final getScript = icu
          .lookupFunction<
            ffi.Int32 Function(
              ffi.Pointer<ffi.Uint8>,
              ffi.Pointer<ffi.Uint8>,
              ffi.Int32,
              ffi.Pointer<ffi.Int32>,
            ),
            int Function(
              ffi.Pointer<ffi.Uint8>,
              ffi.Pointer<ffi.Uint8>,
              int,
              ffi.Pointer<ffi.Int32>,
            )
          >('uloc_getScript');
      final status = buffer.cast<ffi.Int32>(),
          parsed = buffer.cast<ffi.Int32>() + 1;
      final input = buffer.cast<ffi.Uint8>() + 8;
      final locale = input + inputBytes;
      final likely = locale + localeCapacity;
      final result = likely + localeCapacity;
      input.asTypedList(tag.length).setAll(0, tag.codeUnits);
      final localeLength = fromTag(
        input,
        locale,
        localeCapacity,
        parsed,
        status,
      );
      if (status.value > 0 ||
          parsed.value != tag.length ||
          localeLength <= 0 ||
          localeLength >= localeCapacity)
        return null;
      status.value = 0;
      final likelyLength = maximize(locale, likely, localeCapacity, status);
      if (status.value > 0 ||
          likelyLength <= 0 ||
          likelyLength >= localeCapacity)
        return null;
      status.value = 0;
      final scriptLength = getScript(likely, result, scriptCapacity, status);
      if (status.value > 0 || scriptLength != 4) return null;
      return ascii(result, scriptLength);
    } on ArgumentError {
      return null;
    } finally {
      owner.free(heap, 0, buffer);
    }
  }

  String? numbering(
    String? nativeDigits,
    int? substitution,
    ffi.Pointer<ffi.Void> heap,
  ) {
    final digits = switch (substitution) {
      1 => '0123456789',
      2 => nativeDigits,
      0 when nativeDigits == '0123456789' => nativeDigits,
      _ => null,
    };
    // Contextual non-Latin substitution has no single numbering-system value.
    if (digits == null || digits.runes.length != 10) return null;
    if (_numberingCache.containsKey(digits)) return _numberingCache[digits];
    const capacity = 64;
    final buffer = owner.allocate(heap, 0x00000008, 8 + 2 * capacity);
    if (buffer == ffi.nullptr) return null;
    try {
      final icu = load(heap);
      if (icu == null) return null;
      final openNames = icu
          .lookupFunction<
            ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Int32>),
            ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Int32>)
          >('unumsys_openAvailableNames');
      final next = icu
          .lookupFunction<
            ffi.Pointer<ffi.Uint8> Function(
              ffi.Pointer<ffi.Void>,
              ffi.Pointer<ffi.Int32>,
              ffi.Pointer<ffi.Int32>,
            ),
            ffi.Pointer<ffi.Uint8> Function(
              ffi.Pointer<ffi.Void>,
              ffi.Pointer<ffi.Int32>,
              ffi.Pointer<ffi.Int32>,
            )
          >('uenum_next');
      final closeNames = icu
          .lookupFunction<
            ffi.Void Function(ffi.Pointer<ffi.Void>),
            void Function(ffi.Pointer<ffi.Void>)
          >('uenum_close');
      final openSystem = icu
          .lookupFunction<
            ffi.Pointer<ffi.Void> Function(
              ffi.Pointer<ffi.Uint8>,
              ffi.Pointer<ffi.Int32>,
            ),
            ffi.Pointer<ffi.Void> Function(
              ffi.Pointer<ffi.Uint8>,
              ffi.Pointer<ffi.Int32>,
            )
          >('unumsys_openByName');
      final closeSystem = icu
          .lookupFunction<
            ffi.Void Function(ffi.Pointer<ffi.Void>),
            void Function(ffi.Pointer<ffi.Void>)
          >('unumsys_close');
      final algorithmic = icu
          .lookupFunction<
            ffi.Int8 Function(ffi.Pointer<ffi.Void>),
            int Function(ffi.Pointer<ffi.Void>)
          >('unumsys_isAlgorithmic');
      final radix = icu
          .lookupFunction<
            ffi.Int32 Function(ffi.Pointer<ffi.Void>),
            int Function(ffi.Pointer<ffi.Void>)
          >('unumsys_getRadix');
      final description = icu
          .lookupFunction<
            ffi.Int32 Function(
              ffi.Pointer<ffi.Void>,
              ffi.Pointer<ffi.Uint16>,
              ffi.Int32,
              ffi.Pointer<ffi.Int32>,
            ),
            int Function(
              ffi.Pointer<ffi.Void>,
              ffi.Pointer<ffi.Uint16>,
              int,
              ffi.Pointer<ffi.Int32>,
            )
          >('unumsys_getDescription');
      final status = buffer.cast<ffi.Int32>(),
          length = buffer.cast<ffi.Int32>() + 1;
      final output = (buffer.cast<ffi.Uint8>() + 8).cast<ffi.Uint16>();
      final names = openNames(status);
      if (names == ffi.nullptr) return null;
      try {
        if (status.value > 0) return null;
        for (var index = 0; index < 1024; index++) {
          status.value = 0;
          final name = next(names, length, status);
          if (status.value > 0) return null;
          if (name == ffi.nullptr) {
            _numberingCache[digits] = null;
            return null;
          }
          if (length.value <= 0 || length.value > 64) return null;
          final id = ascii(name, length.value);
          if (id == null) return null;
          final system = openSystem(name, status);
          if (system == ffi.nullptr) return null;
          try {
            if (status.value > 0) return null;
            if (algorithmic(system) != 0 || radix(system) != 10) continue;
            final count = description(system, output, capacity, status);
            if (status.value > 0 || count <= 0 || count >= capacity)
              return null;
            if (_WindowsLocale.text(output, count + 1) == digits) {
              _numberingCache[digits] = id;
              return id;
            }
          } finally {
            closeSystem(system);
          }
        }
        return null;
      } finally {
        closeNames(names);
      }
    } on ArgumentError {
      return null;
    } finally {
      owner.free(heap, 0, buffer);
    }
  }

  void dispose() {
    library?.close();
    library = null;
    _numberingCache.clear();
  }
}
