import 'dart:ffi' as ffi;

final class WindowsCpuCoreReference {
  final ffi.DynamicLibrary library;
  WindowsCpuCoreReference(String path)
    : library = ffi.DynamicLibrary.open(path);
  List<
    ({
      int logical,
      int coreMinimum,
      int packageMinimum,
      int? currentMhz,
      int? maximumMhz,
    })
  >
  read() {
    final count = library.lookupFunction<ffi.Uint32 Function(), int Function()>(
      'readout_probe_cpu_cores_refresh',
    )();
    if (count == 0 || count > 4096)
      throw StateError(
        'Native CPU-core reference is unavailable on this host.',
      );
    final field = library
        .lookupFunction<
          ffi.Uint32 Function(ffi.Uint32, ffi.Uint32),
          int Function(int, int)
        >('readout_probe_cpu_core_value');
    final clocksValid =
        library.lookupFunction<ffi.Uint32 Function(), int Function()>(
          'readout_probe_cpu_core_clocks_valid',
        )() ==
        1;
    return List.generate(
      count,
      (index) => (
        logical: field(index, 0),
        coreMinimum: field(index, 1),
        packageMinimum: field(index, 2),
        currentMhz: clocksValid ? field(index, 4) : null,
        maximumMhz: clocksValid ? field(index, 3) : null,
      ),
    );
  }

  void dispose() => library.close();
}
