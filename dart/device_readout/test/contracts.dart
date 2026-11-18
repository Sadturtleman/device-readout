import 'dart:async';
import 'dart:isolate';
import 'dart:io';

import 'package:device_readout/device_readout.dart';

import 'observers.dart' as observerTests;
import 'state_sources.dart' as stateSourceTests;
import 'sensors.dart' as sensorTests;
import 'failure_sources.dart' as failureSourceTests;
import 'native_state_streams.dart' as nativeStateTests;
import 'discovery.dart' as discoveryTests;
import 'capabilities.dart' as capabilityTests;
import 'sensor_metadata.dart' as sensorMetadataTests;
import 'rotations.dart' as rotationTests;
import 'completion.dart' as completionTests;
import 'native_windows.dart' as nativeWindowsTests;
import 'native_windows_process.dart' as nativeProcessTests;
import 'native_windows_runtime.dart' as nativeRuntimeTests;
import 'native_windows_os.dart' as nativeOsTests;
import 'native_windows_time_zone.dart' as nativeTimeZoneTests;
import 'native_windows_locale.dart' as nativeLocaleTests;
import 'native_windows_power.dart' as nativePowerTests;
import 'native_windows_connectivity.dart' as nativeConnectivityTests;
import 'native_windows_network_performance.dart' as nativePerformanceTests;
import 'native_windows_wifi.dart' as nativeWifiTests;
import 'native_windows_connectivity_faults.dart' as nativeConnectivityFaultTests;
import 'native_windows_storage.dart' as nativeStorageTests;
import 'native_windows_storage_faults.dart' as nativeStorageFaultTests;
import 'native_windows_cpu.dart' as nativeCpuTests;
import 'native_windows_cpu_controls.dart' as nativeCpuControlTests;
import 'native_windows_cpu_faults.dart' as nativeCpuFaultTests;
import 'native_windows_cpu_cores.dart' as nativeCpuCoreTests;
import 'native_windows_cpu_core_faults.dart' as nativeCpuCoreFaultTests;
import 'native_windows_network.dart' as nativeNetworkTests;
import 'native_windows_network_faults.dart' as nativeNetworkFaultTests;
import 'native_windows_network_events.dart' as nativeNetworkEventTests;
import 'native_windows_device_info.dart' as nativeDeviceInfoTests;
import 'native_windows_registry.dart' as nativeRegistryTests;

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

DeviceCollector ramCollector(Object? data) => _RamCollector(data as SendPort);

final class _RamCollector implements DeviceCollector {
  final SendPort probe;
  _RamCollector(this.probe) {
    probe.send(['created', Isolate.current.debugName]);
  }
  @override
  DeviceSnapshot read(EntityAddress entity, ReadContext context) {
    probe.send(['read', Isolate.current.debugName]);
    return RamSnapshot(
      physicalBytes: BigInt.parse('18446744073709551615'),
      availableBytes: BigInt.zero,
      lowMemory: false,
    );
  }

  @override
  void dispose() {
    probe.send(['disposed', Isolate.current.debugName]);
  }
}

Future<void> isolatedTypedRead() async {
  final port = ReceivePort();
  final events = <List<Object?>>[];
  final disposed = Completer<void>();
  final subscription = port.listen((Object? message) {
    final event = message as List<Object?>;
    events.add(event);
    if (event[0] == 'disposed') disposed.complete();
  });
  final sdk = DeviceAccess.isolated(ramCollector, initialData: port.sendPort);
  try {
    await Future<void>.delayed(const Duration(milliseconds: 30));
    check(events.isEmpty, 'Creating access must not start a collector.');
    final before = DateTime.now().toUtc();
    final RamSnapshot snapshot = await sdk.get(Entities.ram);
    check(
      snapshot.physicalBytes.toString() == '18446744073709551615',
      'The unsigned 64-bit maximum must remain exact.',
    );
    check(
      snapshot.availableBytes == BigInt.zero && snapshot.lowMemory == false,
      'Zero and false are values.',
    );
    check(snapshot.freeBytes == null, 'Unread fields remain null.');
    check(
      !snapshot.collectedAt.isBefore(before) && snapshot.collectedAt.isUtc,
      'The worker stamps completion in UTC.',
    );
    check(
      snapshot.toJson()['physicalBytes'] == '18446744073709551615',
      'JSON counters use decimal strings.',
    );
    check(
      events.where((e) => e[0] == 'read').single[1] !=
          Isolate.current.debugName,
      'Collection must execute in a different isolate.',
    );
    sdk.dispose();
    await disposed.future.timeout(const Duration(seconds: 2));
    check(
      events.last[1] != Isolate.current.debugName,
      'Resource cleanup must execute in its owning isolate.',
    );
  } finally {
    sdk.dispose();
    await subscription.cancel();
    port.close();
  }
}

