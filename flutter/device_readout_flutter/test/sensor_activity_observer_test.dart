import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' as widgets;
import 'package:flutter_test/flutter_test.dart';
import 'package:device_readout_flutter/device_readout_flutter.dart' as readout;

readout.DeviceCollector forbiddenFactory(Object? _) => throw StateError(
  'Lifecycle observation must not initialize a native collector.',
);

final class LifecycleBinding extends Fake implements widgets.WidgetsBinding {
  widgets.AppLifecycleState? state;
  int reads = 0;
  final observers = <widgets.WidgetsBindingObserver>{};
  @override
  widgets.AppLifecycleState? get lifecycleState {
    reads++;
    return state;
  }

  @override
  void addObserver(widgets.WidgetsBindingObserver observer) =>
      observers.add(observer);
  @override
  bool removeObserver(widgets.WidgetsBindingObserver observer) =>
      observers.remove(observer);
  void publish(widgets.AppLifecycleState value) {
    state = value;
    for (final observer in observers.toList()) {
      observer.didChangeAppLifecycleState(value);
    }
  }
}

void main() {
  testWidgets(
    'mobile lifecycle releases sensor demand and resumes without stale samples',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final initial = tester.binding.lifecycleState;
      try {
        await tester.runAsync(() async {
          tester.binding.handleAppLifecycleStateChanged(
            widgets.AppLifecycleState.paused,
          );
          final access = readout.DeviceAccess.isolated(forbiddenFactory);
          final observer = readout.FlutterSensorActivityObserver.attach(access);
          final target = access.observers.target(
            readout.Entities.pressure,
            'mobile-pressure',
          );
          final sessions =
              <readout.SensorObserverSession<readout.PressureSnapshot>>[];
          var cleanups = 0, permissionRequests = 0;
          access.observers.onPermissionRequest((_) {
            permissionRequests++;
          });
          access.observers.sensorSource(
            target,
            readout.SensorObserverSource<readout.PressureSnapshot>(
              subscribe: (session) {
                sessions.add(session);
                return () {
                  cleanups++;
                };
              },
            ),
          );
          final values = <double?>[], errors = <Object>[];
          final first = Completer<void>();
          final ended = Completer<void>();
          final subscription = access
              .withReadTimeout(const Duration(milliseconds: 150))
              .withSensorSamplingRate(readout.SensorSamplingRate.atHertz(60))
              .watch(target)
              .listen(
                (sample) {
                  values.add(sample.value);
                  if (!first.isCompleted) first.complete();
                },
                onError: (Object error) => errors.add(error),
                onDone: ended.complete,
              );
          try {
            await Future<void>.delayed(const Duration(milliseconds: 200));
            expect(sessions, isEmpty);
            expect(errors, isEmpty);
            tester.binding.handleAppLifecycleStateChanged(
              widgets.AppLifecycleState.resumed,
            );
            expect(sessions, hasLength(1));
            expect(sessions.single.samplingRate.hertz, 60);
            tester.binding.handleAppLifecycleStateChanged(
              widgets.AppLifecycleState.inactive,
            );
            expect(sessions.single.cancellation.isCancelled, isTrue);
            await Future<void>.delayed(Duration.zero);
            expect(cleanups, 1);
            sessions.single.publish(readout.PressureSnapshot(value: 999));
            tester.binding.handleAppLifecycleStateChanged(
              widgets.AppLifecycleState.hidden,
            );
            tester.binding.handleAppLifecycleStateChanged(
              widgets.AppLifecycleState.paused,
            );
            tester.binding.handleAppLifecycleStateChanged(
              widgets.AppLifecycleState.resumed,
            );
            expect(sessions, hasLength(2));
            sessions.last.publish(readout.PressureSnapshot(value: 101325));
            await first.future.timeout(const Duration(seconds: 2));
            expect(values, [101325]);
            expect(errors, isEmpty);
            expect(permissionRequests, 0);
            observer.dispose();
            observer.dispose();
            expect(cleanups, 2);
            tester.binding.handleAppLifecycleStateChanged(
              widgets.AppLifecycleState.resumed,
            );
            expect(sessions, hasLength(2));
            access.dispose();
            await ended.future.timeout(const Duration(seconds: 2));
            expect(errors.single, isA<readout.DeviceReadoutCancelled>());
          } finally {
            await subscription.cancel();
            observer.dispose();
            access.dispose();
          }
        });
      } finally {
        tester.binding.handleAppLifecycleStateChanged(
          initial ?? widgets.AppLifecycleState.resumed,
        );
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('desktop focus loss retains sensor subscriptions', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final initial = tester.binding.lifecycleState;
    try {
      await tester.runAsync(() async {
        tester.binding.handleAppLifecycleStateChanged(
          widgets.AppLifecycleState.inactive,
        );
        final access = readout.DeviceAccess.isolated(forbiddenFactory);
        final observer = readout.FlutterSensorActivityObserver.attach(access);
        final target = access.observers.target(
          readout.Entities.stepDetected,
          'desktop-event',
        );
        final sessions =
            <readout.SensorObserverSession<readout.StepDetectedSnapshot>>[];
        var cleanups = 0;
        access.observers.sensorSource(
          target,
          readout.SensorObserverSource<readout.StepDetectedSnapshot>(
            subscribe: (session) {
              sessions.add(session);
              return () {
                cleanups++;
              };
            },
          ),
        );
        final first = Completer<readout.StepDetectedSnapshot>();
        final errors = <Object>[];
        final subscription = access
            .watch(target)
            .listen(
              first.complete,
              onError: (Object error) => errors.add(error),
            );
        try {
          expect(sessions, hasLength(1));
          tester.binding.handleAppLifecycleStateChanged(
            widgets.AppLifecycleState.resumed,
          );
          tester.binding.handleAppLifecycleStateChanged(
            widgets.AppLifecycleState.inactive,
          );
          expect(sessions, hasLength(1));
          expect(sessions.single.cancellation.isCancelled, isFalse);
          tester.binding.handleAppLifecycleStateChanged(
            widgets.AppLifecycleState.hidden,
          );
          expect(sessions.single.cancellation.isCancelled, isTrue);
          tester.binding.handleAppLifecycleStateChanged(
            widgets.AppLifecycleState.inactive,
          );
          expect(sessions, hasLength(2));
          sessions.last.publish(readout.StepDetectedSnapshot(value: true));
          expect(
            (await first.future.timeout(const Duration(seconds: 2))).value,
            isTrue,
          );
          expect(errors, isEmpty);
          await subscription.cancel();
          expect(cleanups, 2);
          access.dispose();
          tester.binding.handleAppLifecycleStateChanged(
            widgets.AppLifecycleState.resumed,
          );
          expect(tester.takeException(), isNull);
        } finally {
          await subscription.cancel();
          observer.dispose();
          access.dispose();
        }
      });
    } finally {
      tester.binding.handleAppLifecycleStateChanged(
        initial ?? widgets.AppLifecycleState.resumed,
      );
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test('unknown lifecycle waits for observation without UI polling', () async {
    final binding = LifecycleBinding();
    final access = readout.DeviceAccess.isolated(forbiddenFactory);
    final observer = readout.FlutterSensorActivityObserver.attach(
      access,
      binding: binding,
    );
    final target = access.observers.target(
      readout.Entities.pressure,
      'initially-unknown',
    );
    var starts = 0;
    access.observers.sensorSource(
      target,
      readout.SensorObserverSource<readout.PressureSnapshot>(
        description: readout.SensorDescription(name: 'Fixture barometer'),
        subscribe: (session) {
          starts++;
          session.publish(readout.PressureSnapshot(value: 101325));
          return null;
        },
      ),
    );
    final first = Completer<readout.PressureSnapshot>();
    final errors = <Object>[];
    final subscription = access
        .watch(target)
        .listen(first.complete, onError: (Object error) => errors.add(error));
    try {
      expect(binding.observers, hasLength(1));
      await expectLater(
        access.withReadTimeout(const Duration(milliseconds: 40)).get(target),
        throwsA(
          isA<readout.DeviceReadoutException>().having(
            (error) => error.code,
            'code',
            readout.ErrorCode.readTimeout,
          ),
        ),
      );
      expect((await access.describe(target)).name, 'Fixture barometer');
      expect(await access.list(readout.Entities.pressure), [target]);
      expect(await access.current(readout.Entities.pressure), isNull);
      expect(starts, 0);
      expect(binding.reads, 1);
      binding.publish(widgets.AppLifecycleState.resumed);
      expect(
        (await first.future.timeout(const Duration(seconds: 2))).value,
        101325,
      );
      expect((await access.get(target)).value, 101325);
      expect(starts, 2);
      expect(binding.reads, 1);
      expect(errors, isEmpty);
      await subscription.cancel();
      access.dispose();
      binding.publish(widgets.AppLifecycleState.paused);
      expect(binding.observers, isEmpty);
    } finally {
      await subscription.cancel();
      observer.dispose();
      access.dispose();
    }
  });
}
