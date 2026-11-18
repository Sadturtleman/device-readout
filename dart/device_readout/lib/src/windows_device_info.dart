part of 'transport_native.dart';

final class _WindowsDeviceInfo {
  final kernel = ffi.DynamicLibrary.open('kernel32.dll');
  ffi.DynamicLibrary? advapi;
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
  late final computerName = kernel
      .lookupFunction<
        ffi.Int32 Function(ffi.Pointer<ffi.Uint16>, ffi.Pointer<ffi.Uint32>),
        int Function(ffi.Pointer<ffi.Uint16>, ffi.Pointer<ffi.Uint32>)
      >('GetComputerNameW');
  late final registry = (advapi ??= ffi.DynamicLibrary.open('advapi32.dll'))
      .lookupFunction<
        ffi.Int32 Function(
          ffi.Pointer<ffi.Void>,
          ffi.Pointer<ffi.Uint16>,
          ffi.Pointer<ffi.Uint16>,
          ffi.Uint32,
          ffi.Pointer<ffi.Uint32>,
          ffi.Pointer<ffi.Void>,
          ffi.Pointer<ffi.Uint32>,
        ),
        int Function(
          ffi.Pointer<ffi.Void>,
          ffi.Pointer<ffi.Uint16>,
          ffi.Pointer<ffi.Uint16>,
          int,
          ffi.Pointer<ffi.Uint32>,
          ffi.Pointer<ffi.Void>,
          ffi.Pointer<ffi.Uint32>,
        )
      >('RegGetValueW');

  // Decode only within the reported buffer, preserving Unicode and empty strings.
  static String? wideString(ffi.Pointer<ffi.Uint16> pointer, int units) {
    final result = <int>[];
    for (var i = 0; i < units; i++) {
      final value = pointer[i];
      if (value == 0) return String.fromCharCodes(result);
      if (value >= 0xd800 && value <= 0xdbff) {
        if (++i >= units) return null;
        final next = pointer[i];
        if (next < 0xdc00 || next > 0xdfff) return null;
        result.addAll([value, next]);
      } else {
        if (value >= 0xdc00 && value <= 0xdfff) return null;
        result.add(value);
      }
    }
    return null;
  }

  String? readName() {
    final owner = heap();
    if (owner == ffi.nullptr) return null;
    const capacity = 256;
    final storage = allocate(owner, 0x00000008, 4 + 2 * capacity);
    if (storage == ffi.nullptr) return null;
    try {
      final count = storage.cast<ffi.Uint32>()..value = capacity;
      final text = (storage.cast<ffi.Uint8>() + 4).cast<ffi.Uint16>();
      if (computerName(text, count) == 0 || count.value >= capacity)
        return null;
      return wideString(text, count.value + 1);
    } on ArgumentError {
      return null;
    } finally {
      free(owner, 0, storage);
    }
  }

  String? biosString(String name) =>
      registryString(r'HARDWARE\DESCRIPTION\System\BIOS', name);

  String? registryString(String key, String name) {
    final owner = heap();
    if (owner == ffi.nullptr) return null;
    final inputs = <ffi.Pointer<ffi.Void>>[];
    ffi.Pointer<ffi.Void> reserve(int size) {
      final pointer = allocate(owner, 0x00000008, size);
      if (pointer != ffi.nullptr) inputs.add(pointer);
      return pointer;
    }

    ffi.Pointer<ffi.Uint16> wide(String value) {
      final pointer = reserve(2 * (value.length + 1)).cast<ffi.Uint16>();
      if (pointer != ffi.nullptr) {
        pointer.asTypedList(value.length).setAll(0, value.codeUnits);
      }
      return pointer;
    }

    try {
      final path = wide(key);
      final value = wide(name);
      final count = reserve(4).cast<ffi.Uint32>();
      if (path == ffi.nullptr || value == ffi.nullptr || count == ffi.nullptr)
        return null;
      // HKEY_LOCAL_MACHINE is a sign-extended predefined handle, not owned here.
      final machine = ffi.Pointer<ffi.Void>.fromAddress(-2147483646);
      // REG_SZ only, explicit 64-bit view, zero output on failure. No key writes.
      const flags = 0x20010002;
      if (registry(
            machine,
            path,
            value,
            flags,
            ffi.nullptr,
            ffi.nullptr,
            count,
          ) !=
          0)
        return null;
      const maximumBytes = 64 * 1024;
      for (var attempt = 0; attempt < 3; attempt++) {
        final required = count.value;
        // A size-only REG_SZ query can reserve another UTF-16 terminator even
        // when the stored value is already terminated. Try the bounded read
        // before rejecting that two-byte sizing allowance.
        if (required > maximumBytes + 2 || required.isOdd) return null;
        // Allow RegGetValue to append a missing terminator within a bounded buffer.
        final capacity = required < maximumBytes - 2
            ? required + 2
            : maximumBytes;
        final output = allocate(owner, 0x00000008, capacity);
        if (output == ffi.nullptr) return null;
        try {
          count.value = capacity;
          final status = registry(
            machine,
            path,
            value,
            flags,
            ffi.nullptr,
            output,
            count,
          );
          if (status == 0) {
            final bytes = count.value;
            if (bytes < 2 || bytes > capacity || bytes.isOdd) return null;
            return wideString(output.cast<ffi.Uint16>(), bytes ~/ 2);
          }
          if (status != 234)
            return null; // ERROR_MORE_DATA may race the sizing read.
          if (capacity == maximumBytes) return null;
        } finally {
          free(owner, 0, output);
        }
      }
      return null;
    } on ArgumentError {
      return null;
    } finally {
      for (final pointer in inputs.reversed) {
        free(owner, 0, pointer);
      }
    }
  }

  DeviceInfoSnapshot read() {
    final name = readName();
    final manufacturer = biosString('SystemManufacturer');
    final model = biosString('SystemProductName');
    final board = biosString('BaseBoardProduct');
    if (name == null &&
        manufacturer == null &&
        model == null &&
        board == null) {
      throw const DeviceReadoutException(
        ErrorCode.readFailed,
        'Windows device information is unavailable.',
      );
    }
    return DeviceInfoSnapshot(
      deviceName: name,
      manufacturer: manufacturer,
      modelName: model,
      board: board,
    );
  }

  void dispose() {
    try {
      advapi?.close();
    } finally {
      advapi = null;
      kernel.close();
    }
  }
}
