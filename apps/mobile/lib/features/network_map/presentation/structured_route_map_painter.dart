import 'dart:math' as math;

import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/widgets.dart';

import '../../stations/domain/station_line.dart' show stationLineColor;
import '../domain/map_camera.dart';
import '../domain/structured_route_map.dart';
import 'route_map_label_placement.dart';

// 구조화 노선도 native canvas 렌더러 코어 (#1641 Stage 2).
//
// WebView SVG 렌더러를 대체하는 CustomPainter. 이 파일은 선(line path)과
// 역 점(station point) 레이어를 viewport culling + LOD로 그린다. 라벨/환승
// 노드/경로 강조는 Stage 3, controller 이벤트·접근성은 Stage 4에서 얹는다.
/// line_id → hex 색 문자열 맵을 렌더러용 [Color] 맵으로 변환한다.
/// 기존 [stationLineColor] 파서를 재사용한다(hex 파싱·fallback 일원화).
Map<String, Color> routeMapLineColors(Map<String, String> hexColorByLineId) {
  return {
    for (final entry in hexColorByLineId.entries)
      entry.key: stationLineColor(entry.value),
  };
}

/// 카메라 scale을 #1636 LOD zoom bucket(0/1/2)으로 매핑한다.
/// 0 = 최소 확대(선·환승만), 1 = 중간, 2 = 최대 확대(전체 역).
int routeMapZoomBucket(MapCameraState camera) {
  final range = camera.maxScale - camera.minScale;
  if (range <= 0) {
    return 2;
  }
  final t = ((camera.scale - camera.minScale) / range).clamp(0.0, 1.0);
  if (t < 1 / 3) {
    return 0;
  }
  if (t < 2 / 3) {
    return 1;
  }
  return 2;
}

/// 라벨 우선순위(낮을수록 먼저 자리 차지): 환승 0 > 주요 1 > 일반 2.
int routeMapLabelPriorityFor(RouteMapLabelClass labelClass) {
  switch (labelClass) {
    case RouteMapLabelClass.transfer:
      return 0;
    case RouteMapLabelClass.major:
      return 1;
    case RouteMapLabelClass.regular:
      return 2;
  }
}

/// #1642 라벨 렌더 경로의 순수 후보 생성. painter의 `_paintLabels`와 동일한
/// bucket·LOD·환승/역 규칙으로 [RouteMapLabelCandidate] 목록을 만든다. 텍스트
/// 실측([measure])·가시성([isVisible])만 주입받아 순수 함수라, 테스트가 지역·
/// zoom bucket별로 후보 구성과 (placeRouteMapLabels 후) 겹침 0을 기계 판정할 수
/// 있다. bucket 0(선만)이나 텍스트 없는 역은 후보에서 제외한다.
List<RouteMapLabelCandidate> routeMapLabelCandidates(
  StructuredRouteMap map,
  MapCameraState camera,
  int bucket, {
  required Map<String, String> labelTextByStationId,
  required Size Function(String id, String text) measure,
  required bool Function(Offset source) isVisible,
  required double stationRadius,
  required double transferAnchorPadding,
}) {
  final candidates = <RouteMapLabelCandidate>[];
  if (bucket < 1) {
    return candidates;
  }
  if (bucket >= minLabelZoomBucketFor(RouteMapLabelClass.transfer)) {
    for (final group in map.transferGroups) {
      if (!isVisible(group.centroid)) {
        continue;
      }
      final text = labelTextByStationId[group.stationId];
      if (text == null || text.isEmpty) {
        continue;
      }
      final id = 'transfer:${group.stationId}';
      candidates.add(
        RouteMapLabelCandidate(
          id: id,
          anchor: camera.sourceToViewportPoint(group.centroid),
          size: measure(id, text),
          priority: routeMapLabelPriorityFor(RouteMapLabelClass.transfer),
          anchorPadding: transferAnchorPadding,
        ),
      );
    }
  }
  for (final station in map.stations) {
    if (station.labelClass == RouteMapLabelClass.transfer) {
      continue;
    }
    if (bucket < minLabelZoomBucketFor(station.labelClass)) {
      continue;
    }
    if (!isVisible(station.position)) {
      continue;
    }
    final text = labelTextByStationId[station.stationId];
    if (text == null || text.isEmpty) {
      continue;
    }
    final id = '${station.stationId}:${station.lineId}';
    candidates.add(
      RouteMapLabelCandidate(
        id: id,
        anchor: camera.sourceToViewportPoint(station.position),
        size: measure(id, text),
        priority: routeMapLabelPriorityFor(station.labelClass),
        anchorPadding: stationRadius,
      ),
    );
  }
  return candidates;
}

