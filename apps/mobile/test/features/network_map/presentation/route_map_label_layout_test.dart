import 'dart:math' as math;
import 'dart:ui';

import 'package:easysubway_mobile/features/network_map/domain/route_map_design_space.dart';
import 'package:easysubway_mobile/features/network_map/domain/route_map_owner_labels.dart';
import 'package:easysubway_mobile/features/network_map/domain/structured_route_map.dart';
import 'package:easysubway_mobile/features/network_map/presentation/route_map_label_layout.dart';
import 'package:flutter_test/flutter_test.dart';

// 결정적 실측: 글자 수 × 9px, 높이 13px (bold·fontSize 무관 — 이 파일 전
// 테스트가 fontSize=13(기본값 또는 entry(fontSizePx:13.0)·designScale 1)만
// 쓰므로 fontSize 인자는 시그니처만 맞추고 무시해도 안전하다, #2068 9차).
Size _measureLabel(
  String text, {
  required bool bold,
  required double fontSize,
}) => Size(text.length * 9.0, 13.0);
Size _measureBadge(String text, {required double fontSize}) =>
    Size(text.length * 8.0 + 10, 18.0);

/// 환승 1 + 일반 N을 design 기준 간격으로 배치한 대표 지도.
StructuredRouteMap _gridMap({double sourceSpacing = 24, int count = 30}) {
  final stations = <RouteMapStructuredStation>[];
  final positions = <Offset>[];
  for (var i = 0; i < count; i += 1) {
    final pos = Offset((i % 6) * sourceSpacing, (i ~/ 6) * sourceSpacing);
    positions.add(pos);
    stations.add(
      RouteMapStructuredStation(
        stationId: 's$i',
        lineId: 'L1',
        sequence: i,
        position: pos,
        labelPolygon: const [],
        labelClass: i == 0
            ? RouteMapLabelClass.transfer
            : RouteMapLabelClass.regular,
      ),
    );
  }
  return StructuredRouteMap(
    lines: [
      RouteMapLineGeometry(lineId: 'L1', polylines: [positions]),
    ],
    stations: stations,
    transferGroups: [
      RouteMapTransferGroup(
        stationId: 's0',
        lineIds: const ['L1', 'L2'],
        centroid: positions.first,
        memberPositions: [positions.first],
      ),
    ],
  );
}

RouteMapStaticLabelLayout _solve(StructuredRouteMap map) {
  return solveRouteMapLabelLayout(
    map: map,
    design: routeMapDesignSpaceFor(map),
    labelTextByStationId: {
      for (final s in map.stations) s.stationId: '역${s.stationId}',
    },
    badgeLabelByLineId: const {'L1': '1'},
    measureLabel: _measureLabel,
    measureBadge: _measureBadge,
  );
}

