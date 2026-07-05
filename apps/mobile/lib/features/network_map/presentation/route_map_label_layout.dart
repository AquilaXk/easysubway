import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import '../domain/route_map_design_space.dart';
import '../domain/structured_route_map.dart';
import 'route_map_label_placement.dart';

// 정적 라벨 레이아웃 솔버 (#1789 스펙 S3·S4).
//
// 지역 로드 시 1회, design space에서 라벨·뱃지 자리를 확정한다. 이후 팬·줌은
// 그림 전체 스케일이라 재배치가 없다 — "설계 스케일에서 충돌 없으면 모든
// 줌에서 충돌 없음"(균등 스케일 불변성). 카카오지하철 문법대로 전부 표시:
// 어떤 라벨도 숨기지 않으며, 물리적으로 불가피한 겹침만 최소화 배치 후
// unresolvedOverlapCount로 집계해 감사·튜닝 대상으로 남긴다.

/// 배치된 역명 라벨 (design space px). [bold]는 환승 또는 종착.
class RouteMapStaticLabel {
  const RouteMapStaticLabel({
    required this.id,
    required this.text,
    required this.rect,
    required this.bold,
  });

  /// `transfer:<stationId>` 또는 `<stationId>:<lineId>`.
  final String id;
  final String text;
  final Rect rect; // design space px
  final bool bold;
}

/// 배치된 노선 뱃지 pill (design space px).
class RouteMapStaticBadge {
  const RouteMapStaticBadge({
    required this.lineId,
    required this.label,
    required this.rect,
  });

  final String lineId;
  final String label;
  final Rect rect; // design space px
}

/// 정적 레이아웃 결과. [unresolvedOverlapCount]는 최소 겹침 fallback으로 강제
/// 배치된(=겹침을 못 피한) 라벨 수 — 데이터 품질 감사·튜닝용.
class RouteMapStaticLabelLayout {
  const RouteMapStaticLabelLayout({
    required this.labels,
    required this.badges,
    required this.unresolvedOverlapCount,
  });

  final List<RouteMapStaticLabel> labels;
  final List<RouteMapStaticBadge> badges;
  final int unresolvedOverlapCount;
}

/// 우선순위: 뱃지 -1 > 환승 0 > 주요 1 > 일반 2 (기존 규칙 유지).
int _priorityFor(RouteMapLabelClass labelClass) {
  switch (labelClass) {
    case RouteMapLabelClass.transfer:
      return 0;
    case RouteMapLabelClass.major:
      return 1;
    case RouteMapLabelClass.regular:
      return 2;
  }
}

class _Candidate {
  _Candidate({
    required this.id,
    required this.text,
    required this.anchor,
    required this.size,
    required this.priority,
    required this.anchorPadding,
    required this.bold,
    this.badgeLineId,
  });
  final String id;
  final String text;
  final Offset anchor;
  final Size size;
  final int priority;
  final double anchorPadding;
  final bool bold;
  final String? badgeLineId; // null이면 역 라벨.
}

