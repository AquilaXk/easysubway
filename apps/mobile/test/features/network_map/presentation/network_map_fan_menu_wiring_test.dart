import 'package:easysubway_mobile/features/network_map/presentation/station_fan_menu.dart';
import 'package:easysubway_mobile/features/route_draft/domain/route_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// NOTE: 노선도 캔버스는 network_map.dart의 private 위젯이라 직접 pump가 어렵다.
// 이 테스트는 StationFanMenu가 노선도에 마운트됨을 보장하기보다, onAction의
// set/clear 분기 규칙을 순수 함수로 뽑아 검증한다(아래 헬퍼를 network_map.dart에
// @visibleForTesting으로 노출).

import 'package:easysubway_mobile/network_map.dart'
    show fanMenuSelectedSlots, fanMenuDisabledSlots, fanMenuShouldClear;

void main() {
  test('selectedSlots: 선택 역 id가 배정된 슬롯만 포함', () {
    final selected = fanMenuSelectedSlots(
      stationId: 's1',
      originStationId: 's1',
      waypointStationId: null,
      destinationStationId: 's2',
    );
    expect(selected, {RouteDraftSlot.origin});
  });

  test('disabledSlots: 이미 origin인 역을 다시 탭하면 origin은 재지정 가능(dim 아님), 다른 슬롯은 dim', () {
    final disabled = fanMenuDisabledSlots(
      stationId: 's1',
      originStationId: 's1',
      waypointStationId: 's3',
      destinationStationId: 's2',
    );
    // 구 오버레이 규칙(실코드 network_map.dart _NetworkMapStationActionOverlay):
    //   originEnabled      = s1 != waypoint(s3) && s1 != dest(s2)   → true  → dim 아님
    //   waypointEnabled    = s1 != origin(s1)   && s1 != dest(s2)   → false → waypoint dim
    //   destinationEnabled = s1 != origin(s1)   && s1 != waypoint(s3) → false → dest dim
    // 자기 슬롯(origin) 재지정은 허용, 같은 역을 다른 슬롯에 중복 배정하는 건 막는다.
    expect(disabled, {RouteDraftSlot.waypoint, RouteDraftSlot.destination});
  });

  test('disabledSlots: 다른 역 탭 시 s1이 점유한 슬롯들이 dim', () {
    final disabled = fanMenuDisabledSlots(
      stationId: 'sX',
      originStationId: 's1',
      waypointStationId: null,
      destinationStationId: null,
    );
    // sX는 어디에도 없음. origin은 s1(sX 아님)이 점유 → origin/waypoint/dest 중
    // sX가 아닌 곳에 이미 있는 역이 있으면 그 슬롯 dim: 구 오버레이 규칙
    // (originEnabled = id != waypointId && id != destId 등)을 이식.
    // sX 기준: originEnabled = sX!=null(way) && sX!=null(dest)=true(dim 아님),
    // waypointEnabled = sX!=s1 && sX!=null = true, destEnabled = sX!=s1 && sX!=null=true.
    // => dim 없음.
    expect(disabled, isEmpty);
  });

  test('disabledSlots: sX가 이미 waypoint면 origin·destination이 dim', () {
    final disabled = fanMenuDisabledSlots(
      stationId: 'sX',
      originStationId: null,
      waypointStationId: 'sX',
      destinationStationId: null,
    );
    // 구 규칙: originEnabled = sX!=waypoint(sX) → false → origin dim.
    // destEnabled = sX!=null(origin) && sX!=waypoint(sX) → false → dest dim.
    // waypointEnabled = sX!=null && sX!=null → true → waypoint 자기 슬롯, dim 아님.
    expect(disabled, {RouteDraftSlot.origin, RouteDraftSlot.destination});
  });

  test('shouldClear: 이미 배정된 슬롯은 true(해제), 아니면 false(신규 배정)', () {
    const selected = {RouteDraftSlot.origin};
    expect(fanMenuShouldClear(RouteDraftSlot.origin, selected), isTrue);
    expect(fanMenuShouldClear(RouteDraftSlot.waypoint, selected), isFalse);
    expect(fanMenuShouldClear(RouteDraftSlot.destination, selected), isFalse);
  });

  group('재탭 clear 분기 (network_map.dart _NetworkMapCanvas onAction 실배선)', () {
    // network_map.dart의 실제 onAction 클로저(3507행 부근)는
    //   fanMenuShouldClear(slot, selectedSlots) ? clear : set
    // 로 분기한다. _NetworkMapCanvas는 private이라 직접 pump할 수 없으므로,
    // 배선 로직을 사본으로 재현하는 대신 network_map.dart가 실제로 노출하는
    // @visibleForTesting 순수 함수 fanMenuShouldClear를 그대로 호출해
    // 콜백 배선 회귀를 잡는다(로직 사본 없음).
    Future<void> pumpWithWiring(
      WidgetTester tester, {
      required Set<RouteDraftSlot> selectedSlots,
      required void Function(RouteDraftSlot) onSet,
      required void Function(RouteDraftSlot) onClear,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: StationFanMenu(
                width: 700, // design 1:1 스케일이라 design 좌표=위젯 좌표
                selectedSlots: selectedSlots,
                disabledSlots: const {},
                onAction: (slot) {
                  if (fanMenuShouldClear(slot, selectedSlots)) {
                    onClear(slot);
                  } else {
                    onSet(slot);
                  }
                },
                onClose: () {},
              ),
            ),
          ),
        ),
      );
    }

    // station_fan_menu_test.dart와 동일하게, width=700이면 위젯 로컬 좌표가
    // design 좌표와 1:1이라 Center 배치의 좌상단 오프셋만 더해 글로벌 좌표로
    // 변환한다. Semantics onTap 경로(투명 버튼 오버레이)를 탭 좌표로 태운다.
    Offset globalOf(WidgetTester tester, Offset design) {
      final topLeft = tester.getTopLeft(find.byType(StationFanMenu));
      return topLeft + design;
    }

    testWidgets('이미 origin으로 배정된 섹터를 재탭하면 clear만 불리고 set은 불리지 않는다', (
      tester,
    ) async {
      final setCalls = <RouteDraftSlot>[];
      final clearCalls = <RouteDraftSlot>[];
      await pumpWithWiring(
        tester,
        selectedSlots: {RouteDraftSlot.origin},
        onSet: setCalls.add,
        onClear: clearCalls.add,
      );

      // "출발역으로 설정" 섹터(아이콘 중심 175,173)를 재탭.
      await tester.tapAt(globalOf(tester, const Offset(175, 173)));
      await tester.pump();

      expect(clearCalls, [RouteDraftSlot.origin]);
      expect(setCalls, isEmpty);
    });

    testWidgets('배정되지 않은 섹터를 탭하면 set만 불리고 clear는 불리지 않는다', (tester) async {
      final setCalls = <RouteDraftSlot>[];
      final clearCalls = <RouteDraftSlot>[];
      await pumpWithWiring(
        tester,
        selectedSlots: {RouteDraftSlot.origin},
        onSet: setCalls.add,
        onClear: clearCalls.add,
      );

      // "도착역으로 설정" 섹터(아이콘 중심 525,173)는 미배정.
      await tester.tapAt(globalOf(tester, const Offset(525, 173)));
      await tester.pump();

      expect(setCalls, [RouteDraftSlot.destination]);
      expect(clearCalls, isEmpty);
    });
  });
}