void main() {
  test('기준 간격 지도는 겹침 0으로 전 라벨 배치 (숨김 금지 계약)', () {
    final map = _gridMap();
    final layout = _solve(map);
    // 전부 표시: 텍스트 있는 모든 역 라벨이 존재(환승은 그룹당 1개).
    expect(layout.labels.length, 30);
    expect(layout.unresolvedOverlapCount, 0);
    final rects = [
      ...layout.labels.map((l) => l.rect),
      ...layout.badges.map((b) => b.rect),
    ];
    for (var i = 0; i < rects.length; i += 1) {
      for (var j = i + 1; j < rects.length; j += 1) {
        expect(
          rects[i].overlaps(rects[j]),
          isFalse,
          reason: 'rect $i vs $j 겹침',
        );
      }
    }
  });

  test('결정성: 같은 입력 → 같은 출력', () {
    final map = _gridMap();
    final a = _solve(map);
    final b = _solve(map);
    expect(a.labels.length, b.labels.length);
    for (var i = 0; i < a.labels.length; i += 1) {
      expect(a.labels[i].id, b.labels[i].id);
      expect(a.labels[i].rect, b.labels[i].rect);
    }
    expect(
      a.badges.map((x) => x.rect).toList(),
      b.badges.map((x) => x.rect).toList(),
    );
  });

  test('뱃지는 노선 종점 2개만 (반복 없음 — 역명 가림 방지)', () {
    final map = _gridMap(count: 60);
    final layout = _solve(map);
    // 공식 노선도 관례: 노선명은 종점에만. 중간 반복은 역명을 덮으므로 없앤다.
    expect(layout.badges.length, 2);
  });

  test(
    '#2068 광주 2차: suppressLineBadges=true면 노선 뱃지 후보를 만들지 않는다',
    () {
      final map = _gridMap(count: 60);
      final layout = solveRouteMapLabelLayout(
        map: map,
        design: routeMapDesignSpaceFor(map),
        labelTextByStationId: {
          for (final s in map.stations) s.stationId: '역${s.stationId}',
        },
        badgeLabelByLineId: const {'L1': '1'},
        measureLabel: _measureLabel,
        measureBadge: _measureBadge,
        suppressLineBadges: true,
      );
      expect(layout.badges, isEmpty);
      // 역 라벨 자체는 불변(뱃지만 억제, 다른 배치에 영향 없음).
      expect(layout.labels.length, 60);
    },
  );

  test('전부 충돌이어도 숨기지 않고 최소 겹침 배치 + unresolved 집계', () {
    // 같은 좌표에 역 30개 → gap 사다리 슬롯(방향 8 × gap 4 = 32)을 채워도 물리적
    // 으로 겹침 불가피. (라벨당 slot 하나를 잡아도 후반부는 남는 자리가 겹친다.)
    const n = 30;
    final stations = [
      for (var i = 0; i < n; i += 1)
        RouteMapStructuredStation(
          stationId: 'x$i',
          lineId: 'L$i',
          sequence: 0,
          position: Offset.zero,
          labelPolygon: const [],
          labelClass: RouteMapLabelClass.regular,
        ),
    ];
    final map = StructuredRouteMap(
      lines: const [],
      stations: stations,
      transferGroups: const [],
    );
    final layout = solveRouteMapLabelLayout(
      map: map,
      design: const RouteMapDesignSpace(designScale: 1),
      labelTextByStationId: {for (final s in stations) s.stationId: '긴긴긴역명'},
      badgeLabelByLineId: const {},
      measureLabel: _measureLabel,
      measureBadge: _measureBadge,
    );
    expect(layout.labels.length, n); // 숨김 금지.
    expect(layout.unresolvedOverlapCount, greaterThan(0));
  });

  test('환승·종착 라벨은 bold', () {
    final map = _gridMap();
    final layout = _solve(map);
    final byId = {for (final l in layout.labels) l.id: l};
    expect(byId['transfer:s0']!.bold, isTrue); // 환승
    expect(byId['s29:L1']!.bold, isTrue); // 종착(마지막 sequence)
    expect(byId['s5:L1']!.bold, isFalse); // 일반
  });

  test('라벨은 환승 캡슐 rect를 덮지 않는다 (캡슐 장애물)', () {
    // 환승 1(스팬 캡슐) + 바로 옆 일반역 1 — 일반역 라벨의 기본 방향 후보가
    // 캡슐과 부딪히도록 배치한다.
    final map = StructuredRouteMap(
      lines: const [],
      stations: [
        RouteMapStructuredStation(
          stationId: 't',
          lineId: 'L1',
          sequence: 0,
          position: const Offset(0, 0),
          labelPolygon: const [],
          labelClass: RouteMapLabelClass.transfer,
        ),
        RouteMapStructuredStation(
          stationId: 'r',
          lineId: 'L1',
          sequence: 1,
          position: const Offset(30, 0),
          labelPolygon: const [],
          labelClass: RouteMapLabelClass.regular,
        ),
      ],
      transferGroups: [
        RouteMapTransferGroup(
          stationId: 't',
          lineIds: const ['L1', 'L2'],
          centroid: const Offset(0, 0),
          memberPositions: const [Offset(-6, 0), Offset(6, 0)], // 스팬 이격 12
        ),
      ],
    );
    const design = RouteMapDesignSpace(designScale: 1);
    final obstacles = routeMapTransferObstacleRects(map, design);
    expect(obstacles, hasLength(1));

    final layout = solveRouteMapLabelLayout(
      map: map,
      design: design,
      labelTextByStationId: const {'t': '환승역명', 'r': '일반역명'},
      badgeLabelByLineId: const {},
      measureLabel: _measureLabel,
      measureBadge: _measureBadge,
    );
    for (final label in layout.labels) {
      for (final obstacle in obstacles) {
        final overlap = label.rect.intersect(obstacle);
        expect(
          overlap.width > 0 && overlap.height > 0,
          isFalse,
          reason: '${label.id} 라벨이 캡슐을 덮음',
        );
      }
    }
  });

  test('basemap 모드 캡슐 장애물은 SVG 실측 반폭으로 부풀린다', () {
    // 멤버 2점 이격 12 → design(designScale=1) bounding box는 12×0(폭 12, 높이 0).
    // basemap은 멤버 수 기반 반폭 max(13, (2-1)*7.5+9=16.5)=16.5만큼 inflate →
    // 45×33 (중심 (0,0)).
    final map = StructuredRouteMap(
      lines: const [],
      stations: const [],
      transferGroups: [
        RouteMapTransferGroup(
          stationId: 't',
          lineIds: const ['L1', 'L2'],
          centroid: const Offset(0, 0),
          memberPositions: const [Offset(-6, 0), Offset(6, 0)],
        ),
      ],
    );
    const design = RouteMapDesignSpace(designScale: 1);

    final express = routeMapTransferObstacleRects(map, design);
    final basemap = routeMapTransferObstacleRects(map, design, basemap: true);
    expect(express, hasLength(1));
    expect(basemap, hasLength(1));
    // basemap rect는 멤버 수 기반 반폭 16.5로 부풀어 express(구조화 캡슐)보다
    // 크다.
    expect(basemap.first, const Rect.fromLTRB(-22.5, -16.5, 22.5, 16.5));
    expect(basemap.first.height, greaterThan(express.first.height));
    expect(basemap.first.width, greaterThan(express.first.width));
  });

  test('basemap 모드 환승 라벨은 확대된 캡슐 장애물을 덮지 않는다', () {
    final map = StructuredRouteMap(
      lines: const [],
      stations: [
        RouteMapStructuredStation(
          stationId: 't',
          lineId: 'L1',
          sequence: 0,
          position: const Offset(0, 0),
          labelPolygon: const [],
          labelClass: RouteMapLabelClass.transfer,
        ),
        RouteMapStructuredStation(
          stationId: 'r',
          lineId: 'L1',
          sequence: 1,
          position: const Offset(30, 0),
          labelPolygon: const [],
          labelClass: RouteMapLabelClass.regular,
        ),
      ],
      transferGroups: [
        RouteMapTransferGroup(
          stationId: 't',
          lineIds: const ['L1', 'L2'],
          centroid: const Offset(0, 0),
          memberPositions: const [Offset(-6, 0), Offset(6, 0)],
        ),
      ],
    );
    const design = RouteMapDesignSpace(designScale: 1);
    final obstacles = routeMapTransferObstacleRects(map, design, basemap: true);

    final layout = solveRouteMapLabelLayout(
      map: map,
      design: design,
      labelTextByStationId: const {'t': '환승역명', 'r': '일반역명'},
      badgeLabelByLineId: const {},
      measureLabel: _measureLabel,
      measureBadge: _measureBadge,
      basemap: true,
    );
    for (final label in layout.labels) {
      for (final obstacle in obstacles) {
        final overlap = label.rect.intersect(obstacle);
        expect(
          overlap.width > 0 && overlap.height > 0,
          isFalse,
          reason: '${label.id} 라벨이 basemap 캡슐을 덮음',
        );
      }
    }
  });

  test('basemap 모드는 일반 역 노드 심벌을 장애물로 시드해 이웃 라벨이 노드를 덮지 않는다', () {
    // 한 줄에 일반역 6개. 각 노드 design 좌표 중심 실측 반경 rect가 장애물이므로
    // 어떤 라벨도 (자기 포함) 노드 원을 덮지 않아야 한다(#2068 실기기 반려).
    final map = _gridMap(count: 6);
    const design = RouteMapDesignSpace(designScale: 1);
    final layout = solveRouteMapLabelLayout(
      map: map,
      design: design,
      labelTextByStationId: {
        for (final s in map.stations) s.stationId: '역${s.stationId}',
      },
      badgeLabelByLineId: const {'L1': '1'},
      measureLabel: _measureLabel,
      measureBadge: _measureBadge,
      basemap: true,
    );
    final nodeRects = [
      for (final s in map.stations)
        if (s.labelClass != RouteMapLabelClass.transfer)
          Rect.fromCenter(
            center: design.toDesign(s.position),
            width: kRouteMapBasemapStationNodeRadiusPx * 2,
            height: kRouteMapBasemapStationNodeRadiusPx * 2,
          ),
    ];
    for (final label in layout.labels) {
      for (final node in nodeRects) {
        final overlap = label.rect.intersect(node);
        expect(
          overlap.width > 0 && overlap.height > 0,
          isFalse,
          reason: '${label.id} 라벨이 일반 역 노드를 덮음',
        );
      }
    }
  });

  test('기본 모드는 일반 역 노드 장애물을 시드하지 않는다 (basemap 전용 — baseline 불변)', () {
    // 겹치는 좌표 두 역: basemap이면 노드 rect가 서로를 밀어내지만, 기본 모드는
    // 노드 장애물이 없어 라벨이 상대 노드 좌표 근처에 놓일 수 있다. 두 모드의
    // 배치가 달라짐을 확인해 basemap 전용 시드를 회귀 검증한다.
    final map = StructuredRouteMap(
      lines: const [],
      stations: [
        RouteMapStructuredStation(
          stationId: 'a',
          lineId: 'L1',
          sequence: 0,
          position: const Offset(0, 0),
          labelPolygon: const [],
          labelClass: RouteMapLabelClass.regular,
        ),
        RouteMapStructuredStation(
          stationId: 'b',
          lineId: 'L1',
          sequence: 1,
          position: const Offset(4, 0),
          labelPolygon: const [],
          labelClass: RouteMapLabelClass.regular,
        ),
      ],
      transferGroups: const [],
    );
    const design = RouteMapDesignSpace(designScale: 1);
    RouteMapStaticLabelLayout run({required bool basemap}) =>
        solveRouteMapLabelLayout(
          map: map,
          design: design,
          labelTextByStationId: const {'a': '가나다', 'b': '라마바'},
          badgeLabelByLineId: const {},
          measureLabel: _measureLabel,
          measureBadge: _measureBadge,
          basemap: basemap,
        );
    final express = run(basemap: false);
    final base = run(basemap: true);
    final expressRects = {for (final l in express.labels) l.id: l.rect};
    final baseRects = {for (final l in base.labels) l.id: l.rect};
    // 노드 장애물 + anchorPadding 상향으로 basemap 배치는 기본 모드와 달라진다.
    expect(baseRects, isNot(equals(expressRects)));
  });

  test('basemap 일반 역 라벨은 자기 노드 반경 이상 이격된다 (anchorPadding 상향)', () {
    // 선·이웃 없는 단독 일반역: 라벨이 자기 노드(실측 반경) 밖에 놓여야 한다.
    final map = StructuredRouteMap(
      lines: const [],
      stations: [
        RouteMapStructuredStation(
          stationId: 's',
          lineId: 'L1',
          sequence: 0,
          position: const Offset(0, 0),
          labelPolygon: const [],
          labelClass: RouteMapLabelClass.regular,
        ),
      ],
      transferGroups: const [],
    );
    const design = RouteMapDesignSpace(designScale: 1);
    final layout = solveRouteMapLabelLayout(
      map: map,
      design: design,
      labelTextByStationId: const {'s': '역명'},
      badgeLabelByLineId: const {},
      measureLabel: _measureLabel,
      measureBadge: _measureBadge,
      basemap: true,
    );
    final rect = layout.labels.single.rect;
    // anchor(0,0)에서 rect 최근접점까지 거리 ≥ 노드 반경.
    final nx = 0.0.clamp(rect.left, rect.right);
    final ny = 0.0.clamp(rect.top, rect.bottom);
    final dist = Offset(nx, ny).distance;
    expect(
      dist,
      greaterThanOrEqualTo(kRouteMapBasemapStationNodeRadiusPx),
      reason: '라벨이 자기 노드 반경 안($dist)에 놓임',
    );
  });

  test('basemap 선 반폭 마킹은 라벨을 노선 밴드 밖으로 밀어낸다 (기본 모드보다 큰 이격)', () {
    // 평행 두 선: A(y=0), B(y=12). 일반역은 A 위에만. B 쪽으로 놓이는 라벨이
    // 기본 모드(중심선만)에서는 B 밴드에 걸치지만, basemap(반폭 4.5)에서는 B에서
    // 더 멀리 밀려난다. 라벨-선(B 중심선) 최소거리로 검증한다.
    final aPositions = [for (var i = 0; i < 6; i += 1) Offset(i * 24.0, 0)];
    final bPositions = [for (var i = 0; i < 6; i += 1) Offset(i * 24.0, 12)];
    final map = StructuredRouteMap(
      lines: [
        RouteMapLineGeometry(lineId: 'A', polylines: [aPositions]),
        RouteMapLineGeometry(lineId: 'B', polylines: [bPositions]),
      ],
      stations: [
        for (var i = 0; i < 6; i += 1)
          RouteMapStructuredStation(
            stationId: 'a$i',
            lineId: 'A',
            sequence: i,
            position: aPositions[i],
            labelPolygon: const [],
            labelClass: RouteMapLabelClass.regular,
          ),
      ],
      transferGroups: const [],
    );
    final design = routeMapDesignSpaceFor(map);
    RouteMapStaticLabelLayout run({required bool basemap}) =>
        solveRouteMapLabelLayout(
          map: map,
          design: design,
          labelTextByStationId: {
            for (final s in map.stations) s.stationId: '역',
          },
          badgeLabelByLineId: const {},
          measureLabel: _measureLabel,
          measureBadge: _measureBadge,
          basemap: basemap,
        );
    double minDistToLineB(RouteMapStaticLabelLayout layout) {
      var best = double.infinity;
      final b0 = design.toDesign(bPositions.first);
      final b1 = design.toDesign(bPositions.last);
      for (final l in layout.labels) {
        best = math.min(best, _segRectDist(b0, b1, l.rect));
      }
      return best;
    }

    final expressMin = minDistToLineB(run(basemap: false));
    final baseMin = minDistToLineB(run(basemap: true));
    // basemap은 B 밴드(반폭 4.5)를 장애물로 보므로 가장 가까운 라벨도 더 멀다.
    expect(
      baseMin,
      greaterThanOrEqualTo(expressMin),
      reason: 'basemap 최소이격 $baseMin < 기본 $expressMin',
    );
    expect(
      baseMin,
      greaterThanOrEqualTo(kRouteMapBasemapLineHalfWidthPx - 1.0),
      reason: 'basemap 라벨이 B 밴드 반폭 안에 걸침 ($baseMin)',
    );
  });

  test('basemap corridor(다중 노선 공유 좌표)는 병렬 오프셋만큼 밴드가 더 넓게 마킹된다', () {
    // 노선 A·B가 완전히 같은 좌표를 공유(corridor) — routeMapParallelLineOffsets가
    // 각 노선을 법선 방향으로 ±0.5×kRouteMapDesignLineWidthPx(=±2.0)만큼 fan-out
    // 한다(painter와 동일 공식). corridor 실제 폭은 중심선에서 2.0(오프셋)+4.5
    // (반폭)=6.5까지 — 라벨은 A 하나만 있을 때(플레인 반폭 4.5)보다 더 멀리
    // 밀려나야 한다(#2068 실기기 재검증 후속: 공유 corridor 실폭 미반영 대응).
    final positions = [for (var i = 0; i < 6; i += 1) Offset(i * 24.0, 0)];
    StructuredRouteMap buildMap({required bool withCorridorPartner}) =>
        StructuredRouteMap(
          lines: [
            RouteMapLineGeometry(lineId: 'A', polylines: [positions]),
            if (withCorridorPartner)
              RouteMapLineGeometry(lineId: 'B', polylines: [positions]),
          ],
          stations: [
            for (var i = 0; i < 6; i += 1)
              RouteMapStructuredStation(
                stationId: 'a$i',
                lineId: 'A',
                sequence: i,
                position: positions[i],
                labelPolygon: const [],
                labelClass: RouteMapLabelClass.regular,
              ),
          ],
          transferGroups: const [],
        );
    final soloMap = buildMap(withCorridorPartner: false);
    final corridorMap = buildMap(withCorridorPartner: true);
    final design = routeMapDesignSpaceFor(soloMap);

    RouteMapStaticLabelLayout solve(StructuredRouteMap map) =>
        solveRouteMapLabelLayout(
          map: map,
          design: design,
          labelTextByStationId: {
            for (final s in map.stations) s.stationId: '역',
          },
          badgeLabelByLineId: const {},
          measureLabel: _measureLabel,
          measureBadge: _measureBadge,
          basemap: true,
        );
    // 내부 역(양 끝 a0·a5 제외, 이웃 라벨 접촉으로 밀도가 높아 corridor 유무와
    // 무관하게 같은 gap 단에 안착하는 인접 역들)만 비교한다.
    double distFor(RouteMapStaticLabelLayout layout, String id) {
      final a0 = design.toDesign(positions.first);
      final a1 = design.toDesign(positions.last);
      final label = layout.labels.firstWhere((l) => l.id == id);
      return _segRectDist(a0, a1, label.rect);
    }

    final soloLayout = solve(soloMap);
    final corridorLayout = solve(corridorMap);
    for (final id in ['a1:A', 'a2:A', 'a3:A', 'a4:A']) {
      final soloDist = distFor(soloLayout, id);
      final corridorDist = distFor(corridorLayout, id);
      expect(
        corridorDist,
        greaterThan(soloDist),
        reason:
            'corridor 오프셋 마킹이 반영되지 않음($id): solo=$soloDist '
            'corridor=$corridorDist',
      );
    }
  });

  group('basemap 오너 라벨 앵커(#2068 6차)', () {
    RouteMapOwnerLabelEntry entry({
      required Offset position,
      RouteMapOwnerLabelAnchor anchor = RouteMapOwnerLabelAnchor.start,
      String role = 'ordinary',
    }) => RouteMapOwnerLabelEntry(
      station: 's',
      role: role,
      position: position,
      anchor: anchor,
      fontSizePx: 13.0,
    );

    StructuredRouteMap soloStationMap() => StructuredRouteMap(
      lines: const [],
      stations: [
        RouteMapStructuredStation(
          stationId: 's',
          lineId: 'L1',
          sequence: 0,
          position: const Offset(0, 0),
          labelPolygon: const [],
          labelClass: RouteMapLabelClass.regular,
        ),
      ],
      transferGroups: const [],
    );

    test('매치되면 오너 앵커에 SVG anchor 의미(start/middle/end)대로 배치한다', () {
      const design = RouteMapDesignSpace(designScale: 1);
      final map = soloStationMap();
      for (final anchor in RouteMapOwnerLabelAnchor.values) {
        final layout = solveRouteMapLabelLayout(
          map: map,
          design: design,
          labelTextByStationId: const {'s': '역명'},
          badgeLabelByLineId: const {},
          measureLabel: _measureLabel,
          measureBadge: _measureBadge,
          basemap: true,
          ownerLabelsByStationName: {
            '역명전체': entry(position: const Offset(100, 50), anchor: anchor),
          },
          stationNameByStationId: const {'s': '역명전체'},
        );
        final rect = layout.labels.single.rect;
        // size = _measureLabel('역명', bold:false) = (2*9, 13) = (18, 13).
        // anchorDesign = (100, 50). top = 50 - 0.8*13 = 39.6.
        expect(rect.top, closeTo(39.6, 1e-9));
        expect(rect.height, 13);
        switch (anchor) {
          case RouteMapOwnerLabelAnchor.start:
            expect(rect.left, 100);
          case RouteMapOwnerLabelAnchor.middle:
            expect(rect.center.dx, closeTo(100, 1e-9));
          case RouteMapOwnerLabelAnchor.end:
            expect(rect.right, 100);
        }
      }
    });

    test('오너 라벨은 검색을 거치지 않는다 — 장애물이 있어도 앵커 위치 그대로', () {
      const design = RouteMapDesignSpace(designScale: 1);
      final map = soloStationMap();
      final layout = solveRouteMapLabelLayout(
        map: map,
        design: design,
        labelTextByStationId: const {'s': '역명'},
        badgeLabelByLineId: const {},
        measureLabel: _measureLabel,
        measureBadge: _measureBadge,
        basemap: true,
        ownerLabelsByStationName: {'역명전체': entry(position: const Offset(0, 0))},
        stationNameByStationId: const {'s': '역명전체'},
      );
      // anchor(0,0), start → rect.left=0, top=0-0.8*13=-10.4. 자기 노드
      // 장애물(반경 4.5, 자기 anchor와 같은 위치)과 겹쳐도 검색으로 피하지
      // 않고 그대로 배치되며 unresolvedOverlapCount로만 감사된다.
      final rect = layout.labels.single.rect;
      expect(rect.left, 0);
      expect(rect.top, closeTo(-10.4, 1e-9));
      expect(layout.unresolvedOverlapCount, 1); // 자기 노드와 겹침 감사.
    });

    test('원본명 미제공(stationNameByStationId 비어있음)이면 기존 솔버로 폴백한다', () {
      const design = RouteMapDesignSpace(designScale: 1);
      final map = soloStationMap();
      final layout = solveRouteMapLabelLayout(
        map: map,
        design: design,
        labelTextByStationId: const {'s': '역명'},
        badgeLabelByLineId: const {},
        measureLabel: _measureLabel,
        measureBadge: _measureBadge,
        basemap: true,
        ownerLabelsByStationName: {
          '역명전체': entry(position: const Offset(999, 999)),
        },
        // stationNameByStationId 기본값(빈 맵) — 원본명 없어 매치 불가.
      );
      final rect = layout.labels.single.rect;
      // 폴백 경로는 station.position(0,0) 기준 검색 배치 — 오너 앵커
      // (999,999)와 무관해야 한다.
      expect((rect.center - const Offset(999, 999)).distance, greaterThan(50));
    });

    test('환승 그룹도 station 원본명으로 오너 라벨을 매치한다', () {
      const design = RouteMapDesignSpace(designScale: 1);
      final map = StructuredRouteMap(
        lines: const [],
        stations: [
          RouteMapStructuredStation(
            stationId: 't',
            lineId: 'L1',
            sequence: 0,
            position: const Offset(0, 0),
            labelPolygon: const [],
            labelClass: RouteMapLabelClass.transfer,
          ),
          RouteMapStructuredStation(
            stationId: 't',
            lineId: 'L2',
            sequence: 0,
            position: const Offset(10, 0),
            labelPolygon: const [],
            labelClass: RouteMapLabelClass.transfer,
          ),
        ],
        transferGroups: [
          RouteMapTransferGroup(
            stationId: 't',
            lineIds: const ['L1', 'L2'],
            centroid: const Offset(5, 0),
            memberPositions: const [Offset(0, 0), Offset(10, 0)],
          ),
        ],
      );
      final layout = solveRouteMapLabelLayout(
        map: map,
        design: design,
        labelTextByStationId: const {'t': '환승역'},
        badgeLabelByLineId: const {},
        measureLabel: _measureLabel,
        measureBadge: _measureBadge,
        basemap: true,
        ownerLabelsByStationName: {
          // centroid(5,0)에서 위치 게이트(185px) 이내(#2068 7차).
          '환승역전체': entry(position: const Offset(50, 30), role: 'transfer'),
        },
        stationNameByStationId: const {'t': '환승역전체'},
      );
      expect(layout.labels.single.id, 'transfer:t');
      expect(layout.labels.single.rect.left, 50);
      expect(layout.labels.single.bold, isTrue);
    });

    test('위치 게이트(#2068 7차): 오너 앵커가 station에서 너무 멀면 폴백한다', () {
      const design = RouteMapDesignSpace(designScale: 1);
      final map = soloStationMap();
      final layout = solveRouteMapLabelLayout(
        map: map,
        design: design,
        labelTextByStationId: const {'s': '역명'},
        badgeLabelByLineId: const {},
        measureLabel: _measureLabel,
        measureBadge: _measureBadge,
        basemap: true,
        ownerLabelsByStationName: {
          // station(0,0)에서 200px — kRouteMapOwnerLabelMaxAnchorDistancePx
          // (185)를 넘는 병리적 오배치(#2068 7차 양평 케이스 재현).
          '역명전체': entry(position: const Offset(200, 0)),
        },
        stationNameByStationId: const {'s': '역명전체'},
      );
      final rect = layout.labels.single.rect;
      // 폴백 경로는 station(0,0) 기준 검색 배치 — 오너 앵커(200,0)와 무관.
      expect((rect.center - const Offset(200, 0)).distance, greaterThan(50));
    });

    test('동명이역(#2068 7차): 같은 이름 후보가 여럿이면 가장 가까운 1개만 오너 라벨을 쓴다', () {
      const design = RouteMapDesignSpace(designScale: 1);
      final map = StructuredRouteMap(
        lines: const [],
        stations: [
          RouteMapStructuredStation(
            stationId: 'near',
            lineId: 'L1',
            sequence: 0,
            position: const Offset(10, 0), // 오너 앵커(0,0)에서 거리 10.
            labelPolygon: const [],
            labelClass: RouteMapLabelClass.regular,
          ),
          RouteMapStructuredStation(
            stationId: 'far',
            lineId: 'L2',
            sequence: 0,
            position: const Offset(60, 0), // 오너 앵커(0,0)에서 거리 60.
            labelPolygon: const [],
            labelClass: RouteMapLabelClass.regular,
          ),
        ],
        transferGroups: const [],
      );
      final layout = solveRouteMapLabelLayout(
        map: map,
        design: design,
        labelTextByStationId: const {'near': '동명역', 'far': '동명역'},
        badgeLabelByLineId: const {},
        measureLabel: _measureLabel,
        measureBadge: _measureBadge,
        basemap: true,
        ownerLabelsByStationName: {
          '동명역전체': entry(position: const Offset(0, 0)),
        },
        stationNameByStationId: const {'near': '동명역전체', 'far': '동명역전체'},
      );
      final nearLabel = layout.labels.firstWhere((l) => l.id == 'near:L1');
      final farLabel = layout.labels.firstWhere((l) => l.id == 'far:L2');
      // near만 오너 앵커(0,0)를 쓴다 — start anchor → rect.left == 0.
      expect(nearLabel.rect.left, 0);
      // far는 폴백 검색 배치 — 자기 station(60,0) 근방, 오너 앵커(0,0)와 무관.
      expect(
        (farLabel.rect.center - const Offset(0, 0)).distance,
        greaterThan(30),
      );
      // 두 라벨은 서로 겹치지 않아야 한다(동명이역 겹침 해소가 핵심 목적).
      expect(nearLabel.rect.overlaps(farLabel.rect), isFalse);
    });

    test('이름 정규화(#2068 7차): 중점(·)↔마침표(.) 표기 차를 매칭한다', () {
      const design = RouteMapDesignSpace(designScale: 1);
      final map = soloStationMap();
      // sidecar 키는 중점, station 원본명은 마침표(반대 방향도 대칭 성립).
      final layout = solveRouteMapLabelLayout(
        map: map,
        design: design,
        labelTextByStationId: const {'s': '4.19민주묘지'},
        badgeLabelByLineId: const {},
        measureLabel: _measureLabel,
        measureBadge: _measureBadge,
        basemap: true,
        ownerLabelsByStationName: {
          '4·19민주묘지': entry(position: const Offset(0, 0)),
        },
        stationNameByStationId: const {'s': '4.19민주묘지'},
      );
      expect(layout.labels.single.rect.left, 0); // 오너 앵커 사용 확인.
    });
  });
}

