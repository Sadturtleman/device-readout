import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:device_readout_flutter/device_readout_flutter.dart' as readout;

const channel = MethodChannel('device_readout.test/windows_viewport');
const deadline = Duration(seconds: 10);

void require(bool condition, String reason) {
  if (!condition) throw StateError(reason);
}

Future<Map<Object?, Object?>> state([int? width, int? height]) async {
  final value = await channel.invokeMapMethod<Object?, Object?>(
    width == null ? 'state' : 'resize',
    width == null ? null : <String, int>{'width': width, 'height': height!},
  );
  require(
    value != null,
    'The Windows runner must return its own window state.',
  );
  require(
    value!['processId'] == pid,
    'The test must only control its own HWND.',
  );
  require(
    value['visible'] == false,
    'The verification window must stay hidden.',
  );
  return value;
}

bool matches(readout.ViewportSnapshot value, Map<Object?, Object?> native) {
  final scale = (native['dpi']! as int) / 96;
  return value.size?.width == (native['width']! as int) / scale &&
      value.size?.height == (native['height']! as int) / scale;
}

Future<void> removed(Future<Object?> operation) async {
  try {
    await operation;
  } on readout.DeviceReadoutException catch (error) {
    require(
      error.code == readout.ErrorCode.entityRemoved,
      'Expected EntityRemoved.',
    );
    return;
  }
  throw StateError('The removed handle unexpectedly remained readable.');
}

readout.DeviceCollector blockingFactory(Object? data) =>
    BlockingCollector(data! as SendPort);

final class BlockingCollector implements readout.DeviceCollector {
  final SendPort probe;
  BlockingCollector(this.probe);

  @override
  readout.DeviceSnapshot read(
    readout.EntityAddress entity,
    readout.ReadContext context,
  ) {
    if (entity.kind == readout.EntityKind.runtime) {
      return readout.RuntimeSnapshot(processBitness: 64);
    }
    probe.send('entered');
    sleep(const Duration(milliseconds: 500));
    probe.send('returned');
    return readout.RamSnapshot(physicalBytes: BigInt.from(4096));
  }

  @override
  void dispose() => probe.send('disposed');
}

final class MetricsProbe with WidgetsBindingObserver {
  Completer<void>? next;
  int count = 0;
  @override
  void didChangeMetrics() {
    count++;
    next?.complete();
    next = null;
  }
}

