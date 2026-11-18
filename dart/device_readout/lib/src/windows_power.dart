part of 'transport_native.dart';

final class _SystemPowerStatus extends ffi.Struct {
  @ffi.Uint8()
  external int acLineStatus;
  @ffi.Uint8()
  external int batteryFlag;
  @ffi.Uint8()
  external int batteryLifePercent;
  @ffi.Uint8()
  external int systemStatusFlag;
  @ffi.Uint32()
  external int batteryLifeTime;
  @ffi.Uint32()
  external int batteryFullLifeTime;
}

// SYSTEM_POWER_CAPABILITIES: preserve unrelated feature bytes, battery
// reporting scales and wake-state enums so native writes stay within the ABI.
final class _SystemPowerCapabilities extends ffi.Struct {
  @ffi.Array(12)
  external ffi.Array<ffi.Uint8> miscellaneousFeatures;
  @ffi.Uint8()
  external int upsPresent;
  @ffi.Array(17)
  external ffi.Array<ffi.Uint8> processorSleepAndDiskFeatures;
  @ffi.Uint8()
  external int systemBatteriesPresent;
  @ffi.Uint8()
  external int batteriesAreShortTerm;
  @ffi.Array(11)
  external ffi.Array<ffi.Uint32> batteryScalesAndWakeStates;
}

/// Read-only power binding and output storage, owned by the collection isolate.
final class _WindowsPower {
  final kernel = ffi.DynamicLibrary.open('kernel32.dll');
  ffi.DynamicLibrary? powerLibrary;
  int Function(ffi.Pointer<_SystemPowerCapabilities>)? capabilities;
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
  late final query = kernel
      .lookupFunction<
        ffi.Int32 Function(ffi.Pointer<_SystemPowerStatus>),
        int Function(ffi.Pointer<_SystemPowerStatus>)
      >('GetSystemPowerStatus');
  late final lastError = kernel
      .lookupFunction<ffi.Uint32 Function(), int Function()>('GetLastError');

  PowerSnapshot read() {
    final heap = processHeap();
    if (heap == ffi.nullptr) {
      throw const DeviceReadoutException(
        ErrorCode.readFailed,
        'The process heap is unavailable.',
      );
    }
    final buffer = allocate(heap, 0x00000008, ffi.sizeOf<_SystemPowerStatus>());
    if (buffer == ffi.nullptr) {
      throw const DeviceReadoutException(
        ErrorCode.readFailed,
        'Native power storage allocation failed.',
      );
    }
    try {
      final status = buffer.cast<_SystemPowerStatus>();
      if (query(status) == 0) {
        throw DeviceReadoutException(
          ErrorCode.readFailed,
          'GetSystemPowerStatus failed (Win32 ${lastError()}).',
        );
      }
      return PowerSnapshot(
        powerSource: switch (status.ref.acLineStatus) {
          // ACLineStatus alone cannot distinguish onboard batteries and UPS.
          0 => _hasOnlyOnboardBatteries() ? PowerSource.battery : null,
          1 => PowerSource.external,
          _ => null,
        },
        powerSaveMode: switch (status.ref.systemStatusFlag) {
          0 => false,
          1 => true,
          _ => null,
        },
      );
    } finally {
      free(heap, 0, buffer);
    }
  }

  bool _hasOnlyOnboardBatteries() {
    final heap = processHeap();
    if (heap == ffi.nullptr) return false;
    final buffer = allocate(
      heap,
      0x00000008,
      ffi.sizeOf<_SystemPowerCapabilities>(),
    );
    if (buffer == ffi.nullptr) return false;
    try {
      if (capabilities == null) {
        final directoryBuffer = allocate(heap, 0x00000008, 32768 * 2);
        if (directoryBuffer == ffi.nullptr) return false;
        late final String directory;
        try {
          final directoryQuery = kernel
              .lookupFunction<
                ffi.Uint32 Function(ffi.Pointer<ffi.Uint16>, ffi.Uint32),
                int Function(ffi.Pointer<ffi.Uint16>, int)
              >('GetSystemDirectoryW');
          final count = directoryQuery(directoryBuffer.cast(), 32768);
          if (count == 0 || count >= 32768) return false;
          directory = String.fromCharCodes(
            directoryBuffer.cast<ffi.Uint16>().asTypedList(count),
          );
        } finally {
          free(heap, 0, directoryBuffer);
        }
        final library = powerLibrary ??= ffi.DynamicLibrary.open(
          '$directory\\powrprof.dll',
        );
        capabilities = library
            .lookupFunction<
              ffi.Uint8 Function(ffi.Pointer<_SystemPowerCapabilities>),
              int Function(ffi.Pointer<_SystemPowerCapabilities>)
            >('GetPwrCapabilities');
      }
      final value = buffer.cast<_SystemPowerCapabilities>();
      return capabilities!(value) != 0 &&
          value.ref.systemBatteriesPresent == 1 &&
          value.ref.upsPresent == 0 &&
          value.ref.batteriesAreShortTerm == 0;
    } on ArgumentError {
      // Missing optional information leaves only the ambiguous source null.
      return false;
    } finally {
      free(heap, 0, buffer);
    }
  }

  void dispose() {
    try {
      powerLibrary?.close();
    } finally {
      powerLibrary = null;
      capabilities = null;
      kernel.close();
    }
  }
}
