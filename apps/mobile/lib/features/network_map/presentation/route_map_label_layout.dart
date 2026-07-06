import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import '../domain/route_map_design_space.dart';
import '../domain/structured_route_map.dart';
import 'route_map_label_placement.dart';
import 'route_map_transfer_marker.dart';

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
  });
  final String id;
  final String text;
  final Offset anchor;
  final Size size;
  final int priority;
  final double anchorPadding;
  final bool bold;
}

// 노선 뱃지 개수: 트렁크가 길면 3, 아니면 2(#1789 — 노선당 소수, 클러터 회피).
int _badgeCountForLine(RouteMapLineGeometry line, RouteMapDesignSpace design) {
  var maxLen = 0.0;
  for (final poly in line.polylines) {
    var len = 0.0;
    for (var i = 1; i < poly.length; i += 1) {
      len += (design.toDesign(poly[i]) - design.toDesign(poly[i - 1])).distance;
    }
    if (len > maxLen) {
      maxLen = len;
    }
  }
  return maxLen > 2000 ? 3 : 2;
}

// 간선(가장 긴 polyline) arc-length 균등 후보 앵커(design px). 후보를 넉넉히 만들어
//   겹치는 위치를 건너뛰고 다음을 시도할 여지를 준다(1/8..7/8).
List<Offset> _badgeAnchorsAlong(
  RouteMapLineGeometry line,
  RouteMapDesignSpace design,
) {
  var trunk = const <Offset>[];
  var trunkLen = -1.0;
  for (final poly in line.polylines) {
    final pts = [for (final p in poly) design.toDesign(p)];
    var len = 0.0;
    for (var i = 1; i < pts.length; i += 1) {
      len += (pts[i] - pts[i - 1]).distance;
    }
    if (len > trunkLen) {
      trunkLen = len;
      trunk = pts;
    }
  }
  if (trunk.length < 2 || trunkLen <= 0) {
    return const [];
  }
  const divisions = 7;
  return [
    for (var i = 1; i <= divisions; i += 1)
      _pointAtFraction(trunk, trunkLen, i / (divisions + 1)),
  ];
}

// polyline 위 arc-length fraction(0..1) 위치의 점.
Offset _pointAtFraction(List<Offset> pts, double totalLen, double fraction) {
  final target = totalLen * fraction;
  var acc = 0.0;
  for (var i = 1; i < pts.length; i += 1) {
    final seg = (pts[i] - pts[i - 1]).distance;
    if (acc + seg >= target) {
      final t = seg == 0 ? 0.0 : (target - acc) / seg;
      return Offset.lerp(pts[i - 1], pts[i], t)!;
    }
    acc += seg;
  }
  return pts.last;
}