Future<void> verify(List<Map<String, Object?>> checks) async {
  final binding = WidgetsBinding.instance;
  final view = ui.PlatformDispatcher.instance.implicitView!;
  final access = readout.DeviceAccess.native().withPollInterval(
    const Duration(minutes: 1),
  );
  var observer = readout.FlutterViewportObserver.attach(access, view: view);
  final displays = readout.FlutterDisplayObserver.attach(access);
  StreamSubscription<readout.ViewportSnapshot>? subscription;
  try {
    final native = await state();
    final first = await access.get(observer.entity);
    require(
      matches(first, native),
      'Initial snapshot must match native client pixels / DPI.',
    );
    require(
      first.visualViewportSize == null && first.visualViewportScale == null,
      'Missing visual viewport fields must remain null.',
    );
    require(
      (await access.viewports.list()).single == observer.entity,
      'The attached view must be discoverable.',
    );
    require(
      await access.viewports.current() == null,
      'Current selection must be explicit.',
    );
    access.observers.current(readout.Entities.viewport, observer.entity);
    require(
      await access.viewports.current() == observer.entity,
      'Current selection was lost.',
    );
    checks.add({
      'name': 'initial native client size and explicit selection',
      'native': native.map((key, value) => MapEntry(key.toString(), value)),
      'logicalWidth': first.size?.width,
      'logicalHeight': first.size?.height,
    });

    // The engine starts Dart before the runner finishes parenting its child
    // view. Establish a fresh native metrics notification after that startup.
    final settled = MetricsProbe()..next = Completer<void>();
    binding.addObserver(settled);
    try {
      final metricsReady = settled.next!.future;
      await state(955, 645);
      await metricsReady.timeout(deadline);
    } finally {
      binding.removeObserver(settled);
    }
    final nativeDisplay = (await channel.invokeMapMethod<String, Object?>(
      'displayState',
    ))!;
    final displayTargets = await access.displays.list();
    require(
      displayTargets.length == nativeDisplay['count'],
      'Flutter display inventory must agree with independent native enumeration.',
    );
    require(
      await access.displays.current() == null,
      'Display selection must be app-owned.',
    );
    displays.selectView(view);
    final displayEntity = (await access.displays.current())!;
    final displayValue = await access.get(displayEntity);
    require(
      displayValue.pixelSize?.width == nativeDisplay['width'] &&
          displayValue.pixelSize?.height == nativeDisplay['height'],
      'Display pixels must agree with the native monitor, not the window. '
      'Native=$nativeDisplay; snapshot=${displayValue.toJson()}; '
      'Flutter=${view.display}; inventory=${ui.PlatformDispatcher.instance.displays}',
    );
    require(
      displayValue.scaleFactor == (nativeDisplay['dpi']! as int) / 96,
      'The selected display scale must agree with the window DPI.',
    );
    require(
      displayValue.currentMode?.refreshRateHz == nativeDisplay['rate'],
      'Windows current mode must agree with EnumDisplaySettings.',
    );
    require(
      displayValue.densityDpi == null &&
          displayValue.maximumRefreshRateHz == null,
      'Display scale and current mode must not fabricate physical DPI or a maximum.',
    );
    final displayEvents = <readout.DisplaySnapshot>[];
    final displayFirst = Completer<void>(), displayNext = Completer<void>();
    final displaySubscription = access.watch(displayEntity).listen((value) {
      displayEvents.add(value);
      if (displayEvents.length == 1) displayFirst.complete();
      if (displayEvents.length == 2) displayNext.complete();
    });
    try {
      await displayFirst.future.timeout(deadline);
      await channel.invokeMethod<void>('notifyDisplays');
      await displayNext.future.timeout(deadline);
      require(
        (await access.displays.list()).length == displayTargets.length &&
            await access.displays.current() == displayEntity,
        'Native re-enumeration must preserve the existing display handles.',
      );
    } finally {
      await displaySubscription.cancel();
    }
    checks.add({
      'name': 'native monitor inventory, current mode and re-enumeration',
      'native': nativeDisplay,
      'snapshots': displayEvents.length,
    });

    final values = <readout.ViewportSnapshot>[];
    final errors = <Object>[];
    final ended = Completer<void>();
    final arrived = StreamController<readout.ViewportSnapshot>.broadcast(
      sync: true,
    );
    subscription = access
        .watch(observer.entity)
        .listen(
          (value) {
            values.add(value);
            arrived.add(value);
          },
          onError: (Object error) {
            errors.add(error);
          },
          onDone: ended.complete,
        );
    Future<readout.ViewportSnapshot> waitFor(
      Map<Object?, Object?> expected,
    ) async {
      if (values.isNotEmpty && matches(values.last, expected))
        return values.last;
      return arrived.stream
          .firstWhere((value) => matches(value, expected))
          .timeout(deadline);
    }

    await waitFor(await state());
    final resized = await state(901, 607);
    await waitFor(resized);
    final resizedAgain = await state(1133, 733);
    await waitFor(resizedAgain);
    require(errors.isEmpty, 'Native window resizing must not fail the stream.');
    checks.add({
      'name': 'actual WM_SIZE reaches watch before the one-minute poll',
      'states': values
          .map(
            (value) => <String, Object?>{
              'width': value.size?.width,
              'height': value.size?.height,
            },
          )
          .toList(),
    });

    final old = observer.entity;
    observer.dispose();
    await ended.future.timeout(deadline);
    require(
      errors.length == 1 &&
          errors.single is readout.DeviceReadoutException &&
          (errors.single as readout.DeviceReadoutException).code ==
              readout.ErrorCode.entityRemoved,
      'Removal must terminate the old stream with EntityRemoved.',
    );
    final count = values.length;
    await state(847, 521);
    await removed(access.get(old));
    require(
      values.length == count,
      'The disposed subscription received a later resize.',
    );
    require(
      (await access.viewports.list()).isEmpty &&
          await access.viewports.current() == null,
      'Removal must clear discovery and current selection.',
    );
    observer = readout.FlutterViewportObserver.attach(access, view: view);
    require(
      observer.entity != old,
      'Reattachment must create a fresh SDK target.',
    );
    require(
      matches(await access.get(observer.entity), await state()),
      'Reattached size is stale.',
    );
    await removed(access.get(old));
    await arrived.close();
    checks.add({
      'name':
          'detach retires old handle and reattach captures fresh native size',
    });
  } finally {
    displays.dispose();
    observer.dispose();
    await subscription?.cancel();
    access.dispose();
  }

  final probe = ReceivePort();
  final entered = Completer<void>(),
      returned = Completer<void>(),
      disposed = Completer<void>();
  final messages = probe.listen((Object? event) {
    if (event == 'entered') entered.complete();
    if (event == 'returned') returned.complete();
    if (event == 'disposed') disposed.complete();
  });
  final isolated = readout.DeviceAccess.isolated(
    blockingFactory,
    initialData: probe.sendPort,
  );
  final watched = readout.FlutterViewportObserver.attach(isolated, view: view);
  final metrics = MetricsProbe();
  binding.addObserver(metrics);
  var ticks = 0;
  Timer? heartbeat;
  try {
    await isolated.get(readout.Entities.runtime);
    heartbeat = Timer.periodic(const Duration(milliseconds: 10), (_) {
      ticks++;
    });
    final pending = isolated
        .withReadTimeout(const Duration(milliseconds: 200))
        .get(readout.Entities.ram)
        .then<Object?>((value) => value, onError: (Object error) => error);
    await entered.future.timeout(deadline);
    final next = Completer<void>();
    metrics.next = next;
    final resized = await state(971, 619);
    await next.future.timeout(deadline);
    require(
      !returned.isCompleted,
      'Native window callback must run during blocked collection.',
    );
    final result = await pending;
    require(
      result is readout.DeviceReadoutException &&
          result.code == readout.ErrorCode.readTimeout,
      'The blocked collector must respect the independent host deadline.',
    );
    require(
      ticks >= 3 && !returned.isCompleted,
      'Flutter host heartbeat and deadline must precede the native return.',
    );
    await returned.future.timeout(deadline);
    require(
      matches(await isolated.get(watched.entity), resized),
      'The worker must receive the latest observed native size after unblocking.',
    );
    watched.dispose();
    isolated.dispose();
    await disposed.future.timeout(deadline);
    checks.add({
      'name': 'native resize and host deadline during blocked helper isolate',
      'heartbeatTicks': ticks,
      'nativeMetricsCallbacks': metrics.count,
    });
  } finally {
    heartbeat?.cancel();
    binding.removeObserver(metrics);
    watched.dispose();
    isolated.dispose();
    await messages.cancel();
    probe.close();
  }
}

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SizedBox.expand());
  final checks = <Map<String, Object?>>[];
  final report = <String, Object?>{'passed': false, 'checks': checks};
  try {
    require(arguments.length == 1, 'Pass the test-owned report path.');
    await verify(checks).timeout(const Duration(seconds: 40));
    report['passed'] = true;
  } catch (error, stack) {
    report['error'] = '$error';
    report['stack'] = '$stack';
  } finally {
    if (arguments.length == 1) {
      await File(arguments.single).writeAsString(
        const JsonEncoder.withIndent('  ').convert(report),
        flush: true,
      );
    }
    await channel.invokeMethod<void>('finish');
  }
}