/// polyline의 bounding box가 [rect]와 겹치는지 — viewport culling 판정.
bool routeMapPolylineIntersectsRect(List<Offset> polyline, Rect rect) {
  if (polyline.isEmpty) {
    return false;
  }
  var minX = polyline.first.dx;
  var maxX = polyline.first.dx;
  var minY = polyline.first.dy;
  var maxY = polyline.first.dy;
  for (final point in polyline) {
    if (point.dx < minX) minX = point.dx;
    if (point.dx > maxX) maxX = point.dx;
    if (point.dy < minY) minY = point.dy;
    if (point.dy > maxY) maxY = point.dy;
  }
  return maxX >= rect.left &&
      minX <= rect.right &&
      maxY >= rect.top &&
      minY <= rect.bottom;
}

/// 구조화 노선도 line/station layer를 그리는 CustomPainter.
class StructuredRouteMapPainter extends CustomPainter {
  StructuredRouteMapPainter({
    required this.map,
    required this.camera,
    required this.lineColors,
    this.labelTextByStationId = const {},
    this.attributionText,
    this.lineWidth = 4.0,
    this.stationRadius = 3.0,
    this.transferStationRadius = 5.0,
    this.labelStyle = _defaultLabelStyle,
    this.attributionStyle = _defaultAttributionStyle,
    Map<String, TextPainter>? labelPainterCache,
  }) : _labelPainters = labelPainterCache ?? {};

  final StructuredRouteMap map;
  final MapCameraState camera;

  /// line_id → 색. 없으면 노선 색 fallback을 쓴다.
  final Map<String, Color> lineColors;

  /// station_id → 역명. 비어 있으면 라벨을 그리지 않는다.
  final Map<String, String> labelTextByStationId;

  /// 출처 표기(#1637 attribution 필요 지역). null/빈 문자열이면 그리지 않는다.
  final String? attributionText;
  final double lineWidth;
  final double stationRadius;
  final double transferStationRadius;
  final TextStyle labelStyle;
  final TextStyle attributionStyle;

