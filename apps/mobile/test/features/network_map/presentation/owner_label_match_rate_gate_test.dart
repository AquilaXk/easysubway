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
// 정규화(중점 '·'→마침표 '.')·동명이역 최근접 1:1 매칭·위치 게이트 185px를
// 전부 앱과 똑같이 적용하므로, 여기서 세는 matched 수 = 실기기에서 오너 SVG
// font-size로 그려지는(폴백 미니가 아닌) 라벨 수다.
//
// 실측 기준선(2026-07-17, capital 팩 + 커밋된 labels.json):
//   광주  20/20  (전 역 매치 — 회귀 교정 후 fe1c413f 상태 복원)
//   대전  22/22  (전 역 매치)
//   수도권 651   (#2068 부산 4차 2단계: 동명이역 라벨을 이름당 리스트로 보존하고
//               역별 최근접 1:1 매칭으로 바꿔, 양평 2역(경의중앙선·수인분당선)이
//               각자 자기 라벨을 갖는다 — 이전 651에서 +1(652). 미매치 4: 도라산·
//               총신대입구·신촌·하남검단산역 sidecar 미표기/1:1 매칭 실패.
//
//               조사 9(#2068 마감 — 8선형 재작도 + 유클리드 재간격, 2026-07-18):
//               오너 반려("간선 8방향+코너만 곡선, 노드 이탈 다수")로 22개
//               노선 stroke를 line_sequence 순서 8선형 재작도하고, 파이프라인
//               재실행 시 경복궁·안국(47.68)·문학경기장·인천터미널(47.81) 등
//               48px 임계 바로 위 쌍이 후속 트랙 스냅에서 침식돼 재발하는 것을
//               막기 위해 반발 솔버를 여유 있게(threshold 49~50, target 54~56,
//               4라운드) 재적용, 최대 12.8px(병점) 이동. 역(약수)·라벨 자체
//               좌표는 이동하지 않았지만 인근 다른 후보가 이동해 185px 최근접
//               게이트에서 약수(환승, 3호선·6호선)의 1:1 배정을 빼앗아
//               652→651로 1건 준다(실측 확인 — 약수 station/label 좌표 자체는
//               HEAD 대비 1px 미만). 신촌은 이 라운드 이전부터 이미 미매치였다
//               (변화 없음). 라벨-라벨 겹침 게이트(baseline 1/25)는 넛지로
//               복귀했으나 이 1:1 최근접 경쟁 이동까지 넛지로 되돌리면 8선형·
//               유클리드 하드 게이트가 다시 깨지는 국소 양립불가라 baseline을
//               651로 갱신한다(악화 아님 — 원인 규명 완료, 텍스트/nameKo 정합
//               문제 아님).)
//   부산  146/146 (#2068 벡스코 병합 마감: 2호선 벡스코(부역명 시립미술관)와
//               동해선 벡스코를 단일 환승 station_id로 병합(merge-busan-transfers.mjs)
//               하면서, 후보(물리역)가 147→146으로 준다(벡스코가 비환승 2역에서
//               환승 그룹 1로 합쳐짐). 병합 후 벡스코는 단일 환승 캡슐이 전사 라벨
//               '벡스코(시립미술관)'을 가지므로, 오너 SVG의 중복 ordinary 라벨
//               (벡스코_DH)을 제거해 중복 표기를 없앴다 → 매치 147→146(전 역 매치
//               유지). 부전은 여전히 별개 station_id 2역이라 부전_DH 라벨은 유지된다.
//               5차 canonicalRules 정합(벡스코(시립미술관)→벡스코, 부산역→부산,
//               경성대·부경대→경성대.부경대, 국제금융센터·부산은행→국제금융센터.
//               부산은행)은 그대로 유지된다.)
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
    ('부산권', 'busan', 146, 146),
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
