part of 'transport_native.dart';

/// The calling isolate owns the DLL reference and temporary native buffer.
final class _WindowsRuntime {
  final kernel = ffi.DynamicLibrary.open('kernel32.dll');
  void dispose() => kernel.close();

  late final processHeap = kernel
      .lookupFunction<
        ffi.Pointer<ffi.Void> Function(),
        ffi.Pointer<ffi.Void> Function()
      >('GetProcessHeap');
  late final currentProcess = kernel
      .lookupFunction<
        ffi.Pointer<ffi.Void> Function(),
        ffi.Pointer<ffi.Void> Function()
      >('GetCurrentProcess');
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
  late final machine = kernel
      .lookupFunction<
        ffi.Int32 Function(
          ffi.Pointer<ffi.Void>,
          ffi.Pointer<ffi.Uint16>,
          ffi.Pointer<ffi.Uint16>,
        ),
        int Function(
          ffi.Pointer<ffi.Void>,
          ffi.Pointer<ffi.Uint16>,
          ffi.Pointer<ffi.Uint16>,
        )
      >('IsWow64Process2');

  Architecture? hostArchitecture() {
    final heap = processHeap();
    if (heap == ffi.nullptr) return null;
    final buffer = allocate(heap, 0x00000008, 2 * ffi.sizeOf<ffi.Uint16>());
    if (buffer == ffi.nullptr) return null;
    try {
      final processMachine = buffer.cast<ffi.Uint16>();
      final nativeMachine = processMachine + 1;
      // GetCurrentProcess returns a pseudo handle: it must not be closed.
      if (machine(currentProcess(), processMachine, nativeMachine) == 0)
        return null;
      // IMAGE_FILE_MACHINE constants. The process-machine output may be UNKNOWN
      // for a native process; only the native-machine output identifies the host.
      return switch (nativeMachine.value) {
        0x014c => Architecture.x86,
        0x8664 => Architecture.x64,
        0x01c4 => Architecture.arm32,
        0xaa64 => Architecture.arm64,
        _ => null,
      };
    } on ArgumentError {
      // A missing native export leaves this optional field unavailable.
      return null;
    } finally {
      free(heap, 0, buffer);
    }
  }
}