Future<void> coldStateWatch() async {
  final port = ReceivePort();
  final events = <List<Object?>>[];
  final disposed = Completer<void>();
  final listener = port.listen((Object? raw) {
    final event = raw as List<Object?>;
    events.add(event);
    if (event[0] == 'disposed') disposed.complete();
  });
  final sdk = DeviceAccess.isolated(ramCollector, initialData: port.sendPort);
  final fast = sdk.withPollInterval(const Duration(milliseconds: 25));
  final stream = fast.watch(Entities.ram);
  final slower = fast
      .withPollInterval(const Duration(seconds: 5))
      .withReadTimeout(const Duration(seconds: 2))
      .withSensorSamplingRate(SensorSamplingRate.atHertz(60));
  try {
    await Future<void>.delayed(const Duration(milliseconds: 30));
    check(events.isEmpty, 'watch must remain cold until it has a listener.');
    check(
      sdk.pollInterval == const Duration(seconds: 1) &&
          sdk.readTimeout == const Duration(seconds: 5) &&
          fast.pollInterval == const Duration(milliseconds: 25) &&
          slower.pollInterval == const Duration(seconds: 5) &&
          sdk.sensorSamplingRate == SensorSamplingRate.platformDefault,
      'Configuration views must preserve the original and each other.',
    );
    final values = await stream
        .take(3)
        .toList()
        .timeout(const Duration(seconds: 2));
    check(
      values.length == 3 && values.every((s) => s.lowMemory == false),
      'Equal snapshots must be emitted for every poll.',
    );
    check(
      values[1].collectedAt.isAfter(values[0].collectedAt) &&
          values[2].collectedAt.isAfter(values[1].collectedAt),
      'Each poll has a new completion timestamp.',
    );
    final reads = events.where((e) => e[0] == 'read').length;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    check(
      events.where((e) => e[0] == 'read').length == reads,
      'Cancelling a stream stops its polling.',
    );
    sdk.dispose();
    await disposed.future.timeout(const Duration(seconds: 2));
  } finally {
    sdk.dispose();
    await listener.cancel();
    port.close();
  }
}

DeviceCollector blockedCollector(Object? data) =>
    _BlockedCollector(data as SendPort);

final class _BlockedCollector implements DeviceCollector {
  final SendPort probe;
  _BlockedCollector(this.probe);
  @override
  DeviceSnapshot read(EntityAddress entity, ReadContext context) {
    probe.send(entity.kind.name);
    if (entity.kind == EntityKind.cpu) {
      return CpuSnapshot(availableLogicalProcessorCount: 1);
    }
    // Models an uncooperative synchronous native call in the OS adapter.
    sleep(const Duration(milliseconds: 400));
    return RamSnapshot(physicalBytes: BigInt.from(16384));
  }

  @override
  void dispose() {
    sleep(const Duration(milliseconds: 80));
    probe.send('disposed');
  }
}

Future<Object?> failureOf(Future<Object?> future) async {
  try {
    await future;
    return null;
  } catch (error) {
    return error;
  }
}

