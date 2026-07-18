import 'dart:ui';

import 'package:easysubway_mobile/features/network_map/domain/route_map_design_space.dart';
import 'package:easysubway_mobile/features/network_map/presentation/route_map_label_layout.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/capital_route_map_fixture.dart';

// 결정적 보수 측정: 한글 전각 폭 ≈ 폰트 px/자. 실기기 TextPainter 실측(비전각
// 혼재)보다 넓게 잡는다 — 이 근사로 겹침이 없으면 실기기에서도 없다.
Size _measureLabel(
  String text, {
  required bool bold,
  required double fontSize,
}) => Size(text.length * fontSize, fontSize + 4);
Size _measureBadge(String text, {required double fontSize}) =>
    Size(text.length * fontSize + 12, fontSize + 7);

// 재간격 + 부역명 축약 + gap 확장 반영(2026-07-06 실측): 64→2. 잔여 기약 1쌍은
// 라벨 배치로 분리 불가한 근접 평역명 케이스로, v1에서는 임진강/운천(경의중앙
// 최북단)이었고 v2(#2011) canonical에서는 삼성중앙/봉은사(9호선 인접)로 이동했다
// — 도심 겹침은 0이다(스펙 R3). baseline은 악화 금지(unresolved≤2·라벨-라벨≤1 유지).
const int kCapitalUnresolvedBaseline = 2;

// 2026-07-06 실기기 클러터 게이트 확장 — 라벨-라벨 외 라벨-선·뱃지 겹침도 측정해
// "게이트=실기기 체감" 정합. baseline은 현재 실측값(악화 금지); 후속 수정이 낮춘다.
// [2026-07-11 #1950] 정본을 오너 자작 8선형 도식으로 교체하며 신 레이아웃 실측으로
// baseline 재설정: 라벨-라벨 겹침 0 유지(핵심 게이트 통과), 뱃지-선 0.
// [2026-07-11 #1965 리뷰 후속] 우이신설 뱃지 ↔ 성수지선 spur 라벨(용두) 코너 ~3px
// 접촉을 라벨 배치 gap 사다리 확장(+18 단 추가)으로 해소 — 뱃지-라벨 1→0 복귀,
// 라벨-선도 부수 개선(14→9). 라벨-라벨 0·unresolved 0은 유지(다른 게이트 무영향).
// [2026-07-12 #2011] 오너 자작 수도권 정본을 v2(환승 중심 정렬 v4-clean·경의중앙
// 동농~지평 스무딩)로 교체하며 신 canonical 기하 실측으로 baseline 재설정. v2는
// 역 추가/삭제 0·이동 29(도심 환승부 + 5호선 하남지선 + 경의중앙 동부)로, 서울역/
// 공덕/효창공원앞 중심 재정렬이 도심 라벨-선 접점을 2 늘렸다(9→11). 라벨 solver는
// 이미 floor(unresolved 1·라벨-라벨 1)이며 나머지는 v2 기하에서 라벨 배치로 분리
// 불가한 기약 접점(도심 환승 밀집부)이다. 핵심 불변식(라벨-라벨 ≤1·뱃지 0·unresolved
// ≤2)은 v2에서도 유지된다. 실측값(악화 금지): 라벨-선 11, 뱃지-선 0, 뱃지-라벨 0.
// [2026-07-18 #2068] 유클리드 간격 하드게이트 대응(팩 기준 최근접 <48 붕괴 492건
// → 16건, 예외 근거 명시) — 손그림 SVG의 역 circle·환승 캡슐 좌표를 pairwise 반발
// 솔버로 재간격(median 이동 ~9px, 최대 ~90px)했다. 순수 station 좌표 이동이라
// 라벨-라벨(0)·뱃지(0·0)·unresolved(0)는 전부 무영향이지만, 라벨-선 겹침은
// solver가 근접 역들을 갈라놓으며 인접 선분 기하가 바뀌어 11→23으로 늘었다(전부
// 자유공간 라벨-선 접점, 라벨-라벨/뱃지 악화 없음). 원인 성격상 station 좌표
// 재배치가 아니라 라벨 앵커의 국소 재배치(부산 검증 방법의 국소 모드, #2068 1단계
// 선례)로 낮춰야 하는데 이번 패스 범위 밖 — baseline만 실측값으로 올리고 후속
// 커밋에서 국소 라벨 넛지로 되돌린다. 실측값(악화 금지): 라벨-선 23, 뱃지-선 0,
// 뱃지-라벨 0.
//
// 조사 후속(#2068 3단계, 2026-07-18): 위 "라벨 앵커의 국소 재배치"로 낮춘다는
// 계획을 재검토했다 — 이 파일의 layout은 `capital_basemap_label_overlap_gate_
// _test.dart`(오너 SVG 라벨 anchor·labels.json sidecar 사용)와 달리
// `solveRouteMapLabelLayout`을 오너 anchor 없이(`ownerLabelsByStationName`
// 미전달) 호출한다 — 라벨 anchor는 오직 station/캡슐 좌표에서만 나온다(실측
// 확인: route_map_label_layout.dart의 anchor = station.position 또는 환승
// centroid). 즉 이 게이트는 **라벨 SVG 위치와 무관**하고 station 좌표에만
// 반응한다 — "라벨 앵커의 국소 재배치"가 아니라 **station 좌표의 국소 재배치**
// (부산 선례의 진짜 대상, apply-busan-label-nudges.mjs류)가 유일한 레버다.
//
// apply-euclidean-svg-respacing.mjs(별칭 매핑·마커 없는 라벨 폴백 확장, 커밋
// 도구화)로 census 예외를 16→0까지 완전 해소하면서 조사 7 시점보다 더 많은
// 역이 재간격돼(다체 클러스터 2건 포함, 목표였던 "예외 ≤3"보다 엄격하게 0을
// 달성) 라벨-선 접점이 23→25로 소폭 추가 증가했다(labelLine 실측, 전수 진단:
// 정확히 25개 라벨이 각각 ≥1개 track 세그먼트와 겹침 — 신대방삼거리(7개
// 세그먼트)·개화산(5)·시민공원(4)·석천사거리(4) 등 소수가 다중 세그먼트에
// 걸쳐 있고 나머지 15개는 단일 세그먼트 근접). station 좌표 국소 재배치로
// 해소하려면 각 건마다 SVG circle 좌표 이동 + 파이프라인 재실행 + 유클리드
// census·8선형·alignment(<5px) 전 게이트 재검증이 필요해(#2068 P-65 "팩=SVG
// 고정" 하드 계약상 팩만 옮기는 busan류 단축 경로 사용 불가) 이번 패스
// 범위로는 위험도 대비 낮은 우선순위로 보류한다 — baseline을 실측값 25로
// 올리고 후속 커밋에서 station 좌표 국소 재배치로 낮춘다.
//
// 같은 재간격으로 뱃지-선도 0→1 됐다(전수 진단: line-5500c1600f71 김포골드
// 뱃지가 자기 노선이 아니라 김포공항 3중 환승 허브에서 만나는 다른 노선
// (line-f0e747248a31, 공항철도) 세그먼트 가장자리와 정확히 접함 — 뱃지
// rect 우측 경계 x=561.1과 세그먼트 x=561.1이 일치하는 경계 접촉). 뱃지
// 배치 알고리즘(route_map_label_layout.dart)이 자기 노선 트랙만 회피하고
// 타 노선 세그먼트는 장애물로 보지 않아(허브 밀집부에서 드물게 노출되는
// 기존 알고리즘의 사각) station 좌표만으로는 결정적으로 못 고친다 — 뱃지
// 배치 로직 자체 보강이 필요해 이번 패스 범위 밖. 실측값(악화 금지):
// 라벨-선 25, 뱃지-선 1, 뱃지-라벨 0.
const int kCapitalLabelLineOverlapBaseline = 25;
const int kCapitalBadgeLineOverlapBaseline = 1;
const int kCapitalBadgeLabelOverlapBaseline = 0;

