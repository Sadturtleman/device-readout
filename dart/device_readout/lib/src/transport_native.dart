import 'dart:async';
import 'dart:collection';
import 'dart:ffi' as ffi;
import 'dart:io' show Platform;
import 'dart:isolate';

import 'core.dart';
import 'transport_api.dart';

part 'transport_native_watch.dart';
part 'windows_memory.dart';
part 'windows_runtime.dart';
part 'windows_os.dart';
part 'windows_power.dart';
part 'windows_device_info.dart';
part 'windows_time_zone.dart';
part 'windows_locale.dart';
part 'windows_locale_unicode.dart';

CollectionChannel createWebChannel(Uri workerUri) =>
    throw const DeviceReadoutException(
      ErrorCode.unsupportedEntity,
      'Web collection requires a browser runtime.',
    );

enum _ReadOperation { snapshot, list, current, capabilities }

CollectionChannel createChannel(
  CollectorFactory factory,
  Object? initialData,
) => _IsolateChannel(factory, initialData);

DeviceCollector createNativeCollector(Object? _) => _NativeCollector();

final class _NativeCollector
    implements DeviceCollector, DeviceCapabilityCollector {
  // The factory and this lazy binding are accessed only by the collection isolate.
  _WindowsMemory? windowsMemory;
  _WindowsRuntime? windowsRuntime;
  _WindowsOs? windowsOs;
  _WindowsDeviceInfo? windowsDeviceInfo;
  _WindowsTimeZone? windowsTimeZone;
  _WindowsLocale? windowsLocale;
  _WindowsPower? windowsPower;

  @override
  EntityCapabilities capabilities(EntityAddress entity, ReadContext context) {
    context.cancellation.throwIfCancelled();
    final available =
        entity.kind == EntityKind.runtime ||
        (Platform.isWindows &&
            (entity.kind == EntityKind.ram ||
                entity.kind == EntityKind.processMemory ||
                entity.kind == EntityKind.os ||
                entity.kind == EntityKind.timeZone ||
                entity.kind == EntityKind.locale ||
                entity.kind == EntityKind.power ||
                entity.kind == EntityKind.deviceInfo));
    return EntityCapabilities(readable: available, watchable: available);
  }

  @override
  DeviceSnapshot read(EntityAddress entity, ReadContext context) {
    context.cancellation.throwIfCancelled();
    if (Platform.isWindows && entity.kind == EntityKind.ram) {
      return (windowsMemory ??= _WindowsMemory()).read();
    }
    if (Platform.isWindows && entity.kind == EntityKind.processMemory) {
      return (windowsMemory ??= _WindowsMemory()).readProcess();
    }
    if (Platform.isWindows && entity.kind == EntityKind.os) {
      return (windowsOs ??= _WindowsOs()).read();
    }
    if (Platform.isWindows && entity.kind == EntityKind.deviceInfo) {
      return (windowsDeviceInfo ??= _WindowsDeviceInfo()).read();
    }
    if (Platform.isWindows && entity.kind == EntityKind.timeZone) {
      return (windowsTimeZone ??= _WindowsTimeZone()).read();
    }
    if (Platform.isWindows && entity.kind == EntityKind.locale) {
      return (windowsLocale ??= _WindowsLocale()).read();
    }
    if (Platform.isWindows && entity.kind == EntityKind.power) {
      return (windowsPower ??= _WindowsPower()).read();
    }
    if (entity.kind != EntityKind.runtime) {
      throw const DeviceReadoutException(
        ErrorCode.unsupportedEntity,
        'A native Dart collector is not yet implemented for this entity.',
      );
    }
    const architectures = <ffi.Abi, Architecture>{
      ffi.Abi.androidArm: Architecture.arm32,
      ffi.Abi.androidArm64: Architecture.arm64,
      ffi.Abi.androidIA32: Architecture.x86,
      ffi.Abi.androidX64: Architecture.x64,
      ffi.Abi.androidRiscv64: Architecture.riscV64,
      ffi.Abi.fuchsiaArm64: Architecture.arm64,
      ffi.Abi.fuchsiaX64: Architecture.x64,
      ffi.Abi.fuchsiaRiscv64: Architecture.riscV64,
      ffi.Abi.iosArm: Architecture.arm32,
      ffi.Abi.iosArm64: Architecture.arm64,
      ffi.Abi.iosX64: Architecture.x64,
      ffi.Abi.linuxArm: Architecture.arm32,
      ffi.Abi.linuxArm64: Architecture.arm64,
      ffi.Abi.linuxIA32: Architecture.x86,
      ffi.Abi.linuxX64: Architecture.x64,
      ffi.Abi.linuxRiscv32: Architecture.riscV32,
      ffi.Abi.linuxRiscv64: Architecture.riscV64,
      ffi.Abi.macosArm64: Architecture.arm64,
      ffi.Abi.macosX64: Architecture.x64,
      ffi.Abi.windowsArm64: Architecture.arm64,
      ffi.Abi.windowsIA32: Architecture.x86,
      ffi.Abi.windowsX64: Architecture.x64,
    };
    return RuntimeSnapshot(
      hostArchitecture: Platform.isWindows
          ? (windowsRuntime ??= _WindowsRuntime()).hostArchitecture()
          : null,
      processArchitecture: architectures[ffi.Abi.current()],
      processBitness: ffi.sizeOf<ffi.IntPtr>() * 8,
    );
  }

  @override
  void dispose() {
    try {
      try {
        try {
          try {
            windowsPower?.dispose();
          } finally {
            windowsPower = null;
            windowsLocale?.dispose();
          }
        } finally {
          windowsLocale = null;
          windowsTimeZone?.dispose();
        }
      } finally {
        windowsTimeZone = null;
        windowsDeviceInfo?.dispose();
      }
    } finally {
      windowsDeviceInfo = null;
      try {
        windowsOs?.dispose();
      } finally {
        windowsOs = null;
        try {
          windowsRuntime?.dispose();
        } finally {
          windowsRuntime = null;
          windowsMemory?.dispose();
          windowsMemory = null;
        }
      }
    }
  }
}

