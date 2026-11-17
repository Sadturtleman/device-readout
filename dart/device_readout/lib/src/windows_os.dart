part of 'transport_native.dart';

final class _WindowsVersion extends ffi.Struct {
  @ffi.Uint32()
  external int size;
  @ffi.Uint32()
  external int major;
  @ffi.Uint32()
  external int minor;
  @ffi.Uint32()
  external int build;
  @ffi.Uint32()
  external int platform;
  @ffi.Array(128)
  external ffi.Array<ffi.Uint16> servicePack;
}

/// OS binding and output storage are owned by the collection isolate.
final class _WindowsOs {
  final kernel = ffi.DynamicLibrary.open('kernel32.dll');
  ffi.DynamicLibrary? ntdll;

  late final processHeap = kernel
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
  late final version = (ntdll ??= ffi.DynamicLibrary.open('ntdll.dll'))
      .lookupFunction<
        ffi.Int32 Function(ffi.Pointer<_WindowsVersion>),
        int Function(ffi.Pointer<_WindowsVersion>)
      >('RtlGetVersion');

  ({String version, String build})? versionInfo() {
    final heap = processHeap();
    if (heap == ffi.nullptr) return null;
    final size = ffi.sizeOf<_WindowsVersion>();
    final buffer = allocate(heap, 0x00000008, size);
    if (buffer == ffi.nullptr) return null;
    try {
      final value = buffer.cast<_WindowsVersion>();
      value.ref.size = size;
      if (version(value) != 0 ||
          value.ref.platform != 2 ||
          value.ref.major == 0) {
        return null;
      }
      return (
        version: '${value.ref.major}.${value.ref.minor}.${value.ref.build}',
        build: value.ref.build.toString(),
      );
    } on ArgumentError {
      // A missing optional version source leaves its fields unavailable.
      return null;
    } finally {
      free(heap, 0, buffer);
    }
  }

  OsSnapshot read() {
    final info = versionInfo();
    return OsSnapshot(
      family: OsFamily.windows,
      name: 'Windows',
      version: info?.version,
      build: info?.build,
      kernelName: 'Windows NT',
      kernelVersion: info?.version,
    );
  }

  void dispose() {
    try {
      ntdll?.close();
    } finally {
      ntdll = null;
      kernel.close();
    }
  }
}
