import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:easysubway_mobile/features/network_map/domain/route_map_design_space.dart';
import 'package:easysubway_mobile/features/network_map/domain/route_map_parallel_offsets.dart';
import 'package:easysubway_mobile/features/network_map/domain/structured_route_map.dart';
import 'package:easysubway_mobile/features/network_map/presentation/route_map_label_layout.dart';
import 'package:easysubway_mobile/features/network_map/presentation/structured_route_map_painter.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/capital_route_map_fixture.dart';

// #1876 S0 스파이크 육안 채증(golden). route-map-defs의 스파이크 팩(2·4·7호선 +
// 한강 guide)을 정적 스케일 렌더러(recordRouteMapPicture)로 그려 두 프레임을 고정한다:
//   ① 전체 뷰(스파이크 아트보드 전체, 종횡비 1.5)
//   ② 도심 프레이밍(2호선 루프 + 마진 — S0 판정 기준 프레임)
// 렌더러 프로덕션 코드는 건드리지 않는다(테스트 전용 소비). golden 이미지는 host
// 래스터라이저 의존이라 macOS 호스트에서만 비교한다(CI 크로스플랫폼 오탐 방지).
//
// 스파이크 팩 경로는 flutter test CWD(apps/mobile) 기준 리포 루트 상대다. 팩은
// assets에 등록돼 있지 않아 기존 실데이터/golden 계약에 영향을 주지 않는다.
const String _spikePackPath =
    '../../tools/route-map/route-map-defs/capital-s0-spike.sqlite.gz';

// 서울 2호선(도심 루프) line_id — 도심 프레이밍 기준.
const String _loopLineId = 'seoul-2';

Size _measureLabel(
  String text, {
  required bool bold,
  required double fontSize,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
      ),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  final size = painter.size;
  painter.dispose();
  return size;
}

Size _measureBadge(String text, {required double fontSize}) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w700),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  final size = Size(
    math.max(kRouteMapDesignBadgeRadiusPx * 2, painter.size.width + 10),
    kRouteMapDesignBadgeRadiusPx * 2,
  );
  painter.dispose();
  return size;
}

/// source-space [view]를 [canvas] 픽셀에 맞춰(비율 유지, 중앙 정렬) design space
/// [picture]를 래스터라이즈한다. design 좌표 = source × designScale.
Future<ui.Image> _renderFrame({
  required ui.Picture picture,
  required double designScale,
  required Rect view,
  required Size canvas,
}) {
  final designView = Rect.fromLTRB(
    view.left * designScale,
    view.top * designScale,
    view.right * designScale,
    view.bottom * designScale,
  );
  final scale = math.min(
    canvas.width / designView.width,
    canvas.height / designView.height,
  );
  final recorder = ui.PictureRecorder();
  final c = Canvas(recorder);
  c.drawRect(Offset.zero & canvas, Paint()..color = const Color(0xFFF4F7F7));
  c.translate(canvas.width / 2, canvas.height / 2);
  c.scale(scale);
  c.translate(-designView.center.dx, -designView.center.dy);
  c.drawPicture(picture);
  return recorder.endRecording().toImage(
    canvas.width.round(),
    canvas.height.round(),
  );
}

/// source-space에서 [predicate]에 맞는 역 위치의 bbox에 [marginRatio] 여백을 더한다.
Rect _boundsWithMargin(
  Iterable<RouteMapStructuredStation> stations,
  bool Function(RouteMapStructuredStation) predicate, {
  required double marginRatio,
}) {
  var minX = double.infinity, minY = double.infinity;
  var maxX = -double.infinity, maxY = -double.infinity;
  for (final s in stations) {
    if (!predicate(s)) continue;
    minX = math.min(minX, s.position.dx);
    minY = math.min(minY, s.position.dy);
    maxX = math.max(maxX, s.position.dx);
    maxY = math.max(maxY, s.position.dy);
  }
  final mx = (maxX - minX) * marginRatio;
  final my = (maxY - minY) * marginRatio;
  return Rect.fromLTRB(minX - mx, minY - my, maxX + mx, maxY + my);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final skipReason = Platform.isMacOS
      ? null
      : 'golden 비교는 macOS 호스트 래스터라이저에서만 (CI 크로스플랫폼 오탐 방지)';

  group('#1876 S0 스파이크 노선도 golden', () {
    late CapitalRouteMapFixture fixture;
    late RouteMapDesignSpace design;
    late ui.Picture picture;

    setUpAll(() {
      fixture = loadCapitalRouteMapFixture(packAssetPath: _spikePackPath);
      design = routeMapDesignSpaceFor(fixture.map);
      final layout = solveRouteMapLabelLayout(
        map: fixture.map,
        design: design,
        labelTextByStationId: fixture.labelTextByStationId,
        badgeLabelByLineId: fixture.badgeLabelByLineId,
        measureLabel: _measureLabel,
        measureBadge: _measureBadge,
      );
      picture = recordRouteMapPicture(
        map: fixture.map,
        design: design,
        layout: layout,
        lineColors: routeMapLineColors(fixture.lineColorHexById),
        lineOffsets: routeMapParallelLineOffsets(fixture.map.lines),
      );
    });

    tearDownAll(() => picture.dispose());

    test('전체 뷰: 스파이크 아트보드 전체', () async {
      final view = _boundsWithMargin(
        fixture.map.stations,
        (_) => true,
        marginRatio: 0.04,
      );
      final image = await _renderFrame(
        picture: picture,
        designScale: design.designScale,
        view: view,
        canvas: const Size(960, 640),
      );
      await expectLater(
        image,
        matchesGoldenFile('goldens/s0_spike_full_view.png'),
      );
    }, skip: skipReason);

    test('도심 프레이밍: 2호선 루프 + 마진', () async {
      final view = _boundsWithMargin(
        fixture.map.stations,
        (s) => s.lineId == _loopLineId,
        marginRatio: 0.12,
      );
      final image = await _renderFrame(
        picture: picture,
        designScale: design.designScale,
        view: view,
        canvas: const Size(720, 720),
      );
      await expectLater(
        image,
        matchesGoldenFile('goldens/s0_spike_loop_framing.png'),
      );
    }, skip: skipReason);
  });
}
