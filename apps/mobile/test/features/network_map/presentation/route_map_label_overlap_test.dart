import 'dart:ui';

import 'package:easysubway_mobile/features/network_map/domain/map_camera.dart';
import 'package:easysubway_mobile/features/network_map/domain/structured_route_map.dart';
import 'package:easysubway_mobile/features/network_map/presentation/route_map_label_placement.dart';
import 'package:easysubway_mobile/features/network_map/presentation/structured_route_map_painter.dart';
import 'package:flutter_test/flutter_test.dart';

// #1642 라벨 겹침 0건 기계 판정: painter가 소비하는 순수 후보 생성
// routeMapLabelCandidates + placeRouteMapLabels 파이프라인을 지역·zoom bucket별로
// 태워, 렌더될 라벨이 서로 겹치지 않고 LOD 정책(bucket 0 선만 / 1 환승·주요 /
// 2 전체)을 지키는지 검증한다. 텍스트 실측은 결정적 크기로 주입한다.

const _labelSize = Size(40, 12);

MapCameraState _camera({double scale = 2.0}) {
  return MapCameraState(
    sourceBounds: const Rect.fromLTWH(0, 0, 4000, 4000),
    viewportSize: const Size(1080, 2000),
    center: const Offset(2000, 2000),
    scale: scale,
    minScale: 0.5,
    maxScale: 3.5,
    revision: 1,
  );
}

/// 대표 지역 맵: 환승 2 + 주요 3 + 일반 N을 격자로 배치한다. [spacing]이 크면
/// 투영 라벨이 서로 멀어 전부 배치되고, 작으면 뭉쳐 충돌 해소가 일어난다.
StructuredRouteMap _gridMap({required double spacing, int regularCount = 12}) {
  final stations = <RouteMapStructuredStation>[];
  final transfers = <RouteMapTransferGroup>[];
  var seq = 0;
  Offset at(int i, int j) => Offset(1500 + i * spacing, 1500 + j * spacing);

  for (var t = 0; t < 2; t += 1) {
    final id = 'transfer-$t';
    stations.add(RouteMapStructuredStation(
      stationId: id,
      lineId: 'L1',
      sequence: seq += 1,
      position: at(t, 0),
      labelPolygon: const [],
      labelClass: RouteMapLabelClass.transfer,
    ));
    transfers.add(RouteMapTransferGroup(
      stationId: id,
      lineIds: const ['L1', 'L2'],
      centroid: at(t, 0),
      memberPositions: [at(t, 0), at(t, 0)],
    ));
  }
  for (var m = 0; m < 3; m += 1) {
    stations.add(RouteMapStructuredStation(
      stationId: 'major-$m',
      lineId: 'L1',
      sequence: seq += 1,
      position: at(m, 1),
      labelPolygon: const [],
      labelClass: RouteMapLabelClass.major,
    ));
  }
  for (var r = 0; r < regularCount; r += 1) {
    stations.add(RouteMapStructuredStation(
      stationId: 'regular-$r',
      lineId: 'L1',
      sequence: seq += 1,
      position: at(r % 6, 2 + r ~/ 6),
      labelPolygon: const [],
      labelClass: RouteMapLabelClass.regular,
    ));
  }
  return StructuredRouteMap(
    // 노선 뱃지 후보가 생기도록 폴리라인 하나를 둔다(양 끝점에 뱃지).
    lines: [
      RouteMapLineGeometry(
        lineId: 'L1',
        polylines: [
          [at(0, 4), at(5, 4)],
        ],
      ),
    ],
    stations: stations,
    transferGroups: transfers,
  );
}

Map<String, String> _labelText(StructuredRouteMap map) => {
      for (final s in map.stations) s.stationId: s.stationId,
    };

const _badgeLabels = <String, String>{'L1': '2'};

List<RouteMapLabelCandidate> _badgeCandidates(StructuredRouteMap map) {
  return routeMapLineBadgeCandidates(
    map,
    _camera(),
    badgeLabelByLineId: _badgeLabels,
    measure: (_, _) => const Size(12, 12),
    isVisible: (_) => true,
    badgeRadius: 9,
  );
}

