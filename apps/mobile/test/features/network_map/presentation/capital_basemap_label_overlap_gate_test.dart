import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:easysubway_mobile/features/network_map/domain/route_map_design_space.dart';
import 'package:easysubway_mobile/features/network_map/domain/route_map_owner_labels.dart';
import 'package:easysubway_mobile/features/network_map/domain/structured_route_map.dart';
import 'package:easysubway_mobile/features/network_map/presentation/route_map_label_layout.dart';
import 'package:easysubway_mobile/features/network_map/presentation/structured_route_map_painter.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/capital_route_map_fixture.dart';
import '../../../support/pretendard_test_font.dart';

// #2068 Pretendard 번들 후: basemap 라벨을 오너 SVG font-size 그대로(클램프 제거)
// + 오너와 동일한 Pretendard로 렌더하고, 앱 렌더와 동일한 실측 경로
// ([measureRouteMapLabel]/[measureRouteMapBadge], basemap:true — Pretendard
// family·weight)로 겹침을 센다. flutter test는 번들 폰트를 자동 로드하지 않으므로
// setUpAll에서 FontLoader로 Pretendard를 로드한다(로드 성공은 support 헬퍼가
// 파일 존재 assert로 보장).
//
// 가설 검증 결과 1(수도권 실데이터 fixture, Pretendard 실메트릭):
// - 10차 32쌍이 "SVG=Pretendard vs 앱=시스템 폰트 자폭차" 탓이라는 가설은
//   **기각**됐다. Pretendard 자폭 일치 후에도 오너 크기(클램프 제거)에서
//   라벨-라벨 겹침은 32→29쌍(미미)에 그쳐, 지배적 원인은 13px 상한 클램프
//   제거로 수도권 밀집부 라벨이 16.48/17.85 design px로 커진 것이었다.
//
// 조사 2(compile-basemap-vec.mjs 추출 결함 2건 발견·교정, 실측 기반):
// - **결함 A**: text-anchor가 속성이 아니라 style 선언 안에만 있는 라벨
//   (Inkscape 수작업, sma-v2 6건: 영등포구청·이수·부천종합운동장·
//   송도달빛축제공원·신검단중앙·국제업무지구)을 전부 "start"로 오판 → 앵커가
//   실제보다 우측으로 쏠려 이웃 라벨과 오탐 겹침을 만들었다.
// - **결함 B**: 여러 줄(2단) 라벨에서 첫 tspan이 부모 <text>와 다른(더 작은)
//   x를 선언하는 4건(영등포구청·이수·부천종합운동장·신검단중앙, 결함 A와
//   교집합)에서 부모 x를 쓰면 마찬가지로 앵커가 우측으로 쏠렸다. SVG 텍스트
//   청크 규칙상 tspan이 자체 x를 선언하면 그 지점이 실제 앵커이므로 tspan을
//   우선한다.
// - 두 결함을 고치고 labels.json을 재생성(compile --verify)하니 pairs
//   29→**25**로 줄었다(extractOwnerLabels 테스트 4건 추가, 회귀 가드).
//
// 조사 3(잔여 25쌍 실측 검증 — 헤드리스 크롬 + 실제 Pretendard로 원본 SVG를
// 직접 렌더해 getBBox로 대조, 2026-07-17):
// - 25쌍 중 24쌍은 한쪽 이상이 오너 SVG에서 **2줄로 줄바꿈된 라벨**이다(예:
//   검단사거리="검단"/"사거리" 2줄, y 오프셋 28.8 — station-label 실측
//   tspan 2개, y 델타 일정). 반면 앱은 basemap 라벨을 항상 **단일 줄**
//   (`maxLines: 1`)로 렌더해, 오너가 2줄로 좁게 배치한 이름을 풀네임 1줄
//   폭으로 측정·배치한다 — 이게 오탐 겹침의 실제 원인이다. 대표 5쌍(검단사거리
//   ×마전·솔밭공원×4.19민주묘지·검단오류×왕길·동두천중앙×지행·신길온천×안산)
//   + 추가 3쌍(을지로3가×을지로4가·장승배기×신대방삼거리·흥선×의정부중앙)을
//   로컬 HTTP 서버로 원본 SVG를 서빙하고 FontFace API로 실제 번들 Pretendard
//   (Regular/SemiBold/Bold)를 로드한 뒤 getBBox()+getCTM()으로 직접 측정 —
//   전부 겹치지 않는다(ox=0, 즉 두 라벨의 실제 렌더 폭 사이에 여백이 있다).
// - 예외 1쌍(마곡나루×신방화, 둘 다 단일 줄): 실제 SVG 렌더에서도 **미세하게
//   겹친다**(ox≈0.04design 단위 — 서브픽셀 수준, 오너 SVG 자체의 근접 배치).
//   이 1쌍만 "오너 디자인 그대로"다.
//
// 조사 4(다줄 라벨 렌더 구현, 2026-07-17): 조사 3의 진단대로 다줄 라벨을
// 실제로 구현했다 — compile-basemap-vec.mjs의 extractOwnerLabelLineLocalPositions
// 가 2줄 이상 라벨의 줄 구성(text+좌표)을 labels.json `lines` 필드로 뽑고
// (daejeon의 class=station-sub 부기 캡션은 표시 라벨이 아니므로 제외),
// route_map_label_layout.dart의 [_ownerFixedLabel]이 (이어붙인 줄 텍스트가
// 앱 표시 텍스트와 정확히 같을 때만, 안전 가드) 줄마다 독립 rect로 배치하며
// structured_route_map_painter.dart가 줄마다 그린다. 결과: pairs
// **25→3**로 줄었다(실측 검증):
// - 마곡나루×신방화(둘 다 단일 줄): 조사 3에서 이미 확인한 오너 SVG 자체의
//   서브픽셀 근접 배치 — "오너 디자인 그대로", 이 게이트가 고칠 대상이 아니다.
// - 솔밭공원×4.19민주묘지: 솔밭공원은 다줄 렌더되지만 4.19민주묘지는 안전
//   가드에 걸려 단일 줄로 폴백한다 — entry.station(오너 SVG 원문, 중점 "4·19
//   민주묘지")과 앱 표시 텍스트("4.19민주묘지", DB 표기는 마침표)가 문자열
//   불일치라 다줄 렌더를 건너뛴다(매칭 자체는 _normalizeOwnerLabelNameKey의
//   중점↔마침표 정규화로 성립하지만, 그 정규화는 후보 키 조회에만 적용되고
//   entry 텍스트 자체를 바꾸지 않는다 — 7차 지시대로 정규화 범위를 넓히지
//   않는다). 헤드리스 크롬 검증(조사 3)에서 이미 이 쌍은 실제 SVG에서
//   겹치지 않음을 확인했다 — 안전 가드의 보수적 비용.
// - 석천사거리×모래내시장(둘 다 다줄): 헤드리스 크롬 getBBox 재검증 결과 실제
//   SVG는 겹치지 않는다(oy=0, 두 라벨이 수직으로 딱 붙어 있을 뿐). 우리 rect
//   모델은 줄 높이를 TextPainter 실측(≈font×1.3)으로 근사하는데, 이 근사가
//   오너의 실제 줄간격(로컬 28.8 단위, font×1.09)보다 살짝 커 인접 줄이
//   0.5design 단위 정도 겹치는 것으로 오판한다 — 폭 근사와 같은 "과대 방향
//   안전 근사"의 부작용(있어도 라벨을 자르지 않지만, 겹침 카운트엔 잡힌다).
// - 클램프 재도입은 오너의 "글자 키워" 요청을 도로 막으므로 하지 않았다(명시적
//   지시 준수). 남은 3쌍은 1건 오너 디자인 그대로 + 2건 근사 모델의 보수적
//   비용이라 baseline을 3으로 고정한다(악화 금지) — 0으로 더 낮추려면 (a)
//   4.19민주묘지류의 · /. 표기차를 흡수하는 별도 정규화, (b) 줄 높이를 더
//   타이트하게 근사(단, 폭과 달리 과소 방향 위험) 가 필요해 별도 과제로 남긴다.
//
// 조사 5(#2068 수도권 노드 간격 최소 기준 패스, 2026-07-18): 인접 역 간 최소
// 간격을 48px 이상으로 벌리는 코리더 방향 보존 연장(같은 노선 내에서만 적용)
// 후 pairs 3→31로 증가했다. 진단(겹치는 라벨 쌍 전수 실측) 결과 31쌍 중
// 30쌍이 "이번에 연장으로 이동한 역(같은 노선 코리더 소속) × 이동하지 않은
// 이웃 역(대개 인접 노선의 환승/근접 역)" 패턴이다 — 예: 도봉산(고정)×
// 의정부(109px 이동), 연신내(고정)×구파발(74px 이동), 회룡(고정)×가능
// (97px 이동). 코리더 연장은 "같은 노선 연속 역"만 방향 보존해 벌리므로,
// 그 결과 이웃한 **다른 노선**의 역·환승 허브 쪽으로 가까워지는 경우까지는
// 고려하지 않는다(원래 실측 범위: 평행 코리더 근접은 "환승 캡슐 내부 밀집
// 제외"와 함께 국소 리팩토링 대상이나, 노드 간격 패스는 승인 범위인 동일노선
// 코리더 연장만 수행했다). 나머지 1쌍(마곡나루×신방화)은 조사 3부터 있던
// 오너 디자인 그대로의 서브픽셀 근접이다.
//
// 조사 6(#2068 수도권 국소 라벨 재배치, 2026-07-18): 조사 5의 31쌍을 국소
// 모드로 해소했다 — 겹침에 연루된 **일반(비환승) 역 라벨 30개만** 앱과
// 동일한 배치 프리미티브(routeMapMapOutwardAnchorOrder 8방향 × gap 사다리,
// routeMapLabelRect)로 자기 노드 앵커 주변에서 최소 변위 무충돌 위치를 찾아
// 옮겼다(환승/허브 라벨은 오너 배치 그대로 고정, 오너 손배치 최대 보존).
// 장애물 모델은 다른 라벨 전체·노드·환승 캡슐·선 밴드·서비스 표장(KTX/SRT/
// AIR)까지 포함한다. 재배치는 SVG(easy-subway-sma-v2.svg) 라벨 앵커를
// 강체 평행이동(합성 스케일 0.455 역산)해 반영하고 compile-basemap-vec로
// labels.json을 재생성했다 — 이동량 중앙값 ≈24 design px, 최대 ≈58.
// 결과 pairs 31→**1**로 줄었다(조사 3~5의 원 baseline 3보다도 낮음). 남은
// 1쌍(보라매×보라매공원)은 보라매 환승 허브 캡슐·라벨과 신풍·당곡 사이에
// 낀 긴 일반 라벨(보라매공원)이 gap 사다리 전 구간에서 무충돌 위치를 못 찾는
// 밀집 제약으로, 허브 라벨을 고정하는 한 남는 하드 케이스다. baseline을 1로
// 갱신한다(악화 금지).
//
// 이름 매칭은 가운뎃점 변형(·/ㆍ)↔마침표(.) 정규화 + 공백 trim만 적용한다
// (#2068 7차 지시 2, #2408 후속 확장 — 다른 정규화는 과매칭 위험이라 하지
// 않는다, route_map_label_layout.dart의 _normalizeOwnerLabelNameKey와 동일
// 규칙을 이 파일 매치율 계산에도 미러링).
String _normalizeNameForMatchRate(String name) =>
    name.replaceAll('·', '.').replaceAll('ㆍ', '.').trim();

