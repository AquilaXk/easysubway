import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../../core/perf/easy_subway_perf.dart';
import '../../stations/domain/station_line.dart' show stationLineColor;
import '../domain/map_camera.dart';
import '../domain/route_map_design_space.dart';
import '../domain/route_map_parallel_offsets.dart';
import '../domain/structured_route_map.dart';
import 'route_map_label_layout.dart';
import 'route_map_transfer_marker.dart';

/// profile 계측용. [easySubwayPerfLogsEnabled]일 때만 증가한다.
int debugStructuredRouteMapPictureBuildCount = 0;
int debugStructuredRouteMapPaintCount = 0;

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

/// #2068 SVG 충실도(2026-07-26 오너 결정): 바탕층 모드가 소비하는 **빈** 라벨
/// 레이아웃. 오너 SVG의 역명 라벨과 종점 마크가 .vec 바탕층에 그대로 구워지므로
/// 앱은 같은 글자를 다시 그리지 않는다("글자도 복붙" — 화면이 SVG와 픽셀 동일).
/// 라벨 솔버 자체는 구조화 노선도 모드(역 심벌을 앱이 그리는 모드)에서 그대로
/// 쓰인다. 게이트: test/features/network_map/presentation/
/// basemap_labels_are_baked_gate_test.dart.
const RouteMapStaticLabelLayout kRouteMapBasemapEmptyLabelLayout =
    RouteMapStaticLabelLayout(
      labels: [],
      badges: [],
      unresolvedOverlapCount: 0,
    );

/// 라벨 font-size로 스타일을 만든다. 색·굵기는 [_labelStyle]/[_boldLabelStyle]
/// 과 동일 — fontSize만 다르게 오버라이드한다.
TextStyle _labelStyleFor({required bool bold, required double fontSizePx}) =>
    (bold ? _boldLabelStyle : _labelStyle).copyWith(fontSize: fontSizePx);

/// 뱃지 font-size([kRouteMapDesignBadgeFontPx])로 스타일을 만든다.
TextStyle _badgeStyleFor({required double fontSizePx}) =>
    _badgeStyle.copyWith(fontSize: fontSizePx);

