import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../stations/domain/station_line.dart' show stationLineColor;
import '../domain/map_camera.dart';
import '../domain/route_map_design_space.dart';
import '../domain/route_map_parallel_offsets.dart';
import '../domain/structured_route_map.dart';
import 'route_map_label_layout.dart';
import 'route_map_transfer_marker.dart';

// 구조화 노선도 정적 스케일 렌더러 (#1789 스펙 S6).
//
// 모든 레이어(선·노드·캡슐·역명·뱃지)를 design space에 고정 배치해 [ui.Picture]로
// 1회 녹화하고, 매 프레임은 카메라 transform + drawPicture만 재생한다. LOD·viewport
// culling·프레임당 라벨 배치는 폐지됐다 — 줌·팬 중 라벨 소멸/겹침/점프/렉을 구조적
// 으로 제거한다("설계 스케일에서 충돌 0이면 모든 줌에서 충돌 0", 균등 스케일 불변성).

/// line_id → hex 색 문자열 맵을 렌더러용 [Color] 맵으로 변환한다.
/// 기존 [stationLineColor] 파서를 재사용한다(hex 파싱·fallback 일원화).
Map<String, Color> routeMapLineColors(Map<String, String> hexColorByLineId) {
  return {
    for (final entry in hexColorByLineId.entries)
      entry.key: stationLineColor(entry.value),
  };
}

/// 노선 식별 뱃지 라벨(#1764 D). `lines.name_ko`(`<지역> <노선>` 형식)를
/// 화면 뱃지용 2~4자 표기로 결정적 축약한다:
/// - 지역 접두(첫 공백 앞)를 뗀다: "수도권 1호선" → "1호선".
/// - 숫자 호선은 접두+숫자: "1호선"→"1", "인천1호선"→"인천1".
/// - GTX 계열은 전체 유지: "GTX-A"→"GTX-A".
/// - 그 외는 노선 표기 앞 4자: "수인분당"→"수인분당", "부산김해경전철"→"부산김해".
/// 순수 함수라 전 노선 입력→출력을 스냅샷 테스트로 고정한다.
String routeMapLineBadgeLabel(String nameKo) {
  final trimmed = nameKo.trim();
  final spaceIndex = trimmed.indexOf(' ');
  final line = spaceIndex >= 0
      ? trimmed.substring(spaceIndex + 1).trim()
      : trimmed;
  if (line.isEmpty) {
    return trimmed;
  }
  final hosun = RegExp(r'^(\D*?)(\d+)호선').firstMatch(line);
  if (hosun != null) {
    return '${hosun.group(1)}${hosun.group(2)}';
  }
  if (line.startsWith('GTX')) {
    return line;
  }
  return line.length <= 4 ? line : line.substring(0, 4);
}

/// 노선도 라벨용 역명 축약: '역명(부역명)' → '역명'(#1789). 준지리형 외곽 역의
/// 긴 부역명이 라벨 겹침의 주원인이라 괄호 부역명을 떼어 표시한다(부역명은 역
/// 탭 정보에서 제공). 첫 '(' 이전만 취하고, '('가 없거나 맨 앞이면 원문 유지.
String routeMapStationLabel(String nameKo) {
  final i = nameKo.indexOf('(');
  return i <= 0 ? nameKo : nameKo.substring(0, i);
}

// 스타일 상수 (design px — 캘리브레이션 상수 소비).
const TextStyle _labelStyle = TextStyle(
  color: Color(0xFF102A2C),
  fontSize: kRouteMapDesignLabelFontPx,
  fontWeight: FontWeight.w500,
);
const TextStyle _boldLabelStyle = TextStyle(
  color: Color(0xFF102A2C),
  fontSize: kRouteMapDesignLabelFontPx,
  fontWeight: FontWeight.w700,
);
const TextStyle _badgeStyle = TextStyle(
  color: Color(0xFFFFFFFF),
  fontSize: kRouteMapDesignBadgeFontPx,
  fontWeight: FontWeight.w700,
);
const TextStyle _attributionStyle = TextStyle(
  color: Color(0xFF466467),
  fontSize: 10,
);

const Color _fallbackLineColor = Color(0xFF8D8D8D);
const Color _transferFill = Color(0xFFFFFFFF);
const Color _transferBorder = Color(0xFF102A2C);
const Color _regularStationFill = Color(0xFFFFFFFF);
// 환승 캡슐 실측 비율(선8·도트10·캡슐짧은축19·간격13 → 선 4px 환산, #1792 G3).
// 도트 크기 상수는 route_map_transfer_marker.dart의 kRouteMapTransferDot*Px 재사용.
const double _transferBorderWidth = 1.5;
const double _regularStationBorderWidth = 1.6;