Size _measureLabel(
  String text, {
  required bool bold,
  required double fontSize,
}) => measureRouteMapLabel(text, bold: bold, fontSize: fontSize, basemap: true);
Size _measureBadge(String text, {required double fontSize}) =>
    measureRouteMapBadge(text, fontSize: fontSize, basemap: true);

// Pretendard 실메트릭 + 오너 크기(클램프 제거) + 추출 결함 교정(text-anchor
// style 파싱·tspan x/y 우선순위·다줄 라벨 렌더, 위 조사 2·4) 후 TextPainter
// 실측정(악화 금지). #2068 수도권 국소 라벨 재배치(조사 6) 후 1로 갱신 —
// 근거는 위 조사 5(노드 간격 패스로 31쌍 발생)·조사 6(국소 재배치로 31→1)
// 참고. 남은 1쌍은 보라매×보라매공원 밀집 하드 케이스.
//
// 조사 7(#2068 유클리드 간격 하드게이트, 2026-07-18): 팩 기준 최근접 <48 붕괴
// 492건(정합 게이트가 표본 9역만 봐 놓친 결함, 원인 규명 완료) 해소를 위해
// 역 circle·환승 캡슐 좌표를 pairwise 반발 솔버로 재간격(492→16, 예외 근거
// 명시)했다. 조사 6과 달리 이번은 **라벨이 아니라 station 좌표**를 옮긴
// 패스라, 재간격으로 벌어진 역들의 라벨 앵커가 이웃 라벨과 새로 겹치는 쌍이
// 생겼다(미금×오리·신풍×영등포·신풍×보라매공원·명학×수리산·연수×동춘 5건 +
// 기존 보라매×보라매공원 1건 = 6). baseline을 실측값 6으로 올렸었다.
//
// 조사 8(#2068 3단계 — apply-euclidean-svg-respacing.mjs 커밋 도구화, 별칭
// 매핑·마커 없는 라벨 폴백 확장 후 census 예외 16→0, 2026-07-18): 조사 7의
// 반발 솔버를 재현 가능한 도구로 승격해 재적용하면서(별칭 미매핑 13건 해소 +
// 다체 클러스터 2건도 반복 적용으로 해소) 역 좌표가 조사 7 시점과는 다시
// 달라졌다 — 그 결과로 이번 재측정에서 라벨-라벨 pairs가 **1**로 자연 복귀했다
// (조사 7이 만든 5건의 신규 쌍은 이번 재간격 경로에서 재현되지 않음. 남은
// 1쌍은 조사 6부터의 보라매×보라매공원 하드 케이스). baseline을 원래
// 값(1)으로 되돌린다 — 조사 6·8 근거 유지.
//
// 조사 9(#2068 라운드 4 — run 투영·전역 충돌해소 재구현 + 간선 겹침/노드
// 직선여유 겨냥 제거, 2026-07-18): 8선형 재작도(run 단위 투영, 코리더 번들
// 오프셋, 겹침 해소로 42개 역 추가 이동)로 총 ~200개 역이 조사 8 시점과는
// 다시 다른 좌표로 재배치됐다 — 그 결과 라벨-라벨 pairs가 1→23으로
// 늘었다(조사 5·7과 같은 패턴: 역 좌표 재배치가 라벨 앵커 간 거리를 바꾼다).
//
// 조사 10(#2068 라운드 5 — 코너 방향 재설계 + 라벨 게이트 복구, 2026-07-18):
// 조사 9의 23쌍을 조사 6과 같은 방식(라벨만 국소 이동, 역 좌표는 불변)으로
// 해소했다 — 21쌍(환승 허브에 걸린 5쌍은 허브 라벨 고정, 상대 일반 라벨만
// 이동/그 외 16쌍은 겹침 깊이가 더 얕은 쪽 라벨을 이동)을 겹침 깊이+3px
// design 여유로 최소 변위 이동(local delta = (겹침폭+여유)/designScale/
// mapScale). 결과 23→1로 회복(신목동×신정네거리 신규 1쌍 — 신정네거리를
// 옮기다 우연히 근접한 부작용, 조사 6의 보라매×보라매공원과 같은 급의 잔여
// 하드 케이스). 라벨-표장(KTX/SRT/AIR chip) 하드 0 게이트도 이 패스에서
// 밀린 신길·강남대(라운드 4~5 공통 재발 패턴)를 재넛지해 0 유지.
// baseline을 원래 값(1)으로 되돌린다(악화 아님 — 조사 6·8과 동일 수준 복귀).
//
// 조사 11(#2068 오너 기준본 전환, 2026-07-19): 오너 결정으로 라운드 2~5
// 산출물을 전부 폐기하고 오너가 손수 다듬은 새 SVG(viewBox 3800×3020,
// 이전 v2와 좌표계 전혀 다름)를 새 정본으로 삼았다 — 조사 1~10의 baseline은
// 전부 옛 소스 기준이라 무효. 새 소스 위에서: (a) 간선을 오너 배치 존중
// 최소침습 다듬기(run 투영 tolerance 18px, 역 재배치 없음)로 8선형 118→3·
// 노드-간선 15→0(6호선 응암 인근 3건 서브px 예외), (b) compile-basemap-vec.mjs
// 의 실측 버그 2건 수정(parseTranslate가 체인 translate 첫 개만 읽던 것 —
// .matchAll 합산으로 수정; station-label-group 감싸 그룹의 transform을 못
// 읽던 것 — 512자 이내 최근접 그룹 탐지로 수정. 두 버그로 오너 매치율이
// 650→185까지 붕괴했었다가 652로 복구), (c) 위 두 수정 후 라벨 위치가
// 정확해지며 라벨-라벨 겹침이 새 소스 기준 실측 7쌍으로 확정된다(조사 6
// 방식의 국소 라벨 재배치는 오너의 "필수만" 스코프 조정 지시로 이번 라운드
// 에서는 하지 않음 — 손질 추천 목록에 남긴다). baseline을 새 소스 실측값
// 7로 재설정한다(옛 소스의 "1"과 비교 불가 — 좌표계 자체가 다른 새 기준선).
const int kCapitalBasemapLabelLabelPairBaseline = 7;

