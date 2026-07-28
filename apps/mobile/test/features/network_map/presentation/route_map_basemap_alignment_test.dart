import 'dart:convert';
import 'dart:io';

import 'package:easysubway_mobile/features/network_map/domain/map_camera.dart';
import 'package:easysubway_mobile/features/network_map/infrastructure/route_map_svg_viewport.dart';
import 'package:easysubway_mobile/features/network_map/presentation/route_map_basemap_view.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

// #2068 하이브리드 바탕층 좌표 정렬 회귀 방지.
//
// (A) 좌표 변환 정합(엄격 <1e-6): RouteMapBasemapPainter의 재생 변환
//     sourceToViewport(P)가 오버레이·카메라가 쓰는
//     camera.sourceToViewportPoint(P − sourceOrigin)와 항등임을 고정한다. 바탕
//     .vec는 viewBox=source 좌표라 designScale 곱셈/나눗셈이 없다 — 이 항등이
//     깨지면 바탕과 인터랙션(히트 rect·팝오버·핀)이 어긋난다.
//
// (B) 바탕↔인터랙션 역위치 실측 정합(전 역 하드 5px, #2068 P-65): SVG 노드
//     좌표(바탕이 그리는 위치)와 팩 좌표(route_map_positions, 인터랙션이
//     쓰는 위치)가 같은 viewBox 좌표계를 공유함을 **표본이 아니라 수도권
//     전 역(799/800, 톤제외 1)**으로 고정한다. respace --pin-stations(P-65
//     재설계)가 팩 좌표를 SVG canonical 배정에 고정하므로 실측 delta는
//     전부 <1px(반올림 잔차)다 — 과거 "표본 9역·40px" 게이트는 나머지
//     791역의 붕괴(#2068 실측 최대 638px)를 놓쳤다(원인 규명 완료, 이 게이트로
//     재발 방지). fixture는
//     tools/route-map/generate-basemap-alignment-fixture.mjs가
//     buildAssignments(apply-sma-svg-positions.mjs의 canonical 정합 단일
//     정본)를 그대로 재사용해 산출 — SVG 파이프라인 재실행 시 함께 재생성한다.
//
// 카메라 세트는 route_map_overlay_camera_sync_test.dart의 4개를 재사용한다.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('5권역 표시명을 각 canonical .svg 자산에 매핑한다', () {
    expect(
      {
        for (final region in ['수도권', '부산', '대구', '대전', '광주'])
          region: routeMapBasemapAssetForRegion(region),
      },
      {
        '수도권': 'assets/datapacks/metro_map_pack/basemap/seoul.svg',
        '부산': 'assets/datapacks/metro_map_pack/basemap/busan.svg',
        '대구': 'assets/datapacks/metro_map_pack/basemap/daegu.svg',
        '대전': 'assets/datapacks/metro_map_pack/basemap/daejeon.svg',
        '광주': 'assets/datapacks/metro_map_pack/basemap/gwangju.svg',
      },
    );
  });

  // route_map_overlay_camera_sync_test.dart와 동일한 비영점 origin 유형.
  final base = const Offset(1000, 700);
  final origin = base - const Offset(54, 54);

  final cameras = <String, MapCameraState>{
    '기본(초기)': MapCameraState(
      sourceBounds: const Rect.fromLTWH(0, 0, 200, 200),
      viewportSize: const Size(400, 800),
      center: const Offset(100, 100),
      scale: 3,
      minScale: 1,
      maxScale: 20,
      revision: 0,
      initialScale: 3,
    ),
    '팬 후 center 이동': MapCameraState(
      sourceBounds: const Rect.fromLTWH(0, 0, 200, 200),
      viewportSize: const Size(400, 800),
      center: const Offset(137, 62),
      scale: 3,
      minScale: 1,
      maxScale: 20,
      revision: 1,
      initialScale: 3,
    ),
    '줌 후 scale 변경': MapCameraState(
      sourceBounds: const Rect.fromLTWH(0, 0, 200, 200),
      viewportSize: const Size(400, 800),
      center: const Offset(100, 100),
      scale: 7.5,
      minScale: 1,
      maxScale: 20,
      revision: 2,
      initialScale: 3,
    ),
    'initialViewport 복원(비영점 origin center)': MapCameraState(
      sourceBounds: const Rect.fromLTWH(0, 0, 200, 200),
      viewportSize: const Size(400, 800),
      center: const Offset(54, 54),
      scale: 4.25,
      minScale: 1,
      maxScale: 20,
      revision: 3,
      initialScale: 4.25,
    ),
  };

  // 여러 viewBox 점(비영점 origin 부근·원점·먼 점 포함)에서 항등을 확인한다.
  final viewBoxPoints = <Offset>[
    Offset.zero,
    base,
    base + const Offset(24, 0),
    base + const Offset(48, 123),
    const Offset(1369.617, 1266.787), // seoul 강남 노드(아래 fixture와 동일).
    const Offset(2400, 1800), // sma-v2 viewBox 우하단 코너.
  ];

  for (final entry in cameras.entries) {
    test('(A) 바탕 재생 변환 == 오버레이 앵커(<1e-6): ${entry.key}', () {
      final camera = entry.value;
      final expected = camera.visibleSourceRect.shift(origin);
      final viewBox = routeMapSvgViewportCameraPayload(
        camera: camera,
        sourceOrigin: origin,
      )['viewBox'] as List<double>;
      expect(viewBox, <double>[
        expected.left,
        expected.top,
        expected.width,
        expected.height,
      ], reason: '${entry.key} viewBox must preserve the shifted camera rect');
    });
  }

  // (B) seoul 전 역: SVG canonical 배정 좌표 vs 팩(route_map_positions) 좌표.
  // fixture 출처: tools/route-map/generate-basemap-alignment-fixture.mjs가
  //   buildAssignments(apply-sma-svg-positions.mjs — SVG↔DB canonical 정합
  //   단일 정본)를 재사용해 산출한
  //   seoul-alignment-fixture.json(수도권 800행 중 799행, 1행은 canonical
  //   미매칭으로 fixture 자체가 unmatchedCount로 보고 — 아래서 최소 커버리지로
  //   고정). P-65(respace --pin-stations) 재설계로 팩 좌표가 SVG 배정에
  //   고정되므로 실측 delta는 전부 <1px(반올림 잔차)다. 임계 5px는 그 실측에
  //   충분한 헤드룸을 둔 하드 게이트 — 과거 "표본 9역·40px"는 나머지 791역의
  //   붕괴(#2068 실측 최대 638px, 파이프라인 project-nodes/respace 원인 규명
  //   완료)를 전혀 잡지 못했다.
  const alignmentThresholdPx = 5.0;
  const minStationCoverage = 700; // 수도권 800행 중 대다수 커버(하드 최소선).

  void expectNoUnmatched(Map<String, dynamic> fixture, String regionKey) {
    final unmatched = (fixture['unmatched'] as List)
        .cast<Map<String, dynamic>>();
    expect(
      fixture['unmatchedCount'],
      0,
      reason: '$regionKey 팩 행 중 SVG 배정이 없는 역이 생겼다(미매핑 회귀)',
    );
    expect(unmatched, isEmpty, reason: '$regionKey fixture에 선언되지 않은 미매칭 역이 있다');
  }

  test('(B) seoul 바탕(SVG 배정) ↔ 인터랙션(팩) 좌표가 같은 viewBox 좌표계 — 전 역 하드 <5px', () {
    // apps/mobile 밖(tools/route-map/route-map-defs/)에 둔다 — pubspec.yaml의
    // assets/datapacks/metro_map_pack/basemap/ 와일드카드 번들에 QA 전용
    // fixture가 딸려 들어가지 않도록(dart:io File은 앱 asset bundle을 거치지
    // 않고 소스 트리를 직접 읽으므로 위치 제약이 없다).
    final file = File(
      '../../tools/route-map/route-map-defs/seoul-alignment-fixture.json',
    );
    expect(
      file.existsSync(),
      isTrue,
      reason:
          'fixture 없음 — node tools/route-map/generate-basemap-alignment-fixture.mjs 로 생성 필요: ${file.path}',
    );
    final fixture = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final entries = (fixture['entries'] as List).cast<Map<String, dynamic>>();
    final unmatched = (fixture['unmatched'] as List)
        .cast<Map<String, dynamic>>();

    expect(fixture['unmatchedCount'], unmatched.length);
    expect(unmatched.length, 1);
    expect(unmatched.single['name'], '도라산');
    expect((unmatched.single['reason'] as String).trim(), isNotEmpty);

    expect(
      entries.length,
      greaterThanOrEqualTo(minStationCoverage),
      reason:
          'fixture 커버리지 급감 — canonical 정합이 대량 깨졌을 가능성(entries=${entries.length})',
    );

    for (final e in entries) {
      final delta = (e['deltaPx'] as num).toDouble();
      expect(
        delta,
        lessThan(alignmentThresholdPx),
        reason:
            '${e['name']}(${e['stationId']}/${e['lineId']}): svg=(${e['svgX']},${e['svgY']}) '
            'pack=(${e['packX']},${e['packY']}) delta=$delta',
      );
    }
  });

  // (C) 부산 전 역: seoul과 동일 하드 게이트를 부산에 미러(#2068 완주 라운드,
  // 오너 v2 재배치 승인 반영). fixture 출처는 (B)와 동일 생성기(부산 재실행,
  // --region 부산권 --geometry easy-subway-busan-v3-geometry.json)이며, 파이프라인이
  // seoul과 동일하게 respace --pin-stations로 팩 좌표를 SVG 배정에 고정한다.
  //
  // 예외 1건: 국제금융센터·부산은행(station-080c154ce646/line-eb7b47920390)은
  // route-map-busan-label-nudges.json의 결정적 라벨-선 겹침 회피 nudge(#2068 10차)로
  // SVG 원좌표에서 의도적으로 이동됨(실측 501px) — 정합 오류가 아니라 별도 결정적
  // 도구가 낸 알려진 편차이므로, 그 nudge 파일에 등재된 (stationId,lineId)만 하드
  // 임계에서 제외한다(새 예외 임의 추가 금지 — nudge 파일이 커지면 이 목록도 함께
  // 커진다).
  const busanNudgeExceptionsFile =
      '../../tools/route-map/route-map-busan-label-nudges.json';
  const minBusanStationCoverage = 150; // 부산 158행 중 대다수 커버(하드 최소선).

  test('(C) busan 바탕(SVG 배정) ↔ 인터랙션(팩) 좌표가 같은 viewBox 좌표계 — 전 역 하드 <5px'
      '(label-nudge 등재 예외 제외)', () {
    final file = File(
      '../../tools/route-map/route-map-defs/busan-alignment-fixture.json',
    );
    expect(
      file.existsSync(),
      isTrue,
      reason:
          'fixture 없음 — node tools/route-map/generate-basemap-alignment-fixture.mjs '
          '--region 부산권 --geometry tools/route-map/route-map-defs/easy-subway-busan-v3-geometry.json '
          '--out tools/route-map/route-map-defs/busan-alignment-fixture.json 로 생성 필요: ${file.path}',
    );
    final fixture = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final entries = (fixture['entries'] as List).cast<Map<String, dynamic>>();
    expectNoUnmatched(fixture, '부산권');

    final nudgeFile = File(busanNudgeExceptionsFile);
    final nudgeExceptions = <String>{};
    if (nudgeFile.existsSync()) {
      final nudges =
          jsonDecode(nudgeFile.readAsStringSync()) as Map<String, dynamic>;
      for (final n in (nudges['nudges'] as List).cast<Map<String, dynamic>>()) {
        nudgeExceptions.add('${n['stationId']}/${n['lineId']}');
      }
    }

    expect(
      entries.length,
      greaterThanOrEqualTo(minBusanStationCoverage),
      reason:
          'fixture 커버리지 급감 — canonical 정합이 대량 깨졌을 가능성(entries=${entries.length})',
    );

    for (final e in entries) {
      final key = '${e['stationId']}/${e['lineId']}';
      if (nudgeExceptions.contains(key)) continue;
      final delta = (e['deltaPx'] as num).toDouble();
      expect(
        delta,
        lessThan(alignmentThresholdPx),
        reason:
            '${e['name']}(${e['stationId']}/${e['lineId']}): svg=(${e['svgX']},${e['svgY']}) '
            'pack=(${e['packX']},${e['packY']}) delta=$delta',
      );
    }
  });

  // (D) 대구 전 역: seoul(B)·busan(C)과 동일 하드 게이트를 대구에 미러(#2068
  // 완주 라운드, 오너 직접 제작본 전환 반영). fixture 출처는 동일 생성기(대구
  // 재실행, --region 대구권 --geometry easy-subway-daegu-v3-geometry.json)이며,
  // 파이프라인이 seoul·busan과 동일하게 respace --pin-stations로 팩 좌표를 SVG
  // 배정에 고정한다 — 실측 delta는 전부 0px(정수 반올림 일치). 대구는 라벨
  // nudge 파일이 없어 예외 없이 전 역 하드다(seoul(B) 패턴).
  const minDaeguStationCoverage = 95; // 대구 102행 중 대다수 커버(하드 최소선).

  test('(D) daegu 바탕(SVG 배정) ↔ 인터랙션(팩) 좌표가 같은 viewBox 좌표계 — 전 역 하드 <5px', () {
    final file = File(
      '../../tools/route-map/route-map-defs/daegu-alignment-fixture.json',
    );
    expect(
      file.existsSync(),
      isTrue,
      reason:
          'fixture 없음 — node tools/route-map/generate-basemap-alignment-fixture.mjs '
          '--region 대구권 --geometry tools/route-map/route-map-defs/easy-subway-daegu-v3-geometry.json '
          '--out tools/route-map/route-map-defs/daegu-alignment-fixture.json 로 생성 필요: ${file.path}',
    );
    final fixture = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final entries = (fixture['entries'] as List).cast<Map<String, dynamic>>();
    expectNoUnmatched(fixture, '대구권');

    expect(
      entries.length,
      greaterThanOrEqualTo(minDaeguStationCoverage),
      reason:
          'fixture 커버리지 급감 — canonical 정합이 대량 깨졌을 가능성(entries=${entries.length})',
    );

    for (final e in entries) {
      final delta = (e['deltaPx'] as num).toDouble();
      expect(
        delta,
        lessThan(alignmentThresholdPx),
        reason:
            '${e['name']}(${e['stationId']}/${e['lineId']}): svg=(${e['svgX']},${e['svgY']}) '
            'pack=(${e['packX']},${e['packY']}) delta=$delta',
      );
    }
  });

  // (E)(F) 대전·광주 전 역: seoul(B)·busan(C)·daegu(D)와 동일 하드 게이트를 남은
  // 두 권역에 미러한다(#2068 오너 재제작 v3 반입). 두 권역은 이번 반입 전까지
  // 이 게이트가 없었고, 실제로 광주는 respace가 팩 좌표를 오너 SVG 노드에서
  // 최대 25.81px 밀어낸 상태였다(run-sma-pipeline-gwangju.sh에 --pin-stations가
  // 빠져 있었다 — 5권역 중 대전·광주만). 두 스크립트에 --pin-stations를 붙여
  // 다른 3권역과 같은 모드로 맞춘 뒤 실측 delta는 전 역 0px다.
  //
  // 대전은 오너가 v3에서 지도 본문을 map-content-positioned-layer(translate(0 88))
  // 로 감쌌다 — 컴파일러가 그 래퍼를 흡수하지 않으면 .vec와 라벨 sidecar만 88px
  // 위로 어긋나고 이 fixture(팩↔SVG 배정)는 여전히 0px이라 못 잡는다. 그 축은
  // compile-basemap-vec.test.mjs의 compiled-map-coordinate-layer 계약이 잡는다.
  const minDaejeonStationCoverage = 22; // 대전 1호선 22행 전수.
  const minGwangjuStationCoverage = 20; // 광주 1호선 20행 전수.

  for (final (label, regionKey, geometry, fixturePath, minCoverage)
      in <(String, String, String, String, int)>[
        (
          'E',
          '대전권',
          'easy-subway-daejeon-v3-geometry.json',
          'daejeon-alignment-fixture.json',
          minDaejeonStationCoverage,
        ),
        (
          'F',
          '광주권',
          'easy-subway-gwangju-v3-geometry.json',
          'gwangju-alignment-fixture.json',
          minGwangjuStationCoverage,
        ),
      ]) {
    test(
      '($label) $regionKey 바탕(SVG 배정) ↔ 인터랙션(팩) 좌표가 같은 viewBox 좌표계 — 전 역 하드 <5px',
      () {
        final file = File('../../tools/route-map/route-map-defs/$fixturePath');
        expect(
          file.existsSync(),
          isTrue,
          reason:
              'fixture 없음 — node tools/route-map/generate-basemap-alignment-fixture.mjs '
              '--region $regionKey --geometry tools/route-map/route-map-defs/$geometry '
              '--out tools/route-map/route-map-defs/$fixturePath 로 생성 필요: ${file.path}',
        );
        final fixture =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        final entries = (fixture['entries'] as List)
            .cast<Map<String, dynamic>>();

        expect(
          entries.length,
          greaterThanOrEqualTo(minCoverage),
          reason:
              'fixture 커버리지 급감 — canonical 정합이 대량 깨졌을 가능성(entries=${entries.length})',
        );
        expectNoUnmatched(fixture, regionKey);

        for (final e in entries) {
          final delta = (e['deltaPx'] as num).toDouble();
          expect(
            delta,
            lessThan(alignmentThresholdPx),
            reason:
                '${e['name']}(${e['stationId']}/${e['lineId']}): svg=(${e['svgX']},${e['svgY']}) '
                'pack=(${e['packX']},${e['packY']}) delta=$delta',
          );
        }
      },
    );
  }
}
