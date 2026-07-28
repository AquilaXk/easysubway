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
    expect(
      routeMapSvgAssetForRegion('수도권'),
      'assets/datapacks/metro_map_pack/basemap/seoul.svg',
    );
    expect(
      routeMapSvgAssetForRegion('부산'),
      'assets/datapacks/metro_map_pack/basemap/busan.svg',
    );
    expect(
      routeMapSvgAssetForRegion('대구'),
      'assets/datapacks/metro_map_pack/basemap/daegu.svg',
    );
    expect(
      routeMapSvgAssetForRegion('대전'),
      'assets/datapacks/metro_map_pack/basemap/daejeon.svg',
    );
    expect(
      routeMapSvgAssetForRegion('광주'),
      'assets/datapacks/metro_map_pack/basemap/gwangju.svg',
    );
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

  test('attach는 handler 등록 뒤 start하고 camera revision을 전송한다', () async {
    final calls = <MethodCall>[];
    const channelName =
        'com.easysubway.easysubway_mobile/route_map_viewport_webview/42';
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel(channelName), (
      call,
    ) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        const MethodChannel(channelName),
        null,
      ),
    );

    final controller = RouteMapSvgViewportController(onUnavailable: () {});
    await controller.attach(viewId: 42);
    await controller.update(
      camera.copyWith(revision: 4, center: const Offset(60.25, 55.5)),
      sourceOrigin: origin,
    );

    expect(calls.map((call) => call.method), ['start', 'setCamera']);
    expect(calls.last.arguments, <String, Object>{
      'viewBox': routeMapSvgViewportCameraPayload(
        camera: camera.copyWith(revision: 4, center: const Offset(60.25, 55.5)),
        sourceOrigin: origin,
      )['viewBox']!,
      'revision': 4,
    });
    controller.dispose();
  });

  test('attach 전 최신 camera는 native start 전에 적용한다', () async {
    final calls = <MethodCall>[];
    const channelName =
        'com.easysubway.easysubway_mobile/route_map_viewport_webview/43';
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel(channelName), (
      call,
    ) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        const MethodChannel(channelName),
        null,
      ),
    );
    final controller = RouteMapSvgViewportController(onUnavailable: () {});
    final latest = camera.copyWith(revision: 5, center: const Offset(61, 56));

    await controller.update(latest, sourceOrigin: origin);
    await controller.attach(viewId: 43);

    expect(calls.map((call) => call.method), ['setCamera', 'start']);
    expect(
      calls.first.arguments,
      routeMapSvgViewportCameraPayload(camera: latest, sourceOrigin: origin),
    );
    controller.dispose();
  });

  for (final method in [
    'assetLoadFailed',
    'cameraApplyFailed',
    'processGone',
  ]) {
    test('$method는 unavailable을 알린다', () async {
      var unavailableCount = 0;
      const channelName =
          'com.easysubway.easysubway_mobile/route_map_viewport_webview/7';
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel(channelName),
        (_) async => null,
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          const MethodChannel(channelName),
          null,
        ),
      );
      final controller = RouteMapSvgViewportController(
        onUnavailable: () => unavailableCount++,
      );
      await controller.attach(viewId: 7);
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
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel(channelName),
      (_) async => null,
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        const MethodChannel(channelName),
        null,
      ),
    );
    final controller = RouteMapSvgViewportController(
      onUnavailable: () => unavailableCount++,
    );
    await controller.attach(viewId: 7);

    await controller.update(
      camera.copyWith(viewportSize: const Size(double.nan, 800), revision: 4),
      sourceOrigin: origin,
    );

    expect(unavailableCount, 1);
    controller.dispose();
  });

  testWidgets('unknown region은 widget unavailable callback을 호출한다', (
    tester,
  ) async {
    var unavailableCount = 0;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: RouteMapSvgViewport(
            region: '알 수 없음',
            camera: camera,
            sourceOrigin: origin,
            onUnavailable: () => unavailableCount++,
          ),
        ),
      );
      await tester.pump();
      expect(unavailableCount, 1);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('unsupported platform은 widget unavailable callback을 호출한다', (
    tester,
  ) async {
    var unavailableCount = 0;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: RouteMapSvgViewport(
            region: '수도권',
            camera: camera,
            sourceOrigin: origin,
            onUnavailable: () => unavailableCount++,
          ),
        ),
      );
      await tester.pump();
      expect(unavailableCount, 1);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('첫 ack 뒤 camera 갱신은 이전 SVG와 overlay를 계속 표시한다', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    const viewId = 91;
    const channelName =
        'com.easysubway.easysubway_mobile/route_map_viewport_webview/91';
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel(channelName),
      (_) async => null,
    );
    try {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: RouteMapSvgViewport(
            region: '수도권',
            camera: camera,
            sourceOrigin: origin,
            onUnavailable: () {},
            overlay: const Text('overlay-3', key: Key('synchronizedOverlay')),
          ),
        ),
      );
      final visibility = tester.widget<Visibility>(find.byType(Visibility));
      expect(visibility.visible, isFalse);
      expect(
        find.descendant(
          of: find.byType(Visibility),
          matching: find.byType(IgnorePointer),
        ),
        findsAtLeastNWidgets(1),
      );
      expect(
        find.descendant(
          of: find.byType(Visibility),
          matching: find.byType(ExcludeSemantics),
        ),
        findsAtLeastNWidgets(1),
      );
      final androidView = tester.widget<AndroidView>(find.byType(AndroidView));
      expect(androidView.creationParams, <String, Object>{
        'assetPath': 'assets/datapacks/metro_map_pack/basemap/seoul.svg',
        'mimeType': 'image/svg+xml',
        'sourceWidth': 200.0,
        'sourceHeight': 200.0,
        ...routeMapSvgViewportCameraPayload(
          camera: camera,
          sourceOrigin: origin,
        ),
      });

      androidView.onPlatformViewCreated!(viewId);
      await messenger.handlePlatformMessage(
        channelName,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('framePresented', <String, Object>{'revision': 3}),
        ),
        (_) {},
      );
      await tester.pump();
      expect(
        tester.widget<Visibility>(find.byType(Visibility)).visible,
        isTrue,
      );

      final nextCamera = camera.copyWith(revision: 4);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: RouteMapSvgViewport(
            region: '수도권',
            camera: nextCamera,
            sourceOrigin: origin,
            onUnavailable: () {},
            overlay: const Text('overlay-4', key: Key('synchronizedOverlay')),
          ),
        ),
      );
      expect(
        tester.widget<Visibility>(find.byType(Visibility)).visible,
        isTrue,
      );
      expect(find.text('overlay-3'), findsOneWidget);
      expect(find.text('overlay-4'), findsNothing);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: RouteMapSvgViewport(
            region: '수도권',
            camera: nextCamera,
            sourceOrigin: origin,
            onUnavailable: () {},
            overlay: const Text('overlay-4b', key: Key('synchronizedOverlay')),
          ),
        ),
      );
      expect(find.text('overlay-3'), findsOneWidget);
      expect(find.text('overlay-4'), findsNothing);
      expect(find.text('overlay-4b'), findsNothing);

      await messenger.handlePlatformMessage(
        channelName,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('framePresented', <String, Object>{'revision': 3}),
        ),
        (_) {},
      );
      await tester.pump();
      expect(
        tester.widget<Visibility>(find.byType(Visibility)).visible,
        isTrue,
      );
      expect(find.text('overlay-3'), findsOneWidget);
      expect(find.text('overlay-4'), findsNothing);

      await messenger.handlePlatformMessage(
        channelName,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('framePresented', <String, Object>{'revision': 4}),
        ),
        (_) {},
      );
      await tester.pump();
      final synchronizedVisibility = tester.widget<Visibility>(
        find.ancestor(
          of: find.byKey(const Key('synchronizedOverlay')),
          matching: find.byType(Visibility),
        ),
      );
      expect(synchronizedVisibility.visible, isTrue);
      expect(find.text('overlay-3'), findsNothing);
      expect(find.text('overlay-4'), findsNothing);
      expect(find.text('overlay-4b'), findsOneWidget);
    } finally {
      messenger.setMockMethodCallHandler(
        const MethodChannel(channelName),
        null,
      );
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
