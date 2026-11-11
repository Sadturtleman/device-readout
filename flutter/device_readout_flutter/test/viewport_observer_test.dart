import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart' as widgets;
import 'package:flutter_test/flutter_test.dart';
import 'package:device_readout_flutter/device_readout_flutter.dart' as readout;

readout.DeviceCollector forbiddenFactory(Object? _) => throw StateError(
  'Flutter observer reads must never initialize a native collector.',
);

final class CountingView extends Fake implements ui.FlutterView {
  final ui.FlutterView source;
  int reads = 0;
  bool fail = false;
  double? ratioOverride;
  ui.PlatformDispatcher? dispatcherOverride;
  CountingView(this.source);
  @override
  int get viewId => source.viewId;
  @override
  ui.PlatformDispatcher get platformDispatcher =>
      dispatcherOverride ?? source.platformDispatcher;
  @override
  double get devicePixelRatio {
    reads++;
    return ratioOverride ?? source.devicePixelRatio;
  }

  @override
  ui.Size get physicalSize {
    reads++;
    if (fail) throw StateError('The platform view is temporarily unavailable.');
    return source.physicalSize;
  }

  @override
  ui.ViewPadding get viewPadding {
    reads++;
    return source.viewPadding;
  }
}

// A getter probe is registered as the canonical view at this explicit platform
// boundary. Real Flutter notifications still use the original WidgetsBinding.
final class CountingDispatcher extends Fake implements ui.PlatformDispatcher {
  final CountingView probe;
  CountingDispatcher(this.probe);
  @override
  ui.FlutterView? view({required int id}) =>
      id == probe.viewId &&
          identical(probe.source.platformDispatcher.view(id: id), probe.source)
      ? probe
      : null;
  @override
  double get textScaleFactor => probe.source.platformDispatcher.textScaleFactor;
}

final class CountingBinding extends Fake implements widgets.WidgetsBinding {
  final widgets.WidgetsBinding source;
  @override
  final CountingDispatcher platformDispatcher;
  CountingBinding(this.source, CountingView probe)
    : platformDispatcher = CountingDispatcher(probe) {
    probe.dispatcherOverride = platformDispatcher;
  }
  @override
  void addObserver(widgets.WidgetsBindingObserver observer) =>
      source.addObserver(observer);
  @override
  bool removeObserver(widgets.WidgetsBindingObserver observer) =>
      source.removeObserver(observer);
}

final class RegistryDispatcher extends Fake implements ui.PlatformDispatcher {
  final registry = <int, ui.FlutterView>{};
  @override
  ui.FlutterView? view({required int id}) => registry[id];
  @override
  double get textScaleFactor => 1;
}

final class RegistryView extends Fake implements ui.FlutterView {
  @override
  final int viewId;
  @override
  final ui.PlatformDispatcher platformDispatcher;
  RegistryView(this.viewId, this.platformDispatcher);
  @override
  double get devicePixelRatio => 2;
  @override
  ui.Size get physicalSize => const ui.Size(1200, 800);
  @override
  ui.ViewPadding get viewPadding => FakeViewPadding.zero;
}

final class RegistryBinding extends Fake implements widgets.WidgetsBinding {
  @override
  final RegistryDispatcher platformDispatcher = RegistryDispatcher();
  final observers = <widgets.WidgetsBindingObserver>{};
  @override
  void addObserver(widgets.WidgetsBindingObserver observer) {
    observers.add(observer);
  }

  @override
  bool removeObserver(widgets.WidgetsBindingObserver observer) =>
      observers.remove(observer);
  void metrics() {
    for (final observer in observers.toList()) {
      observer.didChangeMetrics();
    }
  }
}

readout.DeviceCollector blockingFactory(Object? data) =>
    BlockingCollector(data as SendPort);

final class BlockingCollector implements readout.DeviceCollector {
  final SendPort probe;
  BlockingCollector(this.probe);
  @override
  readout.DeviceSnapshot read(
    readout.EntityAddress entity,
    readout.ReadContext context,
  ) {
    if (entity.kind == readout.EntityKind.runtime)
      return readout.RuntimeSnapshot(processBitness: 64);
    if (entity.kind != readout.EntityKind.ram)
      throw StateError('Unexpected native UI read.');
    probe.send('entered');
    sleep(const Duration(milliseconds: 350));
    probe.send('returned');
    return readout.RamSnapshot(physicalBytes: BigInt.from(16384));
  }

  @override
  void dispose() {
    probe.send('disposed');
  }
}

