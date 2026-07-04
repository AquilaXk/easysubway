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
// 설정하면 다음 프레임에 동기 렌더되므로, post-frame 콜백에서 FramePresented와
// (설정→프레임) CameraLatency를 방출한다.
class StructuredRouteMapRendererController
    implements RouteMapRendererController {
  StructuredRouteMapRendererController({
    void Function(void Function(Duration timeStamp))? scheduleFrame,
    Stopwatch Function()? stopwatchFactory,
  }) : _scheduleFrame = scheduleFrame ??
           ((callback) =>
               SchedulerBinding.instance.addPostFrameCallback(callback)),
       _stopwatchFactory = stopwatchFactory ?? Stopwatch.new {
    // 데이터는 이미 메모리(datapack)에 있으므로 즉시 ready. 리스너가 구독한 뒤
    // 받도록 microtask로 방출한다(broadcast stream은 버퍼링하지 않음).
    scheduleMicrotask(() {
      if (_disposed) {
        return;
      }
      _emit(const RouteMapRendererCreated());
      _emit(const RouteMapRendererAssetLoading());
      _emit(const RouteMapRendererAssetReady());
    });
  }

  final void Function(void Function(Duration timeStamp)) _scheduleFrame;
  final Stopwatch Function() _stopwatchFactory;
  final StreamController<RouteMapRendererEvent> _controller =
      StreamController<RouteMapRendererEvent>.broadcast();
  bool _disposed = false;

  @override
  Stream<RouteMapRendererEvent> get events => _controller.stream;

  @override
  Future<void> setCamera(MapCameraState camera) async {
    if (_disposed) {
      return;
    }
    final revision = camera.revision;
    _emit(RouteMapRendererCameraRequested(revision));
    final stopwatch = _stopwatchFactory()..start();
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

  @override
  Future<void> retry() async {
    if (_disposed) {
      return;
    }
    // native canvas는 실패 상태가 없다 — ready를 재확인한다.
    _emit(const RouteMapRendererAssetReady());
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

  void _emit(RouteMapRendererEvent event) {
    if (_controller.isClosed) {
      return;
    }
    _controller.add(event);
  }
}