RouteMapStaticLabelLayout solveRouteMapLabelLayout({
  required StructuredRouteMap map,
  required RouteMapDesignSpace design,
  required Map<String, String> labelTextByStationId,
  required Map<String, String> badgeLabelByLineId,
  required Size Function(String text, {required bool bold}) measureLabel,
  required Size Function(String text) measureBadge,
}) {
  final terminusIds = routeMapTerminusStationIds(map);
  final candidates = <_Candidate>[];

  // 1) 노선 뱃지: 끝점 + arc length 반복 (스펙 S4 — 노선 중간 확대에도 식별).
  for (final line in map.lines) {
    final label = badgeLabelByLineId[line.lineId];
    if (label == null || label.isEmpty) {
      continue;
    }
    final size = measureBadge(label);
    var emitted = 0;
    void emit(Offset source) {
      candidates.add(
        _Candidate(
          id: 'badge:${line.lineId}:${emitted++}',
          text: label,
          anchor: design.toDesign(source),
          size: size,
          priority: -1,
          anchorPadding: kRouteMapDesignBadgeRadiusPx,
          bold: false,
          badgeLineId: line.lineId,
        ),
      );
    }

    Offset? first;
    Offset? last;
    var sinceLastBadge = 0.0;
    for (final polyline in line.polylines) {
      for (var v = 0; v < polyline.length; v += 1) {
        first ??= polyline[v];
        if (last != null) {
          sinceLastBadge +=
              (design.toDesign(polyline[v]) - design.toDesign(last)).distance;
          if (sinceLastBadge >= kRouteMapDesignBadgeIntervalPx) {
            emit(polyline[v]);
            sinceLastBadge = 0;
          }
        }
        last = polyline[v];
      }
    }
    if (first != null) {
      emit(first);
    }
    if (last != null && last != first) {
      emit(last); // 순환선(first==last)은 한 번만.
    }
  }

  // 2) 환승 라벨(그룹당 1) + 역 라벨(환승 멤버 제외).
  for (final group in map.transferGroups) {
    final text = labelTextByStationId[group.stationId];
    if (text == null || text.isEmpty) {
      continue;
    }
    candidates.add(
      _Candidate(
        id: 'transfer:${group.stationId}',
        text: text,
        anchor: design.toDesign(group.centroid),
        size: measureLabel(text, bold: true),
        priority: _priorityFor(RouteMapLabelClass.transfer),
        // 캡슐이 걸치는 폭까지 띄운다: 캡슐 짧은축 절반 + 멤버 이격 절반.
        anchorPadding:
            kRouteMapDesignBadgeRadiusPx +
            _memberSpread(group.memberPositions) * design.designScale / 2,
        bold: true,
      ),
    );
  }
  for (final station in map.stations) {
    if (station.labelClass == RouteMapLabelClass.transfer) {
      continue;
    }
    final text = labelTextByStationId[station.stationId];
    if (text == null || text.isEmpty) {
      continue;
    }
    final bold = terminusIds.contains(station.stationId);
    candidates.add(
      _Candidate(
        id: '${station.stationId}:${station.lineId}',
        text: text,
        anchor: design.toDesign(station.position),
        size: measureLabel(text, bold: bold),
        priority: _priorityFor(station.labelClass),
        anchorPadding: kRouteMapDesignStationRadiusPx,
        bold: bold,
      ),
    );
  }

  // 3) greedy 배치: 우선순위→id 정렬, 지도 중심 기준 outward 8방향 × gap 2단.
  //    전부 충돌이면 최소 겹침 면적 위치에 강제 배치(숨김 금지).
  candidates.sort((a, b) {
    final byPriority = a.priority.compareTo(b.priority);
    return byPriority != 0 ? byPriority : a.id.compareTo(b.id);
  });
  final mapCenter = _designBoundsCenter(map, design);
  final placedRects = <Rect>[];
  final labels = <RouteMapStaticLabel>[];
  final badges = <RouteMapStaticBadge>[];
  var unresolved = 0;
  for (final candidate in candidates) {
    final order = routeMapMapOutwardAnchorOrder(candidate.anchor, mapCenter);
    Rect? chosen;
    Rect? bestFallback;
    var bestOverlapArea = double.infinity;
    for (final gap in [
      kRouteMapDesignLabelGapPx,
      kRouteMapDesignLabelGapPx + 6,
    ]) {
      for (final anchor in order) {
        final rect = routeMapLabelRect(
          candidate.anchor,
          candidate.size,
          anchor,
          gap + candidate.anchorPadding,
        );
        var overlapArea = 0.0;
        for (final other in placedRects) {
          final overlap = rect.intersect(other);
          if (overlap.width > 0 && overlap.height > 0) {
            overlapArea += overlap.width * overlap.height;
          }
        }
        if (overlapArea == 0) {
          chosen = rect;
          break;
        }
        if (overlapArea < bestOverlapArea) {
          bestOverlapArea = overlapArea;
          bestFallback = rect;
        }
      }
      if (chosen != null) {
        break;
      }
    }
    final rect = chosen ?? bestFallback!;
    if (chosen == null) {
      unresolved += 1;
    }
    placedRects.add(rect);
    if (candidate.badgeLineId != null) {
      badges.add(
        RouteMapStaticBadge(
          lineId: candidate.badgeLineId!,
          label: candidate.text,
          rect: rect,
        ),
      );
    } else {
      labels.add(
        RouteMapStaticLabel(
          id: candidate.id,
          text: candidate.text,
          rect: rect,
          bold: candidate.bold,
        ),
      );
    }
  }
  return RouteMapStaticLabelLayout(
    labels: labels,
    badges: badges,
    unresolvedOverlapCount: unresolved,
  );
}

double _memberSpread(List<Offset> positions) {
  var maxDistance = 0.0;
  for (var i = 0; i < positions.length; i += 1) {
    for (var j = i + 1; j < positions.length; j += 1) {
      maxDistance = math.max(
        maxDistance,
        (positions[i] - positions[j]).distance,
      );
    }
  }
  return maxDistance;
}

Offset _designBoundsCenter(StructuredRouteMap map, RouteMapDesignSpace design) {
  double? minX, minY, maxX, maxY;
  void visit(Offset p) {
    minX = math.min(minX ?? p.dx, p.dx);
    maxX = math.max(maxX ?? p.dx, p.dx);
    minY = math.min(minY ?? p.dy, p.dy);
    maxY = math.max(maxY ?? p.dy, p.dy);
  }

  for (final line in map.lines) {
    for (final polyline in line.polylines) {
      polyline.forEach(visit);
    }
  }
  for (final station in map.stations) {
    visit(station.position);
  }
  if (minX == null) {
    return Offset.zero;
  }
  return design.toDesign(Offset((minX! + maxX!) / 2, (minY! + maxY!) / 2));
}