Future<void> blockedReadDeadline() async {
  final port = ReceivePort();
  final entered = Completer<void>(), disposed = Completer<void>();
  final events = <String>[];
  final listener = port.listen((Object? raw) {
    final event = raw as String;
    events.add(event);
    if (event == 'ram') entered.complete();
    if (event == 'disposed') disposed.complete();
  });
  final sdk = DeviceAccess.isolated(
    blockedCollector,
    initialData: port.sendPort,
  );
  Timer? heartbeat;
  try {
    await sdk.get(Entities.cpu); // Complete startup before measuring deadlines.
    var ticks = 0;
    heartbeat = Timer.periodic(const Duration(milliseconds: 10), (_) {
      ticks++;
    });
    final pending = failureOf(
      sdk.withReadTimeout(const Duration(milliseconds: 90)).get(Entities.ram),
    );
    await entered.future;
    final queued = failureOf(
      sdk.withReadTimeout(const Duration(milliseconds: 25)).get(Entities.os),
    );
    final queuedError = await queued;
    check(
      queuedError is DeviceReadoutException &&
          queuedError.code == ErrorCode.readTimeout,
      'A queued read has its own deadline.',
    );
    final error = await pending;
    check(
      error is DeviceReadoutException && error.code == ErrorCode.readTimeout,
      'The caller deadline must expire while the native read is blocked.',
    );
    check(
      ticks >= 3 && !disposed.isCompleted,
      'The main event loop must continue during the blocked native read.',
    );
    sdk.dispose();
    check(!disposed.isCompleted, 'Closing access must not join a native call.');
    await disposed.future.timeout(const Duration(seconds: 2));
    check(
      !events.contains('os'),
      'An expired queued read must never enter the OS.',
    );
  } finally {
    heartbeat?.cancel();
    sdk.dispose();
    await listener.cancel();
    port.close();
  }
}

Future<void> cancellationDuringNativeRead() async {
  final port = ReceivePort();
  final entered = Completer<void>(), disposed = Completer<void>();
  final events = <String>[];
  final listener = port.listen((Object? raw) {
    final event = raw as String;
    events.add(event);
    if (event == 'ram') entered.complete();
    if (event == 'disposed') disposed.complete();
  });
  final sdk = DeviceAccess.isolated(
    blockedCollector,
    initialData: port.sendPort,
  );
  try {
    await sdk.get(Entities.cpu);
    final activeToken = CancellationToken(), queuedToken = CancellationToken();
    final active = failureOf(sdk.get(Entities.ram, cancellation: activeToken));
    await entered.future;
    final queued = failureOf(sdk.get(Entities.os, cancellation: queuedToken));
    queuedToken.cancel();
    activeToken.cancel();
    check(
      await queued is DeviceReadoutCancelled &&
          await active is DeviceReadoutCancelled,
      'Both queued and active cancellation must remain cancellation.',
    );
    check(
      !disposed.isCompleted,
      'Cancellation must not wait for native completion.',
    );
    final afterClose = failureOf(sdk.get(Entities.os));
    sdk.withPollInterval(const Duration(seconds: 2)).dispose();
    check(
      await afterClose is DeviceReadoutCancelled &&
          await failureOf(sdk.get(Entities.ram)) is DeviceReadoutCancelled,
      'Closing a configured view closes the common context.',
    );
    await disposed.future.timeout(const Duration(seconds: 2));
    check(!events.contains('os'), 'Cancelled queued reads never enter the OS.');
  } finally {
    sdk.dispose();
    await listener.cancel();
    port.close();
  }
}

DeviceCollector normalizationCollector(Object? _) => _NormalizationCollector();

