import 'dart:ffi' as ffi;

/// Independent Windows SDK declarations; used only by verification entrypoints.
final class WindowsCpuReference {
  final ffi.DynamicLibrary library;
  WindowsCpuReference(String path) : library = ffi.DynamicLibrary.open(path);
  Map<String, Object?> read() {
    library.lookupFunction<ffi.Void Function(), void Function()>(
      'readout_probe_cpu_refresh',
    )();
    final count = library
        .lookupFunction<ffi.Uint32 Function(ffi.Uint32), int Function(int)>(
          'readout_probe_cpu_count',
        );
    final text = library
        .lookupFunction<
          ffi.Pointer<ffi.Uint16> Function(ffi.Uint32),
          ffi.Pointer<ffi.Uint16> Function(int)
        >('readout_probe_cpu_text');
    String? string(int field) {
      final pointer = text(field);
      if (pointer == ffi.nullptr) return null;
      final units = <int>[];
      for (var i = 0; i < 32768; i++) {
        final unit = pointer[i];
        if (unit == 0) return String.fromCharCodes(units);
        units.add(unit);
      }
      throw StateError('Unterminated CPU reference text.');
    }

    final result = <String, Object?>{
      'model': string(0),
      'manufacturer': string(1),
    };
    const fields = [
      'logicalProcessorCount',
      'physicalCoreCount',
      'processorPackageCount',
      'availableLogicalProcessorCount',
    ];
    for (var i = 0; i < fields.length; i++) {
      final value = count(i);
      if (value == 0 || value == 0xffffffff)
        throw StateError('Native CPU ${fields[i]} reference unavailable.');
      result[fields[i]] = value;
    }
    return result;
  }

  void dispose() => library.close();
}
