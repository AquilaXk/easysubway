import 'dart:ui';

import 'package:easysubway_mobile/features/network_map/domain/map_camera.dart';
import 'package:easysubway_mobile/features/network_map/infrastructure/route_map_svg_viewport.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const origin = Offset(946, 646);
  final camera = MapCameraState(
    sourceBounds: const Rect.fromLTWH(0, 0, 200, 200),
    viewportSize: const Size(400, 800),
    center: const Offset(54.1234567890123, 54.9876543210987),
    scale: 4.25,
    minScale: 1,
    maxScale: 20,
    revision: 3,
  );

  test('권역을 canonical literal .svg 자산으로만 매핑한다', () {
    expect(routeMapSvgAssetForRegion('수도권'), 'assets/datapacks/metro_map_pack/basemap/seoul.svg');
    expect(routeMapSvgAssetForRegion('부산'), 'assets/datapacks/metro_map_pack/basemap/busan.svg');
    expect(routeMapSvgAssetForRegion('대구'), 'assets/datapacks/metro_map_pack/basemap/daegu.svg');
    expect(routeMapSvgAssetForRegion('대전'), 'assets/datapacks/metro_map_pack/basemap/daejeon.svg');
    expect(routeMapSvgAssetForRegion('광주'), 'assets/datapacks/metro_map_pack/basemap/gwangju.svg');
    expect(routeMapSvgAssetForRegion('알 수 없음'), isNull);
  });

  test('camera viewBox는 origin을 더한 visibleSourceRect의 full precision이다', () {
    final payload = routeMapSvgViewportCameraPayload(
      camera: camera,
      sourceOrigin: origin,
    );
    expect(payload, <String, Object>{
      'viewBox': <double>[
        953.0646332596005,
        606.8700072622752,
        94.11764705882354,
        188.23529411764707,
      ],
      'revision': 3,
    });
  });

  test('camera revision 변경은 setCamera 하나만 전송한다', () async {
    final calls = <MethodCall>[];
    const channelName =
        'com.easysubway.easysubway_mobile/route_map_viewport_webview/42';
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel(channelName), (call) async {
      calls.add(call);
    });
    addTearDown(() => messenger.setMockMethodCallHandler(const MethodChannel(channelName), null));

    final controller = RouteMapSvgViewportController(onUnavailable: () {});
    controller.attach(viewId: 42, camera: camera, sourceOrigin: origin);
    await controller.update(
      camera.copyWith(revision: 4, center: const Offset(60.25, 55.5)),
      sourceOrigin: origin,
    );

    expect(calls, hasLength(1));
    expect(calls.single.method, 'setCamera');
    expect(calls.single.arguments, <String, Object>{
      'viewBox': routeMapSvgViewportCameraPayload(
        camera: camera.copyWith(revision: 4, center: const Offset(60.25, 55.5)),
        sourceOrigin: origin,
      )['viewBox']!,
      'revision': 4,
    });
    controller.dispose();
  });

  test('attach 전 최신 camera는 attach 뒤 setCamera 한 번으로 따라잡는다', () async {
    final calls = <MethodCall>[];
    const channelName =
        'com.easysubway.easysubway_mobile/route_map_viewport_webview/43';
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel(channelName), (call) async {
      calls.add(call);
    });
    addTearDown(() => messenger.setMockMethodCallHandler(const MethodChannel(channelName), null));
    final controller = RouteMapSvgViewportController(onUnavailable: () {});
    final latest = camera.copyWith(revision: 5, center: const Offset(61, 56));

    await controller.update(latest, sourceOrigin: origin);
    await controller.attach(viewId: 43, camera: camera, sourceOrigin: origin);

    expect(calls, hasLength(1));
    expect(calls.single.arguments, routeMapSvgViewportCameraPayload(
      camera: latest,
      sourceOrigin: origin,
    ));
    controller.dispose();
  });

  for (final method in ['assetLoadFailed', 'cameraApplyFailed', 'processGone']) {
    test('$method는 unavailable을 알린다', () async {
      var unavailableCount = 0;
      const channelName =
          'com.easysubway.easysubway_mobile/route_map_viewport_webview/7';
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final controller = RouteMapSvgViewportController(
        onUnavailable: () => unavailableCount++,
      );
      await controller.attach(viewId: 7, camera: camera, sourceOrigin: origin);
      await messenger.handlePlatformMessage(
        channelName,
        const StandardMethodCodec().encodeMethodCall(MethodCall(method)),
        (_) {},
      );
      expect(unavailableCount, 1);
      controller.dispose();
    });
  }

  test('invalid camera는 unavailable을 알린다', () async {
    var unavailableCount = 0;
    const channelName =
        'com.easysubway.easysubway_mobile/route_map_viewport_webview/7';
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final controller = RouteMapSvgViewportController(
      onUnavailable: () => unavailableCount++,
    );
    controller.attach(viewId: 7, camera: camera, sourceOrigin: origin);

    await controller.update(
      camera.copyWith(viewportSize: const Size(double.nan, 800), revision: 4),
      sourceOrigin: origin,
    );

    expect(unavailableCount, 1);
    controller.dispose();
  });

  testWidgets('unknown region은 widget unavailable callback을 호출한다', (tester) async {
    var unavailableCount = 0;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: RouteMapSvgViewport(
          region: '알 수 없음', camera: camera, sourceOrigin: origin,
          onUnavailable: () => unavailableCount++,
        ),
      ));
      await tester.pump();
      expect(unavailableCount, 1);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('unsupported platform은 widget unavailable callback을 호출한다', (tester) async {
    var unavailableCount = 0;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: RouteMapSvgViewport(
          region: '수도권', camera: camera, sourceOrigin: origin,
          onUnavailable: () => unavailableCount++,
        ),
      ));
      await tester.pump();
      expect(unavailableCount, 1);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
