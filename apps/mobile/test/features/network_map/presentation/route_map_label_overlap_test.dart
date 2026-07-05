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
    lines: const [],
    stations: stations,
    transferGroups: transfers,
  );
}

Map<String, String> _labelText(StructuredRouteMap map) => {
      for (final s in map.stations) s.stationId: s.stationId,
    };

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
      final map = _gridMap(spacing: 60);
      final candidates = routeMapLabelCandidates(
        map,
        _camera(),
        0,
        labelTextByStationId: _labelText(map),
        measure: (_, _) => _labelSize,
        isVisible: (_) => true,
        stationRadius: 3,
        transferAnchorPadding: 7,
      );
      expect(candidates, isEmpty);
    });

    test('bucket 1은 환승·주요만, 일반은 제외한다', () {
      final map = _gridMap(spacing: 60);
      final ids = routeMapLabelCandidates(
        map,
        _camera(),
        1,
        labelTextByStationId: _labelText(map),
        measure: (_, _) => _labelSize,
        isVisible: (_) => true,
        stationRadius: 3,
        transferAnchorPadding: 7,
      ).map((c) => c.id).toList();
      expect(ids.where((id) => id.startsWith('transfer:')), hasLength(2));
      expect(ids.where((id) => id.startsWith('major-')), hasLength(3));
      expect(ids.any((id) => id.startsWith('regular-')), isFalse);
    });

    test('bucket 2는 일반 라벨까지 후보에 포함한다', () {
      final map = _gridMap(spacing: 60);
      final ids = routeMapLabelCandidates(
        map,
        _camera(),
        2,
        labelTextByStationId: _labelText(map),
        measure: (_, _) => _labelSize,
        isVisible: (_) => true,
        stationRadius: 3,
        transferAnchorPadding: 7,
      ).map((c) => c.id).toList();
      expect(ids.any((id) => id.startsWith('regular-')), isTrue);
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
        final placed = _place(_gridMap(spacing: 14), bucket);
        expect(_overlapPairs(placed), 0, reason: 'bucket $bucket 밀집 겹침');
      });
    }

    test('여유 있는 지역은 모든 후보가 배치된다 (과잉 숨김 없음)', () {
      final map = _gridMap(spacing: 80);
      final candidates = routeMapLabelCandidates(
        map,
        _camera(),
        2,
        labelTextByStationId: _labelText(map),
        measure: (_, _) => _labelSize,
        isVisible: (_) => true,
        stationRadius: 3,
        transferAnchorPadding: 7,
      );
      final placed = _place(map, 2);
      expect(placed, hasLength(candidates.length));
    });

    test('밀집 지역에서 환승(최우선) 라벨은 반드시 배치된다', () {
      final placed = _place(_gridMap(spacing: 14), 2);
      final placedIds = placed.map((p) => p.candidate.id).toSet();
      expect(placedIds.contains('transfer:transfer-0'), isTrue);
      expect(placedIds.contains('transfer:transfer-1'), isTrue);
    });
  });
}