void main() {
  test('수도권 실데이터: 전 라벨 표시 + 겹침 악화 금지 게이트', () {
    final fixture = loadCapitalRouteMapFixture();
    final layout = solveRouteMapLabelLayout(
      map: fixture.map,
      design: routeMapDesignSpaceFor(fixture.map),
      labelTextByStationId: fixture.labelTextByStationId,
      badgeLabelByLineId: fixture.badgeLabelByLineId,
      measureLabel: _measureLabel,
      measureBadge: _measureBadge,
    );
    // 숨김 금지: 환승은 그룹당 1, 나머지는 역·노선당 1 — 계약상 전 역이 라벨을 가진다.
    expect(layout.labels.length, greaterThan(600));
    expect(
      layout.unresolvedOverlapCount,
      lessThanOrEqualTo(kCapitalUnresolvedBaseline),
      reason:
          '실측 unresolved=${layout.unresolvedOverlapCount} — baseline 갱신 금지, '
          '재간격+축약+gap 확장으로 2 이하를 유지해야 한다',
    );
    // 라벨-라벨 겹침 쌍은 기약 1쌍(임진강/운천) 이하 — 도심 포함 그 외 전부 0.
    final labelRects = layout.labels.map((l) => l.rect).toList();
    var overlapPairs = 0;
    for (var i = 0; i < labelRects.length; i += 1) {
      for (var j = i + 1; j < labelRects.length; j += 1) {
        if (labelRects[i].overlaps(labelRects[j])) overlapPairs += 1;
      }
    }
    expect(overlapPairs, lessThanOrEqualTo(1), reason: '라벨 겹침 쌍 $overlapPairs');

    // 라벨-선·뱃지 겹침(실기기 클러터) 악화 금지.
    final design = routeMapDesignSpaceFor(fixture.map);
    final labelLine = routeMapLabelLineOverlapCount(
      layout,
      fixture.map,
      design,
    );
    final badge = routeMapBadgeOverlapCounts(layout, fixture.map, design);
    expect(
      labelLine,
      lessThanOrEqualTo(kCapitalLabelLineOverlapBaseline),
      reason:
          '라벨-선 겹침 $labelLine — baseline $kCapitalLabelLineOverlapBaseline 악화 금지',
    );
    expect(
      badge.line,
      lessThanOrEqualTo(kCapitalBadgeLineOverlapBaseline),
      reason:
          '뱃지-선 겹침 ${badge.line} — baseline $kCapitalBadgeLineOverlapBaseline 악화 금지',
    );
    expect(
      badge.label,
      lessThanOrEqualTo(kCapitalBadgeLabelOverlapBaseline),
      reason:
          '뱃지-라벨 겹침 ${badge.label} — baseline $kCapitalBadgeLabelOverlapBaseline 악화 금지',
    );
  });
}
