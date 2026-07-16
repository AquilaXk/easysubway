import 'dart:ui';

import 'package:easysubway_mobile/features/network_map/presentation/station_fan_menu_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('design 박스는 700x380', () {
    expect(kFanMenuDesignSize, const Size(700, 380));
  });

  test('섹터 Path는 각 대표 좌표를 포함하고 다른 섹터를 배제한다', () {
    final geo = buildStationFanMenuGeometry();
    // 각 섹터 아이콘 중심(정규화 translate 좌표)은 해당 섹터에 포함된다.
    expect(geo.departure.contains(const Offset(175, 173)), isTrue);
    expect(geo.waypoint.contains(const Offset(350, 127)), isTrue);
    expect(geo.arrival.contains(const Offset(525, 173)), isTrue);
    expect(geo.close.contains(const Offset(350, 277)), isTrue);
    // 상호 배제: 출발 아이콘 중심은 도착 섹터에 없다.
    expect(geo.arrival.contains(const Offset(175, 173)), isFalse);
    expect(geo.departure.contains(const Offset(525, 173)), isFalse);
    expect(geo.departure.contains(const Offset(350, 127)), isFalse);
    expect(geo.arrival.contains(const Offset(350, 127)), isFalse);
    expect(geo.waypoint.contains(const Offset(175, 173)), isFalse);
    expect(geo.waypoint.contains(const Offset(525, 173)), isFalse);
    // 닫기 노치 중심은 출발/도착 섹터 밖.
    expect(geo.departure.contains(const Offset(350, 277)), isFalse);
    expect(geo.arrival.contains(const Offset(350, 277)), isFalse);
  });

  test('실루엣은 네 섹터 대표점을 모두 포함한다', () {
    final geo = buildStationFanMenuGeometry();
    expect(geo.silhouette.contains(const Offset(175, 173)), isTrue);
    expect(geo.silhouette.contains(const Offset(350, 127)), isTrue);
    expect(geo.silhouette.contains(const Offset(525, 173)), isTrue);
    expect(geo.silhouette.contains(const Offset(350, 277)), isTrue);
  });

  test('닫기 섹터와 silhouette는 아이콘·라벨 코어 좌표를 포함한다', () {
    final geo = buildStationFanMenuGeometry();
    expect(geo.close.contains(const Offset(350, 250.93905)), isTrue);
    expect(geo.close.contains(const Offset(350, 302.93903)), isTrue);
    expect(geo.silhouette.contains(const Offset(350, 302.93903)), isTrue);
  });

  test('v3 말풍선 꼬리 팁 상수는 (350,375)이고 닫기·silhouette 하단이 꼬리를 이룬다', () {
    // 팁 상수는 배치(placement)가 소비하는 단일 출처.
    expect(kFanMenuTailTip, const Offset(350, 375));
    final geo = buildStationFanMenuGeometry();
    // 꼬리 내부(팁 바로 위 중심선)는 닫기·silhouette에 포함된다.
    expect(geo.close.contains(const Offset(350, 373)), isTrue);
    expect(geo.silhouette.contains(const Offset(350, 373)), isTrue);
    // 팁 아래(설계 꼬리 밖)는 포함되지 않는다 — 하단이 팁에서 닫힘.
    expect(geo.close.contains(const Offset(350, 377)), isFalse);
    expect(geo.silhouette.contains(const Offset(350, 377)), isFalse);
    // 늘어난 꼬리는 다른 섹터를 침범하지 않는다(#2109 비겹침 유지).
    expect(geo.departure.contains(const Offset(350, 373)), isFalse);
    expect(geo.arrival.contains(const Offset(350, 373)), isFalse);
    expect(geo.waypoint.contains(const Offset(350, 373)), isFalse);
  });

  test('내부 구분선은 SVG의 세 contour만 가진다', () {
    final geo = buildStationFanMenuGeometry();
    expect(geo.dividers.computeMetrics().length, 3);
  });

  test('방사형 공유 경계 양쪽은 각각 인접 섹터에 포함된다', () {
    final geo = buildStationFanMenuGeometry();
    expect(geo.departure.contains(const Offset(255, 150)), isTrue);
    expect(geo.waypoint.contains(const Offset(262, 150)), isTrue);
    expect(geo.waypoint.contains(const Offset(438, 150)), isTrue);
    expect(geo.arrival.contains(const Offset(445, 150)), isTrue);
  });
}
