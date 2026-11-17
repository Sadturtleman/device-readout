part of 'transport_native.dart';

final class _WindowsDynamicTimeZone extends ffi.Struct {
  @ffi.Int32()
  external int bias;
  @ffi.Array(32)
  external ffi.Array<ffi.Uint16> standardName;
  @ffi.Array(8)
  external ffi.Array<ffi.Uint16> standardDate;
  @ffi.Int32()
  external int standardBias;
  @ffi.Array(32)
  external ffi.Array<ffi.Uint16> daylightName;
  @ffi.Array(8)
  external ffi.Array<ffi.Uint16> daylightDate;
  @ffi.Int32()
  external int daylightBias;
  @ffi.Array(128)
  external ffi.Array<ffi.Uint16> keyName;
  @ffi.Uint8()
  external int dynamicDaylightTimeDisabled;
}

/// Native bindings, temporary storage and conversion belong to the isolate.
final class _WindowsTimeZone {
  final kernel = ffi.DynamicLibrary.open('kernel32.dll');
  ffi.DynamicLibrary? icu;
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
  late final query = kernel
      .lookupFunction<
        ffi.Uint32 Function(ffi.Pointer<_WindowsDynamicTimeZone>),
        int Function(ffi.Pointer<_WindowsDynamicTimeZone>)
      >('GetDynamicTimeZoneInformation');
  late final systemDirectory = kernel
      .lookupFunction<
        ffi.Uint32 Function(ffi.Pointer<ffi.Uint16>, ffi.Uint32),
        int Function(ffi.Pointer<ffi.Uint16>, int)
      >('GetSystemDirectoryW');

  static String? text(int capacity, int Function(int) unit) {
    final units = <int>[];
    for (var i = 0; i < capacity; i++) {
      final value = unit(i);
      if (value == 0) return units.isEmpty ? null : String.fromCharCodes(units);
      if (value >= 0xd800 && value <= 0xdbff) {
        if (++i >= capacity) return null;
        final next = unit(i);
        if (next < 0xdc00 || next > 0xdfff) return null;
        units.addAll([value, next]);
      } else {
        if (value >= 0xdc00 && value <= 0xdfff) return null;
        units.add(value);
      }
    }
    return null;
  }

  ffi.DynamicLibrary? loadIcu(ffi.Pointer<ffi.Void> owner) {
    // Resolve the OS library from its system directory, independent of the
    // application's current directory and any bundled ICU library.
    const capacity = 32768;
    final buffer = allocate(owner, 0x00000008, 2 * capacity);
    if (buffer == ffi.nullptr) return null;
    try {
      final chars = buffer.cast<ffi.Uint16>();
      final count = systemDirectory(chars, capacity);
      if (count == 0 || count >= capacity) return null;
      final directory = text(count + 1, (i) => chars[i]);
      if (directory == null) return null;
      return ffi.DynamicLibrary.open('$directory\\icu.dll');
    } on ArgumentError {
      return null;
    } finally {
      free(owner, 0, buffer);
    }
  }

  String? iana(String windowsId, ffi.Pointer<ffi.Void> owner) {
    const capacity = 256;
    final inputBytes = 2 * (windowsId.length + 1);
    final input = allocate(owner, 0x00000008, inputBytes);
    final output = allocate(owner, 0x00000008, 4 + 2 * capacity);
    try {
      if (input == ffi.nullptr || output == ffi.nullptr) return null;
      final library = icu ??= loadIcu(owner);
      if (library == null) return null;
      final convert = library
          .lookupFunction<
            ffi.Int32 Function(
              ffi.Pointer<ffi.Uint16>,
              ffi.Int32,
              ffi.Pointer<ffi.Uint8>,
              ffi.Pointer<ffi.Uint16>,
              ffi.Int32,
              ffi.Pointer<ffi.Int32>,
            ),
            int Function(
              ffi.Pointer<ffi.Uint16>,
              int,
              ffi.Pointer<ffi.Uint8>,
              ffi.Pointer<ffi.Uint16>,
              int,
              ffi.Pointer<ffi.Int32>,
            )
          >('ucal_getTimeZoneIDForWindowsID');
      final source = input.cast<ffi.Uint16>();
      source.asTypedList(windowsId.length).setAll(0, windowsId.codeUnits);
      final status = output.cast<ffi.Int32>();
      final target = (output.cast<ffi.Uint8>() + 4).cast<ffi.Uint16>();
      // No region is inferred from the app locale. Use ICU's default mapping.
      final count = convert(
        source,
        windowsId.length,
        ffi.nullptr,
        target,
        capacity,
        status,
      );
      if (status.value > 0 || count <= 0 || count >= capacity) return null;
      return text(count + 1, (i) => target[i]);
    } on ArgumentError {
      return null;
    } finally {
      if (output != ffi.nullptr) free(owner, 0, output);
      if (input != ffi.nullptr) free(owner, 0, input);
    }
  }

  TimeZoneSnapshot read() {
    final owner = heap();
    if (owner == ffi.nullptr) throw unavailable();
    final storage = allocate(
      owner,
      0x00000008,
      ffi.sizeOf<_WindowsDynamicTimeZone>(),
    );
    if (storage == ffi.nullptr) throw unavailable();
    try {
      final pointer = storage.cast<_WindowsDynamicTimeZone>();
      final state = query(pointer);
      if (state == 0xffffffff) throw unavailable();
      final data = pointer.ref;
      final windowsId = text(128, (i) => data.keyName[i]);
      final adjustment = switch (state) {
        0 => 0,
        1 => data.standardBias,
        2 => data.daylightBias,
        _ => null,
      };
      return TimeZoneSnapshot(
        windowsId: windowsId,
        ianaId: windowsId == null ? null : iana(windowsId, owner),
        utcOffsetSeconds: adjustment == null
            ? null
            : -(data.bias + adjustment) * 60,
        daylightSavingTime: switch (state) {
          0 || 1 => false,
          2 => true,
          _ => null,
        },
      );
    } on ArgumentError {
      throw unavailable();
    } finally {
      free(owner, 0, storage);
    }
  }

  static DeviceReadoutException unavailable() => const DeviceReadoutException(
    ErrorCode.readFailed,
    'Windows time-zone information is unavailable.',
  );

  void dispose() {
    try {
      icu?.close();
    } finally {
      icu = null;
      kernel.close();
    }
  }
}
