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
  test('첫 구독 시 Created/AssetLoading/AssetReady를 방출한다', () async {
    final controller = StructuredRouteMapRendererController(
      scheduleFrame: (_) {},
      requestFrame: () {},
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

  test('setCamera는 프레임을 요청하고 post-frame에 CameraLatency·FramePresented', () async {
    final frames = <void Function(Duration)>[];
    var frameRequests = 0;
    final controller = StructuredRouteMapRendererController(
      scheduleFrame: frames.add,
      requestFrame: () => frameRequests++,
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
    expect(frameRequests, greaterThanOrEqualTo(1)); // 프레임을 실제로 요청함
    expect(events.whereType<RouteMapRendererFramePresented>(), isEmpty);
    expect(frames, hasLength(1));

    frames.single(Duration.zero); // 프레임 도착 시뮬레이션
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

  test('retry는 마지막 revision의 FramePresented를 다시 통지한다(복구 완료)', () async {
    final frames = <void Function(Duration)>[];
    final controller = StructuredRouteMapRendererController(
      scheduleFrame: frames.add,
      requestFrame: () {},
    );
    final events = <RouteMapRendererEvent>[];
    controller.events.listen(events.add);
    await flush();

    await controller.setCamera(cameraAt(5));
    await flush();
    frames.removeLast()(Duration.zero); // 최초 프레임 소비
    await flush();
    events.clear();

    // 복구 시나리오: monitor가 retry 호출 → AssetReady + revision 재통지.
    await controller.retry();
    await flush();
    expect(events.whereType<RouteMapRendererAssetReady>(), hasLength(1));
    expect(frames, hasLength(1));

    frames.single(Duration.zero);
    await flush();
    expect(
      events.whereType<RouteMapRendererFramePresented>().single.revision,
      5,
    );
    await controller.dispose();
  });

  test('trimMemory는 MemoryTrimmed를 방출한다', () async {
    final controller = StructuredRouteMapRendererController(
      scheduleFrame: (_) {},
      requestFrame: () {},
    );
    final events = <RouteMapRendererEvent>[];
    controller.events.listen(events.add);
    await flush();
    events.clear();

    await controller.trimMemory();
    await flush();
    expect(events.whereType<RouteMapRendererMemoryTrimmed>(), hasLength(1));
    await controller.dispose();
  });

  test('dispose는 Disposed 방출 후 스트림을 닫고 이후 호출을 무시한다', () async {
    final frames = <void Function(Duration)>[];
    final controller = StructuredRouteMapRendererController(
      scheduleFrame: frames.add,
      requestFrame: () {},
    );
    final events = <RouteMapRendererEvent>[];
    controller.events.listen(events.add);
    await flush();

    await controller.dispose();
    await flush();
    expect(events.whereType<RouteMapRendererDisposed>(), hasLength(1));

    await controller.setCamera(cameraAt(9));
    await flush();
    expect(frames, isEmpty);
  });

  test('dispose 후 도착한 프레임 콜백은 닫힌 스트림에 쓰지 않는다', () async {
    final frames = <void Function(Duration)>[];
    final controller = StructuredRouteMapRendererController(
      scheduleFrame: frames.add,
      requestFrame: () {},
    );
    controller.events.listen((_) {});
    await flush();

    await controller.setCamera(cameraAt(3));
    await flush();
    expect(frames, hasLength(1));

    await controller.dispose();
    expect(() => frames.single(Duration.zero), returnsNormally);
  });
}
