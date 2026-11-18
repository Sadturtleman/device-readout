part of 'transport_native.dart';

typedef _NetworkRecord = ({int luid, NetworkInterfaceSnapshot snapshot});

/// All native calls, pointer traversal and decoding belong to the collection isolate.
final class _WindowsNetwork {
  final String? _libraryPath;
  final ffi.DynamicLibrary kernel;
  ffi.DynamicLibrary? _ipLibrary;
  _WindowsNetworkNotifications? _notifications;
  Stream<SnapshotRead> watch(String? target, StateWatchContext context) =>
      _WindowsNetworkWatch(this, target, context).stream;
  _WindowsNetwork(this._libraryPath)
    : kernel = ffi.DynamicLibrary.open(_libraryPath ?? 'kernel32.dll');
  ffi.DynamicLibrary get ip =>
      _ipLibrary ??= ffi.DynamicLibrary.open(_libraryPath ?? 'iphlpapi.dll');
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
  late final addresses = ip
      .lookupFunction<
        ffi.Uint32 Function(
          ffi.Uint32,
          ffi.Uint32,
          ffi.Pointer<ffi.Void>,
          ffi.Pointer<ffi.Uint8>,
          ffi.Pointer<ffi.Uint32>,
        ),
        int Function(
          int,
          int,
          ffi.Pointer<ffi.Void>,
          ffi.Pointer<ffi.Uint8>,
          ffi.Pointer<ffi.Uint32>,
        )
      >('GetAdaptersAddresses');

  void dispose() {
    try {
      try {
        _notifications?.dispose();
      } finally {
        _ipLibrary?.close();
      }
    } finally {
      kernel.close();
    }
  }

  late final routeTable = ip
      .lookupFunction<
        ffi.Uint32 Function(ffi.Uint16, ffi.Pointer<ffi.Pointer<ffi.Uint8>>),
        int Function(int, ffi.Pointer<ffi.Pointer<ffi.Uint8>>)
      >('GetIpForwardTable2');
  late final freeTable = ip
      .lookupFunction<
        ffi.Void Function(ffi.Pointer<ffi.Void>),
        void Function(ffi.Pointer<ffi.Void>)
      >('FreeMibTable');

  List<NetworkRoute>? _routes(int luid, ReadContext context) {
    try {
      return _withMemory((reserve) {
        final output = reserve(ffi.sizeOf<ffi.Pointer<ffi.Uint8>>())
            .cast<ffi.Pointer<ffi.Uint8>>();
        context.cancellation.throwIfCancelled();
        final result = routeTable(0, output);
        final table = output.value;
        try {
          context.cancellation.throwIfCancelled();
          if (result == 1168) return <NetworkRoute>[]; // ERROR_NOT_FOUND
          if (result != 0) throw _error(result);
          if (table == ffi.nullptr) throw _invalid();
          final count = table.cast<ffi.Uint32>().value;
          if (count > (_maximum - 8) ~/ 104) throw _invalid();
          final bytes = table.asTypedList(8 + count * 104);
          final data = ByteData.sublistView(bytes);
          ({String address, int bits, bool unspecified}) address(int at) {
            final family = data.getUint16(at, Endian.little);
            final int start, length;
            if (family == 2) {
              start = at + 4;
              length = 4;
            } else if (family == 23) {
              start = at + 8;
              length = 16;
            } else {
              throw _invalid();
            }
            final raw = Uint8List.fromList(
              bytes.sublist(start, start + length),
            );
            var value = InternetAddress.fromRawAddress(raw).address;
            if (family == 23) {
              final scope = data.getUint32(at + 24, Endian.little);
              if (scope != 0) value = '$value%$scope';
            }
            return (
              address: value,
              bits: length * 8,
              unspecified: raw.every((b) => b == 0),
            );
          }

          final routes = <NetworkRoute>[];
          for (var i = 0; i < count; i++) {
            context.cancellation.throwIfCancelled();
            final at = 8 + i * 104;
            if (data.getUint64(at, Endian.little) != luid) continue;
            final destination = address(at + 12), gateway = address(at + 44);
            final prefix = bytes[at + 40];
            if (prefix > destination.bits || destination.bits != gateway.bits)
              throw _invalid();
            routes.add(
              NetworkRoute(
                destination.address,
                prefixLength: prefix,
                gateway: gateway.unspecified ? null : gateway.address,
              ),
            );
          }
          return routes;
        } finally {
          if (table != ffi.nullptr) freeTable(table.cast());
        }
      });
    } on DeviceReadoutException {
      return null;
    }
  }