final class _NormalizationCollector implements DeviceCollector {
  @override
  DeviceSnapshot read(EntityAddress entity, ReadContext context) {
    if (entity.kind == EntityKind.runtime) {
      final original = {Abi.x86_64};
      final snapshot = RuntimeSnapshot(supportedAbis: original);
      original.clear();
      return snapshot;
    }
    return SnapshotCodec.decode(entity.kind, switch (entity.kind) {
      EntityKind.ram => {
        'physicalBytes': '18446744073709551616',
        'availableBytes': '0',
        'freeBytes': '-1',
        'lowMemory': false,
      },
      EntityKind.networkPath => {
        'connectionState': 'FutureState',
        'transports': ['Wifi', 'FutureTransport'],
        'metered': false,
      },
      EntityKind.networkPerformance => {
        'downlinkBps': double.nan,
        'uplinkBps': double.infinity,
        'roundTripTime': -1,
        'effectiveType': 'Future5G',
      },
      EntityKind.originStorage => {
        'quotaBytes': '18446744073709551615',
        'usageBytes': '0',
        'usageByCategory': {'Caches': '0', 'FutureStore': '12'},
      },
      EntityKind.power => {'thermalState': 'AppleThermalState.Serious'},
      _ => <String, Object?>{},
    });
  }

  @override
  void dispose() {}
}

Future<void> normalizedSnapshots() async {
  final sdk = DeviceAccess.isolated(normalizationCollector);
  try {
    final ram = await sdk.get(Entities.ram);
    check(
      ram.physicalBytes == null &&
          ram.freeBytes == null &&
          ram.availableBytes == BigInt.zero &&
          ram.lowMemory == false,
      'Invalid unsigned counters are null; zero and false survive.',
    );
    final network = await sdk.get(Entities.networkPath);
    check(
      network.connectionState == null &&
          network.transports == null &&
          network.metered == false,
      'Unknown enum values invalidate the whole enum collection.',
    );
    final performance = await sdk.get(Entities.networkPerformance);
    check(
      performance.downlinkBps == null &&
          performance.uplinkBps == null &&
          performance.roundTripTime == null &&
          performance.effectiveType == null,
      'Nonfinite values, negative durations and unknown classifications are null.',
    );
    final storage = await sdk.get(Entities.originStorage);
    check(
      storage.quotaBytes.toString() == '18446744073709551615' &&
          storage.usageByCategory == null,
      'Unknown storage keys invalidate the map.',
    );
    final runtime = await sdk.get(Entities.runtime);
    check(
      runtime.supportedAbis?.single == Abi.x86_64,
      'The snapshot detaches collections from the collector.',
    );
    Object? mutationFailure;
    try {
      runtime.supportedAbis!.clear();
    } catch (error) {
      mutationFailure = error;
    }
    check(
      mutationFailure is UnsupportedError,
      'Snapshot collections are immutable.',
    );
    final power = await sdk.get(Entities.power);
    check(
      power.thermalState == AppleThermalState.serious &&
          power.toJson()['thermalState'] == 'AppleThermalState.Serious',
      'Platform thermal states retain their type and wire meaning.',
    );
  } finally {
    sdk.dispose();
  }
}

Future<void> nativeRuntime() async {
  final sdk = DeviceAccess.native();
  try {
    final runtime = await sdk.get(Entities.runtime);
    // This executable is tested using the checksum-verified Windows x64 SDK.
    check(
      runtime.processArchitecture == Architecture.x64 &&
          runtime.processBitness == 64,
      'The Windows x64 process must report X64/64.',
    );
    check(
      runtime.supportedAbis == null,
      'A process ABI cannot establish all supported ABIs.',
    );
    final values = await sdk
        .withPollInterval(const Duration(milliseconds: 20))
        .watch(Entities.runtime)
        .take(2)
        .toList();
    check(
      values.length == 2 && values.every((v) => v.processBitness == 64),
      'Native constant fields still support state polling.',
    );
    final error = await failureOf(sdk.get(Entities.androidBuild));
    check(
      error is DeviceReadoutException &&
          error.code == ErrorCode.unsupportedEntity,
      'Unavailable platform entities must not fabricate values.',
    );
  } finally {
    sdk.dispose();
  }
}

DeviceCollector rateCollector(Object? _) => _RateCollector();

