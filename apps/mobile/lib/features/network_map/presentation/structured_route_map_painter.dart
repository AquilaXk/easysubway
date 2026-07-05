import 'dart:math' as math;

import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/widgets.dart';

import '../../stations/domain/station_line.dart' show stationLineColor;
import '../domain/map_camera.dart';
import '../domain/route_map_parallel_offsets.dart';
import '../domain/structured_route_map.dart';
import 'route_map_label_placement.dart';
import 'route_map_transfer_marker.dart';

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

/// bucket 1 진입 하한(초기 화면 대비 배율). 초기 화면(배율 1.0)은 bucket 0이라
/// 선 실루엣만 보이고, 이만큼 확대해야 환승 캡슐·노선 뱃지가 나타난다(#1789 LOD).
const double routeMapBucket1EnterRatio = 1.5;

/// bucket 2 진입 하한(초기 화면 대비 배율). 이만큼 확대해야 역 노드·역명이 나타난다.
const double routeMapBucket2EnterRatio = 3.0;

/// 카메라 scale을 LOD zoom bucket(0/1/2)으로 매핑한다(#1789 LOD 정비).
/// 절대 scale이 아니라 **지역 초기 화면(initialScale) 대비 배율** `r`로 판정해,
/// 지역 크기와 무관하게 일관된 LOD를 준다. **초기 화면 = bucket 0**(선 실루엣만)
/// 이라 고정 크기 노드·캡슐·라벨이 촘촘한 노선을 덮지 않는다. 확대할수록 캡슐·뱃지
/// (bucket 1) → 역 노드·역명(bucket 2)이 단계적으로 나타난다.
/// initialScale이 없으면(테스트 등) 현재 scale을 기준으로 봐 배율 1.0로 둔다.
int routeMapZoomBucket(MapCameraState camera) {
  final base = camera.initialScale ?? camera.scale;
  if (base <= 0) {
    return 2;
  }
  final r = camera.scale / base;
  if (r < routeMapBucket1EnterRatio) {
    return 0;
  }
  if (r < routeMapBucket2EnterRatio) {
    return 1;
  }
  return 2;
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

/// 일반역 노드(점)를 이 bucket에서 그리는지 여부(#1789 LOD 정비).
/// 축소(bucket 0·1)에선 고정 크기 노드가 촘촘한 역 간격을 덮어 노선을 가리므로
/// 생략하고, 최대 확대(bucket 2)에서만 표시한다. 환승 마커·라벨도 확대 시 표시.
bool routeMapShowsRegularStationNodes(int bucket) => bucket >= 2;

/// 환승 캡슐을 이 bucket에서 그리는지(#1789 LOD): bucket 0(선 실루엣)에선 캡슐도
/// 선을 덮으므로 생략하고, bucket 1부터 표시한다.
bool routeMapShowsTransferMarkers(int bucket) => bucket >= 1;

/// 라벨 우선순위(낮을수록 먼저 자리 차지): 노선 뱃지 -1 > 환승 0 > 주요 1 > 일반 2.
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
  // 역명 라벨은 최대 확대(bucket 2)에서만 — 축소에선 글자가 겹쳐 노선을 덮는다
  // (#1789 LOD). 노선 뱃지는 별도(전 bucket)라 축소에서도 노선 식별이 된다.
  if (bucket < 2) {
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

/// 노선 뱃지 후보(#1764 D)를 순수 함수로 생성한다. 각 노선 폴리라인 양 끝점에
/// priority -1(역명보다 먼저 배치) pill 후보를 만든다. 전 bucket 표시라 bucket
/// 인자를 받지 않는다. 끝점이 보이지 않으면([isVisible]=false) v1에서는 생략한다.
/// painter와 겹침 테스트가 동일 후보를 태우도록 [routeMapLabelCandidates]와
/// 같은 measure/isVisible 주입 패턴을 쓴다.
///
/// id 계약: `<idPrefix><lineId>:<start|end>`. painter는 이 id로 pill 색(lineId)을
/// 되찾으므로, [idPrefix]는 painter의 `_badgeIdPrefix`와 반드시 동일해야 한다.
/// 폐루프(순환선)는 시·종점이 같아 뱃지를 한 번만 둔다. 선행/후행 빈 sub-polyline은
/// 건너뛰고 첫/마지막 non-empty 세그먼트에서 끝점을 취한다.
List<RouteMapLabelCandidate> routeMapLineBadgeCandidates(
  StructuredRouteMap map,
  MapCameraState camera, {
  required Map<String, String> badgeLabelByLineId,
  required Size Function(String id, String text) measure,
  required bool Function(Offset source) isVisible,
  required double badgeRadius,
  double horizontalPadding = 5.0,
  String idPrefix = 'badge:',
}) {
  final candidates = <RouteMapLabelCandidate>[];
  if (badgeLabelByLineId.isEmpty) {
    return candidates;
  }
  final diameter = badgeRadius * 2;
  for (final line in map.lines) {
    final label = badgeLabelByLineId[line.lineId];
    if (label == null || label.isEmpty) {
      continue;
    }
    final start = _routeMapFirstVertex(line.polylines);
    final end = _routeMapLastVertex(line.polylines);
    if (start == null || end == null) {
      continue;
    }
    // 순환선(폐루프)은 시·종점이 같으므로 뱃지를 한 번만 둔다.
    final isLoop = start == end;
    for (final which in isLoop
        ? const ['start']
        : const ['start', 'end']) {
      final source = which == 'start' ? start : end;
      if (!isVisible(source)) {
        continue;
      }
      final id = '$idPrefix${line.lineId}:$which';
      final width = math.max(
        diameter,
        measure(id, label).width + horizontalPadding * 2,
      );
      candidates.add(
        RouteMapLabelCandidate(
          id: id,
          anchor: camera.sourceToViewportPoint(source),
          size: Size(width, diameter),
          priority: -1,
          anchorPadding: badgeRadius,
        ),
      );
    }
  }
  return candidates;
}

/// 첫 non-empty sub-polyline의 시작 정점(없으면 null).
Offset? _routeMapFirstVertex(List<List<Offset>> polylines) {
  for (final polyline in polylines) {
    if (polyline.isNotEmpty) {
      return polyline.first;
    }
  }
  return null;
}

/// 마지막 non-empty sub-polyline의 끝 정점(없으면 null).
Offset? _routeMapLastVertex(List<List<Offset>> polylines) {
  for (var i = polylines.length - 1; i >= 0; i -= 1) {
    if (polylines[i].isNotEmpty) {
      return polylines[i].last;
    }
  }
  return null;
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
    this.lineBadgeLabelByLineId = const {},
    this.lineOffsets = const {},
    this.attributionText,
    this.lineWidth = 4.0,
    this.stationRadius = 3.0,
    this.transferStationRadius = 5.0,
    this.lineBadgeRadius = 9.0,
    this.labelStyle = _defaultLabelStyle,
    this.badgeStyle = _defaultBadgeStyle,
    this.attributionStyle = _defaultAttributionStyle,
    Map<String, TextPainter>? labelPainterCache,
  }) : _labelPainters = labelPainterCache ?? {};

  final StructuredRouteMap map;
  final MapCameraState camera;

  /// line_id → 색. 없으면 노선 색 fallback을 쓴다.
  final Map<String, Color> lineColors;

  /// station_id → 역명. 비어 있으면 라벨을 그리지 않는다.
  final Map<String, String> labelTextByStationId;

  /// line_id → 노선 식별 뱃지 라벨(#1764 D). 비어 있으면 뱃지를 그리지 않는다.
  final Map<String, String> lineBadgeLabelByLineId;

  /// line_id → (polyline별) → (정점별) 평행 오프셋 방향(#1792 G4). 공유 corridor
  /// 에서 track이 겹치지 않도록 렌더 시 정점을 수직으로 민다. 비어 있으면 오프셋
  /// 없음. 방향 벡터(단위 법선×rank)에 [lineWidth] px를 곱해 적용한다.
  final Map<String, List<List<Offset>>> lineOffsets;

  /// 출처 표기(#1637 attribution 필요 지역). null/빈 문자열이면 그리지 않는다.
  final String? attributionText;
  final double lineWidth;
  final double stationRadius;
  final double transferStationRadius;
  final double lineBadgeRadius;
  final TextStyle labelStyle;
  final TextStyle badgeStyle;
  final TextStyle attributionStyle;

  static const Color _transferFill = Color(0xFFFFFFFF);
  static const Color _transferBorder = Color(0xFF102A2C);
  static const Color _regularStationFill = Color(0xFFFFFFFF);
  static const Color _fallbackLineColor = Color(0xFF8D8D8D);
  // 환승 캡슐 테두리: 공식 노선도 비율(테두리:선 = 3:8 ≈ 0.375). 선 4px 기준 1.5.
  static const double _transferBorderWidth = 1.5;
  static const double _regularStationBorderWidth = 1.6;
  // 환승 캡슐 안 색 도트: 노선 수만큼 세로로 쌓는다(#1792 G3). map_korea_page1
  // _review.png 실측 비율(선8·도트10·캡슐짧은축19·간격13)을 선 4px로 환산.
  static const double _transferDotRadius = 2.5; // 도트 지름 5 (10/8×4)
  static const double _transferDotGap = 1.5; // 중심 간격 6.5 (13/8×4)
  static const double _transferDotPadding = 1.5; // 캡슐 짧은축 outer≈9.5 (19/8×4)
  static const double _labelGap = 4.0;
  static const String _badgeIdPrefix = 'badge:';
  static const double _badgeHorizontalPadding = 5.0;
  static const TextStyle _defaultLabelStyle = TextStyle(
    color: Color(0xFF102A2C),
    fontSize: 11,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle _defaultBadgeStyle = TextStyle(
    color: Color(0xFFFFFFFF),
    fontSize: 10,
    fontWeight: FontWeight.w700,
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
  // 일반역 노드: 상용 관례대로 흰 채움 + 노선색 테두리 원(#1764 B).
  static final Paint _regularStationFillPaint = Paint()
    ..style = PaintingStyle.fill
    ..color = _regularStationFill
    ..isAntiAlias = true;
  final Paint _regularStationBorderPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = _regularStationBorderWidth
    ..isAntiAlias = true;
  // 노선 뱃지 pill 채움(노선색). 프레임마다 색만 갈아끼운다.
  final Paint _badgeFillPaint = Paint()
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
  final Paint _transferDotPaint = Paint()
    ..style = PaintingStyle.fill
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
      // 공유 corridor 평행 오프셋(#1792 G4): 정점별 방향 벡터에 lineWidth px를
      // 곱해 뷰포트에서 수직으로 민다 — 겹친 track을 나란히 갈라 놓는다.
      final offsetsByPolyline = lineOffsets[line.lineId];
      for (var p = 0; p < line.polylines.length; p += 1) {
        final polyline = line.polylines[p];
        // viewport 밖 sub-polyline은 그리지 않는다 (culling).
        if (!routeMapPolylineIntersectsRect(polyline, visible)) {
          continue;
        }
        final vertexOffsets =
            offsetsByPolyline != null && p < offsetsByPolyline.length
            ? offsetsByPolyline[p]
            : null;
        final path = Path();
        for (var v = 0; v < polyline.length; v += 1) {
          var viewportPoint = camera.sourceToViewportPoint(polyline[v]);
          if (vertexOffsets != null && v < vertexOffsets.length) {
            viewportPoint += vertexOffsets[v] * lineWidth;
          }
          if (v == 0) {
            path.moveTo(viewportPoint.dx, viewportPoint.dy);
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

    // 역 노드는 라벨 LOD와 무관하게 표시한다(#1764 B): 라벨은 겹침 때문에 LOD로
    // 게이트하지만 노드(점)는 조망 상태에서도 "역이 여기 있다"를 보여야 한다.
    // 일반역 점은 선 실루엣만 보는 bucket 0에서만 생략하고, bucket 1(초기 화면)
    // 부터 상시 표시한다. 환승 마커는 bucket 0에도 유지한다.
    if (routeMapShowsRegularStationNodes(bucket)) {
      // 흰 채움 + 노선색 테두리 원. 환승 노드는 transferGroups에서 한 번만
      // 그리므로 여기서 건너뛴다.
      for (final station in map.stations) {
        if (station.labelClass == RouteMapLabelClass.transfer) {
          continue;
        }
        if (!visible.contains(station.position)) {
          continue;
        }
        final center = camera.sourceToViewportPoint(station.position);
        canvas.drawCircle(center, stationRadius, _regularStationFillPaint);
        _regularStationBorderPaint.color =
            lineColors[station.lineId] ?? _fallbackLineColor;
        canvas.drawCircle(center, stationRadius, _regularStationBorderPaint);
      }
    }

    // 환승 마커: 물리 역당 그룹 하나를 이격에 따라 3모드로 그린다(#1789).
    // 비수렴 PD 기하에서 평행 노선들 위 멤버 노드를 캡슐이 걸치는 것이
    // 공식 노선도 문법이다(한 점 수렴 강제는 기하 훼손이라 하지 않는다).
    // bucket 0(선 실루엣 조망)에선 캡슐도 선을 덮으므로 생략한다(#1789 LOD).
    if (!routeMapShowsTransferMarkers(bucket)) {
      return;
    }
    for (final group in map.transferGroups) {
      if (!visible.contains(group.centroid)) {
        continue;
      }
      final markers = routeMapTransferMarkers(
        memberCenters: [
          for (final position in group.memberPositions)
            camera.sourceToViewportPoint(position),
        ],
        colors: [
          for (final lineId in group.lineIds)
            lineColors[lineId] ?? _fallbackLineColor,
        ],
        sourceSpread: offsetsMaxPairwiseDistance(group.memberPositions),
        dotRadius: _transferDotRadius,
        dotGap: _transferDotGap,
        padding: _transferDotPadding,
      );
      for (final marker in markers) {
        canvas.drawRRect(marker.capsule, _transferFillPaint);
        canvas.drawRRect(marker.capsule, _transferBorderPaint);
        for (final dot in marker.dots) {
          _transferDotPaint.color = dot.color;
          canvas.drawCircle(dot.center, _transferDotRadius, _transferDotPaint);
        }
      }
    }
  }

  void _paintLabels(Canvas canvas, Size size, Rect visible) {
    final bucket = routeMapZoomBucket(camera);
    final painterById = <String, TextPainter>{};

    // 노선 뱃지(bucket>=1)와 역 라벨(bucket>=2)을 한 번의 충돌 배치에 태운다.
    // bucket 0(최대 축소)은 고정 크기 뱃지가 촘촘한 노선을 덮으므로 뱃지도 생략해
    // 선 실루엣만 보인다(#1789 LOD). 뱃지 priority -1 이라 역명보다 먼저 자리를
    // 잡는다(#1764 D). 후보는 순수 함수로 생성해 테스트와 동일 규칙을 태운다.
    final candidates = <RouteMapLabelCandidate>[
      if (bucket >= 1)
        ...routeMapLineBadgeCandidates(
          map,
          camera,
          badgeLabelByLineId: lineBadgeLabelByLineId,
          measure: (id, text) => (painterById[id] ??= _badgePainter(text)).size,
          isVisible: visible.contains,
          badgeRadius: lineBadgeRadius,
          horizontalPadding: _badgeHorizontalPadding,
          // id 프리픽스를 painter의 pill 판정(_badgeIdPrefix)과 결속 — 드리프트 방지.
          idPrefix: _badgeIdPrefix,
        ),
    ];
    if (labelTextByStationId.isNotEmpty) {
      candidates.addAll(
        routeMapLabelCandidates(
          map,
          camera,
          bucket,
          labelTextByStationId: labelTextByStationId,
          isVisible: visible.contains,
          stationRadius: stationRadius,
          transferAnchorPadding: transferStationRadius + _transferBorderWidth,
          measure: (id, text) => (painterById[id] ??= _labelPainter(text)).size,
        ),
      );
    }
    if (candidates.isEmpty) {
      return;
    }

    final placed = placeRouteMapLabels(
      candidates,
      gap: _labelGap,
      viewportBounds: Offset.zero & size,
    );
    for (final label in placed) {
      final id = label.candidate.id;
      final painter = painterById[id];
      if (painter == null) {
        continue;
      }
      if (id.startsWith(_badgeIdPrefix)) {
        // 노선색 pill + 흰 라벨. lineId는 'badge:<lineId>:<start|end>'에서 뽑는다.
        final rest = id.substring(_badgeIdPrefix.length);
        final lineId = rest.substring(0, rest.lastIndexOf(':'));
        _badgeFillPaint.color = lineColors[lineId] ?? _fallbackLineColor;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            label.rect,
            Radius.circular(label.rect.height / 2),
          ),
          _badgeFillPaint,
        );
        painter.paint(
          canvas,
          label.rect.center - Offset(painter.width / 2, painter.height / 2),
        );
      } else {
        painter.paint(canvas, label.rect.topLeft);
      }
    }
  }

  TextPainter _badgePainter(String text) {
    return _labelPainters.putIfAbsent(
      '$_badgeIdPrefix$text',
      () => TextPainter(
        text: TextSpan(text: text, style: badgeStyle),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(),
    );
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
        oldDelegate.camera.initialScale != camera.initialScale ||
        !identical(oldDelegate.map, map) ||
        !mapEquals(oldDelegate.lineColors, lineColors) ||
        !mapEquals(oldDelegate.labelTextByStationId, labelTextByStationId) ||
        !mapEquals(
          oldDelegate.lineBadgeLabelByLineId,
          lineBadgeLabelByLineId,
        ) ||
        oldDelegate.attributionText != attributionText ||
        oldDelegate.labelStyle != labelStyle ||
        oldDelegate.badgeStyle != badgeStyle ||
        oldDelegate.attributionStyle != attributionStyle ||
        oldDelegate.lineWidth != lineWidth ||
        oldDelegate.stationRadius != stationRadius ||
        oldDelegate.transferStationRadius != transferStationRadius ||
        oldDelegate.lineBadgeRadius != lineBadgeRadius;
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
  final Map<String, TextPainter> _labelPainters = {};

  // 평행 오프셋(#1792 G4)은 map 정점 전수 계산이라 프레임마다 하면 비싸다.
  // map이 바뀔 때만 다시 계산해 painter로 넘긴다(라벨 캐시와 같은 State 소유).
  StructuredRouteMap? _offsetsSourceMap;
  Map<String, List<List<Offset>>> _lineOffsets = const {};

  Map<String, List<List<Offset>>> _ensureLineOffsets() {
    if (!identical(_offsetsSourceMap, widget.map)) {
      _offsetsSourceMap = widget.map;
      _lineOffsets = routeMapParallelLineOffsets(widget.map.lines);
    }
    return _lineOffsets;
  }

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
        lineBadgeLabelByLineId: widget.lineBadgeLabelByLineId,
        lineOffsets: _ensureLineOffsets(),
        attributionText: widget.attributionText,
        labelPainterCache: _labelPainters,
      ),
    );
  }
}
