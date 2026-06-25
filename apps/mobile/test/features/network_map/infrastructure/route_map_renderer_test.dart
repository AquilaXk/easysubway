import 'dart:async';

import 'package:easysubway_mobile/features/network_map/domain/map_camera.dart';
import 'package:easysubway_mobile/features/network_map/infrastructure/route_map_renderer.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const camera = MapCameraState(
    sourceBounds: Rect.fromLTWH(0, 0, 1000, 500),
    viewportSize: Size(250, 125),
    center: Offset(500, 250),
    scale: 0.5,
    minScale: 0.1,
    maxScale: 4,
    revision: 3,
  );

  test('health monitor retries when requested camera frame is blank', () async {
    final controller = _FakeRouteMapRendererController();
    final observed = <RouteMapRendererEvent>[];
    final monitor = RouteMapRendererHealthMonitor(
      controller,
      blankTimeout: const Duration(milliseconds: 10),
      onEvent: observed.add,
    )..start();
    addTearDown(monitor.stop);

    controller.emit(const RouteMapRendererCameraRequested(5));
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(controller.retryCalls, 1);
    expect(
      observed,
      containsAllInOrder(<Matcher>[
        isA<RouteMapRendererCameraRequested>().having(
          (event) => event.revision,
          'revision',
          5,
        ),
        isA<RouteMapRendererFrameTimeout>().having(
          (event) => event.revision,
          'revision',
          5,
        ),
        isA<RouteMapRendererRecovering>().having(
          (event) => event.attempt,
          'attempt',
          1,
        ),
      ]),
    );
  });

  test('health monitor cancels blank watchdog after frame presents', () async {
    final controller = _FakeRouteMapRendererController();
    final observed = <RouteMapRendererEvent>[];
    final monitor = RouteMapRendererHealthMonitor(
      controller,
      blankTimeout: const Duration(milliseconds: 20),
      onEvent: observed.add,
    )..start();
    addTearDown(monitor.stop);

    controller
      ..emit(const RouteMapRendererCameraRequested(7))
      ..emit(const RouteMapRendererFramePresented(7));
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(controller.retryCalls, 0);
    expect(observed.whereType<RouteMapRendererFrameTimeout>(), isEmpty);
  });

  test('health monitor retries when renderer process is gone', () async {
    final controller = _FakeRouteMapRendererController();
    final observed = <RouteMapRendererEvent>[];
    final monitor = RouteMapRendererHealthMonitor(
      controller,
      onEvent: observed.add,
    )..start();
    addTearDown(monitor.stop);

    controller.emit(const RouteMapRendererProcessGone(didCrash: true));
    await pumpEventQueue();

    expect(controller.retryCalls, 1);
    expect(
      observed,
      containsAllInOrder(<Matcher>[
        isA<RouteMapRendererProcessGone>().having(
          (event) => event.didCrash,
          'didCrash',
          isTrue,
        ),
        isA<RouteMapRendererRecovering>().having(
          (event) => event.attempt,
          'attempt',
          1,
        ),
      ]),
    );
  });

  test('health monitor cancels pending watchdog during recovery', () async {
    final controller = _FakeRouteMapRendererController();
    final monitor = RouteMapRendererHealthMonitor(
      controller,
      blankTimeout: const Duration(milliseconds: 10),
    )..start();
    addTearDown(monitor.stop);

    controller
      ..emit(const RouteMapRendererCameraRequested(8))
      ..emit(const RouteMapRendererProcessGone(didCrash: true));
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(controller.retryCalls, 1);
  });

  test('health monitor delegates memory pressure trim to controller', () async {
    final controller = _FakeRouteMapRendererController();
    final monitor = RouteMapRendererHealthMonitor(controller)..start();
    addTearDown(monitor.stop);

    await monitor.trimMemory();

    expect(controller.trimMemoryCalls, 1);
  });

  test('health monitor stops delegating after renderer is disposed', () async {
    final controller = _FakeRouteMapRendererController();
    final monitor = RouteMapRendererHealthMonitor(controller)..start();
    addTearDown(monitor.stop);

    controller.emit(const RouteMapRendererDisposed());
    await pumpEventQueue();
    await monitor.trimMemory();
    await monitor.disposeRenderer();

    expect(controller.trimMemoryCalls, 0);
    expect(controller.disposeCalls, 0);
  });

  test('fake controller mirrors camera request and latency events', () async {
    final controller = _FakeRouteMapRendererController();
    final observed = <RouteMapRendererEvent>[];
    final subscription = controller.events.listen(observed.add);
    addTearDown(subscription.cancel);

    await controller.setCamera(camera);
    controller.emit(const RouteMapRendererFramePresented(3));
    await pumpEventQueue();

    expect(
      observed,
      containsAllInOrder(<Matcher>[
        isA<RouteMapRendererCameraRequested>().having(
          (event) => event.revision,
          'revision',
          3,
        ),
        isA<RouteMapRendererCameraLatency>().having(
          (event) => event.revision,
          'revision',
          3,
        ),
        isA<RouteMapRendererFramePresented>().having(
          (event) => event.revision,
          'revision',
          3,
        ),
      ]),
    );
  });
}

class _FakeRouteMapRendererController implements RouteMapRendererController {
  final _events = StreamController<RouteMapRendererEvent>.broadcast();
  final _pendingCameraFrames = <int, Stopwatch>{};
  int retryCalls = 0;
  int trimMemoryCalls = 0;
  int disposeCalls = 0;

  @override
  Stream<RouteMapRendererEvent> get events => _events.stream;

  void emit(RouteMapRendererEvent event) {
    if (event case RouteMapRendererFramePresented(:final revision)) {
      final pending = _pendingCameraFrames.remove(revision);
      if (pending != null) {
        pending.stop();
        _events.add(
          RouteMapRendererCameraLatency(
            revision: revision,
            elapsed: pending.elapsed,
          ),
        );
      }
    }
    _events.add(event);
  }

  @override
  Future<void> setCamera(MapCameraState camera) async {
    _pendingCameraFrames[camera.revision] = Stopwatch()..start();
    _events.add(RouteMapRendererCameraRequested(camera.revision));
  }

  @override
  Future<void> retry() async {
    retryCalls += 1;
  }

  @override
  Future<void> trimMemory() async {
    trimMemoryCalls += 1;
    _events.add(const RouteMapRendererMemoryTrimmed());
  }

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
    await _events.close();
  }
}
