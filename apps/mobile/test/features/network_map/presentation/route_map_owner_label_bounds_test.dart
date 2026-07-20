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
    // 뻗어 최우측 extent를 만든다. entry.fontSizePx는 이미 source 단위라
    // 클램프 없이(#2068 Pretendard 번들 후) 그대로 쓴다.
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
      final rects = networkMapOwnerLabelSourceRects(ownerLabels: ownerLabels);
      // 최우측 extent = '학동·증심사입구'(x=1594, fontSizePx=66, start) 라벨
      // 오른쪽 끝 — 클램프 제거 후 '조선대'(x=2060, fontSizePx=14, 폭 3×14=42
      // → right=2102)보다 폭이 훨씬 커(7 runes×66=462 → right=2056) 근접하지만,
      // 실측값으로 largest-right를 그대로 구한다(어느 쪽이든 회귀 가드 의미는
      // 동일 — 역 기반 bounds보다 넓게 뻗는지).
      final rightmost = rects.reduce((a, b) => a.right >= b.right ? a : b);
      expect(rightmost.right, greaterThan(1594), reason: '앵커에서 오른쪽으로 뻗어야');

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
      final rects = networkMapOwnerLabelSourceRects(ownerLabels: ownerLabels);
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
    test('#2068 Pretendard 번들 후: 큰 오너 폰트도 클램프 없이 source 폰트 그대로 폭을 잡는다', () {
      const entry = RouteMapOwnerLabelEntry(
        station: '가나다', // 3 runes
        role: 'ordinary',
        position: Offset(1000, 500),
        anchor: RouteMapOwnerLabelAnchor.start,
        fontSizePx: 66,
      );
      final rects = networkMapOwnerLabelSourceRects(ownerLabels: const [entry]);
      // 폭 = 글자수 × source 폰트(클램프 없음) = 3 × 66 = 198.
      expect(rects.single.width, closeTo(3 * 66, 0.001));
      // start 앵커: 왼쪽이 앵커 x, 오른쪽으로 폭만큼.
      expect(rects.single.left, 1000);
      expect(rects.single.right, closeTo(1000 + 198, 0.001));
    });

    test('end 앵커는 앵커 x에서 왼쪽으로 뻗는다', () {
      const entry = RouteMapOwnerLabelEntry(
        station: '가나', // 2 runes
        role: 'ordinary',
        position: Offset(1000, 500),
        anchor: RouteMapOwnerLabelAnchor.end,
        fontSizePx: 10,
      );
      final rects = networkMapOwnerLabelSourceRects(ownerLabels: const [entry]);
      // 폭 = 2 × 10 = 20, end라 오른쪽 끝이 앵커.
      expect(rects.single.right, 1000);
      expect(rects.single.left, closeTo(980, 0.001));
    });

    test('#2068 다줄 라벨 렌더: lines가 있으면 단일 줄 근사와 줄별 근사의 합집합을 잡는다', () {
      // 단일 줄 근사("검단사거리" 5 runes × 20 = 100, x=0 start → right=100)보다
      // 줄별 근사(각 줄 x가 달라 실제 더 넓게 뻗을 수 있음)가 넓은 경우를
      // 검증 — union이 항상 둘 중 넓은 쪽 이상이어야 안전.
      const entry = RouteMapOwnerLabelEntry(
        station: '검단사거리',
        role: 'ordinary',
        position: Offset(0, 100),
        anchor: RouteMapOwnerLabelAnchor.start,
        fontSizePx: 20,
        lines: [
          RouteMapOwnerLabelLine(text: '검단', position: Offset(0, 100)),
          RouteMapOwnerLabelLine(text: '사거리', position: Offset(30, 128.8)),
        ],
      );
      final rects = networkMapOwnerLabelSourceRects(ownerLabels: const [entry]);
      final rect = rects.single;
      // 단일 줄 근사 right = 0 + 5×20 = 100.
      // 줄2 근사 right = 30 + 3×20 = 90 (단일 줄 근사가 더 넓음 — union은 100).
      expect(rect.right, greaterThanOrEqualTo(100));
      // 줄2가 줄1보다 아래(y=128.8)까지 뻗으므로 bottom은 단일 줄 근사보다 낮다.
      // 단일 줄 근사 bottom = 100 - 0.8×20 + 20×1.3 = 110.
      // 줄2 근사 bottom = 128.8 - 0.8×20 + 20×1.3 = 138.8.
      expect(rect.bottom, greaterThanOrEqualTo(138.8 - 0.001));
    });
  });
}
