import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' as widgets;
import 'package:flutter_test/flutter_test.dart';
import 'package:device_readout_flutter/device_readout_flutter.dart' as readout;

readout.DeviceCollector forbiddenFactory(Object? _) =>
    throw StateError('No native UI reads.');

final class FixtureDisplay extends Fake implements ui.Display {
  @override
  final int id;
  int reads = 0;
  bool failSize = false;
  ui.Size pixels = const ui.Size(1920, 1080);
  double ratio = 1.5, rate = 120;
  FixtureDisplay(this.id);
  @override
  ui.Size get size {
    reads++;
    if (failSize) throw StateError('Pixel size unavailable.');
    return pixels;
  }

  @override
  double get devicePixelRatio {
    reads++;
    return ratio;
  }

  @override
  double get refreshRate {
    reads++;
    return rate;
  }
}

final class FixtureDispatcher extends Fake implements ui.PlatformDispatcher {
  List<ui.Display> inventory = [];
  final viewsById = <int, ui.FlutterView>{};
  int reads = 0;
  bool failInventory = false;
  @override
  Iterable<ui.Display> get displays {
    reads++;
    if (failInventory) throw StateError('Display inventory unavailable.');
    return inventory;
  }

  @override
  ui.FlutterView? view({required int id}) => viewsById[id];
}

final class FixtureView extends Fake implements ui.FlutterView {
  @override
  final int viewId;
  @override
  final FixtureDispatcher platformDispatcher;
  @override
  ui.Display display;
  FixtureView(this.viewId, this.platformDispatcher, this.display);
}

final class FixtureBinding extends Fake implements widgets.WidgetsBinding {
  @override
  final FixtureDispatcher platformDispatcher = FixtureDispatcher();
  final observers = <widgets.WidgetsBindingObserver>{};
  @override
  void addObserver(widgets.WidgetsBindingObserver observer) =>
      observers.add(observer);
  @override
  bool removeObserver(widgets.WidgetsBindingObserver observer) =>
      observers.remove(observer);
  void metrics() {
    for (final observer in observers.toList()) {
      observer.didChangeMetrics();
    }
  }
}

Matcher code(readout.ErrorCode value) => isA<readout.DeviceReadoutException>()
    .having((error) => error.code, 'code', value);

