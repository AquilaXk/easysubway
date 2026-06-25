import 'package:easysubway_mobile/features/network_map/domain/map_camera.dart';
import 'package:easysubway_mobile/features/network_map/infrastructure/android_route_map_viewport_webview.dart';
import 'package:easysubway_mobile/features/network_map/infrastructure/route_map_renderer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const camera = MapCameraState(
    sourceBounds: Rect.fromLTWH(0, 0, 1000, 500),
    viewportSize: Size(250, 125),
    center: Offset(500, 250),
    scale: 0.5,
    minScale: 0.1,
    maxScale: 4,
    revision: 3,
  );

  test('creation params send source bounds and initial viewBox', () {
    expect(
      androidRouteMapViewportCreationParams(
        assetPath: 'assets/datapacks/maps/seoul-official-route-map.svg',
        mimeType: 'image/svg+xml',
        camera: camera,
      ),
      <String, Object?>{
        'assetPath': 'assets/datapacks/maps/seoul-official-route-map.svg',
        'mimeType': 'image/svg+xml',
        'sourceWidth': 1000.0,
        'sourceHeight': 500.0,
        'viewBox': <double>[250.0, 125.0, 500.0, 250.0],
        'revision': 3,
      },
    );
  });

  test(
    'camera update is needed when viewBox changes without revision change',
    () {
      expect(
        androidRouteMapViewportNeedsCameraUpdate(
          previous: camera,
          next: camera.copyWith(viewportSize: const Size(500, 125)),
        ),
        isTrue,
      );
    },
  );

  test('controller sends camera updates to the view channel', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel(
            'com.easysubway.easysubway_mobile/route_map_viewport_webview/7',
          ),
          (call) async {
            calls.add(call);
            return null;
          },
        );
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(
              'com.easysubway.easysubway_mobile/route_map_viewport_webview/7',
            ),
            null,
          );
    });

    final controller = AndroidRouteMapViewportController(7);
    await controller.setCamera(camera);
    await controller.retry();
    await controller.dispose();

    expect(calls.map((call) => call.method), <String>[
      'setCamera',
      'reload',
      'dispose',
    ]);
    expect(calls.first.arguments, <String, Object?>{
      'viewBox': <double>[250.0, 125.0, 500.0, 250.0],
      'revision': 3,
    });
  });

  test('controller emits frame acknowledgements from native view', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel(
            'com.easysubway.easysubway_mobile/route_map_viewport_webview/7',
          ),
          (_) async => null,
        );
    final controller = AndroidRouteMapViewportController(7);
    final frame = expectLater(
      controller.events,
      emits(isA<RouteMapRendererFramePresented>()),
    );

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'com.easysubway.easysubway_mobile/route_map_viewport_webview/7',
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('framePresented', <String, Object?>{
              'revision': 9,
            }),
          ),
          (_) {},
        );

    await frame;
    await controller.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel(
            'com.easysubway.easysubway_mobile/route_map_viewport_webview/7',
          ),
          null,
        );
  });

  test('controller emits created after listeners subscribe', () async {
    final controller = AndroidRouteMapViewportController(8);
    final created = expectLater(
      controller.events,
      emits(isA<RouteMapRendererCreated>()),
    );

    controller.emitCreated();

    await created;
    await controller.dispose();
    await expectLater(controller.events, emitsDone);
  });

  testWidgets('widget recreates platform view when asset identity changes', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: AndroidRouteMapViewportWebView(
          assetPath: 'assets/datapacks/maps/seoul-official-route-map.svg',
          mimeType: 'image/svg+xml',
          camera: camera,
        ),
      ),
    );

    final view = tester.widget<AndroidView>(find.byType(AndroidView));

    expect(
      view.key,
      const ValueKey<String>(
        'routeMapViewportWebView:assets/datapacks/maps/seoul-official-route-map.svg:image/svg+xml',
      ),
    );
    debugDefaultTargetPlatformOverride = null;
  });
}