bool _rectOverlaps(Rect a, Rect b) {
  final o = a.intersect(b);
  return o.width > 0 && o.height > 0;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPretendardTestFont);

  test(
    '수도권 basemap: 오너 라벨 매치율 ≥98% · 전 라벨 표시 · 라벨-라벨 겹침 ≤$kCapitalBasemapLabelLabelPairBaseline쌍 (#2068 Pretendard)',
    () {
      final fixture = loadCapitalRouteMapFixture();
      final design = routeMapDesignSpaceFor(fixture.map);
      final sidecarJson = File(
        'assets/datapacks/metro_map_pack/basemap/labels.json',
      ).readAsStringSync();
      final ownerLabels = parseRouteMapOwnerLabelsForRegion(
        sidecarJson,
        'seoul',
      );
      // #2068 수도권 KTX·SRT 표장(오너 확정 11역, 2026-07-18): 라벨이 표장
      // 위에 얹히지 않도록 regional 게이트와 같은 방식으로 solver에 넘긴다.
      final serviceTagObstacles = parseRouteMapServiceTagObstaclesForRegion(
        sidecarJson,
        'seoul',
      );
      final normalizedOwnerLabelNames = ownerLabels.keys
          .map(_normalizeNameForMatchRate)
          .toSet();
      // 전 후보(환승 그룹 + 비환승 역) 대비 매치율(정규화 후 — 위치 게이트·
      // 최근접 우선은 매치율이 아니라 "어느 물리역이 쓰는지"만 바꾸므로 여기
      // 매치율 계산에는 영향 없다).
      final candidateNames = <String>{
        for (final group in fixture.map.transferGroups)
          ?fixture.stationNameByStationId[group.stationId],
        for (final station in fixture.map.stations)
          if (station.labelClass != RouteMapLabelClass.transfer)
            ?fixture.stationNameByStationId[station.stationId],
      };
      final matchedCount = candidateNames
          .where(
            (name) => normalizedOwnerLabelNames.contains(
              _normalizeNameForMatchRate(name),
            ),
          )
          .length;
      expect(
        matchedCount / candidateNames.length,
        greaterThanOrEqualTo(0.98),
        reason:
            '오너 라벨 매치율 $matchedCount/${candidateNames.length} — '
            '98% 미만이면 sidecar·nameKo 정합이 깨진 것',
      );

      final layout = solveRouteMapLabelLayout(
        map: fixture.map,
        design: design,
        labelTextByStationId: fixture.labelTextByStationId,
        badgeLabelByLineId: fixture.badgeLabelByLineId,
        measureLabel: _measureLabel,
        measureBadge: _measureBadge,
        basemap: true,
        ownerLabelsByStationName: ownerLabels,
        stationNameByStationId: fixture.stationNameByStationId,
        serviceTagObstacles: serviceTagObstacles,
      );

      // 전 역 표시(숨김 금지 계약) — 미매치도 폴백 경로로 라벨을 낸다.
      expect(layout.labels.length, greaterThan(600));

      // 라벨-라벨 겹침 쌍 — 실측치로 고정(악화 금지). 0 미도달 원인은 파일
      // 상단 주석 참고.
      var pairs = 0;
      for (var i = 0; i < layout.labels.length; i += 1) {
        for (var j = i + 1; j < layout.labels.length; j += 1) {
          if (layout.labels[i].rect.overlaps(layout.labels[j].rect)) {
            pairs += 1;
          }
        }
      }
      // ignore: avoid_print
      print('[수도권 basemap] 라벨-라벨 겹침 쌍 pairs=$pairs');
      expect(
        pairs,
        lessThanOrEqualTo(kCapitalBasemapLabelLabelPairBaseline),
        reason:
            '라벨-라벨 겹침 쌍 $pairs — baseline '
            '$kCapitalBasemapLabelLabelPairBaseline 악화 금지',
      );

      // 이하 참고 보고(하드 게이트 아님) — 구조화 오버레이 근사 장애물 모델
      // 기준. 회귀 감시용으로 print만 한다(assert 없음).
      final nodeRects = [
        for (final s in fixture.map.stations)
          if (s.labelClass != RouteMapLabelClass.transfer)
            Rect.fromCenter(
              center: design.toDesign(s.position),
              width: kRouteMapBasemapStationNodeRadiusPx * 2,
              height: kRouteMapBasemapStationNodeRadiusPx * 2,
            ),
      ];
      final capsules = routeMapTransferObstacleRects(
        fixture.map,
        design,
        basemap: true,
      );
      final serviceTagRects = [
        for (final tag in serviceTagObstacles)
          Rect.fromCenter(
            center: design.toDesign(tag.center),
            width: tag.halfWidth * 2 * design.designScale,
            height: tag.halfHeight * 2 * design.designScale,
          ),
      ];
      var labelNode = 0, labelCapsule = 0, labelBand = 0, labelServiceTag = 0;
      for (final l in layout.labels) {
        if (nodeRects.any((n) => _rectOverlaps(l.rect, n))) labelNode += 1;
        if (capsules.any((c) => _rectOverlaps(l.rect, c))) labelCapsule += 1;
        if (_bandHit(
          l.rect,
          fixture.map,
          design,
          kRouteMapBasemapLineHalfWidthPx,
        )) {
          labelBand += 1;
        }
        if (serviceTagRects.any((s) => _rectOverlaps(l.rect, s))) {
          labelServiceTag += 1;
        }
      }
      final labelLine = routeMapLabelLineOverlapCount(
        layout,
        fixture.map,
        design,
      );
      // ignore: avoid_print
      print(
        '[참고] labelNode=$labelNode labelCapsule=$labelCapsule '
        'labelBand=$labelBand labelLine=$labelLine '
        'labelServiceTag=$labelServiceTag '
        'unresolved(오너 겹침 감사)=${layout.unresolvedOverlapCount}',
      );
      // #2068 수도권 KTX·SRT 표장(오너 확정 11역) — regional 게이트와 같은
      // 하드 0 게이트. 라벨이 표장 아이콘 위에 얹히면 회귀.
      expect(
        labelServiceTag,
        0,
        reason: '수도권 라벨-표장 겹침 $labelServiceTag — 0 악화 금지',
      );
    },
  );
}

bool _bandHit(
  Rect r,
  StructuredRouteMap map,
  RouteMapDesignSpace d,
  double half,
) {
  for (final line in map.lines) {
    for (final poly in line.polylines) {
      for (var i = 1; i < poly.length; i += 1) {
        if (_segRectDist(d.toDesign(poly[i - 1]), d.toDesign(poly[i]), r) <=
            half) {
          return true;
        }
      }
    }
  }
  return false;
}

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
