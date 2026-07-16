import 'package:easysubway_mobile/features/network_map/domain/map_camera.dart';
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
// (B) 바탕↔인터랙션 역위치 실측 정합(느슨 40px): SVG 노드 좌표(바탕이 그리는
//     위치)와 팩 좌표(route_map_positions, 인터랙션이 쓰는 위치)가 같은 viewBox
//     좌표계를 공유함을 seoul 대표 역 9곳으로 고정한다. 두 좌표는 octolinear
//     snap·respacing·track projection·parallel offset 후처리로 소량 편차가 있으나
//     (#2068 이슈 "11~30px 이내"), 원점·스케일은 동일하다.
//
// 카메라 세트는 route_map_overlay_camera_sync_test.dart의 4개를 재사용한다.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('5권역 표시명을 각 바탕 .vec 자산에 매핑한다', () {
    expect(
      {
        for (final region in ['수도권', '부산', '대구', '대전', '광주'])
          region: routeMapBasemapAssetForRegion(region),
      },
      {
        '수도권': 'assets/datapacks/metro_map_pack/basemap/seoul.vec',
        '부산': 'assets/datapacks/metro_map_pack/basemap/busan.vec',
        '대구': 'assets/datapacks/metro_map_pack/basemap/daegu.vec',
        '대전': 'assets/datapacks/metro_map_pack/basemap/daejeon.vec',
        '광주': 'assets/datapacks/metro_map_pack/basemap/gwangju.vec',
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
      // sourceOrigin을 geometry origin으로 넘긴 painter가 실제 렌더 상태.
      final painter = RouteMapBasemapPainter(
        picture: null, // 변환 수식 검증에는 picture 불필요.
        camera: camera,
        sourceOrigin: origin,
      );
      for (final p in viewBoxPoints) {
        final canvasPoint = painter.sourceToViewport(p);
        final overlayPoint = camera.sourceToViewportPoint(p - origin);
        expect(
          (canvasPoint - overlayPoint).distance,
          lessThan(1e-6),
          reason:
              '${entry.key} / viewBox=$p: '
              'canvas=$canvasPoint overlay=$overlayPoint '
              'delta=${canvasPoint - overlayPoint}',
        );
      }
    });
  }

  // (B) seoul 대표 역 9곳: SVG 노드 좌표 vs 팩(route_map_positions) 좌표.
  // 출처: SVG 노드 = easy-subway-sma-v2-geometry.json stationNodes(viewBox 좌표),
  //       팩 = capital.sqlite route_map_positions(x/y, 동일 viewBox 좌표계).
  // measuredDelta는 #2068 실측치. 임계값 40px 근거: octolinear snap·respacing·
  //   track projection·parallel offset 후처리로 발생하는 worst-case 편차(#2068
  //   이슈 "11~30px 이내")에 헤드룸을 둔 값 — 두 좌표가 같은 원점·스케일의 viewBox
  //   좌표계를 공유한다는 사실을 고정한다(권역 대표로 seoul만; 5권역 확장 안 함).
  const seoulFixture =
      <({String name, Offset svgNode, Offset pack, double measured})>[
        (
          name: '강남',
          svgNode: Offset(1369.617, 1266.787),
          pack: Offset(1369.8, 1266.9),
          measured: 0.17,
        ),
        (
          name: '잠실',
          svgNode: Offset(1532.203, 1121.976),
          pack: Offset(1529.4, 1120.3),
          measured: 3.26,
        ),
        (
          name: '사당',
          svgNode: Offset(1184.615, 1262.218),
          pack: Offset(1186.5, 1261.9),
          measured: 1.91,
        ),
        (
          name: '서울역',
          svgNode: Offset(1055.9, 905.304),
          pack: Offset(1053.5, 897.7),
          measured: 7.97,
        ),
        (
          name: '청량리',
          svgNode: Offset(1553.242, 753.882),
          pack: Offset(1551.8, 753.2),
          measured: 1.57,
        ),
        (
          name: '인천',
          svgNode: Offset(391.867, 1419.985),
          pack: Offset(391.0, 1417.9),
          measured: 2.27,
        ),
        (
          name: '수원',
          svgNode: Offset(1148.164, 1631.347),
          pack: Offset(1146.3, 1630.4),
          measured: 2.08,
        ),
        (
          name: '의정부',
          svgNode: Offset(1456.977, 468.558),
          pack: Offset(1457.1, 468.4),
          measured: 0.26,
        ),
        (
          name: '동두천',
          svgNode: Offset(1129.377, 468.558),
          pack: Offset(1125.4, 468.4),
          measured: 3.99,
        ),
      ];

  const alignmentThresholdPx = 40.0;

  test('(B) seoul 바탕(SVG 노드) ↔ 인터랙션(팩) 좌표가 같은 viewBox 좌표계(<40px)', () {
    for (final f in seoulFixture) {
      final delta = (f.svgNode - f.pack).distance;
      // fixture 무결성: 계산 delta가 표기 measured와 대략 일치(좌표·measured가
      // 각각 독립 반올림된 실측이라 0.5px 여유). 표 손상(자릿수 뒤바뀜 등) 조기 감지용.
      expect(
        (delta - f.measured).abs(),
        lessThan(0.5),
        reason: '${f.name}: 계산 delta=$delta, fixture measured=${f.measured}',
      );
      // 핵심 불변식: 바탕과 인터랙션이 같은 좌표계를 공유(원점·스케일 동일).
      expect(
        delta,
        lessThan(alignmentThresholdPx),
        reason: '${f.name}: svgNode=${f.svgNode} pack=${f.pack} delta=$delta',
      );
    }
  });
}
