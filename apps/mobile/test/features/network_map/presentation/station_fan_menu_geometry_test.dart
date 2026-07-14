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
}
