import 'dart:io';

import 'package:easysubway_mobile/features/network_map/domain/route_map_owner_labels.dart';
import 'package:easysubway_mobile/network_map.dart';
import 'package:flutter_test/flutter_test.dart';

// #2068 재발 방지 게이트 — 오너 라벨 sidecar(labels.json)의 **실제 소비처** 기준
// 권역별 실측 고정.
//
// 무엇을 왜 재는가:
//   labels.json은 더 이상 화면 라벨을 그리는 데 쓰이지 않는다. 오너 SVG의 역명
//   라벨이 .vec 바탕층에 그대로 구워지고 앱은 라벨을 렌더하지 않는다(#2068 SVG
//   충실도, 2026-07-26 오너 결정). 남은 소비처는 둘뿐이다:
//     (1) [networkMapOwnerLabelSourceRects] — 라벨 extents를 지도 geometry
//         bounds에 더해 초기 fit·팬 한계·탭 히트 소스 경계를 넓힌다
//         (network_map.dart `_geometryFor`).
//     (2) 초기 카메라 가독 배율 — 라벨 fontSizePx 중앙값
//         ([networkMapReadableInitialMapScale], 별도 게이트
//         route_map_initial_camera_zoom_test.dart가 계산식을 고정한다).
//   두 소비처 모두 **역명 매칭 없이 sidecar 엔트리를 그대로 훑는다**. 그래서 이
//   게이트는 "권역별로 몇 개의 엔트리가 실려 있고, 그 전부가 bounds에 기여하는
//   유효한 rect를 내는가"를 실측값으로 못 박는다. sidecar가 통째로 비거나 일부
//   권역이 누락되면(컴파일러 회귀·자산 갱신 사고) 즉시 red다.
//
// 종전 게이트를 왜 대체했는가:
//   이 파일은 원래 `resolveRouteMapOwnerLabelsForTesting`(솔버의 basemap 전용
//   후보 해소기)로 "오너 라벨 매치 수"를 쟀다. 바탕층 모드가 솔버를 아예 호출하지
//   않게 되면서 그 경로는 프로덕션 도달 불가가 됐고(죽은 코드로 제거), 매치율은
//   실기기 화면과 아무 상관 없는 수가 됐다 — 틀려도 사용자에게 보이는 것이 없고,
//   맞아도 아무것도 보장하지 못한다. 그래서 측정 대상을 살아 있는 소비처로
//   옮겼다. 화면 라벨 자체의 SVG 정합은
//   tools/route-map/basemap-svg-fidelity-gate.test.mjs(SVG↔산출물 전수 대조)가
//   지킨다.
//
// 실측 기준선(2026-07-26, 커밋된 labels.json). 라벨 추가/교정으로 수가 바뀌면
// 의도한 변경인지 확인하고 기준선을 함께 갱신한다.
void main() {
  final sidecarJson = File(
    'assets/datapacks/metro_map_pack/basemap/labels.json',
  ).readAsStringSync();

  // (표시명, sidecarId, 엔트리 수, 서로 다른 역명 키 수).
  // 엔트리 수 > 키 수인 권역은 동명이역(seoul 2건, busan 3건)이 있다는 뜻 —
  // 이름 단일 맵으로 파싱이 퇴화하면 키 수만 남아 red가 된다.
  const cases = <(String, String, int, int)>[
    ('수도권', 'seoul', 655, 653),
    ('부산권', 'busan', 147, 144),
    ('대구권', 'daegu', 97, 97),
    ('대전권', 'daejeon', 22, 22),
    ('광주권', 'gwangju', 20, 20),
  ];

  for (final (region, sidecarId, expectedEntries, expectedNames) in cases) {
    test(
      '$region labels.json 엔트리 $expectedEntries건이 전부 bounds rect를 낸다 (#2068)',
      () {
        final ownerLabels = parseRouteMapOwnerLabelsForRegion(
          sidecarJson,
          sidecarId,
        );
        expect(
          ownerLabels.length,
          expectedNames,
          reason: '$region sidecar 역명 키 ${ownerLabels.length} — 자산·파서 정합이 바뀜',
        );
        final entries = ownerLabels.values
            .expand((entries) => entries)
            .toList(growable: false);
        expect(
          entries.length,
          expectedEntries,
          reason:
              '$region sidecar 엔트리 ${entries.length} — 동명이역 리스트 보존이 깨졌거나 '
              'SVG 라벨이 추가/삭제됨',
        );

        // 살아 있는 소비처(1): 엔트리 1건당 정확히 rect 1건, 전부 유한·비퇴화.
        // 퇴화 rect(폭·높이 0, NaN)는 geometry bounds에 아무것도 더하지 못해
        // 라벨이 화면 밖으로 잘리는 실기기 반려로 이어진다(#2068 광주 '학동·
        // 증심사입구' 사례).
        final rects = networkMapOwnerLabelSourceRects(ownerLabels: entries);
        expect(rects.length, entries.length);
        for (var i = 0; i < rects.length; i += 1) {
          final rect = rects[i];
          expect(
            rect.isFinite && rect.width > 0 && rect.height > 0,
            isTrue,
            reason:
                '$region ${entries[i].station} 라벨 rect가 퇴화($rect) — '
                'geometry bounds에 기여하지 못한다',
          );
        }
      },
    );
  }
}