  static const _maximum = 8 * 1024 * 1024;
  static DeviceReadoutException _invalid() => const DeviceReadoutException(
    ErrorCode.readFailed,
    'Invalid Windows network response.',
  );
  static DeviceReadoutException _error(int error) => DeviceReadoutException(
    error == 5 ? ErrorCode.permissionDenied : ErrorCode.readFailed,
    'Windows network query failed ($error).',
  );

  T _withMemory<T>(T Function(ffi.Pointer<ffi.Void> Function(int)) action) {
    final owner = heap();
    if (owner == ffi.nullptr) throw _invalid();
    final buffers = <ffi.Pointer<ffi.Void>>[];
    try {
      return action((bytes) {
        if (bytes <= 0 || bytes > _maximum) throw _invalid();
        final pointer = allocate(owner, 8, bytes);
        if (pointer == ffi.nullptr) throw _invalid();
        buffers.add(pointer);
        return pointer;
      });
    } finally {
      for (final buffer in buffers.reversed) {
        free(owner, 0, buffer);
      }
    }
  }

  Map<String, _NetworkRecord> _inventory(
    ReadContext context, {
    bool fields = false,
  }) {
    if (ffi.sizeOf<ffi.UintPtr>() != 8) {
      throw const DeviceReadoutException(
        ErrorCode.unsupportedEntity,
        'Windows network collection requires a 64-bit process.',
      );
    }
    return _withMemory((reserve) {
      final size = reserve(4).cast<ffi.Uint32>();
      var capacity = 15 * 1024;
      for (var attempt = 0; attempt < 3; attempt++) {
        context.cancellation.throwIfCancelled();
        final pointer = reserve(capacity).cast<ffi.Uint8>();
        size.value = capacity;
        final result = addresses(
          0,
          2 | 4 | 128 | 256,
          ffi.nullptr,
          pointer,
          size,
        );
        context.cancellation.throwIfCancelled();
        if (result == 232) return <String, _NetworkRecord>{}; // ERROR_NO_DATA
        if (result == 111) {
          // ERROR_BUFFER_OVERFLOW: discard this attempt's data.
          if (size.value <= capacity || size.value > _maximum) throw _invalid();
          capacity = size.value;
          continue;
        }
        if (result != 0) throw _error(result);
        if (size.value == 0 || size.value > capacity) throw _invalid();
        final buffer = _NetworkBuffer(pointer, size.value, context);
        final resultMap = <String, _NetworkRecord>{};
        for (final offset in buffer.nodes(pointer.address, 232)) {
          final adapter = buffer.text(buffer.pointer(offset + 16), wide: false);
          final luid = buffer.data.getUint64(offset + 224, Endian.little);
          if (adapter == null || adapter.isEmpty || luid == 0) throw _invalid();
          final key = '${luid.toRadixString(16)}:$adapter';
          if (resultMap.containsKey(key)) throw _invalid();
          resultMap[key] = (
            luid: luid,
            snapshot: fields
                ? buffer.snapshot(offset)
                : NetworkInterfaceSnapshot(),
          );
        }
        return resultMap;
      }
      throw _invalid();
    });
  }

  List<String> list(ReadContext context) => _inventory(context).keys.toList();

  NetworkInterfaceSnapshot read(String? target, ReadContext context) {
    final record = _inventory(context, fields: true)[target];
    if (record == null)
      throw const DeviceReadoutException(
        ErrorCode.entityRemoved,
        'Network interface is no longer present.',
      );
    final routes = _routes(record.luid, context);
    // A route table and an adapter inventory are separate OS snapshots. Reject
    // a removed/replaced target rather than attaching another lifetime's routes.
    if (!_inventory(context).containsKey(target)) {
      throw const DeviceReadoutException(
        ErrorCode.entityRemoved,
        'Network interface was removed during collection.',
      );
    }
    final value = record.snapshot;
    return NetworkInterfaceSnapshot(
      name: value.name,
      interfaceType: value.interfaceType,
      operationalState: value.operationalState,
      hardwareAddress: value.hardwareAddress,
      ipAddresses: value.ipAddresses,
      dnsServers: value.dnsServers,
      gateways: value.gateways,
      routes: routes,
      mtuBytes: value.mtuBytes,
    );
  }
}

/// Windows x64/ARM64 IP_ADAPTER_ADDRESSES_LH layout. A successful query owns
/// the entire linked graph in one caller-allocated buffer; no pointer escapes it.
final class _NetworkBuffer {
  final ffi.Pointer<ffi.Uint8> base;
  final int length;
  final ReadContext context;
  final Uint8List bytes;
  final ByteData data;
  _NetworkBuffer(this.base, this.length, this.context)
    : bytes = base.asTypedList(length),
      data = ByteData.sublistView(base.asTypedList(length));
  int offset(int pointer, int size) {
    if (pointer < base.address ||
        pointer > base.address + length ||
        size < 0 ||
        size > base.address + length - pointer) {
      throw _WindowsNetwork._invalid();
    }
    return pointer - base.address;
  }