/// 선분 a→b와 rect의 최소 거리 (0이면 관통).
double _segRectDist(Offset a, Offset b, Rect r) {
  bool seg(Offset p1, Offset p2, Offset p3, Offset p4) {
    double cross(Offset o, Offset x, Offset y) =>
        (x.dx - o.dx) * (y.dy - o.dy) - (x.dy - o.dy) * (y.dx - o.dx);
    final d1 = cross(p3, p4, p1), d2 = cross(p3, p4, p2);
    final d3 = cross(p1, p2, p3), d4 = cross(p1, p2, p4);
    return ((d1 > 0) != (d2 > 0)) && ((d3 > 0) != (d4 > 0));
  }

  final tl = r.topLeft, tr = r.topRight, br = r.bottomRight, bl = r.bottomLeft;
  final edges = [
    [tl, tr],
    [tr, br],
    [br, bl],
    [bl, tl],
  ];
  if (r.contains(a) || r.contains(b)) return 0;
  for (final e in edges) {
    if (seg(a, b, e[0], e[1])) return 0;
  }
  double pointSeg(Offset p, Offset s, Offset t) {
    final st = t - s;
    final len2 = st.distanceSquared;
    final u = len2 == 0
        ? 0.0
        : (((p - s).dx * st.dx + (p - s).dy * st.dy) / len2).clamp(0.0, 1.0);
    return (p - (s + st * u)).distance;
  }

  var best = double.infinity;
  for (final e in edges) {
    best = math.min(best, pointSeg(a, e[0], e[1]));
    best = math.min(best, pointSeg(b, e[0], e[1]));
    best = math.min(best, pointSeg(e[0], a, b));
    best = math.min(best, pointSeg(e[1], a, b));
  }
  return best;
}