List<PlacedRouteMapLabel> _place(StructuredRouteMap map, int bucket) {
  final candidates = routeMapLabelCandidates(
    map,
    _camera(),
    bucket,
    labelTextByStationId: _labelText(map),
    measure: (_, _) => _labelSize,
    isVisible: (_) => true,
    stationRadius: 3,
    transferAnchorPadding: 7,
  );
  return placeRouteMapLabels(
    candidates,
    gap: 4,
    viewportBounds: const Rect.fromLTWH(-2000, -2000, 8000, 8000),
  );
}

List<RouteMapLabelCandidate> _candidates(StructuredRouteMap map, int bucket) {
  return routeMapLabelCandidates(
    map,
    _camera(),
    bucket,
    labelTextByStationId: _labelText(map),
    measure: (_, _) => _labelSize,
    isVisible: (_) => true,
    stationRadius: 3,
    transferAnchorPadding: 7,
  );
}

int _overlapPairs(List<PlacedRouteMapLabel> placed) {
  var count = 0;
  for (var i = 0; i < placed.length; i += 1) {
    for (var j = i + 1; j < placed.length; j += 1) {
      if (placed[i].rect.overlaps(placed[j].rect)) count += 1;
    }
  }
  return count;
}

void main() {
  group('routeMapLabelCandidates LOD 정책', () {
    test('bucket 0은 라벨 후보가 없다 (선만)', () {
      expect(_candidates(_gridMap(spacing: 60), 0), isEmpty);
    });

    test('bucket 1은 환승·주요만, 일반은 제외한다', () {
      final ids = _candidates(_gridMap(spacing: 60), 1).map((c) => c.id);
      expect(ids.where((id) => id.startsWith('transfer:')), hasLength(2));
      expect(ids.where((id) => id.startsWith('major-')), hasLength(3));
      expect(ids.any((id) => id.startsWith('regular-')), isFalse);
    });

    test('bucket 2는 일반 라벨까지 후보에 포함한다', () {
      final ids = _candidates(_gridMap(spacing: 60), 2).map((c) => c.id);
      expect(ids.any((id) => id.startsWith('regular-')), isTrue);
    });

    // painter는 candidate.id로 painterById를 keying해 배치 후 paint한다. id 포맷이
    // 드리프트하면 paint lookup이 null이 되어 라벨이 조용히 누락되므로 계약으로 핀.
    test('candidate id 포맷은 painter의 painterById key 규약을 따른다', () {
      final ids = _candidates(_gridMap(spacing: 60), 2).map((c) => c.id).toSet();
      expect(ids.contains('transfer:transfer-0'), isTrue);
      expect(ids.contains('regular-0:L1'), isTrue);
      expect(ids.contains('major-0:L1'), isTrue);
    });
  });

  group('라벨 겹침 0건 (지역 × zoom bucket)', () {
    for (final bucket in [1, 2]) {
      test('bucket $bucket: 배치된 라벨은 서로 겹치지 않는다 (여유 배치)', () {
        final placed = _place(_gridMap(spacing: 80), bucket);
        expect(placed, isNotEmpty);
        expect(_overlapPairs(placed), 0, reason: 'bucket $bucket 라벨 겹침');
      });

      test('bucket $bucket: 밀집 배치에서도 겹침 0 (충돌분은 숨김)', () {
        final map = _gridMap(spacing: 8);
        final candidates = _candidates(map, bucket);
        final placed = _place(map, bucket);
        // vacuous pass 방지: 후보는 있는데 전부 사라지면 안 되고(추출 회귀),
        // 충돌 해소가 실제로 일어났음(placed < candidates)을 함께 단정한다.
        expect(candidates, isNotEmpty);
        expect(placed, isNotEmpty, reason: 'bucket $bucket 최우선 라벨은 남아야');
        expect(
          placed.length,
          lessThan(candidates.length),
          reason: 'bucket $bucket 밀집인데 억제가 없다',
        );
        expect(_overlapPairs(placed), 0, reason: 'bucket $bucket 밀집 겹침');
      });
    }

    test('여유 있는 지역은 모든 후보가 배치된다 (과잉 숨김 없음)', () {
      final map = _gridMap(spacing: 80);
      final candidates = _candidates(map, 2);
      final placed = _place(map, 2);
      expect(candidates, isNotEmpty);
      expect(placed, hasLength(candidates.length));
    });

    test('밀집 지역에서 환승(최우선) 라벨은 반드시 배치된다', () {
      final placed = _place(_gridMap(spacing: 8), 2);
      final placedIds = placed.map((p) => p.candidate.id).toSet();
      expect(placedIds.contains('transfer:transfer-0'), isTrue);
      expect(placedIds.contains('transfer:transfer-1'), isTrue);
    });
  });

  group('노선 뱃지 후보 (#1764 D)', () {
    test('뱃지는 노선 폴리라인 양 끝점에 2개 생기고 priority -1', () {
      final badges = _badgeCandidates(_gridMap(spacing: 60));
      expect(badges, hasLength(2));
      expect(badges.every((b) => b.priority == -1), isTrue);
      expect(
        badges.map((b) => b.id).toSet(),
        {'badge:L1:start', 'badge:L1:end'},
      );
    });

    // 뱃지는 전 bucket 표시라, 라벨이 없는 bucket 0에서도 배치된다.
    List<PlacedRouteMapLabel> placeCombined(StructuredRouteMap map, int bucket) {
      final candidates = <RouteMapLabelCandidate>[
        ..._badgeCandidates(map),
        ..._candidates(map, bucket),
      ];
      return placeRouteMapLabels(
        candidates,
        gap: 4,
        viewportBounds: const Rect.fromLTWH(-2000, -2000, 8000, 8000),
      );
    }

    for (final bucket in [0, 1, 2]) {
      test('bucket $bucket: 뱃지+라벨 결합 배치에 겹침 0, 뱃지는 유지', () {
        final map = _gridMap(spacing: 60);
        final placed = placeCombined(map, bucket);
        final placedIds = placed.map((p) => p.candidate.id).toSet();
        // priority -1 뱃지는 어느 bucket에서도 밀려나지 않는다.
        expect(placedIds.contains('badge:L1:start'), isTrue);
        expect(placedIds.contains('badge:L1:end'), isTrue);
        expect(_overlapPairs(placed), 0, reason: 'bucket $bucket 뱃지+라벨 겹침');
      });
    }

    test('밀집 지역에서도 뱃지(priority -1)는 역명보다 먼저 배치돼 유지된다', () {
      final map = _gridMap(spacing: 8);
      final placed = placeCombined(map, 2);
      final placedIds = placed.map((p) => p.candidate.id).toSet();
      expect(placedIds.contains('badge:L1:start'), isTrue);
      expect(placedIds.contains('badge:L1:end'), isTrue);
      expect(_overlapPairs(placed), 0);
    });

    StructuredRouteMap lineOnlyMap(List<List<Offset>> polylines) {
      return StructuredRouteMap(
        lines: [RouteMapLineGeometry(lineId: 'L1', polylines: polylines)],
        stations: const [],
        transferGroups: const [],
      );
    }

    test('순환선(시·종점 동일)은 뱃지를 한 번만 둔다', () {
      // 폐루프: 첫 정점 == 마지막 정점.
      final map = lineOnlyMap([
        const [Offset(100, 100), Offset(200, 100), Offset(100, 100)],
      ]);
      final badges = _badgeCandidates(map);
      expect(badges, hasLength(1));
      expect(badges.single.id, 'badge:L1:start');
    });

    test('선행/후행 빈 sub-polyline이 있어도 유효 세그먼트에서 뱃지 2개', () {
      final map = lineOnlyMap([
        const [],
        const [Offset(100, 100), Offset(300, 100)],
        const [],
      ]);
      final badges = _badgeCandidates(map);
      expect(badges.map((b) => b.id).toSet(), {'badge:L1:start', 'badge:L1:end'});
    });

    test('모든 sub-polyline이 비면 뱃지 없음', () {
      final map = lineOnlyMap([const [], const []]);
      expect(_badgeCandidates(map), isEmpty);
    });
  });
}
