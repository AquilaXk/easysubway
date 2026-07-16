import 'package:easysubway_mobile/features/network_map/domain/route_map_owner_labels.dart';
import 'package:easysubway_mobile/network_map.dart';
import 'package:flutter_test/flutter_test.dart';

// #2068: basemap 오너 라벨(sidecar)의 실제 렌더 extents를 지도 geometry bounds에
// 포함해야 초기 fit·팬 한계가 라벨을 자르지 않는다. 광주 '학동·증심사입구'류
// 오른쪽으로 길게 뻗는 라벨이 합성 label_polygon보다 훨씬 넓어 잘리던 실기기
// 반려 대응. 최우측 오너 라벨 rect가 bounds에 들어오는지 회귀 가드한다.

NetworkMapStation _station(String id, double x, double y) {
  return NetworkMapStation(
    id: id,
    nameKo: id,
    nameEn: id,
    region: '광주',
    lineId: 'GJ1',
    stationCode: id,
    sequence: 0,
    position: NetworkMapPosition(
      x: x.toInt(),
      y: y.toInt(),
      labelDx: 0,
      labelDy: 0,
      upPath: '',
      downPath: '',
      sourceId: id,
    ),
  );
}

void main() {
  group('#2068 오너 라벨 extents가 geometry bounds에 포함', () {
    // 광주급 소규모 지역: 역은 왼쪽~중앙에, 최우측 오너 라벨은 그보다 오른쪽에.
    final stations = [_station('A', 160, 400), _station('B', 1600, 900)];
    // Gwangju sidecar 대표값. '조선대'(anchor start, x=2060) 라벨이 오른쪽으로
    // 뻗어 최우측 extent를 만든다. designScale=0.4는 광주급(14px는 그대로,
    // 66px는 min(13/0.4=32.5, 66)=32.5로 클램프) 렌더를 재현한다.
    const designScale = 0.4;
    final ownerLabels = <RouteMapOwnerLabelEntry>[
      const RouteMapOwnerLabelEntry(
        station: '조선대',
        role: 'ordinary',
        position: Offset(2060, 874),
        anchor: RouteMapOwnerLabelAnchor.start,
        fontSizePx: 14,
      ),
      const RouteMapOwnerLabelEntry(
        station: '학동·증심사입구',
        role: 'ordinary',
        position: Offset(1594, 996),
        anchor: RouteMapOwnerLabelAnchor.start,
        fontSizePx: 66,
      ),
    ];

    test('최우측 라벨 rect가 bounds 밖에 있던 것이 수정 후 포함된다', () {
      final rects = networkMapOwnerLabelSourceRects(
        ownerLabels: ownerLabels,
        designScale: designScale,
      );
      // 최우측 extent = '조선대'(x=2060, start) 라벨 오른쪽 끝.
      final rightmost = rects.reduce((a, b) => a.right >= b.right ? a : b);
      expect(rightmost.right, greaterThan(2060), reason: '앵커에서 오른쪽으로 뻗어야');

      final boundsWithout = networkMapGeometrySourceBoundsFor(stations);
      final boundsWith = networkMapGeometrySourceBoundsFor(
        stations,
        ownerLabelSourceRects: rects,
      );

      // 수정 전(라벨 미포함): 역 기반 bounds는 최우측 라벨을 담지 못한다.
      expect(
        boundsWithout.right,
        lessThan(rightmost.right),
        reason: '역만으로는 최우측 오너 라벨이 bounds 밖',
      );

      // 수정 후: bounds가 최우측 라벨 rect를 완전히 포함한다.
      expect(boundsWith.right, greaterThanOrEqualTo(rightmost.right));
      expect(boundsWith.left, lessThanOrEqualTo(rightmost.left));
      expect(boundsWith.top, lessThanOrEqualTo(rightmost.top));
      expect(boundsWith.bottom, greaterThanOrEqualTo(rightmost.bottom));
    });

    test('오너 라벨을 넣어도 bounds가 좁아지지 않는다(단조 확장)', () {
      final rects = networkMapOwnerLabelSourceRects(
        ownerLabels: ownerLabels,
        designScale: designScale,
      );
      final boundsWithout = networkMapGeometrySourceBoundsFor(stations);
      final boundsWith = networkMapGeometrySourceBoundsFor(
        stations,
        ownerLabelSourceRects: rects,
      );
      expect(boundsWith.left, lessThanOrEqualTo(boundsWithout.left));
      expect(boundsWith.top, lessThanOrEqualTo(boundsWithout.top));
      expect(boundsWith.right, greaterThanOrEqualTo(boundsWithout.right));
      expect(boundsWith.bottom, greaterThanOrEqualTo(boundsWithout.bottom));
    });
  });

  group('오너 라벨 source rect 렌더 규칙', () {
    test('큰 오너 폰트는 앱 기본(13 design px) 이하로 클램프되어 폭이 준다', () {
      // designScale=0.4에서 66px는 min(13/0.4=32.5, 66)=32.5로 렌더된다.
      const clampedEntry = RouteMapOwnerLabelEntry(
        station: '가나다', // 3 runes
        role: 'ordinary',
        position: Offset(1000, 500),
        anchor: RouteMapOwnerLabelAnchor.start,
        fontSizePx: 66,
      );
      final rects = networkMapOwnerLabelSourceRects(
        ownerLabels: const [clampedEntry],
        designScale: 0.4,
      );
      // 폭 = 글자수 × 클램프된 source 폰트 = 3 × 32.5 = 97.5.
      expect(rects.single.width, closeTo(3 * 32.5, 0.001));
      // start 앵커: 왼쪽이 앵커 x, 오른쪽으로 폭만큼.
      expect(rects.single.left, 1000);
      expect(rects.single.right, closeTo(1000 + 97.5, 0.001));
    });

    test('end 앵커는 앵커 x에서 왼쪽으로 뻗는다', () {
      const entry = RouteMapOwnerLabelEntry(
        station: '가나', // 2 runes
        role: 'ordinary',
        position: Offset(1000, 500),
        anchor: RouteMapOwnerLabelAnchor.end,
        fontSizePx: 10,
      );
      final rects = networkMapOwnerLabelSourceRects(
        ownerLabels: const [entry],
        designScale: 1.0, // 10 < 13이라 클램프 미발동, source 폰트 그대로 10.
      );
      // 폭 = 2 × 10 = 20, end라 오른쪽 끝이 앵커.
      expect(rects.single.right, 1000);
      expect(rects.single.left, closeTo(980, 0.001));
    });
  });
}
