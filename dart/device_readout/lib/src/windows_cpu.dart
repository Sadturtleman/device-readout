part of 'transport_native.dart';

typedef _CpuAffinity = ({int groups, int count, BigInt process, BigInt system});
typedef _CpuTopology = ({
  Map<int, CpuCoreSnapshot> logical,
  int cores,
  int? packages,
});

/// Processor topology and process-default scheduling availability. Every native
/// query, bounded allocation and decode runs on the collection isolate.
final class _WindowsCpu {
  final ffi.DynamicLibrary kernel;
  final String? _libraryPath;
  ffi.DynamicLibrary? _powerLibrary;
  _WindowsCpu([this._libraryPath])
    : kernel = ffi.DynamicLibrary.open(_libraryPath ?? 'kernel32.dll');
  late final readPower =
      (_powerLibrary ??= ffi.DynamicLibrary.open(
        _libraryPath ?? 'powrprof.dll',
      )).lookupFunction<
        ffi.Int32 Function(
          ffi.Int32,
          ffi.Pointer<ffi.Void>,
          ffi.Uint32,
          ffi.Pointer<ffi.Void>,
          ffi.Uint32,
        ),
        int Function(
          int,
          ffi.Pointer<ffi.Void>,
          int,
          ffi.Pointer<ffi.Void>,
          int,
        )
      >('CallNtPowerInformation');
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
  late final activeCount = kernel
      .lookupFunction<ffi.Uint32 Function(ffi.Uint16), int Function(int)>(
        'GetActiveProcessorCount',
      );
  late final groupCount = kernel
      .lookupFunction<ffi.Uint16 Function(), int Function()>(
        'GetActiveProcessorGroupCount',
      );
  late final topology = kernel.lookup<ffi.Void>(
    'GetLogicalProcessorInformationEx',
  );
  late final affinity = kernel.lookup<ffi.Void>('GetProcessAffinityMask');
  late final defaultSets = kernel.lookup<ffi.Void>('GetProcessDefaultCpuSets');
  late final systemSets = kernel.lookup<ffi.Void>('GetSystemCpuSetInformation');
  static final _currentProcess = ffi.Pointer<ffi.Void>.fromAddress(-1).address;

  void dispose() {
    try {
      _powerLibrary?.close();
    } finally {
      kernel.close();
    }
  }

