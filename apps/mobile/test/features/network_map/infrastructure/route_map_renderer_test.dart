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
    final timers = _ManualTimerFactory();
    final observed = <RouteMapRendererEvent>[];
    final monitor = RouteMapRendererHealthMonitor(
      controller,
      blankTimeout: const Duration(milliseconds: 10),
      onEvent: observed.add,
      timerFactory: timers.create,
    )..start();
    addTearDown(monitor.stop);

    controller.emit(const RouteMapRendererCameraRequested(5));
    await pumpEventQueue();
    timers.elapse(const Duration(milliseconds: 10));

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

  test('health monitor waits for asset ready before retry watchdog', () async {
    final controller = _FakeRouteMapRendererController();
    final timers = _ManualTimerFactory();
    final monitor = RouteMapRendererHealthMonitor(
      controller,
      blankTimeout: const Duration(milliseconds: 10),
      timerFactory: timers.create,
    )..start();
    addTearDown(monitor.stop);

    controller.emit(const RouteMapRendererCameraRequested(5));
    await pumpEventQueue();
    timers.elapse(const Duration(milliseconds: 35));

    expect(controller.retryCalls, 1);
  });

  test(
    'health monitor re-arms blank watchdog after retry asset ready',
    () async {
      final controller = _FakeRouteMapRendererController();
      final timers = _ManualTimerFactory();
      final monitor = RouteMapRendererHealthMonitor(
        controller,
        blankTimeout: const Duration(milliseconds: 10),
        timerFactory: timers.create,
      )..start();
      addTearDown(monitor.stop);

      controller.emit(const RouteMapRendererCameraRequested(5));
      await pumpEventQueue();
      timers.elapse(const Duration(milliseconds: 10));
      controller.emit(const RouteMapRendererAssetReady());
      await pumpEventQueue();
      timers.elapse(const Duration(milliseconds: 10));

      expect(controller.retryCalls, 2);
    },
  );

  test(
    'health monitor reports failure after repeated blank recoveries',
    () async {
      final controller = _FakeRouteMapRendererController();
      final timers = _ManualTimerFactory();
      final observed = <RouteMapRendererEvent>[];
      final monitor = RouteMapRendererHealthMonitor(
        controller,
        blankTimeout: const Duration(milliseconds: 10),
        maxRecoveryAttempts: 1,
        onEvent: observed.add,
        timerFactory: timers.create,
      )..start();
      addTearDown(monitor.stop);

      controller.emit(const RouteMapRendererCameraRequested(5));
      await pumpEventQueue();
      timers.elapse(const Duration(milliseconds: 10));
      controller.emit(const RouteMapRendererAssetReady());
      await pumpEventQueue();
      timers.elapse(const Duration(milliseconds: 10));

      expect(controller.retryCalls, 1);
      expect(
        observed,
        contains(
          isA<RouteMapRendererFailed>().having(
            (event) => event.reason,
            'reason',
            contains('did not present a frame'),
          ),
        ),
      );
    },
  );

  test('health monitor cancels blank watchdog after frame presents', () async {
    final controller = _FakeRouteMapRendererController();
    final timers = _ManualTimerFactory();
    final observed = <RouteMapRendererEvent>[];
    final monitor = RouteMapRendererHealthMonitor(
      controller,
      blankTimeout: const Duration(milliseconds: 20),
      onEvent: observed.add,
      timerFactory: timers.create,
    )..start();
    addTearDown(monitor.stop);

    controller
      ..emit(const RouteMapRendererCameraRequested(7))
      ..emit(const RouteMapRendererFramePresented(7));
    await pumpEventQueue();
    timers.elapse(const Duration(milliseconds: 40));

    expect(controller.retryCalls, 0);
    expect(observed.whereType<RouteMapRendererFrameTimeout>(), isEmpty);
  });

  test('health monitor ignores stale higher revision frame', () async {
    final controller = _FakeRouteMapRendererController();
    final timers = _ManualTimerFactory();
    final monitor = RouteMapRendererHealthMonitor(
      controller,
      blankTimeout: const Duration(milliseconds: 10),
      timerFactory: timers.create,
    )..start();
    addTearDown(monitor.stop);

    controller
      ..emit(const RouteMapRendererCameraRequested(0))
      ..emit(const RouteMapRendererFramePresented(5));
    await pumpEventQueue();
    timers.elapse(const Duration(milliseconds: 10));

    expect(controller.retryCalls, 1);
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
    final timers = _ManualTimerFactory();
    final monitor = RouteMapRendererHealthMonitor(
      controller,
      blankTimeout: const Duration(milliseconds: 10),
      timerFactory: timers.create,
    )..start();
    addTearDown(monitor.stop);

    controller
      ..emit(const RouteMapRendererCameraRequested(8))
      ..emit(const RouteMapRendererProcessGone(didCrash: true));
    await pumpEventQueue();
    timers.elapse(const Duration(milliseconds: 30));

    expect(controller.retryCalls, 1);
  });

  test('health monitor reports retry errors without throwing', () async {
    final controller = _FakeRouteMapRendererController()
      ..retryError = StateError('reload failed');
    final observed = <RouteMapRendererEvent>[];
    final monitor = RouteMapRendererHealthMonitor(
      controller,
      onEvent: observed.add,
    )..start();
    addTearDown(monitor.stop);

    controller.emit(const RouteMapRendererProcessGone(didCrash: true));
    await pumpEventQueue();

    expect(
      observed,
      contains(
        isA<RouteMapRendererFailed>().having(
          (event) => event.reason,
          'reason',
          contains('reload failed'),
        ),
      ),
    );
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

  test('health monitor close disposes renderer and stops delegation', () async {
    final controller = _FakeRouteMapRendererController();
    final monitor = RouteMapRendererHealthMonitor(controller)..start();
    addTearDown(monitor.stop);

    await monitor.close(disposeRenderer: true);
    await monitor.trimMemory();
    await monitor.disposeRenderer();
    await monitor.close(disposeRenderer: true);

    expect(controller.disposeCalls, 1);
    expect(controller.trimMemoryCalls, 0);
  });

  test('health monitor close only disposes once when calls overlap', () async {
    final controller = _FakeRouteMapRendererController()
      ..disposeCompleter = Completer<void>();
    final monitor = RouteMapRendererHealthMonitor(controller)..start();
    addTearDown(monitor.stop);

    final firstClose = monitor.close(disposeRenderer: true);
    final secondClose = monitor.close(disposeRenderer: true);
    await pumpEventQueue();

    expect(controller.disposeCalls, 1);

    controller.disposeCompleter!.complete();
    await Future.wait(<Future<void>>[firstClose, secondClose]);
    await monitor.disposeRenderer();

    expect(controller.disposeCalls, 1);
  });

  test('health monitor close stops after renderer dispose failure', () async {
    final controller = _FakeRouteMapRendererController()
      ..disposeError = StateError('dispose failed');
    final monitor = RouteMapRendererHealthMonitor(controller)..start();
    addTearDown(monitor.stop);

    await expectLater(
      monitor.close(disposeRenderer: true),
      throwsA(isA<StateError>()),
    );
    await monitor.trimMemory();
    await monitor.disposeRenderer();

    expect(controller.disposeCalls, 1);
    expect(controller.trimMemoryCalls, 0);
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
  Object? retryError;
  Object? disposeError;
  Completer<void>? disposeCompleter;
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
    final error = retryError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<void> trimMemory() async {
    trimMemoryCalls += 1;
    _events.add(const RouteMapRendererMemoryTrimmed());
  }

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
    await disposeCompleter?.future;
    final error = disposeError;
    if (error != null) {
      throw error;
    }
    await _events.close();
  }
}

class _ManualTimerFactory {
  final _timers = <_ManualTimer>[];

  Timer create(Duration duration, void Function() callback) {
    final timer = _ManualTimer(duration, callback);
    _timers.add(timer);
    return timer;
  }

  void elapse(Duration duration) {
    for (final timer in List<_ManualTimer>.of(_timers)) {
      timer.elapse(duration);
    }
    _timers.removeWhere((timer) => !timer.isActive);
  }
}

class _ManualTimer implements Timer {
  _ManualTimer(this._remaining, this._callback);

  Duration _remaining;
  final void Function() _callback;
  bool _active = true;
  int _tick = 0;

  void elapse(Duration duration) {
    if (!_active) {
      return;
    }
    _remaining -= duration;
    if (_remaining > Duration.zero) {
      return;
    }
    _active = false;
    _tick = 1;
    _callback();
  }

  @override
  void cancel() {
    _active = false;
  }

  @override
  bool get isActive => _active;

  @override
  int get tick => _tick;
}
