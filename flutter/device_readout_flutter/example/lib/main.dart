import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:device_readout_flutter/device_readout_flutter.dart' as readout;

void main() => runApp(const MaterialApp(home: ViewportReadout()));

class ViewportReadout extends StatefulWidget {
  const ViewportReadout({super.key});
  @override
  State<ViewportReadout> createState() => _ViewportReadoutState();
}

class _ViewportReadoutState extends State<ViewportReadout> {
  final access = kIsWeb
      ? readout.FlutterWebDeviceAccess.create()
      : readout.DeviceAccess.native();
  ui.FlutterView? view;
  readout.FlutterViewportObserver? observer;
  Stream<readout.ViewportSnapshot>? snapshots;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final currentView = View.of(context);
    if (identical(currentView, view)) return;
    observer?.dispose();
    view = currentView;
    observer = readout.FlutterViewportObserver.attach(
      access,
      view: currentView,
    );
    access.observers.current(readout.Entities.viewport, observer!.entity);
    snapshots = access.watch(observer!.entity);
  }

  @override
  void dispose() {
    observer?.dispose();
    access.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('DeviceReadout')),
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: StreamBuilder<readout.ViewportSnapshot>(
        stream: snapshots,
        builder: (context, state) {
          if (state.hasError) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('조회 오류: ${state.error}'),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    setState(() {
                      snapshots = access.watch(observer!.entity);
                    });
                  },
                  child: const Text('구독 다시 시작'),
                ),
              ],
            );
          }
          final value = state.data;
          if (value == null) return const Text('화면 정보를 기다리고 있습니다.');
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('화면 크기: ${value.size?.width} × ${value.size?.height}'),
              Text('텍스트 배율: ${value.textScaleFactor}'),
              Text('안전 영역 위쪽: ${value.safeAreaInsets?.top}'),
              const SizedBox(height: 16),
              const Text('창 크기나 시스템 텍스트 배율을 변경하면 관찰한 값이 갱신됩니다.'),
            ],
          );
        },
      ),
    ),
  );
}