/// #2068: 솔버 시드 rect와 렌더가 정확히 같은 폰트 메트릭을 쓰도록, 라벨 실측을
/// [_labelStyleFor]를 통해 단일화한다. [StructuredRouteMapView]와 게이트 테스트가
/// 공유한다 — 테스트가 이 함수로 실측하면 앱과 100% 동일한 폭을 얻는다.
@visibleForTesting
Size measureRouteMapLabel(
  String text, {
  required bool bold,
  required double fontSize,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: _labelStyleFor(bold: bold, fontSizePx: fontSize),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  final size = painter.size;
  painter.dispose();
  return size;
}

/// #2068: 뱃지 pill 실측(폭 = max(최소지름, 텍스트폭+좌우패딩), 높이 = 최소지름).
/// pill 기하는 fontSize와 무관하게 불변 — 텍스트 크기만 통일한다(#2068 9차).
@visibleForTesting
Size measureRouteMapBadge(String text, {required double fontSize}) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: _badgeStyleFor(fontSizePx: fontSize),
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
final Paint _transferDotPaint = Paint()
  ..style = PaintingStyle.fill
  ..isAntiAlias = true;

// 환승 국소 corridor 우세 방향(design px) → 도트 가로/세로 결정. 멤버 노선들의
// centroid 최근접 선분 방향을 반원으로 접어(반대 방향 상쇄 방지) 평균한다.
bool _transferDotsHorizontal(
  StructuredRouteMap map,
  RouteMapTransferGroup group,
  RouteMapDesignSpace design,
) {
  final c = design.toDesign(group.centroid);
  var sx = 0.0, sy = 0.0;
  for (final line in map.lines) {
    if (!group.lineIds.contains(line.lineId)) continue;
    var best = double.infinity;
    var bestDir = Offset.zero;
    for (final poly in line.polylines) {
      for (var i = 1; i < poly.length; i += 1) {
        final a = design.toDesign(poly[i - 1]);
        final b = design.toDesign(poly[i]);
        final d = ((a + b) / 2 - c).distanceSquared;
        final seg = b - a;
        if (d < best && seg.distance > 0) {
          best = d;
          bestDir = seg / seg.distance;
        }
      }
    }
    if (bestDir.dx < 0 || (bestDir.dx == 0 && bestDir.dy < 0)) {
      bestDir = -bestDir; // 반원 접기
    }
    sx += bestDir.dx;
    sy += bestDir.dy;
  }
  return sx.abs() > sy.abs();
}

/// [recordRouteMapPicture]에 넘길 라벨 레이아웃을 고른다 — 프로덕션
/// ([_StructuredRouteMapViewState._ensurePicture])과 게이트 테스트가 **같은**
/// 함수를 소비해, 바탕층 라벨 미렌더 결정이 코드에서 사라지면 즉시 red가 되게
/// 한다(#2068 SVG 충실도, 2026-07-26 오너 결정).
///
/// [basemap]이 true(=역 심벌을 앱이 그리지 않는 바탕층 모드)면 솔버를 아예
/// 호출하지 않고 [kRouteMapBasemapEmptyLabelLayout]을 돌려준다 — 오너 SVG의
/// 역명 라벨이 .vec에 구워져 있어 앱이 같은 글자를 다시 그리면 이중 렌더이자
/// 오배치의 원인이 된다. false(구조화 노선도 모드)면 기존 솔버 결과 그대로다.
RouteMapStaticLabelLayout routeMapPictureLabelLayout({
  required bool basemap,
  required StructuredRouteMap map,
  required RouteMapDesignSpace design,
  required Map<String, String> labelTextByStationId,
  required Map<String, String> badgeLabelByLineId,
  required Size Function(
    String text, {
    required bool bold,
    required double fontSize,
  })
  measureLabel,
  required Size Function(String text, {required double fontSize}) measureBadge,
}) {
  if (basemap) {
    return kRouteMapBasemapEmptyLabelLayout;
  }
  return solveRouteMapLabelLayout(
    map: map,
    design: design,
    labelTextByStationId: labelTextByStationId,
    badgeLabelByLineId: badgeLabelByLineId,
    measureLabel: measureLabel,
    measureBadge: measureBadge,
  );
}

/// design space에서 전 레이어를 1회 녹화한다 (#1789 스펙 S6).
/// 프레임 루프에는 이 Picture의 재생만 남는다. 호출자가 dispose 책임.
ui.Picture recordRouteMapPicture({
  required StructuredRouteMap map,
  required RouteMapDesignSpace design,
  required RouteMapStaticLabelLayout layout,
  required Map<String, Color> lineColors,
  required Map<String, List<List<Offset>>> lineOffsets,
  bool drawLines = true,
  bool drawStationSymbols = true,
}) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  if (drawLines) {
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
  }

  if (drawStationSymbols) {
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

    // 3) 환승 캡슐 — 기존 routeMapTransferMarkers를 design 좌표로 호출.
    for (final group in map.transferGroups) {
      final markers = routeMapTransferMarkers(
        memberCenters: [
          for (final p in group.memberPositions) design.toDesign(p),
        ],
        colors: [
          for (final id in group.lineIds) lineColors[id] ?? _fallbackLineColor,
        ],
        designSpread:
            offsetsMaxPairwiseDistance(group.memberPositions) *
            design.designScale,
        dotRadius: kRouteMapTransferDotRadiusPx,
        dotGap: kRouteMapTransferDotGapPx,
        padding: kRouteMapTransferDotPaddingPx,
        horizontalDots: _transferDotsHorizontal(map, group, design),
      );
      for (final marker in markers) {
        canvas.drawRRect(marker.capsule, _transferFillPaint);
        canvas.drawRRect(marker.capsule, _transferBorderPaint);
        for (final dot in marker.dots) {
          _transferDotPaint.color = dot.color;
          canvas.drawCircle(
            dot.center,
            kRouteMapTransferDotRadiusPx,
            _transferDotPaint,
          );
        }
      }
    }
  }

  // 4) 역명 라벨(볼드=환승·종착) — 녹화 시에만 TextPainter 생성·즉시 dispose.
  // #2068 9차: label.fontSizePx로 그린다. 바탕층 모드는 layout 자체가
  // [kRouteMapBasemapEmptyLabelLayout](빈 목록)이라 이 루프가 돌지 않는다.
  for (final label in layout.labels) {
    final painter = TextPainter(
      text: TextSpan(
        text: label.text,
        style: _labelStyleFor(bold: label.bold, fontSizePx: label.fontSizePx),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    painter.paint(canvas, label.rect.topLeft);
    painter.dispose();
  }

  // 5) 노선 뱃지 pill. #2068 9차: badge.fontSizePx로 그린다.
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
      text: TextSpan(
        text: badge.label,
        style: _badgeStyleFor(fontSizePx: badge.fontSizePx),
      ),
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
    this.sourceOrigin = Offset.zero,
    this.attributionText,
    this.attributionPainter,
  });

  final ui.Picture picture;
  final double designScale;
  final MapCameraState camera;

  /// Picture는 raw source 좌표(`station.position·k*`)로 녹화되지만, 카메라와
  /// 오버레이(히트 rect·팝오버·핀)는 origin을 뺀 geometry 공간에서 동작한다(#1970).
  /// 이 origin을 재생 변환에 반영해 두 좌표계를 하나로 맞춘다. 기본 (0,0)은
  /// origin이 없는 맵(테스트 등)과의 하위호환을 유지한다.
  final Offset sourceOrigin;

  final String? attributionText;
  final TextPainter? attributionPainter;

  /// design space point(`source·k*`)를 카메라 재생 후 화면(viewport) 좌표로
  /// 변환한다. paint()의 재생 변환과 동일한 단일 수식이며(#1970 회귀 방지),
  /// `camera.sourceToViewportPoint(source − sourceOrigin)`와 항등이다.
  @visibleForTesting
  Offset designToViewport(Offset designPoint) {
    final vc = camera.viewportSize.center(Offset.zero);
    final source = designPoint / designScale;
    return vc + (source - sourceOrigin - camera.center) * camera.scale;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (easySubwayPerfLogsEnabled) {
      debugStructuredRouteMapPaintCount++;
      easySubwayPerfLog(
        'structured_route_map.paint #$debugStructuredRouteMapPaintCount',
      );
    }
    canvas.save();
    final vc = camera.viewportSize.center(Offset.zero);
    // viewport = vc + (source − sourceOrigin − camera.center)·scale,
    // design = source·k* → translate 후 scale/k* 배율로 Picture 재생.
    // sourceOrigin은 오버레이·카메라의 origin-뺀 공간과 raw picture 공간을 잇는다.
    canvas.translate(
      vc.dx - (camera.center.dx + sourceOrigin.dx) * camera.scale,
      vc.dy - (camera.center.dy + sourceOrigin.dy) * camera.scale,
    );
    canvas.scale(camera.scale / designScale);
    canvas.drawPicture(picture);
    canvas.restore();
    _paintAttribution(canvas, size); // 화면 고정.
  }

  void _paintAttribution(Canvas canvas, Size size) {
    final text = attributionText;
    final painter = attributionPainter;
    // painter는 State가 소유·재사용하는 캐시라 여기서 dispose하지 않는다(#1973).
    if (text == null || text.isEmpty || painter == null) {
      return;
    }
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
  }

  @override
  bool shouldRepaint(StructuredRouteMapPainter oldDelegate) {
    return oldDelegate.camera.revision != camera.revision ||
        !identical(oldDelegate.picture, picture) ||
        oldDelegate.designScale != designScale ||
        oldDelegate.sourceOrigin != sourceOrigin ||
        oldDelegate.attributionText != attributionText ||
        !identical(oldDelegate.attributionPainter, attributionPainter);
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
    this.drawLines = true,
    this.drawStationSymbols = true,
    this.sourceOrigin = Offset.zero,
    this.attributionText,
    super.key,
  });

  final StructuredRouteMap map;
  final MapCameraState camera;
  final Map<String, Color> lineColors;
  final Map<String, String> labelTextByStationId;
  final Map<String, String> lineBadgeLabelByLineId;
  final bool drawLines;
  final bool drawStationSymbols;

  /// 오버레이·카메라의 geometry origin. Picture 재생을 origin-뺀 공간으로 맞춰
  /// 캔버스와 오버레이 좌표계를 일치시킨다(#1970).
  final Offset sourceOrigin;

  final String? attributionText;

  @override
  State<StructuredRouteMapView> createState() => _StructuredRouteMapViewState();
}