  static const Color _transferFill = Color(0xFFFFFFFF);
  static const Color _transferBorder = Color(0xFF102A2C);
  static const Color _fallbackLineColor = Color(0xFF8D8D8D);
  static const double _transferBorderWidth = 2.0;
  static const double _labelGap = 4.0;
  static const TextStyle _defaultLabelStyle = TextStyle(
    color: Color(0xFF102A2C),
    fontSize: 11,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle _defaultAttributionStyle = TextStyle(
    color: Color(0xFF466467),
    fontSize: 10,
  );

  // 텍스트 실측은 비싸므로 TextPainter를 캐시한다. 외부(StatefulWidget)가 캐시를
  // 주입하면 rebuild 간에도 유지되고 소유자가 dispose한다. 없으면 인스턴스 수명용.
  final Map<String, TextPainter> _labelPainters;

  // 프레임마다 재할당하지 않도록 Paint를 인스턴스/정적 필드로 hoist한다.
  final Paint _linePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = StrokeCap.round
    ..isAntiAlias = true;
  final Paint _regularStationPaint = Paint()
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;
  static final Paint _transferFillPaint = Paint()
    ..style = PaintingStyle.fill
    ..color = _transferFill
    ..isAntiAlias = true;
  static final Paint _transferBorderPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = _transferBorderWidth
    ..color = _transferBorder
    ..isAntiAlias = true;

  @override
  void paint(Canvas canvas, Size size) {
    // stroke 폭·점 반지름은 viewport px이므로 source 단위로 환산해 culling
    // rect를 넓힌다. 경계에서 선 끝·반원이 튀는(pop) 현상 방지.
    final maxViewportExtent = math.max(
      lineWidth / 2,
      math.max(stationRadius, transferStationRadius),
    );
    final margin = maxViewportExtent / camera.scale;
    final visible = camera.visibleSourceRect.inflate(margin);
    _paintLines(canvas, visible);
    _paintStations(canvas, visible);
    _paintLabels(canvas, size, visible);
    _paintAttribution(canvas, size);
  }

  void _paintLines(Canvas canvas, Rect visible) {
    _linePaint.strokeWidth = lineWidth;
    for (final line in map.lines) {
      _linePaint.color = lineColors[line.lineId] ?? _fallbackLineColor;
      for (final polyline in line.polylines) {
        // viewport 밖 sub-polyline은 그리지 않는다 (culling).
        if (!routeMapPolylineIntersectsRect(polyline, visible)) {
          continue;
        }
        final path = Path();
        var isFirst = true;
        for (final point in polyline) {
          final viewportPoint = camera.sourceToViewportPoint(point);
          if (isFirst) {
            path.moveTo(viewportPoint.dx, viewportPoint.dy);
            isFirst = false;
          } else {
            path.lineTo(viewportPoint.dx, viewportPoint.dy);
          }
        }
        canvas.drawPath(path, _linePaint);
      }
    }
  }

  void _paintStations(Canvas canvas, Rect visible) {
    final bucket = routeMapZoomBucket(camera);

    // 일반(비환승) 역 점: LOD는 도메인 helper 단일 소스를 재사용한다.
    // 환승 노드는 transferGroups에서 한 번만 그리므로 여기서 건너뛴다.
    for (final station in map.stations) {
      if (station.labelClass == RouteMapLabelClass.transfer) {
        continue;
      }
      if (bucket < minLabelZoomBucketFor(station.labelClass)) {
        continue;
      }
      if (!visible.contains(station.position)) {
        continue;
      }
      _regularStationPaint.color =
          lineColors[station.lineId] ?? _fallbackLineColor;
      canvas.drawCircle(
        camera.sourceToViewportPoint(station.position),
        stationRadius,
        _regularStationPaint,
      );
    }

    // 환승 마커: 물리 역당 한 번, transferGroups 중심 좌표에 그린다.
    if (bucket < minLabelZoomBucketFor(RouteMapLabelClass.transfer)) {
      return;
    }
    for (final group in map.transferGroups) {
      if (!visible.contains(group.centroid)) {
        continue;
      }
      final center = camera.sourceToViewportPoint(group.centroid);
      canvas.drawCircle(center, transferStationRadius, _transferFillPaint);
      canvas.drawCircle(center, transferStationRadius, _transferBorderPaint);
    }
  }

  void _paintLabels(Canvas canvas, Size size, Rect visible) {
    if (labelTextByStationId.isEmpty) {
      return;
    }
    final bucket = routeMapZoomBucket(camera);
    // 후보 생성은 순수 함수 routeMapLabelCandidates로 공유 — painter와 테스트가
    // 동일 bucket·LOD·환승/역 규칙을 태운다(#1642 겹침 0 기계 판정 가능).
    final painterById = <String, TextPainter>{};
    final candidates = routeMapLabelCandidates(
      map,
      camera,
      bucket,
      labelTextByStationId: labelTextByStationId,
      isVisible: visible.contains,
      stationRadius: stationRadius,
      transferAnchorPadding: transferStationRadius + _transferBorderWidth,
      measure: (id, text) => (painterById[id] ??= _labelPainter(text)).size,
    );

    final placed = placeRouteMapLabels(
      candidates,
      gap: _labelGap,
      viewportBounds: Offset.zero & size,
    );
    for (final label in placed) {
      painterById[label.candidate.id]?.paint(canvas, label.rect.topLeft);
    }
  }

  void _paintAttribution(Canvas canvas, Size size) {
    final text = attributionText;
    if (text == null || text.isEmpty) {
      return;
    }
    final painter = _labelPainters.putIfAbsent(
      'attribution:$text',
      () => TextPainter(
        text: TextSpan(text: text, style: attributionStyle),
        textDirection: TextDirection.ltr,
      )..layout(),
    );
    const padding = 4.0;
    final origin = Offset(
      padding + 2,
      // 아주 작은 뷰포트에서 위로 넘어가지 않도록 하한을 둔다.
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

  TextPainter _labelPainter(String text) {
    return _labelPainters.putIfAbsent(
      text,
      () => TextPainter(
        text: TextSpan(text: text, style: labelStyle),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(),
    );
  }

  @override
  bool shouldRepaint(StructuredRouteMapPainter oldDelegate) {
    return oldDelegate.camera.revision != camera.revision ||
        !identical(oldDelegate.map, map) ||
        !mapEquals(oldDelegate.lineColors, lineColors) ||
        !mapEquals(oldDelegate.labelTextByStationId, labelTextByStationId) ||
        oldDelegate.attributionText != attributionText ||
        oldDelegate.labelStyle != labelStyle ||
        oldDelegate.attributionStyle != attributionStyle ||
        oldDelegate.lineWidth != lineWidth ||
        oldDelegate.stationRadius != stationRadius ||
        oldDelegate.transferStationRadius != transferStationRadius;
  }
}

/// 구조화 노선도 canvas 뷰. [camera]/[map]을 받아 [StructuredRouteMapPainter]로
/// 그린다. WebView 없이 native로 렌더링한다.
///
/// TextPainter 캐시를 State가 소유해 rebuild 간에 유지하고 dispose 시 정리한다
/// (painter는 프레임마다 새로 만들어지므로 캐시를 인스턴스에 두면 유지되지 않고
/// native paragraph 핸들이 누수된다).
class StructuredRouteMapView extends StatefulWidget {
  const StructuredRouteMapView({
    required this.map,
    required this.camera,
    required this.lineColors,
    this.labelTextByStationId = const {},
    this.attributionText,
    super.key,
  });

  final StructuredRouteMap map;
  final MapCameraState camera;
  final Map<String, Color> lineColors;
  final Map<String, String> labelTextByStationId;
  final String? attributionText;

  @override
  State<StructuredRouteMapView> createState() => _StructuredRouteMapViewState();
}

class _StructuredRouteMapViewState extends State<StructuredRouteMapView> {
  final Map<String, TextPainter> _labelPainters = {};

  @override
  void dispose() {
    for (final painter in _labelPainters.values) {
      painter.dispose();
    }
    _labelPainters.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: widget.camera.viewportSize,
      painter: StructuredRouteMapPainter(
        map: widget.map,
        camera: widget.camera,
        lineColors: widget.lineColors,
        labelTextByStationId: widget.labelTextByStationId,
        attributionText: widget.attributionText,
        labelPainterCache: _labelPainters,
      ),
    );
  }
}