final class _IsolateChannel implements CollectionChannel {
  @override
  bool get available => true;
  final CollectorFactory _factory;
  final Object? _initialData;
  final Queue<_Read> _queue = Queue();
  final _watches = <int, _NativeStateWatch>{};
  ReceivePort? _messages, _errors, _exits;
  SendPort? _worker;
  _Read? _active;
  int _nextId = 0;
  bool _started = false, _closed = false;
  DeviceReadoutException? _failure;

  _IsolateChannel(this._factory, this._initialData);

  @override
  Future<EntityCapabilities> capabilities(
    EntityAddress entity,
    Duration timeout,
    CancellationToken cancellation,
  ) async => await _request(
    entity,
    SensorSamplingRate.platformDefault,
    timeout,
    cancellation,
    operation: _ReadOperation.capabilities,
  ) as EntityCapabilities;

  @override
  Stream<DeviceSnapshot?> watch(
    EntityAddress entity,
    Duration pollInterval,
    Duration readTimeout,
    CancellationToken cancellation, {
    void Function()? onCollected,
  }) => _NativeStateWatch(
    this,
    ++_nextId,
    entity,
    pollInterval,
    readTimeout,
    cancellation,
    onCollected,
  ).stream;

  @override
  Future<DeviceSnapshot> read(
    EntityAddress entity,
    SensorSamplingRate rate,
    Duration timeout,
    CancellationToken? cancellation, {
    DeviceSnapshot? observed,
    bool description = false,
  }) async => await _request(
    entity,
    rate,
    timeout,
    cancellation,
    observed: observed,
    description: description,
  ) as DeviceSnapshot;

  @override
  Future<List<String>> list(
    EntityKind kind,
    Duration timeout,
    CancellationToken cancellation,
  ) async => await _request(
    EntityAddress(kind),
    SensorSamplingRate.platformDefault,
    timeout,
    cancellation,
    operation: _ReadOperation.list,
  ) as List<String>;

  @override
  Future<String?> current(
    EntityKind kind,
    Duration timeout,
    CancellationToken cancellation,
  ) async => await _request(
    EntityAddress(kind),
    SensorSamplingRate.platformDefault,
    timeout,
    cancellation,
    operation: _ReadOperation.current,
  ) as String?;

  Future<Object?> _request(
    EntityAddress entity,
    SensorSamplingRate rate,
    Duration timeout,
    CancellationToken? cancellation, {
    DeviceSnapshot? observed,
    bool description = false,
    _ReadOperation operation = _ReadOperation.snapshot,
  }) {
    if (_closed || cancellation?.isCancelled == true) {
      return Future.error(const DeviceReadoutCancelled());
    }
    if (_failure != null) return Future.error(_failure!);
    if (_queue.length >= 128) {
      return Future.error(
        const DeviceReadoutException(
          ErrorCode.readFailed,
          'The bounded collection queue is full.',
        ),
      );
    }
    final read = _Read(
      ++_nextId,
      entity,
      rate,
      observed,
      description,
      timeout,
      operation,
    );
    _queue.add(read);
    read.timer = Timer(
      timeout,
      () => _cancel(
        read,
        const DeviceReadoutException(
          ErrorCode.readTimeout,
          'Collection exceeded its read timeout.',
        ),
      ),
    );
    read.detach = cancellation?.listen(
      () => _cancel(read, const DeviceReadoutCancelled()),
    );
    if (!_started) _start();
    _pump();
    return read.result.future;
  }