class _StructuredRouteMapViewState extends State<StructuredRouteMapView> {
  StructuredRouteMap? _sourceMap;
  bool? _drawLines;
  bool? _drawStationSymbols;
  Map<String, Color>? _lineColors;
  Map<String, String>? _labelTextByStationId;
  Map<String, String>? _lineBadgeLabelByLineId;
  RouteMapDesignSpace? _design;
  ui.Picture? _picture;
  // attribution TextPainter는 region(텍스트) 변경 시에만 재생성한다. 매 pan 프레임의
  // TextPainter 생성·layout 할당을 제거하기 위한 캐시(#1973). State가 dispose를 소유한다.
  TextPainter? _attributionPainter;
  String? _attributionPainterText;
  int _pictureBuildGeneration = 0;

  bool _pictureInputsDiffer(
    StructuredRouteMapView a,
    StructuredRouteMapView b,
  ) {
    return !identical(a.map, b.map) ||
        a.drawLines != b.drawLines ||
        a.drawStationSymbols != b.drawStationSymbols ||
        !identical(a.lineColors, b.lineColors) ||
        !identical(a.labelTextByStationId, b.labelTextByStationId) ||
        !identical(a.lineBadgeLabelByLineId, b.lineBadgeLabelByLineId);
  }

  bool _cachedPictureInputsMatch(StructuredRouteMapView current) {
    return identical(_sourceMap, current.map) &&
        _drawLines == current.drawLines &&
        _drawStationSymbols == current.drawStationSymbols &&
        identical(_lineColors, current.lineColors) &&
        identical(_labelTextByStationId, current.labelTextByStationId) &&
        identical(_lineBadgeLabelByLineId, current.lineBadgeLabelByLineId);
  }

