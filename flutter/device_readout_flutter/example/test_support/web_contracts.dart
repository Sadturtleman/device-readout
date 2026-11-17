import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:device_readout_flutter/device_readout_flutter.dart' as readout;

void main() => runApp(const MaterialApp(home: BrowserContracts()));

class BrowserContracts extends StatefulWidget {
  const BrowserContracts({super.key});
  @override
  State<BrowserContracts> createState() => _BrowserContractsState();
}

class _BrowserContractsState extends State<BrowserContracts>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final access = readout.FlutterWebDeviceAccess.create();
  late final readout.FlutterDisplayObserver displays;
  late final readout.FlutterSensorActivityObserver activity;
  readout.FlutterViewportObserver? viewport;
  ui.FlutterView? view;
  StreamSubscription<readout.ViewportSnapshot>? viewportWatch;
  final viewportValues = <Map<String, Object?>>[];
  final streamErrors = <String>[];
  final lifecycleEvents = <String>[];
  readout.Entity<readout.RelativeOrientationSnapshot>? sensor;
  StreamSubscription<readout.RelativeOrientationSnapshot>? sensorWatch;
  void Function()? removeSensor;
  int sensorStarts = 0, sensorStops = 0, samples = 0;
  readout.RelativeOrientationSnapshot? lastSample;
  final sensorErrors = <String>[];
  late final Ticker ticker;
  int frames = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    displays = readout.FlutterDisplayObserver.attach(access);
    activity = readout.FlutterSensorActivityObserver.attach(access);
    ticker = createTicker((_) {
      setState(() {
        frames++;
      });
    })..start();
    globalContext.setProperty(
      'flutterReadoutCommand'.toJS,
      ((JSString command) => _command(
        command.toDart,
      ).then((result) => result.jsify()).toJS).toJS,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      globalContext.setProperty('flutterReadoutReady'.toJS, true.toJS);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = View.of(context);
    if (identical(next, view)) return;
    viewport?.dispose();
    view = next;
    viewport = readout.FlutterViewportObserver.attach(access, view: next);
    displays.selectView(next);
    access.observers.current(readout.Entities.viewport, viewport!.entity);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    lifecycleEvents.add(state.name);
  }

  Future<Map<String, Object?>> _command(String name) async {
    switch (name) {
      case 'startSensor':
        sensor = access.observers.target(
          readout.Entities.relativeOrientation,
          'app-rotation',
        );
        removeSensor = access.observers.sensorSource(
          sensor!,
          readout.SensorObserverSource(
            description: readout.SensorDescription(
              name: 'Controlled browser rotation',
            ),
            subscribe: (session) {
              sensorStarts++;
              final timer = Timer.periodic(const Duration(milliseconds: 20), (
                _,
              ) {
                session.publish(
                  readout.RelativeOrientationSnapshot(
                    value: const readout.Quaternion(0, 0, 3, 4),
                  ),
                );
              });
              return () {
                sensorStops++;
                timer.cancel();
              };
            },
          ),
        );
        final description = await access.describe(sensor!);
        final before = sensorStarts;
        sensorWatch = access
            .watch(sensor!)
            .listen(
              (value) {
                samples++;
                lastSample = value;
              },
              onError: (Object error) {
                sensorErrors.add(
                  error is readout.DeviceReadoutException
                      ? error.code.name
                      : '$error',
                );
              },
            );
        await _until(() => samples >= 2);
        return {
          ..._state(),
          'metadataStartedSources': before,
          'description': description.toJson(),
        };
      case 'inactiveRead':
        return {
          'error': await _failure(
            access
                .withReadTimeout(const Duration(milliseconds: 80))
                .get(sensor!),
          ),
          ..._state(),
        };
      case 'permission':
        var requested = 0;
        final failure = access.observers.failureSource(sensor!);
        final detach = access.observers.onPermissionRequest((request) async {
          requested++;
          await Future<void>.delayed(const Duration(milliseconds: 150));
          failure.publish(null);
          access.observers.permission(
            sensor!,
            readout.PermissionStatus.granted,
          );
        });
        try {
          access.observers.permission(sensor!, readout.PermissionStatus.denied);
          failure.publish(
            const readout.DeviceReadoutException(
              readout.ErrorCode.permissionDenied,
              'App source permission was revoked.',
            ),
          );
          final denied = await _failure(access.get(sensor!));
          final status = await access.permissions.check(sensor!);
          final implicitRequests = requested;
          final elapsed = Stopwatch()..start();
          final granted = await access
              .withReadTimeout(const Duration(milliseconds: 30))
              .permissions
              .request(sensor!);
          final waited = elapsed.elapsedMilliseconds;
          final fresh = await access.get(sensor!);
          return {
            'denied': denied,
            'status': status?.name,
            'implicitRequests': implicitRequests,
            'granted': granted?.name,
            'requested': requested,
            'waitedMs': waited,
            'fresh': fresh.toJson(),
            ..._state(),
          };
        } finally {
          detach();
          failure.dispose();
        }
      case 'heldWorker':
        final held = readout.FlutterWebDeviceAccess.create(
          workerUri: Uri.base.resolve('/held-worker.js'),
        );
        Timer? heartbeat;
        try {
          await held.get(readout.Entities.cpu);
          final startFrames = frames;
          var ticks = 0;
          heartbeat = Timer.periodic(const Duration(milliseconds: 10), (_) {
            ticks++;
          });
          final elapsed = Stopwatch()..start();
          final error = await _failure(
            held
                .withReadTimeout(const Duration(milliseconds: 160))
                .get(readout.Entities.ram),
          );
          return {
            'error': error,
            'frames': frames - startFrames,
            'ticks': ticks,
            'elapsedMs': elapsed.elapsedMilliseconds,
          };
        } finally {
          heartbeat?.cancel();
          held.dispose();
        }
      case 'snapshot':
        final cpu = await access.get(readout.Entities.cpu);
        final locale = await access.get(readout.Entities.locale);
        final screenTargets = await access.displays.list();
        final current = await access.displays.current();
        final screen = current == null ? null : await access.get(current);
        final support = await access.capabilities.get(readout.Entities.cpu);
        return {
          'cpu': cpu.toJson(),
          'locale': locale.toJson(),
          'viewport': (await access.get(viewport!.entity)).toJson(),
          'display': screen?.toJson(),
          'displayCount': screenTargets.length,
          'currentIsListed': screenTargets.contains(current),
          'viewportIsCurrent':
              await access.viewports.current() == viewport!.entity,
          'readable': support.readable,
          'watchable': support.watchable,
        };
      case 'watchViewport':
        final first = Completer<void>();
        viewportWatch = access
            .watch(viewport!.entity)
            .listen(
              (value) {
                viewportValues.add(value.toJson());
                if (!first.isCompleted) first.complete();
              },
              onError: (Object error) {
                streamErrors.add('$error');
                if (!first.isCompleted) first.completeError(error);
              },
            );
        await first.future;
        return _state();
      case 'stopViewport':
        await viewportWatch?.cancel();
        viewportWatch = null;
        return _state();
      case 'retireViewport':
        final old = viewport!.entity;
        viewport!.dispose();
        final failure = await _failure(access.get(old));
        viewport = readout.FlutterViewportObserver.attach(access, view: view!);
        access.observers.current(readout.Entities.viewport, viewport!.entity);
        return {
          'oldError': failure,
          'freshHandle': old != viewport!.entity,
          'count': (await access.viewports.list()).length,
          'fresh': (await access.get(viewport!.entity)).toJson(),
        };
      case 'unmount':
        runApp(const MaterialApp(home: Text('Readout disposed')));
        await WidgetsBinding.instance.endOfFrame;
        return {
          'closedError': await _failure(access.get(readout.Entities.cpu)),
        };
      case 'state':
        return _state();
      default:
        throw StateError('Unknown test command: $name');
    }
  }

  Map<String, Object?> _state() => {
    'frames': frames,
    'lifecycle': WidgetsBinding.instance.lifecycleState?.name,
    'lifecycleEvents': lifecycleEvents,
    'viewportValues': viewportValues,
    'errors': streamErrors,
    'sensorStarts': sensorStarts,
    'sensorStops': sensorStops,
    'samples': samples,
    'sensorErrors': sensorErrors,
    'lastSample': lastSample?.toJson(),
  };

  @override
  void dispose() {
    unawaited(viewportWatch?.cancel());
    unawaited(sensorWatch?.cancel());
    removeSensor?.call();
    viewport?.dispose();
    displays.dispose();
    activity.dispose();
    access.dispose();
    WidgetsBinding.instance.removeObserver(this);
    ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('DeviceReadout browser contracts')),
    body: Center(child: Text('Rendered frames: $frames')),
  );
}

Future<void> _until(bool Function() ready) async {
  final elapsed = Stopwatch()..start();
  while (!ready()) {
    if (elapsed.elapsed > const Duration(seconds: 5))
      throw StateError(
        'The Flutter consumer did not reach its expected state.',
      );
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Future<String> _failure(Future<Object?> operation) async {
  try {
    await operation;
    return 'unexpected-success';
  } on readout.DeviceReadoutException catch (error) {
    return error.code.name;
  } on readout.DeviceReadoutCancelled {
    return 'cancelled';
  }
}