  void _start() {
    _started = true;
    final messages = _messages = ReceivePort();
    final errors = _errors = ReceivePort();
    final exits = _exits = ReceivePort();
    messages.listen(_receive);
    errors.listen(
      (Object? error) => _fail(
        DeviceReadoutException(
          ErrorCode.readFailed,
          'The collection isolate failed: $error',
        ),
      ),
    );
    exits.listen((Object? _) {
      if (!_closed) {
        _fail(
          const DeviceReadoutException(
            ErrorCode.readFailed,
            'The collection isolate exited unexpectedly.',
          ),
        );
      }
      _closePorts();
    });
    unawaited(
      Isolate.spawn(
        _collect,
        [_factory, _initialData, messages.sendPort],
        onError: errors.sendPort,
        onExit: exits.sendPort,
        errorsAreFatal: true,
        debugName: 'DeviceReadout collector',
      ).then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {
          _fail(
            DeviceReadoutException(
              ErrorCode.readFailed,
              'Unable to create the collection isolate: $error',
            ),
          );
          _closePorts();
        },
      ),
    );
  }

  void _receive(Object? raw) {
    final message = raw as List<Object?>;
    switch (message[0]) {
      case 'ready':
        _worker = message[1] as SendPort;
        if (_closed || _failure != null) {
          _worker!.send(['close']);
        } else {
          _pump();
          for (final watch in _watches.values.toList()) {
            watch.send();
          }
        }
      case 'watchReading':
        _watches[message[1]]?.reading();
      case 'watchValue':
        _watches[message[1]]?.value(message[2] as DeviceSnapshot);
        _worker?.send(['watchAck', message[1]]);
      case 'watchFallback':
        _watches[message[1]]?.value(null);
        _watches[message[1]]?.done();
      case 'watchDone':
        _watches[message[1]]?.done();
      case 'watchError':
        _watches[message[1]]?.fail(message[2]!);
      case 'startupError':
        _fail(message[1] as DeviceReadoutException);
      case 'result':
        final read = _active;
        if (read == null || read.id != message[1]) return;
        _active = null;
        if (!read.result.isCompleted) {
          read.stop();
          if (message[3] != null) {
            read.result.completeError(message[3]!);
          } else {
            read.result.complete(message[2]);
          }
        }
        _pump();
    }
  }

  void _pump() {
    if (_worker == null || _closed || _failure != null || _active != null)
      return;
    if (_queue.isEmpty) return;
    final read = _active = _queue.removeFirst();
    final remaining = read.timeout - read.elapsed.elapsed;
    if (remaining <= Duration.zero) {
      _cancel(
        read,
        const DeviceReadoutException(
          ErrorCode.readTimeout,
          'Collection exceeded its read timeout.',
        ),
      );
      _active = null;
      _pump();
      return;
    }
    _worker!.send([
      'read',
      read.id,
      read.entity,
      read.rate,
      read.observed,
      read.description,
      remaining,
      read.operation,
    ]);
  }

  void _cancel(_Read read, Object error) {
    if (read.result.isCompleted) return;
    read.stop();
    _queue.remove(read);
    read.result.completeError(error);
    if (identical(read, _active)) _worker?.send(['cancel', read.id]);
  }

  void _fail(DeviceReadoutException error) {
    _failure ??= error;
    for (final read in [..._queue, if (_active != null) _active!]) {
      _cancel(read, error);
    }
    for (final watch in _watches.values.toList()) {
      watch.fail(error);
    }
    _worker?.send(['close']);
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    for (final read in [..._queue, if (_active != null) _active!]) {
      _cancel(read, const DeviceReadoutCancelled());
    }
    for (final watch in _watches.values.toList()) {
      watch.fail(const DeviceReadoutCancelled());
    }
    _worker?.send(['close']);
  }

  void _closePorts() {
    _messages?.close();
    _errors?.close();
    _exits?.close();
    _worker = null;
  }
}

final class _Read {
  final int id;
  final EntityAddress entity;
  final SensorSamplingRate rate;
  final DeviceSnapshot? observed;
  final bool description;
  final Duration timeout;
  final _ReadOperation operation;
  final elapsed = Stopwatch()..start();
  final result = Completer<Object?>();
  Timer? timer;
  void Function()? detach;
  _Read(
    this.id,
    this.entity,
    this.rate,
    this.observed,
    this.description,
    this.timeout,
    this.operation,
  );
  void stop() {
    timer?.cancel();
    detach?.call();
    detach = null;
  }
}

