import 'dart:async';

import 'package:flutter/scheduler.dart';

import '../domain/map_camera.dart';
import 'route_map_renderer.dart';

// 구조화 canvas 렌더러용 RouteMapRendererController 구현 (#1641 Stage 4).
//
// WebView 렌더러와 같은 이벤트 계약(Created/AssetReady/CameraRequested/
// CameraLatency/FramePresented/...)을 유지해, run-route-map-android-evidence.sh
// 증거 파이프라인과 RouteMapRendererHealthMonitor가 그대로 동작하게 한다.
//
// native canvas는 WebView와 달리 process gone/frame timeout이 없다. 카메라를
// 설정하면 프레임을 요청하고, 그 프레임의 post-frame 콜백에서 FramePresented와
// (설정→프레임) CameraLatency를 방출한다.
class StructuredRouteMapRendererController
    implements RouteMapRendererController {
  StructuredRouteMapRendererController({
    void Function(void Function(Duration timeStamp))? scheduleFrame,
    void Function()? requestFrame,
    Stopwatch Function()? stopwatchFactory,
  }) : _scheduleFrame = scheduleFrame ??
           ((callback) =>
               SchedulerBinding.instance.addPostFrameCallback(callback)),
       _requestFrame =
           requestFrame ?? (() => SchedulerBinding.instance.ensureVisualUpdate()),
       _stopwatchFactory = stopwatchFactory ?? Stopwatch.new {
    // 초기 이벤트는 첫 구독 시점(onListen)에 방출한다. broadcast stream은
    // 버퍼링하지 않으므로 생성 시 방출하면 늦게 구독하는 monitor가 놓친다.
    _controller = StreamController<RouteMapRendererEvent>.broadcast(
      onListen: _emitInitialEvents,
    );
  }

  final void Function(void Function(Duration timeStamp)) _scheduleFrame;
  final void Function() _requestFrame;
  final Stopwatch Function() _stopwatchFactory;
  late final StreamController<RouteMapRendererEvent> _controller;
  MapCameraState? _lastCamera;
  bool _initialEmitted = false;
  bool _disposed = false;

  @override
  Stream<RouteMapRendererEvent> get events => _controller.stream;

  @override
  Future<void> setCamera(MapCameraState camera) async {
    if (_disposed) {
      return;
    }
    _lastCamera = camera;
    _emit(RouteMapRendererCameraRequested(camera.revision));
    _presentFrame(camera.revision);
  }

  @override
  Future<void> retry() async {
    if (_disposed) {
      return;
    }
    // native canvas는 실패 상태가 없다. monitor 복구 경로는 retry 후 마지막
    // revision의 FramePresented를 기다리므로, ready 재확인 후 프레임을 다시
    // 통지해 복구가 완료되게 한다.
    _emit(const RouteMapRendererAssetReady());
    final camera = _lastCamera;
    if (camera != null) {
      _presentFrame(camera.revision);
    }
  }

  @override
  Future<void> trimMemory() async {
    if (_disposed) {
      return;
    }
    _emit(const RouteMapRendererMemoryTrimmed());
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _emit(const RouteMapRendererDisposed());
    await _controller.close();
  }

  void _emitInitialEvents() {
    if (_initialEmitted || _disposed) {
      return;
    }
    _initialEmitted = true;
    // 데이터는 이미 datapack 메모리에 있으므로 즉시 ready.
    _emit(const RouteMapRendererCreated());
    _emit(const RouteMapRendererAssetLoading());
    _emit(const RouteMapRendererAssetReady());
    // 구독 전에 카메라가 설정돼 있었다면 프레임을 통지한다.
    final camera = _lastCamera;
    if (camera != null) {
      _presentFrame(camera.revision);
    }
  }

  // 프레임을 요청하고, 그 프레임 이후 CameraLatency·FramePresented를 방출한다.
  void _presentFrame(int revision) {
    final stopwatch = _stopwatchFactory()..start();
    _requestFrame();
    _scheduleFrame((_) {
      stopwatch.stop();
      if (_disposed) {
        return;
      }
      _emit(
        RouteMapRendererCameraLatency(
          revision: revision,
          elapsed: stopwatch.elapsed,
        ),
      );
      _emit(RouteMapRendererFramePresented(revision));
    });
  }

  void _emit(RouteMapRendererEvent event) {
    if (_controller.isClosed) {
      return;
    }
    _controller.add(event);
  }
}
