import 'package:easysubway_mobile/features/network_map/domain/route_map_linear_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RouteMapLinearGeometry.pointAtT', () {
    test('직선 polyline에서 t를 누적 거리로 보간한다', () {
      final geometry = RouteMapLinearGeometry(const [
        Offset(0, 0),
        Offset(10, 0),
      ]);
      expect(geometry.length, 10);
      expect(geometry.pointAtT(0), const Offset(0, 0));
      expect(geometry.pointAtT(0.5), const Offset(5, 0));
      expect(geometry.pointAtT(1), const Offset(10, 0));
    });

    test('여러 구간의 길이 차이를 반영해 t를 배치한다', () {
      // 첫 구간 길이 10, 둘째 구간 길이 30 → 전체 40. t=0.5는 거리 20 지점.
      final geometry = RouteMapLinearGeometry(const [
        Offset(0, 0),
        Offset(10, 0),
        Offset(40, 0),
      ]);
      expect(geometry.length, 40);
      // 거리 20 = 첫 구간(10) 다 지나고 둘째 구간에서 10 더 → x=20.
      expect(geometry.pointAtT(0.5), const Offset(20, 0));
    });

    test('범위 밖 t는 clamp한다', () {
      final geometry = RouteMapLinearGeometry(const [
        Offset(0, 0),
        Offset(10, 0),
      ]);
      expect(geometry.pointAtT(-1), const Offset(0, 0));
      expect(geometry.pointAtT(2), const Offset(10, 0));
      expect(geometry.pointAtT(double.nan), const Offset(0, 0));
    });

    test('빈/단일 polyline을 안전하게 처리한다', () {
      expect(RouteMapLinearGeometry(const []).pointAtT(0.5), Offset.zero);
      expect(
        RouteMapLinearGeometry(const [Offset(3, 4)]).pointAtT(0.5),
        const Offset(3, 4),
      );
    });

    test('NaN/Infinity 좌표는 마지막이 아니라 첫 정점으로 강등한다', () {
      final nan = RouteMapLinearGeometry(const [
        Offset(0, 0),
        Offset(double.nan, 0),
        Offset(10, 0),
      ]);
      expect(nan.pointAtT(0.5), const Offset(0, 0));
      expect(nan.tAtVertex(1), 0);
    });
  });

  group('tAtVertex / pointBetweenVertices', () {
    final geometry = RouteMapLinearGeometry(const [
      Offset(0, 0),
      Offset(10, 0),
      Offset(40, 0),
    ]);

    test('정점의 t는 누적 거리 비율이다', () {
      expect(geometry.tAtVertex(0), 0);
      expect(geometry.tAtVertex(1), closeTo(10 / 40, 1e-9));
      expect(geometry.tAtVertex(2), 1);
    });

    test('두 역(정점) 사이 fraction 위치를 보간한다', () {
      // 정점0(0)→정점1(10) 사이 절반 → x=5.
      expect(geometry.pointBetweenVertices(0, 1, 0.5), const Offset(5, 0));
      // 정점1(10)→정점2(40) 사이 1/3 → 거리 10 + 30/3 = 20 → x=20.
      expect(geometry.pointBetweenVertices(1, 2, 1 / 3).dx, closeTo(20, 1e-9));
    });

    test('fraction 범위 밖·정점 index 밖을 clamp한다', () {
      expect(geometry.pointBetweenVertices(0, 1, 5), const Offset(10, 0));
      expect(geometry.pointBetweenVertices(0, 99, 1), const Offset(40, 0));
    });
  });
}
