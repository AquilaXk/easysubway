import 'dart:ui' show Offset, Rect, Size;

import 'package:easysubway_mobile/features/network_map/domain/map_camera.dart';
import 'package:easysubway_mobile/features/network_map/infrastructure/route_map_renderer.dart';
import 'package:easysubway_mobile/features/network_map/infrastructure/structured_route_map_renderer_controller.dart';
import 'package:flutter_test/flutter_test.dart';

MapCameraState cameraAt(int revision) {
  return MapCameraState(
    sourceBounds: const Rect.fromLTWH(0, 0, 1000, 1000),
    viewportSize: const Size(400, 400),
    center: const Offset(500, 500),
    scale: 1.0,
    minScale: 0.5,
    maxScale: 3.5,
    revision: revision,
  );
}

Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  test('생성 시 Created/AssetLoading/AssetReady를 방출한다', () async {
    final controller = StructuredRouteMapRendererController(
      scheduleFrame: (_) {},
    );
    final events = <RouteMapRendererEvent>[];
    controller.events.listen(events.add);
    await flush();

    expect(events, [
      isA<RouteMapRendererCreated>(),
      isA<RouteMapRendererAssetLoading>(),
      isA<RouteMapRendererAssetReady>(),
    ]);
    await controller.dispose();
  });

  test('setCamera는 CameraRequested 후 post-frame에 CameraLatency·FramePresented', () async {
    final frames = <void Function(Duration)>[];
    final controller = StructuredRouteMapRendererController(
      scheduleFrame: frames.add,
    );
    final events = <RouteMapRendererEvent>[];
    controller.events.listen(events.add);
    await flush();
    events.clear();

    await controller.setCamera(cameraAt(7));
    await flush();

    expect(
      events.whereType<RouteMapRendererCameraRequested>().single.revision,
      7,
    );
    // 아직 프레임이 안 왔으므로 FramePresented 없음.
    expect(events.whereType<RouteMapRendererFramePresented>(), isEmpty);
    expect(frames, hasLength(1));

    // 프레임 도착 시뮬레이션.
    frames.single(Duration.zero);
    await flush();

    expect(
      events.whereType<RouteMapRendererFramePresented>().single.revision,
      7,
    );
    final latency = events.whereType<RouteMapRendererCameraLatency>().single;
    expect(latency.revision, 7);
    expect(latency.elapsed, greaterThanOrEqualTo(Duration.zero));
    await controller.dispose();
  });

  test('retry는 AssetReady, trimMemory는 MemoryTrimmed를 방출한다', () async {
    final controller = StructuredRouteMapRendererController(
      scheduleFrame: (_) {},
    );
    final events = <RouteMapRendererEvent>[];
    controller.events.listen(events.add);
    await flush();
    events.clear();

    await controller.retry();
    await controller.trimMemory();
    await flush();

    expect(events.whereType<RouteMapRendererAssetReady>(), hasLength(1));
    expect(events.whereType<RouteMapRendererMemoryTrimmed>(), hasLength(1));
    await controller.dispose();
  });

  test('dispose는 Disposed 방출 후 스트림을 닫고, 이후 호출은 무시된다', () async {
    final frames = <void Function(Duration)>[];
    final controller = StructuredRouteMapRendererController(
      scheduleFrame: frames.add,
    );
    final events = <RouteMapRendererEvent>[];
    controller.events.listen(events.add);
    await flush();

    await controller.dispose();
    await flush();
    expect(events.whereType<RouteMapRendererDisposed>(), hasLength(1));

    // dispose 이후 setCamera는 아무 이벤트도 만들지 않고 프레임도 예약 안 함.
    await controller.setCamera(cameraAt(9));
    await flush();
    expect(frames, isEmpty);
  });

  test('dispose 후 도착한 프레임 콜백은 닫힌 스트림에 쓰지 않는다', () async {
    final frames = <void Function(Duration)>[];
    final controller = StructuredRouteMapRendererController(
      scheduleFrame: frames.add,
    );
    controller.events.listen((_) {});
    await flush();

    await controller.setCamera(cameraAt(3));
    await flush();
    expect(frames, hasLength(1));

    await controller.dispose();
    // 늦게 도착한 프레임 콜백이 예외를 던지지 않아야 한다.
    expect(() => frames.single(Duration.zero), returnsNormally);
  });
}
