import 'dart:ffi' as ffi;

/// Portable test helper. Native reference calls run before/after public SDK reads;
/// they are not included in the SDK or the normal Flutter example entrypoint.
final class WindowsStorageReference {
  final ffi.DynamicLibrary _library;
  WindowsStorageReference(String libraryPath)
    : _library = ffi.DynamicLibrary.open(libraryPath);

  Map<String, Object?> read() {
    final refresh = _library
        .lookupFunction<ffi.Int32 Function(), int Function()>(
          'readout_probe_storage_refresh',
        );
    if (refresh() != 1) throw StateError('Native storage reference failed.');
    final number = _library
        .lookupFunction<ffi.Uint64 Function(ffi.Uint32), int Function(int)>(
          'readout_probe_storage_value',
        );
    final text = _library
        .lookupFunction<
          ffi.Pointer<ffi.Uint16> Function(ffi.Uint32),
          ffi.Pointer<ffi.Uint16> Function(int)
        >('readout_probe_storage_text');
    String string(int field) {
      final buffer = text(field);
      if (buffer == ffi.nullptr) throw StateError('Missing reference text.');
      final units = <int>[];
      for (var i = 0; i < 261; i++) {
        final unit = buffer[i];
        if (unit == 0) return String.fromCharCodes(units);
        units.add(unit);
      }
      throw StateError('Unterminated reference text.');
    }

    BigInt bytes(int index) => BigInt.from(number(index)).toUnsigned(64);
    return {
      'totalBytes': bytes(0),
      'freeBytes': bytes(1),
      'totalBytesForCaller': bytes(2),
      'availableToCallerBytes': bytes(3),
      'readOnly': number(4) != 0,
      'removable': switch (number(5)) {
        2 => true,
        3 => false,
        _ => null,
      },
      'structureSize': number(6),
      'name': string(0),
      'fileSystem': string(1),
    };
  }

  int count() {
    final value = _library
        .lookupFunction<ffi.Uint32 Function(), int Function()>(
          'readout_probe_storage_count',
        )();
    if (value == 0xffffffff)
      throw StateError('Native volume inventory failed.');
    return value;
  }

  void dispose() => _library.close();
}