/// 환승 흰 원의 design space 외접 Rect — 라벨 배치의 선점 장애물(#1789).
/// painter와 같은 [routeMapTransferRings] 호출로 기하 정합을 보장한다.
List<Rect> routeMapTransferObstacleRects(
  StructuredRouteMap map,
  RouteMapDesignSpace design,
) {
  final rects = <Rect>[];
  for (final group in map.transferGroups) {
    final marker = routeMapTransferRings(
      members: [for (final p in group.memberPositions) design.toDesign(p)],
    );
    for (final ring in marker.rings) {
      rects.add(Rect.fromCircle(center: ring.center, radius: ring.radius));
    }
  }
  return rects;
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

  // 노선 뱃지(색 원)는 역 라벨 배치가 끝난 뒤 별도 pass에서 간선 arc-length 위에
  //   놓는다(아래) — 역명을 가리면 생략(역명 판독 우선, #1789).

  // 환승 라벨(그룹당 1) + 역 라벨(환승 멤버 제외).
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
  final lineGrid = _RouteMapLineGrid.build(map, design);
  // 환승 캡슐은 라벨보다 먼저 자리를 선점한 장애물이다 — 라벨이 캡슐을 덮지
  // 않도록 시드한다(출력에는 포함되지 않음).
  final placedRects = <Rect>[...routeMapTransferObstacleRects(map, design)];
  final labels = <RouteMapStaticLabel>[];
  final badges = <RouteMapStaticBadge>[];
  var unresolved = 0;
  for (final candidate in candidates) {
    final order = routeMapMapOutwardAnchorOrder(candidate.anchor, mapCenter);
    // 라벨-라벨 겹침 0(하드 계약)을 먼저 만족한 뒤, 그중 선 겹침이 최소인 위치를
    // 고른다 — 라벨이 선을 안 덮도록(사실상 선에 수직인 바깥쪽으로 밀려난다).
    Rect? perfect; // 라벨 0 & 선 0.
    Rect? bestClear; // 라벨 0, 선 최소.
    var bestClearLine = double.infinity;
    Rect? bestFallback; // 라벨 겹침 최소(전부 충돌 시).
    var bestFallbackLabel = double.infinity;
    for (final gap in [
      kRouteMapDesignLabelGapPx,
      kRouteMapDesignLabelGapPx + 6,
      kRouteMapDesignLabelGapPx + 12,
    ]) {
      for (final anchor in order) {
        final rect = routeMapLabelRect(
          candidate.anchor,
          candidate.size,
          anchor,
          gap + candidate.anchorPadding,
        );
        var labelOverlap = 0.0;
        for (final other in placedRects) {
          final overlap = rect.intersect(other);
          if (overlap.width > 0 && overlap.height > 0) {
            labelOverlap += overlap.width * overlap.height;
          }
        }
        if (labelOverlap == 0) {
          final lineOverlap = lineGrid.overlapArea(rect);
          if (lineOverlap == 0) {
            perfect = rect;
            break;
          }
          if (lineOverlap < bestClearLine) {
            bestClearLine = lineOverlap;
            bestClear = rect;
          }
        }
        if (labelOverlap < bestFallbackLabel) {
          bestFallbackLabel = labelOverlap;
          bestFallback = rect;
        }
      }
      if (perfect != null) {
        break;
      }
    }
    final rect = perfect ?? bestClear ?? bestFallback!;
    if (perfect == null && bestClear == null) {
      unresolved += 1; // 라벨-라벨 겹침을 못 피한 경우만 집계.
    }
    placedRects.add(rect);
    labels.add(
      RouteMapStaticLabel(
        id: candidate.id,
        text: candidate.text,
        rect: rect,
        bold: candidate.bold,
      ),
    );
  }

  // 노선 뱃지 색 원: 간선 arc-length 위 후보 중 이미 배치된 역 라벨·환승 원·다른
  //   뱃지와 안 겹치는 위치에만 놓는다(역명 판독 > 노선번호 존재 — 겹치면 생략,
  //   노선당 0개 허용). 간선 색 위에 놓이는 것은 정상(공식 서울메트로 룩).
  for (final line in map.lines) {
    final label = badgeLabelByLineId[line.lineId];
    if (label == null || label.isEmpty) {
      continue;
    }
    final size = measureBadge(label);
    final radius = math.max(kRouteMapDesignBadgeRadiusPx, size.width / 2 + 1);
    final maxBadges = _badgeCountForLine(line, design);
    var placed = 0;
    for (final anchor in _badgeAnchorsAlong(line, design)) {
      if (placed >= maxBadges) {
        break;
      }
      final rect = Rect.fromCircle(center: anchor, radius: radius);
      var clash = false;
      for (final other in placedRects) {
        final overlap = rect.intersect(other);
        if (overlap.width > 0 && overlap.height > 0) {
          clash = true;
          break;
        }
      }
      if (clash) {
        continue; // 역명 등과 겹치면 이 위치는 생략(어거지 삽입 금지).
      }
      placedRects.add(rect);
      badges.add(
        RouteMapStaticBadge(lineId: line.lineId, label: label, rect: rect),
      );
      placed += 1;
    }
  }

  return RouteMapStaticLabelLayout(
    labels: labels,
    badges: badges,
    unresolvedOverlapCount: unresolved,
  );
}

/// 세그먼트 a→b가 rect를 관통하나 — 끝점 내부 or 4변 교차(정확 판정).
bool _segmentHitsRect(Offset a, Offset b, Rect r) {
  if (r.contains(a) || r.contains(b)) return true;
  bool segCross(Offset p1, Offset p2, Offset p3, Offset p4) {
    double cross(Offset o, Offset x, Offset y) =>
        (x.dx - o.dx) * (y.dy - o.dy) - (x.dy - o.dy) * (y.dx - o.dx);
    final d1 = cross(p3, p4, p1), d2 = cross(p3, p4, p2);
    final d3 = cross(p1, p2, p3), d4 = cross(p1, p2, p4);
    return ((d1 > 0) != (d2 > 0)) && ((d3 > 0) != (d4 > 0));
  }

  final tl = r.topLeft, tr = r.topRight, br = r.bottomRight, bl = r.bottomLeft;
  return segCross(a, b, tl, tr) ||
      segCross(a, b, tr, br) ||
      segCross(a, b, br, bl) ||
      segCross(a, b, bl, tl);
}