final class _RateCollector implements DeviceCollector {
  @override
  DeviceSnapshot read(EntityAddress entity, ReadContext context) {
    if (context.sensorSamplingRate.hertz != null) {
      throw StateError(
        'One-shot reads must not receive a watch sampling setting.',
      );
    }
    return RamSnapshot();
  }

  @override
  void dispose() {}
}

Future<void> samplingAppliesOnlyToWatch() async {
  final sdk = DeviceAccess.isolated(rateCollector);
  try {
    final configured = sdk.withSensorSamplingRate(
      SensorSamplingRate.atHertz(60),
    );
    await configured.get(Entities.ram);
    check(
      configured.sensorSamplingRate.hertz == 60 &&
          sdk.sensorSamplingRate == SensorSamplingRate.platformDefault,
      'Frequency requests are immutable and remain available for continuous watches.',
    );
  } finally {
    sdk.dispose();
  }
}

DeviceCollector failingCollector(Object? data) =>
    _FailingCollector(data as SendPort);

final class _FailingCollector implements DeviceCollector {
  final SendPort probe;
  int count = 0;
  _FailingCollector(this.probe);
  @override
  DeviceSnapshot read(EntityAddress entity, ReadContext context) {
    probe.send(++count);
    if (count > 1) {
      throw const DeviceReadoutException(
        ErrorCode.permissionDenied,
        'The application permission observer denied access.',
      );
    }
    return RamSnapshot(lowMemory: false);
  }

  @override
  void dispose() {}
}

Future<void> streamFailureIsTerminal() async {
  final port = ReceivePort();
  final calls = <int>[];
  final probe = port.listen((Object? raw) {
    calls.add(raw as int);
  });
  final sdk = DeviceAccess.isolated(
    failingCollector,
    initialData: port.sendPort,
  ).withPollInterval(const Duration(milliseconds: 20));
  final done = Completer<void>();
  final values = <RamSnapshot>[], errors = <Object>[];
  final listener = sdk
      .watch(Entities.ram)
      .listen(
        values.add,
        onError: (Object e) {
          errors.add(e);
        },
        onDone: done.complete,
      );
  try {
    await done.future.timeout(const Duration(seconds: 2));
    await Future<void>.delayed(const Duration(milliseconds: 80));
    check(
      values.length == 1 &&
          errors.length == 1 &&
          errors.single is DeviceReadoutException &&
          (errors.single as DeviceReadoutException).code ==
              ErrorCode.permissionDenied,
      'A whole-read failure is delivered as a typed terminal stream error.',
    );
    check(
      calls.length == 2,
      'The SDK must not silently retry a failed stream.',
    );
  } finally {
    await listener.cancel();
    sdk.dispose();
    await probe.cancel();
    port.close();
  }
}

DeviceCollector failedStartup(Object? _) =>
    throw StateError('Native startup failed');

Future<void> configurationAndStartupErrors() async {
  final sdk = DeviceAccess.isolated(failedStartup);
  try {
    for (final invalid in <void Function()>[
      () {
        sdk.withPollInterval(Duration.zero);
      },
      () {
        sdk.withReadTimeout(const Duration(microseconds: -1));
      },
      () {
        SensorSamplingRate.atHertz(double.nan);
      },
      () {
        SensorSamplingRate.atHertz(double.infinity);
      },
      () {
        SensorSamplingRate.atHertz(0);
      },
    ]) {
      Object? failure;
      try {
        invalid();
      } catch (error) {
        failure = error;
      }
      check(
        failure is DeviceReadoutException &&
            failure.code == ErrorCode.invalidConfiguration,
        'Invalid configuration must fail when the view is constructed.',
      );
    }
    final targetError = await failureOf(sdk.get(Entities.display));
    check(
      targetError is DeviceReadoutException &&
          targetError.code == ErrorCode.invalidConfiguration,
      'A target kind cannot be used as a discovered handle.',
    );
    final startup = await failureOf(sdk.get(Entities.ram));
    check(
      startup is DeviceReadoutException && startup.code == ErrorCode.readFailed,
      'A failed worker factory must reject pending reads instead of hanging.',
    );
    final subsequent = await failureOf(sdk.get(Entities.ram));
    check(
      subsequent is DeviceReadoutException &&
          subsequent.code == ErrorCode.readFailed,
      'A failed worker context must remain failed without restarting implicitly.',
    );
  } finally {
    sdk.dispose();
  }
}

