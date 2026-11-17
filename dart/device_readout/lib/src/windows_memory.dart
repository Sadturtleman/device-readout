part of 'transport_native.dart';

final class _MemoryStatus extends ffi.Struct {
  @ffi.Uint32()
  external int length;
  @ffi.Uint32()
  external int memoryLoad;
  @ffi.Uint64()
  external int totalPhysical;
  @ffi.Uint64()
  external int availablePhysical;
  @ffi.Uint64()
  external int totalPageFile;
  @ffi.Uint64()
  external int availablePageFile;
  @ffi.Uint64()
  external int totalVirtual;
  @ffi.Uint64()
  external int availableVirtual;
  @ffi.Uint64()
  external int availableExtendedVirtual;
}

/// Win32 buffers and notification handles never leave the collection isolate.
final class _WindowsMemory {
  final kernel = ffi.DynamicLibrary.open('kernel32.dll');
  void dispose() => kernel.close();
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
  late final status = kernel
      .lookupFunction<
        ffi.Int32 Function(ffi.Pointer<_MemoryStatus>),
        int Function(ffi.Pointer<_MemoryStatus>)
      >('GlobalMemoryStatusEx');
  late final installed = kernel
      .lookupFunction<
        ffi.Int32 Function(ffi.Pointer<ffi.Uint64>),
        int Function(ffi.Pointer<ffi.Uint64>)
      >('GetPhysicallyInstalledSystemMemory');
  late final notification = kernel
      .lookupFunction<
        ffi.Pointer<ffi.Void> Function(ffi.Int32),
        ffi.Pointer<ffi.Void> Function(int)
      >('CreateMemoryResourceNotification');
  late final query = kernel
      .lookupFunction<
        ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Int32>),
        int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Int32>)
      >('QueryMemoryResourceNotification');
  late final close = kernel
      .lookupFunction<
        ffi.Int32 Function(ffi.Pointer<ffi.Void>),
        int Function(ffi.Pointer<ffi.Void>)
      >('CloseHandle');

  ProcessMemorySnapshot readProcess() {
    final heap = processHeap();
    if (heap == ffi.nullptr) {
      throw const DeviceReadoutException(
        ErrorCode.readFailed,
        'The process heap is unavailable.',
      );
    }
    final size = ffi.sizeOf<_MemoryStatus>();
    final buffer = allocate(heap, 0x00000008, size);
    if (buffer == ffi.nullptr) {
      throw const DeviceReadoutException(
        ErrorCode.readFailed,
        'Native memory allocation failed.',
      );
    }
    try {
      final memory = buffer.cast<_MemoryStatus>();
      memory.ref.length = size;
      if (status(memory) == 0) {
        throw const DeviceReadoutException(
          ErrorCode.readFailed,
          'Windows process memory query failed.',
        );
      }
      // Windows reports the current process's available commit budget here.
      // Physical available RAM and unreserved virtual address space are distinct.
      return ProcessMemorySnapshot(
        allocationRemainingBytes: BigInt.from(memory.ref.availablePageFile)
            .toUnsigned(64),
      );
    } finally {
      free(heap, 0, buffer);
    }
  }

  RamSnapshot read() {
    final heap = processHeap();
    if (heap == ffi.nullptr) {
      throw const DeviceReadoutException(
        ErrorCode.readFailed,
        'The process heap is unavailable.',
      );
    }
    final statusSize = ffi.sizeOf<_MemoryStatus>();
    final installedSize = ffi.sizeOf<ffi.Uint64>();
    // HEAP_ZERO_MEMORY; separate aligned output slots follow MEMORYSTATUSEX.
    final buffer = allocate(
      heap,
      0x00000008,
      statusSize + installedSize + ffi.sizeOf<ffi.Int32>(),
    );
    if (buffer == ffi.nullptr) {
      throw const DeviceReadoutException(
        ErrorCode.readFailed,
        'Native memory allocation failed.',
      );
    }
    try {
      final memory = buffer.cast<_MemoryStatus>();
      memory.ref.length = statusSize;
      final statusRead = status(memory) != 0;
      final kibibytes = (buffer.cast<ffi.Uint8>() + statusSize)
          .cast<ffi.Uint64>();
      BigInt? physical;
      if (installed(kibibytes) != 0) {
        final bytes =
            BigInt.from(kibibytes.value).toUnsigned(64) * BigInt.from(1024);
        if (bytes > BigInt.zero && bytes.bitLength <= 64) physical = bytes;
      }
      bool? lowMemory;
      // LowMemoryResourceNotification. This only observes current OS state.
      final handle = notification(0);
      if (handle != ffi.nullptr) {
        try {
          final state = (buffer.cast<ffi.Uint8>() + statusSize + installedSize)
              .cast<ffi.Int32>();
          if (query(handle, state) != 0) lowMemory = state.value != 0;
        } finally {
          close(handle);
        }
      }
      if (!statusRead && physical == null && lowMemory == null) {
        throw const DeviceReadoutException(
          ErrorCode.readFailed,
          'Windows memory queries failed.',
        );
      }
      return RamSnapshot(
        physicalBytes: physical,
        kernelAccessibleBytes: statusRead
            ? BigInt.from(memory.ref.totalPhysical).toUnsigned(64)
            : null,
        availableBytes: statusRead
            ? BigInt.from(memory.ref.availablePhysical).toUnsigned(64)
            : null,
        lowMemory: lowMemory,
      );
    } finally {
      free(heap, 0, buffer);
    }
  }
}
