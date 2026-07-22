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

    test('openWaypointSlot은 빈 경유 행만 열고, clearWaypoint로 닫힌다', () {
      final controller = RouteDraftController();

      controller.openWaypointSlot();
      expect(controller.isWaypointRowVisible, isTrue);
      expect(controller.draft.waypoint, isNull);

      controller.clearWaypoint();
      expect(controller.isWaypointRowVisible, isFalse);
    });

    test('마지막 역 clear 시 열린 경유 슬롯도 닫힌다', () {
      final controller = RouteDraftController()
        ..setOrigin(origin)
        ..openWaypointSlot();
      expect(controller.isWaypointRowVisible, isTrue);

      controller.clearOrigin();
      expect(controller.draft.isEmpty, isTrue);
      expect(controller.isWaypointRowVisible, isFalse);
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

    test('이미 다른 슬롯에 있는 역은 그 슬롯 지정을 거부한다 (#1975)', () {
      final controller = RouteDraftController();
      controller.setOrigin(origin);
      var notifications = 0;
      controller.addListener(() => notifications += 1);

      // 출발과 같은 역을 경유/도착으로 지정하려 하면 무시된다.
      controller.setWaypoint(origin);
      expect(controller.draft.waypoint, isNull);
      controller.setDestination(origin);
      expect(controller.draft.destination, isNull);
      expect(notifications, 0);

      // 경유가 채워진 뒤 출발/도착을 경유와 같은 역으로 지정해도 무시된다.
      controller.setWaypoint(waypoint);
      notifications = 0;
      controller.setOrigin(waypoint);
      expect(controller.draft.origin?.id, 'gangnam');
      controller.setDestination(waypoint);
      expect(controller.draft.destination, isNull);
      expect(notifications, 0);
    });

    test('같은 슬롯에 같은 역 재지정(덮어쓰기)은 허용한다 (#1975)', () {
      final controller = RouteDraftController();
      controller.setOrigin(origin);
      var notifications = 0;
      controller.addListener(() => notifications += 1);

      controller.setOrigin(origin);
      expect(controller.draft.origin?.id, 'gangnam');
      expect(notifications, 1);
    });
  });

  group('RouteDraftController 슬롯 재배열 (#1985)', () {
    const origin = RouteDraftStation(id: 'gangnam', nameKo: '강남');
    const destination = RouteDraftStation(id: 'jamsil', nameKo: '잠실');
    const waypoint = RouteDraftStation(id: 'seolleung', nameKo: '선릉');

    test('swapSlots(출발, 도착)은 두 값을 바꾸고 경유는 보존한다', () {
      final controller = RouteDraftController();
      controller.setOrigin(origin);
      controller.setDestination(destination);
      controller.setWaypoint(waypoint);
      var notifications = 0;
      controller.addListener(() => notifications += 1);

      controller.swapSlots(RouteDraftSlot.origin, RouteDraftSlot.destination);

      expect(controller.draft.origin?.id, 'jamsil');
      expect(controller.draft.destination?.id, 'gangnam');
      expect(controller.draft.waypoint?.id, 'seolleung');
      expect(notifications, 1);
    });

    test('swapSlots(출발, 경유)는 출발·경유를 바꾸고 도착은 보존한다', () {
      final controller = RouteDraftController();
      controller.setOrigin(origin);
      controller.setDestination(destination);
      controller.setWaypoint(waypoint);
      var notifications = 0;
      controller.addListener(() => notifications += 1);

      controller.swapSlots(RouteDraftSlot.origin, RouteDraftSlot.waypoint);

      expect(controller.draft.origin?.id, 'seolleung');
      expect(controller.draft.waypoint?.id, 'gangnam');
      expect(controller.draft.destination?.id, 'jamsil');
      expect(notifications, 1);
    });

    test('swapSlots(경유, 도착)은 경유·도착을 바꾸고 출발은 보존한다', () {
      final controller = RouteDraftController();
      controller.setOrigin(origin);
      controller.setDestination(destination);
      controller.setWaypoint(waypoint);
      var notifications = 0;
      controller.addListener(() => notifications += 1);

      controller.swapSlots(RouteDraftSlot.waypoint, RouteDraftSlot.destination);

      expect(controller.draft.waypoint?.id, 'jamsil');
      expect(controller.draft.destination?.id, 'seolleung');
      expect(controller.draft.origin?.id, 'gangnam');
      expect(notifications, 1);
    });

    test('swapSlots(a, a)는 no-op이고 notify하지 않는다', () {
      final controller = RouteDraftController();
      controller.setOrigin(origin);
      var notifications = 0;
      controller.addListener(() => notifications += 1);

      controller.swapSlots(RouteDraftSlot.origin, RouteDraftSlot.origin);

      expect(controller.draft.origin?.id, 'gangnam');
      expect(notifications, 0);
    });

    test('swapSlots 두 슬롯 모두 비어 있으면 no-op이고 notify하지 않는다', () {
      final controller = RouteDraftController();
      controller.setWaypoint(waypoint);
      var notifications = 0;
      controller.addListener(() => notifications += 1);

      controller.swapSlots(RouteDraftSlot.origin, RouteDraftSlot.destination);

      expect(controller.draft.waypoint?.id, 'seolleung');
      expect(controller.draft.origin, isNull);
      expect(controller.draft.destination, isNull);
      expect(notifications, 0);
    });

    test('moveSlot은 to가 비어 있으면 from 값을 to로 옮기고 from을 비운다', () {
      final controller = RouteDraftController();
      controller.setOrigin(origin);
      var notifications = 0;
      controller.addListener(() => notifications += 1);

      controller.moveSlot(RouteDraftSlot.origin, RouteDraftSlot.destination);

      expect(controller.draft.origin, isNull);
      expect(controller.draft.destination?.id, 'gangnam');
      expect(notifications, 1);
    });

    test('moveSlot은 from이 비어 있으면 no-op이고 notify하지 않는다', () {
      final controller = RouteDraftController();
      controller.setDestination(destination);
      var notifications = 0;
      controller.addListener(() => notifications += 1);

      controller.moveSlot(RouteDraftSlot.origin, RouteDraftSlot.destination);

      expect(controller.draft.origin, isNull);
      expect(controller.draft.destination?.id, 'jamsil');
      expect(notifications, 0);
    });

    test('moveSlot은 to가 채워져 있으면 값 소실 없이 두 값을 교환한다(swap 폴백)', () {
      final controller = RouteDraftController();
      controller.setOrigin(origin);
      controller.setDestination(destination);
      var notifications = 0;
      controller.addListener(() => notifications += 1);

      controller.moveSlot(RouteDraftSlot.origin, RouteDraftSlot.destination);

      expect(controller.draft.origin?.id, 'jamsil');
      expect(controller.draft.destination?.id, 'gangnam');
      expect(notifications, 1);
    });
  });
}