void main() {
  testWidgets(
    'display observer failure and recovery preserve the app-owned gate',
    (tester) async {
      await tester.runAsync(() async {
        final access = readout.DeviceAccess.isolated(forbiddenFactory);
        final binding = FixtureBinding();
        final dispatcher = binding.platformDispatcher;
        dispatcher.inventory = [FixtureDisplay(1)];
        final observer = readout.FlutterDisplayObserver.attach(
          access,
          binding: binding,
        );
        const denied = readout.DeviceReadoutException(
          readout.ErrorCode.permissionDenied,
          'The application has disabled display access.',
        );
        try {
          final target = (await access.displays.list()).single;
          access.observers.failure(readout.Entities.display, denied);
          dispatcher.failInventory = true;
          binding.metrics();
          await expectLater(access.displays.list(), throwsA(same(denied)));
          dispatcher.failInventory = false;
          binding.metrics();
          await expectLater(access.get(target), throwsA(same(denied)));
          access.observers.failure(readout.Entities.display, null);
          expect((await access.get(target)).pixelSize?.width, 1920);

          dispatcher.failInventory = true;
          binding.metrics();
          access.observers.failure(readout.Entities.display, denied);
          observer.dispose();
          await expectLater(access.displays.list(), throwsA(same(denied)));
          access.observers.failure(readout.Entities.display, null);
          expect(await access.displays.list(), isEmpty);
          expect(binding.observers, isEmpty);
        } finally {
          observer.dispose();
          access.dispose();
        }
      });
    },
  );

  testWidgets(
    'Flutter display state maps independent fields and follows explicit view selection',
    (tester) async {
      tester.view.display.size = const ui.Size(2560, 1440);
      tester.view.display.devicePixelRatio = 1.5;
      addTearDown(tester.view.display.reset);
      await tester.runAsync(() async {
        final access = readout.DeviceAccess.isolated(forbiddenFactory);
        final observer = readout.FlutterDisplayObserver.attach(
          access,
          binding: tester.binding,
        );
        try {
          final entity = (await access.displays.list()).single;
          final value = await access.get(entity);
          expect(value.pixelSize?.width, 2560);
          expect(value.pixelSize?.height, 1440);
          expect(value.scaleFactor, 1.5);
          expect(value.densityDpi, isNull);
          expect(value.logicalBounds, isNull);
          expect(value.maximumRefreshRateHz, isNull);
          expect(value.primary, isNull);
          expect(await access.displays.current(), isNull);
          observer.selectView(tester.view);
          expect(await access.displays.current(), entity);
          observer.selectView(null);
          expect(await access.displays.current(), isNull);
        } finally {
          observer.dispose();
          access.dispose();
        }
      });
    },
  );

  testWidgets(
    'Flutter display metrics stream retains equal notifications and Windows mode semantics',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
      });
      tester.view.display.size = const ui.Size(2560, 1440);
      tester.view.display.devicePixelRatio = 1.5;
      tester.view.display.refreshRate = 120;
      addTearDown(tester.view.display.reset);
      await tester.runAsync(() async {
        final access = readout.DeviceAccess.isolated(forbiddenFactory)
            .withPollInterval(const Duration(minutes: 1));
        final observer = readout.FlutterDisplayObserver.attach(
          access,
          binding: tester.binding,
        );
        StreamSubscription<readout.DisplaySnapshot>? subscription;
        try {
          final entity = (await access.displays.list()).single;
          final first = Completer<void>(), third = Completer<void>();
          final values = <readout.DisplaySnapshot>[];
          subscription = access.watch(entity).listen((value) {
            values.add(value);
            if (values.length == 1) first.complete();
            if (values.length == 3) third.complete();
          });
          await first.future.timeout(const Duration(seconds: 2));
          tester.view.display.refreshRate = 144;
          tester.view.display.refreshRate = 144;
          await third.future.timeout(const Duration(seconds: 2));
          expect(values.map((value) => value.currentMode?.refreshRateHz), [
            120,
            144,
            144,
          ]);
          expect(values.last.currentMode?.pixelSize?.width, 2560);
          expect((await access.displays.list()).single, entity);
          tester.view.display.refreshRate =
              1; // Windows default-hardware sentinel.
          expect((await access.get(entity)).currentMode, isNull);
          debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
          tester.view.display.refreshRate = 120;
          final unverified = await access.get(entity);
          expect(unverified.pixelSize?.width, 2560);
          expect(unverified.currentMode, isNull);
          expect(unverified.maximumRefreshRateHz, isNull);
        } finally {
          debugDefaultTargetPlatformOverride = null;
          await subscription?.cancel();
          observer.dispose();
          access.dispose();
        }
      });
    },
  );

  testWidgets(
    'display inventory replacement preserves live handles and observed removals retire them',
    (tester) async {
      await tester.runAsync(() async {
        final access = readout.DeviceAccess.isolated(forbiddenFactory);
        final binding = FixtureBinding(),
            dispatcher = binding.platformDispatcher;
        final one = FixtureDisplay(1), two = FixtureDisplay(2);
        dispatcher.inventory = [one, two];
        final view = FixtureView(5, dispatcher, one);
        dispatcher.viewsById[5] = view;
        final observer = readout.FlutterDisplayObserver.attach(
          access,
          binding: binding,
        );
        try {
          final initial = await access.displays.list();
          observer.selectView(view);
          expect(await access.displays.current(), initial[0]);
          final replacement = FixtureDisplay(1)
            ..pixels = const ui.Size(3840, 2160);
          dispatcher.inventory = [replacement, two];
          view.display = replacement;
          binding.metrics();
          expect(await access.displays.list(), initial);
          expect((await access.get(initial[0])).pixelSize?.width, 3840);
          view.display = two;
          binding.metrics();
          expect(await access.displays.current(), initial[1]);
          dispatcher.inventory = [replacement];
          binding.metrics();
          expect(await access.displays.current(), isNull);
          await expectLater(
            access.get(initial[1]),
            throwsA(code(readout.ErrorCode.entityRemoved)),
          );
          dispatcher.inventory = [replacement, FixtureDisplay(2)];
          binding.metrics();
          final returned = (await access.displays.list()).last;
          expect(returned, isNot(initial[1]));
          await expectLater(
            access.get(initial[1]),
            throwsA(code(readout.ErrorCode.entityRemoved)),
          );
          // A new Flutter view object under the same ID must not inherit selection.
          dispatcher.viewsById[5] = FixtureView(5, dispatcher, replacement);
          binding.metrics();
          expect(await access.displays.current(), isNull);
          expect(
            () => observer.selectView(view),
            throwsA(code(readout.ErrorCode.entityRemoved)),
          );
          final foreign = FixtureDispatcher();
          expect(
            () => observer.selectView(FixtureView(7, foreign, one)),
            throwsA(code(readout.ErrorCode.invalidConfiguration)),
          );
          expect(
            () => observer.selectView(FixtureView(99, dispatcher, one)),
            throwsA(code(readout.ErrorCode.entityRemoved)),
          );
          dispatcher.inventory = [];
          binding.metrics();
          expect(await access.displays.list(), isEmpty);
          observer.dispose();
          final reads = dispatcher.reads;
          binding.metrics();
          expect(dispatcher.reads, reads);
          expect(binding.observers, isEmpty);
        } finally {
          observer.dispose();
          access.dispose();
        }
      });
    },
  );

  testWidgets(
    'display field failures are nullable and inventory failures invalidate without phantom removal',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
      });
      await tester.runAsync(() async {
        final access = readout.DeviceAccess.isolated(forbiddenFactory);
        final binding = FixtureBinding(),
            dispatcher = binding.platformDispatcher;
        final display = FixtureDisplay(7)..failSize = true;
        dispatcher.inventory = [display];
        final observer = readout.FlutterDisplayObserver.attach(
          access,
          binding: binding,
        );
        StreamSubscription<readout.DisplaySnapshot>? subscription;
        try {
          final entity = (await access.displays.list()).single;
          final partial = await access.get(entity);
          expect(partial.pixelSize, isNull);
          expect(partial.scaleFactor, 1.5);
          expect(partial.currentMode?.refreshRateHz, 120);
          final reads = (dispatcher.reads, display.reads);
          final first = Completer<void>(), ended = Completer<void>();
          final errors = <Object>[];
          subscription = access
              .watch(entity)
              .listen(
                (_) {
                  if (!first.isCompleted) first.complete();
                },
                onError: (Object error) {
                  errors.add(error);
                },
                onDone: ended.complete,
              );
          await first.future.timeout(const Duration(seconds: 2));
          await access.displays.list();
          await access.displays.current();
          await access.get(entity);
          expect((dispatcher.reads, display.reads), reads);
          dispatcher.failInventory = true;
          binding.metrics();
          await ended.future.timeout(const Duration(seconds: 2));
          expect(errors.single, code(readout.ErrorCode.readFailed));
          await expectLater(
            access.displays.list(),
            throwsA(code(readout.ErrorCode.readFailed)),
          );
          dispatcher.failInventory = false;
          display.failSize = false;
          display.pixels = const ui.Size(0, 1080);
          display.ratio = double.nan;
          display.rate = double.infinity;
          binding.metrics();
          expect((await access.displays.list()).single, entity);
          final invalid = await access.get(entity);
          expect(invalid.pixelSize, isNull);
          expect(invalid.scaleFactor, isNull);
          expect(invalid.currentMode, isNull);
          dispatcher.inventory = [display, FixtureDisplay(7)];
          binding.metrics();
          await expectLater(
            access.get(entity),
            throwsA(code(readout.ErrorCode.readFailed)),
          );
          dispatcher.inventory = [display];
          binding.metrics();
          expect((await access.displays.list()).single, entity);
          access.dispose();
          binding.metrics();
          expect(binding.observers, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          debugDefaultTargetPlatformOverride = null;
          await subscription?.cancel();
          observer.dispose();
          access.dispose();
        }
      });
    },
  );
}
