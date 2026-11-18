part of 'transport_native.dart';

final class _DiskSpaceInformation extends ffi.Struct {
  @ffi.Uint64()
  external int actualTotalAllocationUnits;
  @ffi.Array(10)
  external ffi.Array<ffi.Uint64> otherAllocationUnits;
  @ffi.Uint32()
  external int sectorsPerAllocationUnit;
  @ffi.Uint32()
  external int bytesPerSector;
}

/// Local volume GUID inventory and read-only queries, owned by the collection isolate.
final class _WindowsStorage {
  final kernel = ffi.DynamicLibrary.open('kernel32.dll');
  static const _nameUnits = 261;
  static final _volumeName = RegExp(
    r'^\\\\\?\\Volume\{[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\}\\$',
    caseSensitive: false,
  );
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
  late final lastError = kernel
      .lookupFunction<ffi.Uint32 Function(), int Function()>('GetLastError');
  late final firstVolume = kernel
      .lookupFunction<
        ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Uint16>, ffi.Uint32),
        ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Uint16>, int)
      >('FindFirstVolumeW');
  late final nextVolume = kernel
      .lookupFunction<
        ffi.Int32 Function(
          ffi.Pointer<ffi.Void>,
          ffi.Pointer<ffi.Uint16>,
          ffi.Uint32,
        ),
        int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Uint16>, int)
      >('FindNextVolumeW');
  late final closeSearch = kernel
      .lookupFunction<
        ffi.Int32 Function(ffi.Pointer<ffi.Void>),
        int Function(ffi.Pointer<ffi.Void>)
      >('FindVolumeClose');
  late final diskFreeSpace = kernel
      .lookupFunction<
        ffi.Int32 Function(
          ffi.Pointer<ffi.Uint16>,
          ffi.Pointer<ffi.Uint64>,
          ffi.Pointer<ffi.Uint64>,
          ffi.Pointer<ffi.Uint64>,
        ),
        int Function(
          ffi.Pointer<ffi.Uint16>,
          ffi.Pointer<ffi.Uint64>,
          ffi.Pointer<ffi.Uint64>,
          ffi.Pointer<ffi.Uint64>,
        )
      >('GetDiskFreeSpaceExW');
  late final diskSpace = kernel
      .lookupFunction<
        ffi.Int32 Function(
          ffi.Pointer<ffi.Uint16>,
          ffi.Pointer<_DiskSpaceInformation>,
        ),
        int Function(
          ffi.Pointer<ffi.Uint16>,
          ffi.Pointer<_DiskSpaceInformation>,
        )
      >('GetDiskSpaceInformationW');
  late final driveType = kernel
      .lookupFunction<
        ffi.Uint32 Function(ffi.Pointer<ffi.Uint16>),
        int Function(ffi.Pointer<ffi.Uint16>)
      >('GetDriveTypeW');
  late final openFile = kernel
      .lookupFunction<
        ffi.Pointer<ffi.Void> Function(
          ffi.Pointer<ffi.Uint16>,
          ffi.Uint32,
          ffi.Uint32,
          ffi.Pointer<ffi.Void>,
          ffi.Uint32,
          ffi.Uint32,
          ffi.Pointer<ffi.Void>,
        ),
        ffi.Pointer<ffi.Void> Function(
          ffi.Pointer<ffi.Uint16>,
          int,
          int,
          ffi.Pointer<ffi.Void>,
          int,
          int,
          ffi.Pointer<ffi.Void>,
        )
      >('CreateFileW');
  late final volumeInformation = kernel
      .lookupFunction<
        ffi.Int32 Function(
          ffi.Pointer<ffi.Void>,
          ffi.Pointer<ffi.Uint16>,
          ffi.Uint32,
          ffi.Pointer<ffi.Uint32>,
          ffi.Pointer<ffi.Uint32>,
          ffi.Pointer<ffi.Uint32>,
          ffi.Pointer<ffi.Uint16>,
          ffi.Uint32,
        ),
        int Function(
          ffi.Pointer<ffi.Void>,
          ffi.Pointer<ffi.Uint16>,
          int,
          ffi.Pointer<ffi.Uint32>,
          ffi.Pointer<ffi.Uint32>,
          ffi.Pointer<ffi.Uint32>,
          ffi.Pointer<ffi.Uint16>,
          int,
        )
      >('GetVolumeInformationByHandleW');
  late final closeHandle = kernel
      .lookupFunction<
        ffi.Int32 Function(ffi.Pointer<ffi.Void>),
        int Function(ffi.Pointer<ffi.Void>)
      >('CloseHandle');

  T _withStorage<T>(T Function(ffi.Pointer<ffi.Void> Function(int)) body) {
    // Resolve and warm the error accessor before a failing API can set its value.
    // Lazy native symbol resolution after failure can overwrite GetLastError.
    lastError();
    final heap = processHeap();
    if (heap == ffi.nullptr) {
      throw const DeviceReadoutException(ErrorCode.readFailed, 'The process heap is unavailable.');
    }
    final buffers = <ffi.Pointer<ffi.Void>>[];
    try {
      return body((bytes) {
        final buffer = allocate(heap, 8, bytes);
        if (buffer == ffi.nullptr) {
          throw const DeviceReadoutException(ErrorCode.readFailed, 'Native volume buffer allocation failed.');
        }
        buffers.add(buffer);
        return buffer;
      });
    } finally {
      for (final buffer in buffers.reversed) {
        free(heap, 0, buffer);
      }
    }
  }

  bool _invalid(ffi.Pointer<ffi.Void> handle) =>
      handle == ffi.nullptr ||
      handle.address == ffi.Pointer<ffi.Void>.fromAddress(-1).address;

  String _text(ffi.Pointer<ffi.Uint16> buffer, int capacity) {
    final units = <int>[];
    for (var i = 0; i < capacity; i++) {
      final unit = buffer[i];
      if (unit == 0) return String.fromCharCodes(units);
      units.add(unit);
    }
    throw const DeviceReadoutException(
      ErrorCode.readFailed,
      'Native volume text is not terminated within its bound.',
    );
  }

  List<String> list(ReadContext context) => _withStorage((reserve) {
    context.cancellation.throwIfCancelled();
    const capacity = 64; // A volume GUID path, including its terminator, fits in 50 UTF-16 units.
    final name = reserve(capacity * 2).cast<ffi.Uint16>();
    final handle = firstVolume(name, capacity);
    final firstError = lastError();
    if (_invalid(handle)) {
      if (firstError == 18) return <String>[];
      throw _failure('FindFirstVolumeW', firstError);
    }
    final identities = <String>{};
    try {
      while (true) {
        context.cancellation.throwIfCancelled();
        final value = _text(name, capacity);
        if (!_volumeName.hasMatch(value) ||
            !identities.add(value.toLowerCase()) ||
            identities.length > 4096) {
          throw const DeviceReadoutException(
            ErrorCode.readFailed,
            'Invalid or excessive native volume inventory.',
          );
        }
        for (var i = 0; i < capacity; i++) {
          name[i] = 0;
        }
        final found = nextVolume(handle, name, capacity);
        final error = lastError();
        if (found != 0) continue;
        if (error != 18) throw _failure('FindNextVolumeW', error);
        break;
      }
      return identities.toList(growable: false);
    } finally {
      closeSearch(handle);
    }
  });

  StorageVolumeSnapshot read(String? identity, ReadContext context) {
    if (identity == null || !list(context).contains(identity)) {
      throw const DeviceReadoutException(
        ErrorCode.entityRemoved,
        'The selected native volume is no longer present.',
      );
    }
    return _withStorage((reserve) {
      final root = reserve((identity.length + 1) * 2).cast<ffi.Uint16>();
      for (var i = 0; i < identity.length; i++) {
        root[i] = identity.codeUnitAt(i);
      }
      final counts = reserve(3 * ffi.sizeOf<ffi.Uint64>()).cast<ffi.Uint64>();
      final space = reserve(ffi.sizeOf<_DiskSpaceInformation>())
          .cast<_DiskSpaceInformation>();
      final names = reserve(_nameUnits * 4).cast<ffi.Uint16>();
      final flags = reserve(ffi.sizeOf<ffi.Uint32>()).cast<ffi.Uint32>();
      BigInt? total, available, callerTotal, freeBytes;
      String? name, fileSystem;
      bool? readOnly;
      int? failure;
      if (diskFreeSpace(root, counts, counts + 1, counts + 2) != 0) {
        available = BigInt.from(counts[0]).toUnsigned(64);
        callerTotal = BigInt.from(counts[1]).toUnsigned(64);
        freeBytes = BigInt.from(counts[2]).toUnsigned(64);
      } else {
        failure = lastError();
      }
      context.cancellation.throwIfCancelled();
      if (diskSpace(root, space) == 0) {
        final value = space.ref;
        if (value.sectorsPerAllocationUnit > 0 && value.bytesPerSector > 0) {
          final bytes =
              BigInt.from(value.actualTotalAllocationUnits).toUnsigned(64) *
              BigInt.from(value.sectorsPerAllocationUnit) *
              BigInt.from(value.bytesPerSector);
          if (bytes.bitLength <= 64) total = bytes;
        }
      }
      // Open the root for metadata only, sharing all normal operations. The handle-based
      // information query avoids the path API's documented empty-media prompt behavior.
      final handle = openFile(
        root,
        0,
        7,
        ffi.nullptr,
        3,
        0x02000000,
        ffi.nullptr,
      );
      if (!_invalid(handle)) {
        try {
          if (volumeInformation(
                handle,
                names,
                _nameUnits,
                ffi.nullptr,
                ffi.nullptr,
                flags,
                names + _nameUnits,
                _nameUnits,
              ) !=
              0) {
            name = _text(names, _nameUnits);
            fileSystem = _text(names + _nameUnits, _nameUnits);
            readOnly = (flags.value & 0x00080000) != 0;
          } else {
            failure ??= lastError();
          }
        } finally {
          closeHandle(handle);
        }
      } else {
        failure ??= lastError();
      }
      final removable = switch (driveType(root)) {
        2 => true,
        3 => false,
        _ => null,
      };
      context.cancellation.throwIfCancelled();
      if (!list(context).contains(identity)) {
        throw const DeviceReadoutException(
          ErrorCode.entityRemoved,
          'The volume disappeared during collection.',
        );
      }
      if (total == null &&
          available == null &&
          name == null &&
          removable == null) {
        throw _failure('Volume information', failure ?? 0);
      }
      return StorageVolumeSnapshot(
        name: name,
        fileSystem: fileSystem,
        totalBytes: total,
        freeBytes: freeBytes,
        availableToCallerBytes: available,
        totalBytesForCaller: callerTotal,
        readOnly: readOnly,
        removable: removable,
      );
    });
  }

  DeviceReadoutException _failure(String operation, int error) =>
      DeviceReadoutException(
        error == 5 ? ErrorCode.permissionDenied : ErrorCode.readFailed,
        '$operation failed (Win32 $error).',
      );
  void dispose() => kernel.close();
}
