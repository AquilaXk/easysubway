import 'dart:ui';

import 'package:easysubway_mobile/features/network_map/domain/route_map_design_space.dart';
import 'package:easysubway_mobile/features/network_map/domain/structured_route_map.dart';
import 'package:easysubway_mobile/features/network_map/presentation/route_map_label_layout.dart';
import 'package:flutter_test/flutter_test.dart';

// 결정적 실측: 글자 수 × 9px, 높이 13px (bold 동일 — 판정에 크기 차 불필요).
Size _measureLabel(String text, {required bool bold}) =>
    Size(text.length * 9.0, 13.0);
Size _measureBadge(String text) => Size(text.length * 8.0 + 10, 18.0);

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

  test('뱃지는 끝점 2개 + 반복 배치(긴 노선)', () {
    final map = _gridMap(count: 60); // 폴리라인 길이 > 반복 간격 수 배
    final layout = _solve(map);
    // 끝점 2 + 내부 반복 ≥ floor(arcLen/interval) 근사 — 최소 3개 이상.
    expect(layout.badges.length, greaterThanOrEqualTo(3));
  });

  test('전부 충돌이어도 숨기지 않고 최소 겹침 배치 + unresolved 집계', () {
    // 같은 좌표에 역 5개 → 물리적으로 겹침 불가피.
    final stations = [
      for (var i = 0; i < 5; i += 1)
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
    expect(layout.labels.length, 5); // 숨김 금지.
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
}