  DeviceReadoutException _invalid() => const DeviceReadoutException(
    ErrorCode.readFailed,
    'Invalid Windows CPU response.',
  );
  DeviceReadoutException _queryError(int error) => DeviceReadoutException(
    error == 5 ? ErrorCode.permissionDenied : ErrorCode.readFailed,
    'Windows CPU query failed (Win32 $error).',
  );
  T? _optional<T>(T Function() action) {
    try {
      return action();
    } on DeviceReadoutException {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  T _withMemory<T>(T Function(ffi.Pointer<ffi.Void> Function(int)) body) {
    final owner = heap();
    if (owner == ffi.nullptr) throw _invalid();
    final buffers = <ffi.Pointer<ffi.Void>>[];
    try {
      return body((bytes) {
        final buffer = allocate(owner, 8, bytes);
        if (buffer == ffi.nullptr) throw _invalid();
        buffers.add(buffer);
        return buffer;
      });
    } finally {
      for (final buffer in buffers.reversed) {
        free(owner, 0, buffer);
      }
    }
  }

  Uint8List _bytes(
    ReadContext context,
    int Function(WindowsCalls, int, int, int) query, {
    int unit = 1,
    int maximum = 8 * 1024 * 1024,
    bool allowEmpty = true,
  }) => _withMemory((reserve) {
    final calls = WindowsCalls(reserve);
    final size = reserve(4).cast<ffi.Uint32>();
    context.cancellation.throwIfCancelled();
    if (query(calls, 0, 0, size.address) != 0) {
      if (allowEmpty && size.value == 0) return Uint8List(0);
      throw _invalid();
    }
    if (calls.error != 122) throw _queryError(calls.error);
    // A null-buffer sizing query may report ERROR_INSUFFICIENT_BUFFER with
    // zero required bytes when no CPU sets exist. Topology still requires data.
    if (allowEmpty && size.value == 0) return Uint8List(0);
    for (var attempt = 0; attempt < 3; attempt++) {
      context.cancellation.throwIfCancelled();
      final capacity = size.value;
      if (capacity == 0 || capacity > maximum) throw _invalid();
      final data = reserve(capacity * unit).cast<ffi.Uint8>();
      if (query(calls, data.address, capacity, size.address) != 0) {
        if (size.value > capacity || (!allowEmpty && size.value == 0))
          throw _invalid();
        context.cancellation.throwIfCancelled();
        return Uint8List.fromList(data.asTypedList(size.value * unit));
      }
      if (calls.error != 122) throw _queryError(calls.error);
      if (size.value <= capacity) throw _invalid();
    }
    throw _invalid();
  });

  _CpuTopology _topology(ReadContext context) {
    final pointerBytes = ffi.sizeOf<ffi.UintPtr>();
    // WOW64 masks can fold high bits, so never interpret them as complete topology.
    if (pointerBytes != 8) {
      throw const DeviceReadoutException(
        ErrorCode.unsupportedEntity,
        'This process cannot identify all logical CPUs from native affinity masks.',
      );
    }
    final raw = _bytes(
      context,
      (calls, data, capacity, length) => calls.invoke(
        WindowsCall.processorTopology,
        topology,
        [0xffff, data, length],
      ),
      allowEmpty: false,
    );
    final data = ByteData.sublistView(raw);
    final cores = <Set<int>>[], packages = <Set<int>>[];
    for (var offset = 0; offset < raw.length;) {
      context.cancellation.throwIfCancelled();
      if (raw.length - offset < 8) throw _invalid();
      final kind = data.getUint32(offset, Endian.little);
      final size = data.getUint32(offset + 4, Endian.little);
      if (size < 8 || size > raw.length - offset) throw _invalid();
      if (kind == 0 || kind == 3) {
        if (size < 32) throw _invalid();
        final groups = data.getUint16(offset + 30, Endian.little);
        final stride = pointerBytes + 8;
        if (groups == 0 ||
            (kind == 0 && groups != 1) ||
            32 + groups * stride > size)
          throw _invalid();
        final members = <int>{}, seenGroups = <int>{};
        for (var i = 0; i < groups; i++) {
          final position = offset + 32 + i * stride;
          final mask = BigInt.from(data.getUint64(position, Endian.little))
              .toUnsigned(64);
          final group = data.getUint16(position + pointerBytes, Endian.little);
          if (mask == BigInt.zero || !seenGroups.add(group)) throw _invalid();
          for (var bit = 0; bit < 64; bit++) {
            if ((mask & (BigInt.one << bit)) != BigInt.zero)
              members.add(group * 64 + bit);
          }
        }
        (kind == 0 ? cores : packages).add(members);
      }
      offset += size;
    }
    if (cores.isEmpty) throw _invalid();
    int minimum(Set<int> values) => values.reduce((a, b) => a < b ? a : b);
    cores.sort((a, b) => minimum(a).compareTo(minimum(b)));
    packages.sort((a, b) => minimum(a).compareTo(minimum(b)));
    final logical = <int>{};
    final coreMembership = <int, int>{};
    for (var core = 0; core < cores.length; core++) {
      for (final index in cores[core]) {
        if (!logical.add(index)) throw _invalid();
        coreMembership[index] = core;
      }
    }
    final membership = <int, int>{};
    for (var package = 0; package < packages.length; package++) {
      for (final index in packages[package]) {
        if (!logical.contains(index) || membership.containsKey(index))
          throw _invalid();
        membership[index] = package;
      }
    }
    if (packages.isNotEmpty &&
        (membership.length != logical.length ||
            cores.any(
              (core) =>
                  core.map((index) => membership[index]).toSet().length != 1,
            )))
      throw _invalid();
    return (
      logical: {
        for (final index in logical.toList()..sort())
          index: CpuCoreSnapshot(
            logicalIndex: index,
            coreIndex: coreMembership[index],
            packageIndex: membership[index],
            online: true,
          ),
      },
      cores: cores.length,
      packages: packages.isEmpty ? null : packages.length,
    );
  }

  List<String> list(ReadContext context) =>
      _topology(context).logical.keys
          .map((index) => index.toString())
          .toList(growable: false);

  CpuCoreSnapshot readCore(String? identity, ReadContext context) {
    final data = _topology(context);
    final value = data.logical[int.tryParse(identity ?? '')];
    if (value == null) {
      throw const DeviceReadoutException(
        ErrorCode.entityRemoved,
        'The selected logical CPU is no longer present.',
      );
    }
    final clocks = _optional(() => _clocks(data, value.logicalIndex!, context));
    return CpuCoreSnapshot(
      logicalIndex: value.logicalIndex,
      coreIndex: value.coreIndex,
      packageIndex: value.packageIndex,
      online: value.online,
      currentClockHz: clocks?.current,
      maximumClockHz: clocks?.maximum,
    );
  }

  ({double current, double maximum})? _clocks(
    _CpuTopology data,
    int index,
    ReadContext context,
  ) {
    // Power records expose no processor group. Only a contiguous group-zero
    // inventory can be mapped without guessing which logical CPU they describe.
    final count = data.logical.length;
    if (groupCount() != 1 ||
        count > 64 ||
        data.logical.keys.first != 0 ||
        data.logical.keys.last != count - 1)
      return null;
    return _withMemory((reserve) {
      context.cancellation.throwIfCancelled();
      final values = reserve(count * 24).cast<ffi.Uint32>();
      if (readPower(11, ffi.nullptr, 0, values.cast(), count * 24) != 0)
        return null;
      context.cancellation.throwIfCancelled();
      final numbers = <int>{};
      ({double current, double maximum})? result;
      for (var position = 0; position < count; position++) {
        final offset = position * 6, number = values[offset];
        if (number >= count || !numbers.add(number)) return null;
        if (number == index)
          result = (
            current: values[offset + 2] * 1000000.0,
            maximum: values[offset + 1] * 1000000.0,
          );
      }
      return result;
    });
  }

  _CpuAffinity _affinity(ReadContext context) => _withMemory((reserve) {
    context.cancellation.throwIfCancelled();
    final groups = groupCount(), count = activeCount(0);
    final masks = reserve(2 * ffi.sizeOf<ffi.UintPtr>()).cast<ffi.UintPtr>();
    final calls = WindowsCalls(reserve);
    if (groups == 0 ||
        count == 0 ||
        count == 0xffffffff ||
        calls.invoke(WindowsCall.processAffinity, affinity, [
              _currentProcess,
              masks.address,
              (masks + 1).address,
            ]) ==
            0)
      throw _invalid();
    final width = ffi.sizeOf<ffi.UintPtr>() * 8;
    return (
      groups: groups,
      count: count,
      process: BigInt.from(masks[0]).toUnsigned(width),
      system: BigInt.from(masks[1]).toUnsigned(width),
    );
  });

  Set<int> _selected(ReadContext context) {
    final raw = _bytes(
      context,
      (calls, data, count, length) => calls.invoke(
        WindowsCall.processCpuSets,
        defaultSets,
        [_currentProcess, data, count, length],
      ),
      unit: 4,
      maximum: 65536,
    );
    final data = ByteData.sublistView(raw), ids = <int>{};
    for (var offset = 0; offset < raw.length; offset += 4) {
      if (!ids.add(data.getUint32(offset, Endian.little))) throw _invalid();
    }
    return ids;
  }

  int _bits(BigInt mask) {
    var count = 0;
    while (mask != BigInt.zero) {
      mask &= mask - BigInt.one;
      count++;
    }
    return count;
  }

  int? _available(ReadContext context) {
    final before = _affinity(context), width = ffi.sizeOf<ffi.UintPtr>() * 8;
    if (before.groups != 1 ||
        before.count > width ||
        before.process == BigInt.zero ||
        before.system == BigInt.zero ||
        (before.process & ~before.system) != BigInt.zero)
      return null;
    final selected = _selected(context);
    final raw = _bytes(
      context,
      (calls, data, count, length) => calls.invoke(
        WindowsCall.systemCpuSets,
        systemSets,
        [data, count, length, _currentProcess, 0],
      ),
    );
    final after = _affinity(context), afterSelected = _selected(context);
    if (before != after ||
        selected.length != afterSelected.length ||
        !selected.containsAll(afterSelected))
      return null;
    if (raw.isEmpty) return selected.isEmpty ? _bits(before.process) : null;
    final data = ByteData.sublistView(raw), ids = <int>{};
    var known = BigInt.zero, allowed = BigInt.zero, preferred = BigInt.zero;
    for (var offset = 0; offset < raw.length;) {
      if (raw.length - offset < 8) throw _invalid();
      final size = data.getUint32(offset, Endian.little);
      if (size < 32 ||
          size > raw.length - offset ||
          data.getUint32(offset + 4, Endian.little) != 0)
        throw _invalid();
      final id = data.getUint32(offset + 8, Endian.little),
          group = data.getUint16(offset + 12, Endian.little);
      final logical = data.getUint8(offset + 14),
          flags = data.getUint8(offset + 19);
      if (!ids.add(id) || group != 0 || logical >= width || (flags & 0xf0) != 0)
        throw _invalid();
      final bit = BigInt.one << logical;
      if ((known & bit) != BigInt.zero) throw _invalid();
      known |= bit;
      if ((flags & 2) == 0 || (flags & 4) != 0) {
        allowed |= bit;
        if (selected.contains(id)) preferred |= bit;
      }
      offset += size;
    }
    if ((before.system & ~known) != BigInt.zero || !ids.containsAll(selected))
      return null;
    allowed &= before.process;
    preferred &= allowed;
    final effective = selected.isNotEmpty && preferred != BigInt.zero
        ? preferred
        : allowed;
    return effective == BigInt.zero ? null : _bits(effective);
  }

  CpuSnapshot read(
    ReadContext context,
    String? Function(String, String) registry,
  ) {
    context.cancellation.throwIfCancelled();
    final counts = _optional(() => _topology(context));
    final total = _optional(() {
      final value = activeCount(0xffff);
      return value > 0 && value != 0xffffffff ? value : null;
    });
    final available = _optional(() => _available(context));
    const key = r'HARDWARE\DESCRIPTION\System\CentralProcessor\0';
    final model = registry(key, 'ProcessorNameString'),
        manufacturer = registry(key, 'VendorIdentifier');
    if (counts == null &&
        total == null &&
        available == null &&
        model == null &&
        manufacturer == null)
      throw _invalid();
    return CpuSnapshot(
      model: model,
      manufacturer: manufacturer,
      logicalProcessorCount: counts?.logical.length ?? total,
      availableLogicalProcessorCount: available,
      physicalCoreCount: counts?.cores,
      processorPackageCount: counts?.packages,
    );
  }
}