  int pointer(int offset) => data.getUint64(offset, Endian.little);
  int uint(int offset) => data.getUint32(offset, Endian.little);
  T? optional<T>(T Function() action) {
    try {
      return action();
    } on DeviceReadoutException {
      return null;
    }
  }

  Iterable<int> nodes(int first, int minimum) sync* {
    final visited = <int>{};
    for (var current = first; current != 0;) {
      context.cancellation.throwIfCancelled();
      if (!visited.add(current) || visited.length > 65536)
        throw _WindowsNetwork._invalid();
      final at = offset(current, minimum);
      final size = uint(at);
      if (size < minimum) throw _WindowsNetwork._invalid();
      offset(current, size);
      yield at;
      current = pointer(at + 8);
    }
  }

  String? text(int address, {required bool wide}) => optional(() {
    if (address == 0) throw _WindowsNetwork._invalid();
    final start = offset(address, wide ? 2 : 1);
    if (wide) {
      if (address.isOdd) throw _WindowsNetwork._invalid();
      final available = (length - start) ~/ 2;
      final result = _WindowsDeviceInfo.wideString(
        ffi.Pointer<ffi.Uint16>.fromAddress(address),
        available > 32768 ? 32768 : available,
      );
      if (result == null) throw _WindowsNetwork._invalid();
      return result;
    }
    final value = <int>[];
    for (var i = start; i < length && value.length < 1024; i++) {
      if (bytes[i] == 0) return String.fromCharCodes(value);
      value.add(bytes[i]);
    }
    throw _WindowsNetwork._invalid();
  });
  ({String address, int bits}) socket(int socket) {
    final address = pointer(socket), size = uint(socket + 8);
    final at = offset(address, size);
    if (size < 2) throw _WindowsNetwork._invalid();
    final family = data.getUint16(at, Endian.little);
    final int start, count;
    if (family == 2 && size >= 16) {
      start = at + 4;
      count = 4;
    } else if (family == 23 && size >= 28) {
      start = at + 8;
      count = 16;
    } else {
      throw _WindowsNetwork._invalid();
    }
    var value = InternetAddress.fromRawAddress(
      Uint8List.fromList(bytes.sublist(start, start + count)),
    ).address;
    if (family == 23) {
      final scope = uint(at + 24);
      if (scope != 0) value = '$value%$scope';
    }
    return (address: value, bits: count * 8);
  }

  List<IpAddressInfo>? unicast(int first) =>
      optional(() => [for (final at in nodes(first, 57)) _unicast(at)]);
  IpAddressInfo _unicast(int at) {
    final ip = socket(at + 16), prefix = bytes[at + 56];
    return IpAddressInfo(
      ip.address,
      prefixLength: prefix <= ip.bits ? prefix : null,
    );
  }

  List<String>? addressList(int first) => optional(
    () => [for (final at in nodes(first, 32)) socket(at + 16).address],
  );
  NetworkInterfaceSnapshot snapshot(int at) {
    final hardwareLength = uint(at + 88);
    final hardware = hardwareLength == 0 || hardwareLength > 8
        ? null
        : bytes
              .sublist(at + 80, at + 80 + hardwareLength)
              .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
              .join(':');
    return NetworkInterfaceSnapshot(
      name: text(pointer(at + 72), wide: true),
      interfaceType: switch (uint(at + 100)) {
        6 || 26 || 62 || 69 || 117 => NetworkInterfaceType.ethernet,
        71 => NetworkInterfaceType.wifi,
        24 => NetworkInterfaceType.loopback,
        131 => NetworkInterfaceType.tunnel,
        23 => NetworkInterfaceType.ppp,
        243 || 244 => NetworkInterfaceType.cellular,
        209 => NetworkInterfaceType.bridge,
        _ => null,
      },
      operationalState: switch (uint(at + 104)) {
        1 => NetworkOperationalState.up,
        2 => NetworkOperationalState.down,
        3 => NetworkOperationalState.testing,
        5 => NetworkOperationalState.dormant,
        6 => NetworkOperationalState.notPresent,
        7 => NetworkOperationalState.lowerLayerDown,
        _ => null,
      },
      hardwareAddress: hardware,
      ipAddresses: unicast(pointer(at + 24)),
      dnsServers: addressList(pointer(at + 48)),
      gateways: addressList(pointer(at + 208)),
      mtuBytes: BigInt.from(uint(at + 96)),
    );
  }
}
