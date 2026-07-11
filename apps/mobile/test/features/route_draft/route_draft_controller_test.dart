import 'package:easysubway_mobile/features/route_draft/application/route_draft_controller.dart';
import 'package:easysubway_mobile/features/route_draft/domain/route_draft.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RouteDraftController 경유역', () {
    const origin = RouteDraftStation(id: 'gangnam', nameKo: '강남');
    const destination = RouteDraftStation(id: 'jamsil', nameKo: '잠실');
    const waypoint = RouteDraftStation(id: 'seolleung', nameKo: '선릉');

    test('setWaypoint은 경유역을 채우고, clearWaypoint는 비운다', () {
      final controller = RouteDraftController();

      controller.setWaypoint(waypoint);
      expect(controller.draft.waypoint?.id, 'seolleung');

      controller.clearWaypoint();
      expect(controller.draft.waypoint, isNull);
    });

    test('setOrigin·setDestination은 경유역을 보존한다', () {
      final controller = RouteDraftController();
      controller.setWaypoint(waypoint);

      controller.setOrigin(origin);
      expect(controller.draft.waypoint?.id, 'seolleung');

      controller.setDestination(destination);
      expect(controller.draft.waypoint?.id, 'seolleung');
    });

    test('clearOrigin·clearDestination은 경유역을 보존한다', () {
      final controller = RouteDraftController();
      controller.setOrigin(origin);
      controller.setDestination(destination);
      controller.setWaypoint(waypoint);

      controller.clearOrigin();
      expect(controller.draft.waypoint?.id, 'seolleung');

      controller.clearDestination();
      expect(controller.draft.waypoint?.id, 'seolleung');
    });

    test('swapOriginDestination은 출발·도착만 바꾸고 경유역은 유지한다', () {
      final controller = RouteDraftController();
      controller.setOrigin(origin);
      controller.setDestination(destination);
      controller.setWaypoint(waypoint);

      controller.swapOriginDestination();

      expect(controller.draft.origin?.id, 'jamsil');
      expect(controller.draft.destination?.id, 'gangnam');
      expect(controller.draft.waypoint?.id, 'seolleung');
    });

    test('waypointLabel은 미설정 시 경유 미정, 설정 시 경유 XX역이다', () {
      final controller = RouteDraftController();
      expect(controller.draft.waypointLabel, '경유 미정');

      controller.setWaypoint(waypoint);
      expect(controller.draft.waypointLabel, '경유 선릉역');
    });

    test('경유역만 있어도 draft는 비어있지 않다', () {
      final controller = RouteDraftController();
      controller.setWaypoint(waypoint);

      expect(controller.draft.isEmpty, isFalse);
    });
  });
}