/// 라벨 rect를 노선 track이 관통하는 라벨 수(#1789 실기기 클러터 게이트) — 선을
/// 덮는 라벨은 게이트에 없던 실기기 겹침의 주원인이다.
int routeMapLabelLineOverlapCount(
  RouteMapStaticLabelLayout layout,
  StructuredRouteMap map,
  RouteMapDesignSpace design,
) {
  final segs = <(Offset, Offset)>[];
  for (final line in map.lines) {
    for (final poly in line.polylines) {
      for (var i = 1; i < poly.length; i += 1) {
        segs.add((design.toDesign(poly[i - 1]), design.toDesign(poly[i])));
      }
    }
  }
  var count = 0;
  for (final label in layout.labels) {
    for (final s in segs) {
      if (_segmentHitsRect(s.$1, s.$2, label.rect)) {
        count += 1;
        break;
      }
    }
  }
  return count;
}

/// 뱃지가 노선 track / 역명 라벨을 덮는 수(#1789).
({int line, int label}) routeMapBadgeOverlapCounts(
  RouteMapStaticLabelLayout layout,
  StructuredRouteMap map,
  RouteMapDesignSpace design,
) {
  final segs = <(Offset, Offset)>[];
  for (final line in map.lines) {
    for (final poly in line.polylines) {
      for (var i = 1; i < poly.length; i += 1) {
        segs.add((design.toDesign(poly[i - 1]), design.toDesign(poly[i])));
      }
    }
  }
  var line = 0, lbl = 0;
  for (final b in layout.badges) {
    if (segs.any((s) => _segmentHitsRect(s.$1, s.$2, b.rect))) line += 1;
    if (layout.labels.any((l) => l.rect.overlaps(b.rect))) lbl += 1;
  }
  return (line: line, label: lbl);
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

/// 선을 장애물 셀로 마킹한 그리드 — 라벨이 선을 덮는지 판정한다(#1789 라벨-선 회피).
/// design space에서 각 선분을 반셀 간격으로 샘플해 점유 셀을 Set에 담고, 라벨 rect가
/// 덮는 점유 셀 면적을 스코어로 돌려준다. 로드 시 1회라 비용은 무방하다.
class _RouteMapLineGrid {
  _RouteMapLineGrid._(this._occupied, this._cell);

  final Set<int> _occupied;
  final double _cell;

  static _RouteMapLineGrid build(
    StructuredRouteMap map,
    RouteMapDesignSpace design, {
    double cell = kRouteMapDesignLineWidthPx,
  }) {
    final occupied = <int>{};
    void mark(Offset a, Offset b) {
      final steps = ((b - a).distance / (cell / 2)).ceil();
      for (var i = 0; i <= steps; i += 1) {
        final t = steps == 0 ? 0.0 : i / steps;
        final p = Offset.lerp(a, b, t)!;
        occupied.add(_key((p.dx / cell).floor(), (p.dy / cell).floor()));
      }
    }

    for (final line in map.lines) {
      for (final poly in line.polylines) {
        for (var i = 1; i < poly.length; i += 1) {
          mark(design.toDesign(poly[i - 1]), design.toDesign(poly[i]));
        }
      }
    }
    return _RouteMapLineGrid._(occupied, cell);
  }

  // 20비트씩 pack (음수는 하위 20비트 마스크 — mark/query 일관 사용이라 정합).
  static int _key(int x, int y) => (x & 0xFFFFF) | ((y & 0xFFFFF) << 20);

  /// [rect]가 덮는 선-점유 셀의 면적(design px²). 없으면 0.
  double overlapArea(Rect rect) {
    final x0 = (rect.left / _cell).floor();
    final x1 = (rect.right / _cell).ceil();
    final y0 = (rect.top / _cell).floor();
    final y1 = (rect.bottom / _cell).ceil();
    var count = 0;
    for (var y = y0; y < y1; y += 1) {
      for (var x = x0; x < x1; x += 1) {
        if (_occupied.contains(_key(x, y))) {
          count += 1;
        }
      }
    }
    return count * _cell * _cell;
  }
}
