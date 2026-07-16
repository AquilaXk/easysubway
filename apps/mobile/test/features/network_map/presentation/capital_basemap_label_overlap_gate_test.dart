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
// - 결론: 25쌍 중 24쌍은 **우리 렌더링(단일 줄 강제)의 한계**이지 오너 SVG
//   겹침이 아니다. 다만 이를 고치려면 sidecar 스키마에 줄바꿈 정보를 추가하고
//   앱이 오너 매치 라벨을 다줄로 렌더하도록 painter를 확장해야 한다 — 5권역
//   전체에 영향을 미치는 별도 기능(#2068 범위 밖, 후속 과제로 분리). 클램프
//   재도입은 오너의 "글자 키워" 요청을 도로 막으므로 **하지 않는다**(명시적
//   지시). 따라서 이 baseline은 다줄 라벨 렌더링 후속 과제 전까지 현재 상태를
//   고정하는 회귀 감시값이다(악화 금지, 완화는 후속 과제 완료 후).
//
// 이름 매칭은 중점(·)↔마침표(.) 정규화만 적용한다(#2068 7차 지시 2 — 다른
// 정규화는 과매칭 위험이라 하지 않는다, route_map_label_layout.dart의
// _normalizeOwnerLabelNameKey와 동일 규칙을 이 파일 매치율 계산에도 미러링).
String _normalizeNameForMatchRate(String name) => name.replaceAll('·', '.');

Size _measureLabel(
  String text, {
  required bool bold,
  required double fontSize,
}) => measureRouteMapLabel(text, bold: bold, fontSize: fontSize, basemap: true);
Size _measureBadge(String text, {required double fontSize}) =>
    measureRouteMapBadge(text, fontSize: fontSize, basemap: true);

// Pretendard 실메트릭 + 오너 크기(클램프 제거) + 추출 결함 2건 교정
// (text-anchor style 파싱·tspan x/y 우선순위, 아래 조사 2) 후 TextPainter
// 실측정(악화 금지). 24/25는 앱의 단일 줄 렌더링 한계(조사 3)로 판명 —
// sidecar 다줄 지원 후속 과제 전까지는 이 값이 현재 상태의 정직한 기록이다.
const int kCapitalBasemapLabelLabelPairBaseline = 25;

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
      var labelNode = 0, labelCapsule = 0, labelBand = 0;
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
        'unresolved(오너 겹침 감사)=${layout.unresolvedOverlapCount}',
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