Future<void> main(List<String> arguments) async {
  if (await nativeConnectivityFaultTests.runChildIfRequested(arguments)) return;
  if (await nativeNetworkEventTests.runChildIfRequested(arguments)) return;
  if (await nativeNetworkFaultTests.runChildIfRequested(arguments)) return;
  if (await nativeCpuCoreFaultTests.runChildIfRequested(arguments)) return;
  if (await nativeCpuFaultTests.runChildIfRequested(arguments)) return;
  if (await nativeCpuControlTests.runChildIfRequested(arguments)) return;
  if (await nativeStorageFaultTests.runChildIfRequested(arguments)) return;
  if (await nativeRegistryTests.runChildIfRequested(arguments)) return;
  final tests = <String, Future<void> Function()>{
    ...nativePerformanceTests.checks,
    ...nativeWifiTests.checks,
    ...nativeConnectivityTests.checks,
    ...nativeConnectivityFaultTests.checks,
    ...nativeRegistryTests.checks,
    ...nativeDeviceInfoTests.checks,
    ...nativeOsTests.checks,
    ...nativeTimeZoneTests.checks,
    ...nativeLocaleTests.checks,
    ...nativePowerTests.checks,
    ...nativeStorageTests.checks,
    ...nativeStorageFaultTests.checks,
    ...nativeCpuTests.checks,
    ...nativeCpuControlTests.checks,
    ...nativeCpuFaultTests.checks,
    ...nativeCpuCoreTests.checks,
    ...nativeCpuCoreFaultTests.checks,
    ...nativeNetworkTests.checks,
    ...nativeNetworkFaultTests.checks,
    ...nativeNetworkEventTests.checks,
    ...nativeRuntimeTests.checks,
    ...nativeProcessTests.checks,
    ...nativeWindowsTests.checks,
    ...observerTests.checks,
    ...stateSourceTests.checks,
    ...failureSourceTests.checks,
    ...nativeStateTests.checks,
    ...discoveryTests.checks,
    ...capabilityTests.checks,
    ...sensorMetadataTests.checks,
    ...sensorTests.checks,
    ...rotationTests.checks,
    ...completionTests.checks,
    'typed RAM read is lazy, precise and isolate-owned': isolatedTypedRead,
    'state watch is cold, retains duplicates and captures immutable settings':
        coldStateWatch,
    'blocked native reads preserve host heartbeat, deadlines and deferred cleanup':
        blockedReadDeadline,
    'cancellation and context closure finish without joining native work':
        cancellationDuringNativeRead,
    'snapshots normalize unavailable values and retain exact immutable data':
        normalizedSnapshots,
    'native Windows x64 runtime reports process facts without host guesses':
        nativeRuntime,
    'sampling-rate configuration does not change one-shot reads':
        samplingAppliesOnlyToWatch,
    'stream errors remain typed and terminal without implicit retries':
        streamFailureIsTerminal,
    'invalid configuration and failed worker startup fail predictably':
        configurationAndStartupErrors,
  };
  for (final entry in tests.entries) {
    // Full NDIS inventory verification performs two OS references and a separate
    // default-deadline read for every interface (84 on the current host). This
    // guard bounds the whole verification case, not individual SDK operations.
    final limit = entry.value == nativeNetworkTests.nativeNetworkInterfaces
        ? const Duration(seconds: 45)
        : const Duration(seconds: 12);
    await entry.value().timeout(limit);
    print('PASS ${entry.key}');
  }
  print('${tests.length}/${tests.length} Dart contract checks passed.');
}
