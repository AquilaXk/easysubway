import 'package:easysubway_mobile/features/network_map/domain/map_camera.dart';
import 'package:easysubway_mobile/features/network_map/infrastructure/route_map_svg_viewport.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _channelPrefix =
    'com.easysubway.easysubway_mobile/route_map_viewport_webview/';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('canonical SVG 정상 load는 framePresented 뒤 interactive map을 유지한다', (
    tester,
  ) async {
    await tester.pumpWidget(const _FailureBoundaryHarness());
    await tester.pumpAndSettle();
    await _waitForFramePresented(tester);

    expect(find.byKey(const Key('routeMapInteractiveSurface')), findsOneWidget);
    expect(find.text('노선도를 불러오지 못했어요'), findsNothing);
    final visibility = tester.widget<Visibility>(
      find.descendant(
        of: find.byType(RouteMapSvgViewport),
        matching: find.byType(Visibility),
      ),
    );
    expect(visibility.visible, isTrue);
  });

  for (final fault in <String>[
    'invalidAsset',
    'invalidViewBox',
    'debugProcessGone',
  ]) {
    testWidgets('$fault native event는 Dart failure boundary로 전체 지도 조작을 제거한다', (
      tester,
    ) async {
      await tester.pumpWidget(const _FailureBoundaryHarness());
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('routeMapInteractiveSurface')),
        findsOneWidget,
      );

      await _triggerNativeFault(fault);
      await tester.pumpAndSettle();

      expect(find.text('노선도를 불러오지 못했어요'), findsOneWidget);
      expect(find.byKey(const Key('routeMapInteractiveSurface')), findsNothing);
      expect(find.bySemanticsLabel('노선도'), findsNothing);
    });
  }
}

Future<void> _waitForFramePresented(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    final visibilityFinder = find.descendant(
      of: find.byType(RouteMapSvgViewport),
      matching: find.byType(Visibility),
    );
    if (visibilityFinder.evaluate().isNotEmpty &&
        tester.widget<Visibility>(visibilityFinder).visible) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await tester.pump();
  }
  fail('canonical SVG did not emit framePresented within 5 seconds');
}

Future<void> _triggerNativeFault(String kind) async {
  // Platform-view ids are engine-owned. Probe only this test's small allocation
  // range; a successful invocation proves the native per-view MethodChannel was
  // attached before the deferred debug fault is delivered.
  for (var viewId = 0; viewId < 16; viewId++) {
    try {
      await MethodChannel(
        '$_channelPrefix$viewId',
      ).invokeMethod<void>('debugFault', <String, Object>{'kind': kind});
      return;
    } on MissingPluginException {
      continue;
    }
  }
  fail('route-map platform view MethodChannel was not attached');
}

class _FailureBoundaryHarness extends StatefulWidget {
  const _FailureBoundaryHarness();

  @override
  State<_FailureBoundaryHarness> createState() =>
      _FailureBoundaryHarnessState();
}

class _FailureBoundaryHarnessState extends State<_FailureBoundaryHarness> {
  var _failed = false;

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return const MaterialApp(
        home: Scaffold(body: Center(child: Text('노선도를 불러오지 못했어요'))),
      );
    }
    return MaterialApp(
      home: Scaffold(
        body: Semantics(
          label: '노선도',
          child: GestureDetector(
            key: const Key('routeMapInteractiveSurface'),
            onTap: () {},
            child: RouteMapSvgViewport(
              region: '수도권',
              camera: MapCameraState(
                sourceBounds: const Rect.fromLTWH(0, 0, 200, 200),
                viewportSize: const Size(400, 800),
                center: const Offset(100, 100),
                scale: 4,
                minScale: 1,
                maxScale: 20,
                revision: 1,
              ),
              sourceOrigin: Offset.zero,
              onUnavailable: () => setState(() => _failed = true),
            ),
          ),
        ),
      ),
    );
  }
}
