import 'package:flutter/widgets.dart';

import '../../stations/domain/station_line.dart' show stationLineColor;
import '../domain/map_camera.dart';
import '../domain/structured_route_map.dart';

// 구조화 노선도 native canvas 렌더러 코어 (#1641 Stage 2).
//
// WebView SVG 렌더러를 대체하는 CustomPainter. 이 파일은 선(line path)과
// 역 점(station point) 레이어를 viewport culling + LOD로 그린다. 라벨/환승
// 노드/경로 강조는 Stage 3, controller 이벤트·접근성은 Stage 4에서 얹는다.
//
// 전환은 [RouteMapRendererKind] flag로 제어하며 기본값은 WebView다(병행 유지).
// QA(#1642/#1643) 통과 후 WebView 경로와 assets/datapacks/maps/*.svg를 제거한다.

/// 노선도 렌더러 선택 flag. 기본값 WebView 유지(#1641 전환 전략).
enum RouteMapRendererKind { webView, structuredCanvas }

const RouteMapRendererKind kDefaultRouteMapRenderer =
    RouteMapRendererKind.webView;

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
    this.lineWidth = 4.0,
    this.stationRadius = 3.0,
    this.transferStationRadius = 5.0,
  });

  final StructuredRouteMap map;
  final MapCameraState camera;

  /// line_id → 색. 없으면 노선 색 fallback을 쓴다.
  final Map<String, Color> lineColors;
  final double lineWidth;
  final double stationRadius;
  final double transferStationRadius;

  static const Color _transferFill = Color(0xFFFFFFFF);
  static const Color _transferBorder = Color(0xFF102A2C);
  static const Color _fallbackLineColor = Color(0xFF8D8D8D);

  @override
  void paint(Canvas canvas, Size size) {
    final visible = camera.visibleSourceRect;
    _paintLines(canvas, visible);
    _paintStations(canvas, visible);
  }

  void _paintLines(Canvas canvas, Rect visible) {
    for (final line in map.lines) {
      final paint = Paint()
        ..color = lineColors[line.lineId] ?? _fallbackLineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = lineWidth
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true;
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
        canvas.drawPath(path, paint);
      }
    }
  }

  void _paintStations(Canvas canvas, Rect visible) {
    final bucket = routeMapZoomBucket(camera);
    final fillPaint = Paint()..style = PaintingStyle.fill;
    final transferFillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = _transferFill;
    final transferBorderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = _transferBorder
      ..isAntiAlias = true;
    for (final station in map.stations) {
      final isTransfer = station.labelClass == RouteMapLabelClass.transfer;
      // LOD: 최소 확대(bucket 0)에서는 환승역 점만 그린다.
      if (bucket == 0 && !isTransfer) {
        continue;
      }
      // viewport 밖 역은 그리지 않는다 (culling).
      if (!visible.contains(station.position)) {
        continue;
      }
      final center = camera.sourceToViewportPoint(station.position);
      if (isTransfer) {
        canvas.drawCircle(center, transferStationRadius, transferFillPaint);
        canvas.drawCircle(center, transferStationRadius, transferBorderPaint);
      } else {
        fillPaint.color = lineColors[station.lineId] ?? _fallbackLineColor;
        canvas.drawCircle(center, stationRadius, fillPaint);
      }
    }
  }

  @override
  bool shouldRepaint(StructuredRouteMapPainter oldDelegate) {
    return oldDelegate.camera.revision != camera.revision ||
        !identical(oldDelegate.map, map) ||
        oldDelegate.lineColors != lineColors ||
        oldDelegate.lineWidth != lineWidth ||
        oldDelegate.stationRadius != stationRadius ||
        oldDelegate.transferStationRadius != transferStationRadius;
  }
}

/// 구조화 노선도 canvas 뷰. [camera]/[map]을 받아 [StructuredRouteMapPainter]로
/// 그린다. WebView 없이 native로 렌더링한다.
class StructuredRouteMapView extends StatelessWidget {
  const StructuredRouteMapView({
    required this.map,
    required this.camera,
    required this.lineColors,
    super.key,
  });

  final StructuredRouteMap map;
  final MapCameraState camera;
  final Map<String, Color> lineColors;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: camera.viewportSize,
      painter: StructuredRouteMapPainter(
        map: map,
        camera: camera,
        lineColors: lineColors,
      ),
    );
  }
}