  @override
  void initState() {
    super.initState();
    // cold 진입 첫 프레임에서 label layout + picture record가 build를 막지 않게
    // 다음 프레임으로 미룬다. 그 사이 바탕(.vec)만 보여 체감 jank를 줄인다.
    _schedulePictureBuild();
  }

  @override
  void didUpdateWidget(StructuredRouteMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_pictureInputsDiffer(oldWidget, widget)) {
      _picture?.dispose();
      _picture = null;
      _sourceMap = null;
      _schedulePictureBuild();
    }
  }

  void _schedulePictureBuild({int retry = 0}) {
    final generation = ++_pictureBuildGeneration;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _pictureBuildGeneration) {
        return;
      }
      try {
        easySubwayPerfTimeSync('structured_route_map.picture_build', () {
          _ensurePicture();
        });
      } catch (error, stackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'network_map',
            context: ErrorDescription('구조화 노선도 picture 구축 실패'),
          ),
        );
        // map/flags가 안 바뀌어도 한 번은 다음 프레임에 재시도한다.
        // generation을 올리지 않고 같은 세대에서만 재시도해 최신 예약과 경합하지 않는다.
        if (retry < 1 && mounted && generation == _pictureBuildGeneration) {
          SchedulerBinding.instance.addPostFrameCallback((_) {
            if (!mounted || generation != _pictureBuildGeneration) {
              return;
            }
            try {
              easySubwayPerfTimeSync(
                'structured_route_map.picture_build_retry',
                () {
                  _ensurePicture();
                },
              );
              if (mounted && generation == _pictureBuildGeneration) {
                setState(() {});
              }
            } catch (error, stackTrace) {
              FlutterError.reportError(
                FlutterErrorDetails(
                  exception: error,
                  stack: stackTrace,
                  library: 'network_map',
                  context: ErrorDescription('구조화 노선도 picture 재시도 실패'),
                ),
              );
            }
          });
        }
        return;
      }
      if (!mounted || generation != _pictureBuildGeneration) {
        return;
      }
      setState(() {});
    });
  }

  void _ensurePicture() {
    if (_cachedPictureInputsMatch(widget) && _picture != null) {
      return;
    }
    _picture?.dispose();
    _sourceMap = widget.map;
    _drawLines = widget.drawLines;
    _drawStationSymbols = widget.drawStationSymbols;
    _lineColors = widget.lineColors;
    _labelTextByStationId = widget.labelTextByStationId;
    _lineBadgeLabelByLineId = widget.lineBadgeLabelByLineId;
    final design = routeMapDesignSpaceFor(widget.map);
    _design = design;
    // #2068 9차: fontSize를 인자로 받아 라벨별로 다른 크기로 실측한다 — 솔버
    // 시드 rect와 렌더가 같은 크기를 쓰도록 반드시 이 인자로 측정해야 한다.
    // 실측·렌더가 [measureRouteMapLabel]/[_labelStyleFor]로 단일화돼 게이트
    // 테스트와도 동일 메트릭을 공유한다.
    Size measureLabel(
      String text, {
      required bool bold,
      required double fontSize,
    }) => measureRouteMapLabel(text, bold: bold, fontSize: fontSize);

    Size measureBadge(String text, {required double fontSize}) =>
        measureRouteMapBadge(text, fontSize: fontSize);

    // #2068 SVG 충실도(2026-07-26 오너 결정): **바탕층 모드에서 앱은 역명 글자를
    // 그리지 않는다.** 오너 SVG의 역명 라벨이 .vec 바탕층에 그대로 구워지므로
    // (compile-basemap-vec.mjs의 MAP_BODY_LAYER_IDS에 라벨 레이어 포함), 앱이
    // 같은 글자를 다시 배치·렌더하면 이중 렌더이자 오배치의 원인이 된다 —
    // #1635에서 온 "라벨=구조화 렌더" 조항의 오너 공식 폐기다.
    // 유지되는 것: 역 탭 히트(_labelPolygonFor는 route_map_positions의
    // labelPolygon을 쓰고, labels.json은 networkMapOwnerLabelSourceRects로 히트
    // 소스 경계를 넓히는 데만 관여한다), 팬 메뉴, TalkBack semantics(시각
    // 텍스트와 무관), 경로 강조 오버레이, 초기 카메라 가독 배율(labels.json
    // fontSizePx 기반).
    // 노선 뱃지 pill도 오너 SVG가 자체 종점 마크를 그리므로 함께 비운다.
    // 분기 자체는 [routeMapPictureLabelLayout]에 있고 게이트 테스트가 그 함수와
    // [debugRouteMapLabelSolverInvocationCount]로 되돌림을 감시한다.
    final layout = routeMapPictureLabelLayout(
      basemap: !widget.drawStationSymbols,
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
      drawLines: widget.drawLines,
      drawStationSymbols: widget.drawStationSymbols,
    );
    if (easySubwayPerfLogsEnabled) {
      debugStructuredRouteMapPictureBuildCount++;
      easySubwayPerfLog(
        'structured_route_map.picture_build '
        '#$debugStructuredRouteMapPictureBuildCount',
      );
    }
  }

  void _ensureAttributionPainter() {
    final text = widget.attributionText;
    if (text == null || text.isEmpty) {
      if (_attributionPainter != null) {
        _attributionPainter!.dispose();
        _attributionPainter = null;
        _attributionPainterText = null;
      }
      return;
    }
    if (_attributionPainterText == text && _attributionPainter != null) {
      return;
    }
    _attributionPainter?.dispose();
    _attributionPainter = TextPainter(
      text: TextSpan(text: text, style: _attributionStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    _attributionPainterText = text;
  }

  @override
  void dispose() {
    _picture?.dispose();
    _attributionPainter?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _ensureAttributionPainter();
    final picture = _picture;
    final design = _design;
    // Picture 준비 전: 빈 레이어만 두어 첫 프레임 build를 가볍게 유지한다.
    // 바탕(.vec)은 형제 RouteMapBasemapView가 담당한다.
    if (picture == null || design == null) {
      return SizedBox.fromSize(size: widget.camera.viewportSize);
    }
    // RepaintBoundary로 지도 레이어를 부모 Stack의 형제 오버레이 rebuild와 분리한다.
    // isComplex/willChange 힌트로 정적 Picture 재생 레이어의 raster 캐싱을 돕는다(#1973).
    return RepaintBoundary(
      child: CustomPaint(
        size: widget.camera.viewportSize,
        isComplex: true,
        willChange: true,
        painter: StructuredRouteMapPainter(
          picture: picture,
          designScale: design.designScale,
          camera: widget.camera,
          sourceOrigin: widget.sourceOrigin,
          attributionText: widget.attributionText,
          attributionPainter: _attributionPainter,
        ),
      ),
    );
  }
}