final Paint _regularStationFillPaint = Paint()
  ..style = PaintingStyle.fill
  ..color = _regularStationFill
  ..isAntiAlias = true;
final Paint _regularStationBorderPaint = Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = _regularStationBorderWidth
  ..isAntiAlias = true;
final Paint _transferFillPaint = Paint()
  ..style = PaintingStyle.fill
  ..color = _transferFill
  ..isAntiAlias = true;
final Paint _transferBorderPaint = Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = _transferBorderWidth
  ..color = _transferBorder
  ..isAntiAlias = true;
// 대분산 환승(물리적으로 먼 두 역)의 도보 연결 표현 — 얇은 회색 선.
final Paint _transferConnectorPaint = Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = _transferBorderWidth
  ..color = _transferBorder.withValues(alpha: 0.45)
  ..isAntiAlias = true;

/// design space에서 전 레이어를 1회 녹화한다 (#1789 스펙 S6).
/// 프레임 루프에는 이 Picture의 재생만 남는다. 호출자가 dispose 책임.
ui.Picture recordRouteMapPicture({
  required StructuredRouteMap map,
  required RouteMapDesignSpace design,
  required RouteMapStaticLabelLayout layout,
  required Map<String, Color> lineColors,
  required Map<String, List<List<Offset>>> lineOffsets,
}) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final linePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = kRouteMapDesignLineWidthPx
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = StrokeCap.round
    ..isAntiAlias = true;

  // 1) 선: 정점을 design으로 투영 + G4 평행 오프셋(design px 그대로 적용).
  for (final line in map.lines) {
    linePaint.color = lineColors[line.lineId] ?? _fallbackLineColor;
    final offsetsByPolyline = lineOffsets[line.lineId];
    for (var p = 0; p < line.polylines.length; p += 1) {
      final polyline = line.polylines[p];
      if (polyline.isEmpty) continue;
      final vertexOffsets =
          offsetsByPolyline != null && p < offsetsByPolyline.length
          ? offsetsByPolyline[p]
          : null;
      final path = Path();
      for (var v = 0; v < polyline.length; v += 1) {
        var point = design.toDesign(polyline[v]);
        if (vertexOffsets != null && v < vertexOffsets.length) {
          point += vertexOffsets[v] * kRouteMapDesignLineWidthPx;
        }
        v == 0
            ? path.moveTo(point.dx, point.dy)
            : path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, linePaint);
    }
  }

  // 2) 일반역 노드(흰 채움 + 노선색 테두리) — 상시 표시(스펙 S5).
  for (final station in map.stations) {
    if (station.labelClass == RouteMapLabelClass.transfer) continue;
    final center = design.toDesign(station.position);
    canvas.drawCircle(
      center,
      kRouteMapDesignStationRadiusPx,
      _regularStationFillPaint,
    );
    _regularStationBorderPaint.color =
        lineColors[station.lineId] ?? _fallbackLineColor;
    canvas.drawCircle(
      center,
      kRouteMapDesignStationRadiusPx,
      _regularStationBorderPaint,
    );
  }

  // 3) 환승 흰 원(서울메트로 룩) — 간선 색 선이 만나는 지점에 흰 채움+짙은 테두리
  //    원을 얹는다. 수렴·소분산은 원 1개, 대분산(물리적으로 먼 환승)은 멤버별 원 +
  //    centroid 연결선(공식 지도의 도보 연결 표현).
  for (final group in map.transferGroups) {
    final marker = routeMapTransferRings(
      members: [for (final p in group.memberPositions) design.toDesign(p)],
    );
    // 연결선을 먼저(원 아래).
    for (final connector in marker.connectors) {
      canvas.drawLine(connector.first, connector.last, _transferConnectorPaint);
    }
    for (final ring in marker.rings) {
      canvas.drawCircle(ring.center, ring.radius, _transferFillPaint);
      canvas.drawCircle(ring.center, ring.radius, _transferBorderPaint);
    }
  }

  // 4) 역명 라벨(볼드=환승·종착) — 녹화 시에만 TextPainter 생성·즉시 dispose.
  for (final label in layout.labels) {
    final painter = TextPainter(
      text: TextSpan(
        text: label.text,
        style: label.bold ? _boldLabelStyle : _labelStyle,
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    painter.paint(canvas, label.rect.topLeft);
    painter.dispose();
  }

  // 5) 노선 뱃지 pill.
  final badgeFill = Paint()
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;
  for (final badge in layout.badges) {
    badgeFill.color = lineColors[badge.lineId] ?? _fallbackLineColor;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        badge.rect,
        Radius.circular(badge.rect.height / 2),
      ),
      badgeFill,
    );
    final painter = TextPainter(
      text: TextSpan(text: badge.label, style: _badgeStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    painter.paint(
      canvas,
      badge.rect.center - Offset(painter.width / 2, painter.height / 2),
    );
    painter.dispose();
  }
  return recorder.endRecording();
}

/// 녹화된 design space [picture]를 카메라 transform으로 재생한다 (재생 전용).
class StructuredRouteMapPainter extends CustomPainter {
  StructuredRouteMapPainter({
    required this.picture,
    required this.designScale,
    required this.camera,
    this.attributionText,
  });

  final ui.Picture picture;
  final double designScale;
  final MapCameraState camera;
  final String? attributionText;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    final vc = camera.viewportSize.center(Offset.zero);
    // viewport = vc + (source − camera.center)·scale, design = source·k*
    //  → translate 후 scale/k* 배율로 Picture 재생.
    canvas.translate(
      vc.dx - camera.center.dx * camera.scale,
      vc.dy - camera.center.dy * camera.scale,
    );
    canvas.scale(camera.scale / designScale);
    canvas.drawPicture(picture);
    canvas.restore();
    _paintAttribution(canvas, size); // 화면 고정.
  }

  void _paintAttribution(Canvas canvas, Size size) {
    final text = attributionText;
    if (text == null || text.isEmpty) {
      return;
    }
    final painter = TextPainter(
      text: TextSpan(text: text, style: _attributionStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    const padding = 4.0;
    final origin = Offset(
      padding + 2,
      math.max(padding, size.height - painter.height - padding - 2),
    );
    final background = Rect.fromLTWH(
      origin.dx - 3,
      origin.dy - 2,
      painter.width + 6,
      painter.height + 4,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(background, const Radius.circular(3)),
      Paint()..color = const Color(0xCCFFFFFF),
    );
    painter.paint(canvas, origin);
    painter.dispose();
  }

  @override
  bool shouldRepaint(StructuredRouteMapPainter oldDelegate) {
    return oldDelegate.camera.revision != camera.revision ||
        !identical(oldDelegate.picture, picture) ||
        oldDelegate.designScale != designScale ||
        oldDelegate.attributionText != attributionText;
  }
}

/// 구조화 노선도 canvas 뷰. [map]에서 design·layout·picture를 1회 캐시하고
/// 카메라 변경 시 transform만 재생한다(정적 스케일 렌더, #1789).
class StructuredRouteMapView extends StatefulWidget {
  const StructuredRouteMapView({
    required this.map,
    required this.camera,
    required this.lineColors,
    this.labelTextByStationId = const {},
    this.lineBadgeLabelByLineId = const {},
    this.attributionText,
    super.key,
  });

  final StructuredRouteMap map;
  final MapCameraState camera;
  final Map<String, Color> lineColors;
  final Map<String, String> labelTextByStationId;
  final Map<String, String> lineBadgeLabelByLineId;
  final String? attributionText;

  @override
  State<StructuredRouteMapView> createState() => _StructuredRouteMapViewState();
}

class _StructuredRouteMapViewState extends State<StructuredRouteMapView> {
  StructuredRouteMap? _sourceMap;
  RouteMapDesignSpace? _design;
  ui.Picture? _picture;

  void _ensurePicture() {
    if (identical(_sourceMap, widget.map) && _picture != null) {
      return;
    }
    _picture?.dispose();
    _sourceMap = widget.map;
    final design = routeMapDesignSpaceFor(widget.map);
    _design = design;
    Size measureLabel(String text, {required bool bold}) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: bold ? _boldLabelStyle : _labelStyle),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      final size = painter.size;
      painter.dispose();
      return size;
    }

    Size measureBadge(String text) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: _badgeStyle),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      // pill 좌우 패딩 5px + 최소 지름 유지(기존 뱃지 규칙).
      final size = Size(
        math.max(kRouteMapDesignBadgeRadiusPx * 2, painter.size.width + 10),
        kRouteMapDesignBadgeRadiusPx * 2,
      );
      painter.dispose();
      return size;
    }

    final layout = solveRouteMapLabelLayout(
      map: widget.map,
      design: design,
      labelTextByStationId: widget.labelTextByStationId,
      badgeLabelByLineId: widget.lineBadgeLabelByLineId,
      measureLabel: measureLabel,
      measureBadge: measureBadge,
    );
    _picture = recordRouteMapPicture(
      map: widget.map,
      design: design,
      layout: layout,
      lineColors: widget.lineColors,
      lineOffsets: routeMapParallelLineOffsets(widget.map.lines),
    );
  }

  @override
  void dispose() {
    _picture?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _ensurePicture();
    return CustomPaint(
      size: widget.camera.viewportSize,
      painter: StructuredRouteMapPainter(
        picture: _picture!,
        designScale: _design!.designScale,
        camera: widget.camera,
        attributionText: widget.attributionText,
      ),
    );
  }
}