void main() {
  testWidgets(
    'removing a failed viewport contains late framework recovery callbacks',
    (tester) async {
      await tester.runAsync(() async {
        final access = readout.DeviceAccess.isolated(forbiddenFactory);
        final view = CountingView(tester.view)..fail = true;
        final observer = readout.FlutterViewportObserver.attach(
          access,
          view: view,
          binding: CountingBinding(tester.binding, view),
        );
        try {
          access.observers.remove(observer.entity);
          view.fail = false;
          tester.binding.handleMetricsChanged();
          expect(tester.takeException(), isNull);
          final reads = view.reads;
          tester.binding.handleMetricsChanged();
          expect(view.reads, reads);
          await expectLater(
            access.get(observer.entity),
            throwsA(
              isA<readout.DeviceReadoutException>().having(
                (error) => error.code,
                'code',
                readout.ErrorCode.entityRemoved,
              ),
            ),
          );
        } finally {
          observer.dispose();
          access.dispose();
        }
      });
    },
  );

  testWidgets(
    'viewport observer recovery cannot clear an application-owned target failure',
    (tester) async {
      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = const ui.Size(1200, 800);
      addTearDown(tester.view.reset);
      await tester.runAsync(() async {
        final access = readout.DeviceAccess.isolated(forbiddenFactory);
        final view = CountingView(tester.view);
        final binding = CountingBinding(tester.binding, view);
        final observer = readout.FlutterViewportObserver.attach(
          access,
          view: view,
          binding: binding,
        );
        const denied = readout.DeviceReadoutException(
          readout.ErrorCode.permissionDenied,
          'The application has disabled this viewport.',
        );
        try {
          access.observers.failure(observer.entity, denied);
          view.fail = true;
          tester.binding.handleMetricsChanged();
          await expectLater(access.get(observer.entity), throwsA(same(denied)));
          view.fail = false;
          tester.view.physicalSize = const ui.Size(1600, 900);
          await expectLater(access.get(observer.entity), throwsA(same(denied)));
          access.observers.failure(observer.entity, null);
          expect((await access.get(observer.entity)).size?.width, 800);
        } finally {
          observer.dispose();
          access.dispose();
        }
      });
    },
  );

  testWidgets(
    'explicit Flutter viewport attachment supplies logical size and safe areas',
    (tester) async {
      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = const ui.Size(1200, 800);
      tester.view.viewPadding = const FakeViewPadding(
        top: 48,
        left: 20,
        right: 12,
        bottom: 32,
      );
      tester.platformDispatcher.textScaleFactorTestValue = 1.25;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.runAsync(() async {
        final access = readout.DeviceAccess.isolated(forbiddenFactory);
        readout.FlutterViewportObserver? observer;
        try {
          observer = readout.FlutterViewportObserver.attach(
            access,
            view: tester.view,
            binding: tester.binding,
          );
          final snapshot = await access.get(observer.entity);
          expect(snapshot.size?.width, 600);
          expect(snapshot.size?.height, 400);
          expect(snapshot.safeAreaInsets?.top, 24);
          expect(snapshot.safeAreaInsets?.left, 10);
          expect(snapshot.safeAreaInsets?.right, 6);
          expect(snapshot.safeAreaInsets?.bottom, 16);
          expect(snapshot.textScaleFactor, 1.25);
          expect(snapshot.visualViewportSize, isNull);
          expect(snapshot.visualViewportScale, isNull);
          expect((await access.viewports.list()).single, observer.entity);
          expect(await access.viewports.current(), isNull);
        } finally {
          observer?.dispose();
          access.dispose();
        }
      });
    },
  );

  testWidgets(
    'Flutter callbacks preserve changes while SDK reads never query the view',
    (tester) async {
      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = const ui.Size(1200, 800);
      tester.platformDispatcher.textScaleFactorTestValue = 1;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.runAsync(() async {
        final access = readout.DeviceAccess.isolated(forbiddenFactory)
            .withPollInterval(const Duration(seconds: 60));
        final view = CountingView(tester.view);
        final observer = readout.FlutterViewportObserver.attach(
          access,
          view: view,
          binding: CountingBinding(tester.binding, view),
        );
        final values = <readout.ViewportSnapshot>[], errors = <Object>[];
        final first = Completer<void>(),
            updates = Completer<void>(),
            ended = Completer<void>();
        final subscription = access
            .watch(observer.entity)
            .listen(
              (value) {
                values.add(value);
                if (values.length == 1) first.complete();
                if (values.length == 4) updates.complete();
              },
              onError: (Object error) {
                errors.add(error);
              },
              onDone: ended.complete,
            );
        try {
          await first.future.timeout(const Duration(seconds: 2));
          final initialReads = view.reads;
          await access.get(observer.entity);
          await access.viewports.list();
          expect(view.reads, initialReads);
          tester.view.physicalSize = const ui.Size(1600, 900);
          tester.view.physicalSize = const ui.Size(1600, 900);
          tester.platformDispatcher.textScaleFactorTestValue = 1.4;
          await updates.future.timeout(const Duration(seconds: 2));
          expect(values.map((s) => s.size?.width), [600, 800, 800, 800]);
          expect(values.map((s) => s.textScaleFactor), [1, 1, 1, 1.4]);
          expect(view.reads, initialReads + 9);
          final afterNotifications = view.reads;
          await access.get(observer.entity);
          expect(view.reads, afterNotifications);
          observer.dispose();
          await ended.future.timeout(const Duration(seconds: 2));
          expect(
            errors.single,
            isA<readout.DeviceReadoutException>().having(
              (e) => e.code,
              'code',
              readout.ErrorCode.entityRemoved,
            ),
          );
          tester.view.physicalSize = const ui.Size(1800, 1000);
          expect(view.reads, afterNotifications);
          expect(await access.viewports.list(), isEmpty);
        } finally {
          observer.dispose();
          await subscription.cancel();
          access.dispose();
        }
      });
    },
  );

  testWidgets(
    'viewport source failures stay typed and recover only from fresh Flutter state',
    (tester) async {
      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = const ui.Size(1200, 800);
      addTearDown(tester.view.reset);
      await tester.runAsync(() async {
        final access = readout.DeviceAccess.isolated(forbiddenFactory);
        final view = CountingView(tester.view)..fail = true;
        final observer = readout.FlutterViewportObserver.attach(
          access,
          view: view,
          binding: CountingBinding(tester.binding, view),
        );
        StreamSubscription<readout.ViewportSnapshot>? subscription;
        try {
          await expectLater(
            access.get(observer.entity),
            throwsA(
              isA<readout.DeviceReadoutException>().having(
                (e) => e.code,
                'code',
                readout.ErrorCode.readFailed,
              ),
            ),
          );
          view.fail = false;
          tester.binding.handleMetricsChanged();
          expect((await access.get(observer.entity)).size?.width, 600);
          final first = Completer<void>(), ended = Completer<void>();
          final values = <readout.ViewportSnapshot>[], errors = <Object>[];
          subscription = access
              .watch(observer.entity)
              .listen(
                (value) {
                  values.add(value);
                  if (!first.isCompleted) first.complete();
                },
                onError: (Object error) {
                  errors.add(error);
                },
                onDone: ended.complete,
              );
          await first.future.timeout(const Duration(seconds: 2));
          view.fail = true;
          tester.binding.handleMetricsChanged();
          await ended.future.timeout(const Duration(seconds: 2));
          expect(
            errors.single,
            isA<readout.DeviceReadoutException>().having(
              (e) => e.code,
              'code',
              readout.ErrorCode.readFailed,
            ),
          );
          view.fail = false;
          tester.view.physicalSize = const ui.Size(1600, 900);
          expect((await access.get(observer.entity)).size?.width, 800);
          expect(values, hasLength(1));
          expect(tester.takeException(), isNull);
        } finally {
          observer.dispose();
          await subscription?.cancel();
          access.dispose();
        }
      });
    },
  );

  testWidgets('view removal and ID reuse retire old viewport handles', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final access = readout.DeviceAccess.isolated(forbiddenFactory);
      final binding = RegistryBinding(),
          dispatcher = binding.platformDispatcher;
      final first = RegistryView(42, dispatcher),
          second = RegistryView(43, dispatcher);
      dispatcher.registry[42] = first;
      dispatcher.registry[43] = second;
      final firstProbe = CountingView(first),
          secondProbe = CountingView(second);
      dispatcher.registry[42] = firstProbe;
      dispatcher.registry[43] = secondProbe;
      final one = readout.FlutterViewportObserver.attach(
        access,
        view: firstProbe,
        binding: binding,
      );
      final two = readout.FlutterViewportObserver.attach(
        access,
        view: secondProbe,
        binding: binding,
      );
      readout.FlutterViewportObserver? replacement;
      try {
        expect(await access.viewports.list(), hasLength(2));
        access.observers.current(readout.Entities.viewport, one.entity);
        expect((await access.get(one.entity)).size?.width, 600);
        final reads = firstProbe.reads;
        dispatcher.registry.remove(42);
        binding.metrics();
        await expectLater(
          access.get(one.entity),
          throwsA(
            isA<readout.DeviceReadoutException>().having(
              (e) => e.code,
              'code',
              readout.ErrorCode.entityRemoved,
            ),
          ),
        );
        expect(firstProbe.reads, reads);
        expect(await access.viewports.current(), isNull);
        final newer = RegistryView(43, dispatcher);
        dispatcher.registry[43] = newer;
        binding.metrics();
        expect(
          () => readout.FlutterViewportObserver.attach(
            access,
            view: secondProbe,
            binding: binding,
          ),
          throwsA(
            isA<readout.DeviceReadoutException>().having(
              (error) => error.code,
              'code',
              readout.ErrorCode.entityRemoved,
            ),
          ),
        );
        await expectLater(
          access.get(two.entity),
          throwsA(
            isA<readout.DeviceReadoutException>().having(
              (e) => e.code,
              'code',
              readout.ErrorCode.entityRemoved,
            ),
          ),
        );
        replacement = readout.FlutterViewportObserver.attach(
          access,
          view: newer,
          binding: binding,
        );
        expect(replacement.entity, isNot(two.entity));
        expect((await access.viewports.list()).single, replacement.entity);
      } finally {
        one.dispose();
        two.dispose();
        replacement?.dispose();
        access.dispose();
      }
      expect(binding.observers, isEmpty);
    });
  });

  testWidgets(
    'invalid density does not fabricate dimensions and foreign bindings are rejected',
    (tester) async {
      await tester.runAsync(() async {
        final access = readout.DeviceAccess.isolated(forbiddenFactory);
        final view = CountingView(tester.view)..ratioOverride = 0;
        final observer = readout.FlutterViewportObserver.attach(
          access,
          view: view,
          binding: CountingBinding(tester.binding, view),
        );
        try {
          final snapshot = await access.get(observer.entity);
          expect(snapshot.size, isNull);
          expect(snapshot.safeAreaInsets, isNull);
          expect(
            snapshot.textScaleFactor,
            tester.platformDispatcher.textScaleFactor,
          );
          final foreign = RegistryBinding();
          expect(
            () => readout.FlutterViewportObserver.attach(
              access,
              view: tester.view,
              binding: foreign,
            ),
            throwsA(
              isA<readout.DeviceReadoutException>().having(
                (e) => e.code,
                'code',
                readout.ErrorCode.invalidConfiguration,
              ),
            ),
          );
          final missing = RegistryView(88, foreign.platformDispatcher);
          expect(
            () => readout.FlutterViewportObserver.attach(
              access,
              view: missing,
              binding: foreign,
            ),
            throwsA(
              isA<readout.DeviceReadoutException>().having(
                (e) => e.code,
                'code',
                readout.ErrorCode.entityRemoved,
              ),
            ),
          );
          expect(foreign.observers, isEmpty);
          expect(await access.viewports.list(), hasLength(1));
          access.dispose();
          tester.binding.handleMetricsChanged();
          final stopped = view.reads;
          tester.binding.handleMetricsChanged();
          expect(view.reads, stopped);
          expect(tester.takeException(), isNull);
        } finally {
          observer.dispose();
          access.dispose();
        }
      });
    },
  );

  testWidgets(
    'blocked native collection preserves Flutter callbacks and host deadlines',
    (tester) async {
      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = const ui.Size(1200, 800);
      addTearDown(tester.view.reset);
      await tester.runAsync(() async {
        final probe = ReceivePort();
        final entered = Completer<void>(),
            returned = Completer<void>(),
            disposed = Completer<void>();
        final probeSubscription = probe.listen((Object? event) {
          if (event == 'entered') entered.complete();
          if (event == 'returned') returned.complete();
          if (event == 'disposed') disposed.complete();
        });
        final access = readout.DeviceAccess.isolated(
          blockingFactory,
          initialData: probe.sendPort,
        );
        final view = CountingView(tester.view);
        final observer = readout.FlutterViewportObserver.attach(
          access,
          view: view,
          binding: CountingBinding(tester.binding, view),
        );
        Timer? heartbeat;
        try {
          await access.get(readout.Entities.runtime);
          var ticks = 0;
          heartbeat = Timer.periodic(const Duration(milliseconds: 10), (_) {
            ticks++;
          });
          final pending = access
              .withReadTimeout(const Duration(milliseconds: 100))
              .get(readout.Entities.ram);
          final timedOut = expectLater(
            pending,
            throwsA(
              isA<readout.DeviceReadoutException>().having(
                (e) => e.code,
                'code',
                readout.ErrorCode.readTimeout,
              ),
            ),
          );
          await entered.future.timeout(const Duration(seconds: 2));
          final before = view.reads;
          tester.view.physicalSize = const ui.Size(1600, 900);
          expect(view.reads, before + 3);
          await expectLater(
            access
                .withReadTimeout(const Duration(milliseconds: 35))
                .get(observer.entity),
            throwsA(
              isA<readout.DeviceReadoutException>().having(
                (e) => e.code,
                'code',
                readout.ErrorCode.readTimeout,
              ),
            ),
          );
          await timedOut;
          expect(ticks, greaterThanOrEqualTo(3));
          expect(returned.isCompleted, isFalse);
          await returned.future.timeout(const Duration(seconds: 2));
          expect((await access.get(observer.entity)).size?.width, 800);
          observer.dispose();
          access.dispose();
          await disposed.future.timeout(const Duration(seconds: 2));
        } finally {
          heartbeat?.cancel();
          observer.dispose();
          access.dispose();
          await probeSubscription.cancel();
          probe.close();
        }
      });
    },
  );
}