// This top-level entry point captures no host object graph.
void _collect(List<Object?> initial) async {
  final factory = initial[0] as CollectorFactory;
  final host = initial[2] as SendPort;
  final commands = ReceivePort();
  DeviceCollector? collector;
  Future<DeviceCollector>? constructing;
  DeviceReadoutException? constructionFailure;
  Future<DeviceCollector> nativeCollector() async {
    if (constructionFailure != null) throw constructionFailure!;
    if (collector != null) return collector!;
    return constructing ??= () async {
      try {
        return collector = await factory(initial[1]);
      } catch (error) {
        throw constructionFailure = _failure(error);
      }
    }();
  }

  bool closing = false, disposing = false;
  int? activeId;
  CancellationToken? activeCancellation;
  final watches = <int, _WorkerStateWatch>{};

  Future<void> cleanup() async {
    if (!closing || activeId != null || watches.isNotEmpty || disposing) return;
    disposing = true;
    try {
      await collector?.dispose();
    } finally {
      commands.close();
      Isolate.exit();
    }
  }

  Future<void> read(List<Object?> message) async {
    final id = message[1] as int;
    final entity = message[2] as EntityAddress;
    final cancellation = CancellationToken();
    activeId = id;
    activeCancellation = cancellation;
    Object? snapshot;
    Object? failure;
    try {
      final operation = message[7] as _ReadOperation;
      if (operation == _ReadOperation.capabilities) {
        final source = await nativeCollector();
        cancellation.throwIfCancelled();
        snapshot = source is DeviceCapabilityCollector
            ? await (source as DeviceCapabilityCollector).capabilities(
                entity,
                ReadContext(
                  cancellation,
                  SensorSamplingRate.platformDefault,
                  readTimeout: message[6] as Duration,
                ),
              )
            : const EntityCapabilities(readable: null, watchable: null);
        cancellation.throwIfCancelled();
      } else if (operation != _ReadOperation.snapshot) {
        final source = await nativeCollector();
        cancellation.throwIfCancelled();
        if (source is! DeviceDiscoveryCollector) {
          throw const DeviceReadoutException(
            ErrorCode.unsupportedEntity,
            'Native discovery is unavailable.',
          );
        }
        final discovery = source as DeviceDiscoveryCollector;
        final context = ReadContext(
          cancellation,
          SensorSamplingRate.platformDefault,
          readTimeout: message[6] as Duration,
        );
        if (operation == _ReadOperation.list) {
          final identities = await discovery.list(entity.kind, context);
          cancellation.throwIfCancelled();
          if (identities.length > 4096 ||
              identities.toSet().length != identities.length ||
              identities.any((id) => id.isEmpty || id.length > 1024)) {
            throw const DeviceReadoutException(
              ErrorCode.readFailed,
              'Invalid or oversized native inventory.',
            );
          }
          snapshot = List<String>.unmodifiable(identities);
        } else {
          final identity = await discovery.current(entity.kind, context);
          cancellation.throwIfCancelled();
          if (identity != null &&
              (identity.isEmpty || identity.length > 1024)) {
            throw const DeviceReadoutException(
              ErrorCode.readFailed,
              'Invalid native current identity.',
            );
          }
          snapshot = identity;
        }
      } else {
        var raw = message[4] as DeviceSnapshot?;
        if (raw == null) {
          final source = await nativeCollector();
          cancellation.throwIfCancelled();
          raw = await source.read(
            entity,
            ReadContext(
              cancellation,
              message[3] as SensorSamplingRate,
              readTimeout: message[6] as Duration,
            ),
          );
        }
        cancellation.throwIfCancelled();
        snapshot = message[5] == true
            ? prepareDescription(entity.kind, raw as SensorDescription)
            : prepareSnapshot(entity.kind, raw);
      }
    } catch (error) {
      failure = error is DeviceReadoutCancelled ? error : _failure(error);
    }
    activeId = null;
    activeCancellation = null;
    host.send(['result', id, snapshot, failure]);
    await cleanup();
  }

  commands.listen((Object? raw) {
    final message = raw as List<Object?>;
    switch (message[0]) {
      case 'watch':
        if (!closing) {
          final id = message[1] as int;
          final watch = _WorkerStateWatch(
            id,
            message[2] as EntityAddress,
            StateWatchContext(
              CancellationToken(),
              message[3] as Duration,
              message[4] as Duration,
            ),
            host,
            nativeCollector,
            () {
              watches.remove(id);
              unawaited(cleanup());
            },
          );
          watches[id] = watch;
          unawaited(watch.start());
        }
      case 'watchAck':
        watches[message[1]]?.acknowledge();
      case 'unwatch':
        watches[message[1]]?.stop();
      case 'read':
        if (!closing) unawaited(read(message));
      case 'cancel':
        if (activeId == message[1]) activeCancellation?.cancel();
      case 'close':
        closing = true;
        activeCancellation?.cancel();
        for (final watch in watches.values.toList()) {
          watch.stop();
        }
        unawaited(cleanup());
    }
  });
  host.send(['ready', commands.sendPort]);
}

DeviceReadoutException _failure(Object error) => error is DeviceReadoutException
    ? error
    : DeviceReadoutException(ErrorCode.readFailed, error.toString());
