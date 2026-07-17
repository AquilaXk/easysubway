import 'dart:io';

import 'package:easysubway_mobile/features/network_map/domain/route_map_design_space.dart';
import 'package:easysubway_mobile/features/network_map/domain/route_map_owner_labels.dart';
import 'package:easysubway_mobile/features/network_map/domain/structured_route_map.dart';
import 'package:easysubway_mobile/features/network_map/presentation/route_map_label_layout.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/capital_route_map_fixture.dart';

// #2068 재발 방지 게이트 — 권역별 오너 라벨 매치 수 고정.
//
// basemap 라벨은 오너 SVG에서 추출한 sidecar(labels.json)의 실측 좌표·크기로
// 그려지고, 역명 매칭에 실패하면 자동 솔버 폴백(작은 미니 크기)으로 렌더된다.
// SVG <text> 내용이 카탈로그 nameKo와 어긋나면(예: '광주송정'↔'광주송정역') 그
// 역만 조용히 미니 크기로 회귀한다(9ab890ef 실기기 회귀). 이 게이트는 그런
// 회귀가 나면 즉시 red가 되도록 각 권역 매치 수를 실측값으로 못 박는다.
//
// 매칭 판정은 앱 렌더와 100% 동일 로직을 재사용한다 —
// route_map_label_layout.dart의 [resolveRouteMapOwnerLabelsForTesting]
// (=solveRouteMapLabelLayout이 basemap 모드에서 쓰는 후보 해소기). 이름
// 정규화(중점 '·'→마침표 '.')·동명이역 최근접 1개 채택·위치 게이트 185px를
// 전부 앱과 똑같이 적용하므로, 여기서 세는 matched 수 = 실기기에서 오너 SVG
// font-size로 그려지는(폴백 미니가 아닌) 라벨 수다.
//
// 실측 기준선(2026-07-16, capital 팩 + 커밋된 labels.json):
//   광주  20/20  (전 역 매치 — 회귀 교정 후 fe1c413f 상태 복원)
//   대전  22/22  (전 역 매치)
//   수도권 651   (미매치 5: 도라산·총신대입구·하남검단산역 등 sidecar 미표기
//               + 동명이역 위치 게이트 제외분 — 폴백 솔버로 표시됨)
//   부산  141    (미매치 5: 벡스코·부산 등 표기차 + 게이트 제외분)
//   대구  97/97  (#2068 대구 QA: 부호·하양·서대구역 canonicalRules 교정으로 전 역 매치)
// 이 수는 하한이 아니라 정확값이다 — 라벨 추가/교정으로 개선되면(의도적)
// 기준선을 함께 올리고, 줄면 회귀이므로 red가 정상이다.
void main() {
  final sidecarJson = File(
    'assets/datapacks/metro_map_pack/basemap/labels.json',
  ).readAsStringSync();

  // (dbRegion, sidecarId, 기대 매치 수, 후보(=물리역) 수).
  const cases = <(String, String, int, int)>[
    ('수도권', 'seoul', 651, 656),
    ('부산권', 'busan', 141, 146),
    ('대구권', 'daegu', 97, 97),
    ('대전권', 'daejeon', 22, 22),
    ('광주권', 'gwangju', 20, 20),
  ];

  for (final (dbRegion, sidecarId, expectedMatched, expectedCandidates)
      in cases) {
    test('$dbRegion basemap 오너 라벨 매치 $expectedMatched건 고정 (#2068)', () {
      final fixture = loadCapitalRouteMapFixture(region: dbRegion);
      final design = routeMapDesignSpaceFor(fixture.map);
      final ownerLabels = parseRouteMapOwnerLabelsForRegion(
        sidecarJson,
        sidecarId,
      );

      // 후보(=오너 라벨을 받을 수 있는 물리역) 수 — 앱 후보 생성과 동일 규칙
      // (환승 그룹당 1 + 비환승 역·노선당 1). sidecar/카탈로그가 통째로
      // 어긋나면 이 수부터 흔들리므로 함께 고정한다.
      var candidateKeys = 0;
      for (final group in fixture.map.transferGroups) {
        if (fixture.stationNameByStationId[group.stationId] != null) {
          candidateKeys += 1;
        }
      }
      for (final station in fixture.map.stations) {
        if (station.labelClass != RouteMapLabelClass.transfer &&
            fixture.stationNameByStationId[station.stationId] != null) {
          candidateKeys += 1;
        }
      }
      expect(
        candidateKeys,
        expectedCandidates,
        reason: '$dbRegion 후보 물리역 수 $candidateKeys — 카탈로그/픽스처 정합이 바뀜',
      );

      final resolved = resolveRouteMapOwnerLabelsForTesting(
        map: fixture.map,
        design: design,
        ownerLabelsByStationName: ownerLabels,
        stationNameByStationId: fixture.stationNameByStationId,
      );
      expect(
        resolved.length,
        expectedMatched,
        reason:
            '$dbRegion 오너 라벨 매치 ${resolved.length}/$candidateKeys (기대 '
            '$expectedMatched) — SVG <text> 텍스트나 카탈로그 nameKo 정합이 깨지면 '
            '해당 역이 폴백 미니 크기로 회귀한다(#2068 광주송정역 사례)',
      );
    });
  }
}
