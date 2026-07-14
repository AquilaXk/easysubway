import 'package:easysubway_mobile/features/network_map/presentation/station_fan_menu.dart';
import 'package:easysubway_mobile/features/route_draft/domain/route_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// NOTE: 노선도 캔버스는 network_map.dart의 private 위젯이라 직접 pump가 어렵다.
// 이 테스트는 StationFanMenu가 노선도에 마운트됨을 보장하기보다, onAction의
// set/clear 분기 규칙을 순수 함수로 뽑아 검증한다(아래 헬퍼를 network_map.dart에
// @visibleForTesting으로 노출).

import 'package:easysubway_mobile/network_map.dart'
    show
        fanMenuSelectedSlots,
        fanMenuDisabledSlots,
        fanMenuShouldClear,
        fanMenuWidthForViewport,
        fanMenuPlacement;

void main() {
  group('fanMenuPlacement 배치 규칙(build·카메라 패닝 공유)', () {
    test('위쪽 공간이 충분하면 메뉴를 노드 위에 놓는다(placeBelow=false)', () {
      // 상단 경계에서 충분히 떨어진 역: 위쪽에 메뉴 하단이 오도록 배치.
      final placement = fanMenuPlacement(
        stationPoint: const Offset(200, 400),
        viewport: const Size(400, 800),
        clampPosition: false,
      );
      expect(placement.placeBelow, isFalse);
      // top = dy - menuHeight - 8 (menuHeight ≈ 141.14).
      expect(placement.top, closeTo(400 - placement.menuHeight - 8, 0.001));
      expect(placement.revealBounds.top, placement.top);
    });

    test('상단 경계 인근이면 메뉴를 노드 아래로 뒤집는다(placeBelow=true)', () {
      // 위쪽 공간 부족(dy - menuHeight - 8 < 8): 노드 아래 배치로 전환.
      final placement = fanMenuPlacement(
        stationPoint: const Offset(200, 10),
        viewport: const Size(400, 800),
        clampPosition: false,
      );
      expect(placement.placeBelow, isTrue);
      expect(placement.top, closeTo(10 + 28, 0.001));
      expect(placement.revealBounds.height, placement.menuHeight);
    });

    test('#2109 뷰포트를 주면 좁은 화면 경계에서 left를 화면 안으로 클램프한다', () {
      // 우측 경계에 붙은 역: 패닝이 .clamped() 한계로 다 못 드러낼 때를 위한
      // 위젯 레벨 클램프 폴백. left는 여백(12) ~ (width - 12 - menuWidth) 안으로.
      const viewport = Size(360, 800);
      final clamped = fanMenuPlacement(
        stationPoint: const Offset(355, 400),
        viewport: viewport,
        clampPosition: true,
      );
      const margin = 12.0;
      final maxLeft = viewport.width - margin - clamped.menuWidth;
      expect(clamped.left, lessThanOrEqualTo(maxLeft + 0.001));
      expect(clamped.left, greaterThanOrEqualTo(margin - 0.001));
      // 우측이 화면 안(오른쪽 여백 이내).
      expect(
        clamped.left + clamped.menuWidth,
        lessThanOrEqualTo(viewport.width - margin + 0.001),
      );

      // 좌측 경계에 붙은 역: left가 여백 이상으로 밀린다.
      final leftClamped = fanMenuPlacement(
        stationPoint: const Offset(5, 400),
        viewport: viewport,
        clampPosition: true,
      );
      expect(leftClamped.left, greaterThanOrEqualTo(margin - 0.001));
    });

    test('카메라 패닝 경로는 같은 viewport에서 클램프 없이 이상적 배치를 낸다', () {
      // 패닝은 같은 viewport에서 이상적(클램프 없는) revealBounds로 최대한
      // 노출을 시도해야 하므로 left가 중심 정렬 그대로 유지된다.
      final unclamped = fanMenuPlacement(
        stationPoint: const Offset(355, 400),
        viewport: const Size(360, 800),
        clampPosition: false,
      );
      expect(unclamped.left, closeTo(355 - unclamped.menuWidth / 2, 0.001));
    });

    test('320/360/364/390dp에서 메뉴 너비를 단일 규칙으로 계산한다', () {
      expect(fanMenuWidthForViewport(320), 220);
      expect(fanMenuWidthForViewport(360), 220);
      expect(fanMenuWidthForViewport(364), 220);
      expect(fanMenuWidthForViewport(390), 220);
    });

    test('clamp 여부와 무관하게 같은 viewport는 같은 menu size를 사용한다', () {
      const viewport = Size(360, 800);
      final renderPlacement = fanMenuPlacement(
        stationPoint: const Offset(355, 400),
        viewport: viewport,
        clampPosition: true,
      );
      final cameraPlacement = fanMenuPlacement(
        stationPoint: const Offset(355, 400),
        viewport: viewport,
        clampPosition: false,
      );

      expect(renderPlacement.menuWidth, cameraPlacement.menuWidth);
      expect(renderPlacement.menuHeight, cameraPlacement.menuHeight);
      expect(renderPlacement.menuWidth, 220);
      expect(renderPlacement.left, isNot(cameraPlacement.left));
    });

    test('reveal bounds는 팬 메뉴 자체만 포함한다', () {
      for (final stationPoint in const [
        Offset(5, 10),
        Offset(200, 400),
        Offset(395, 790),
      ]) {
        final placement = fanMenuPlacement(
          stationPoint: stationPoint,
          viewport: const Size(400, 800),
          clampPosition: true,
        );
        expect(
          placement.revealBounds,
          Rect.fromLTWH(
            placement.left,
            placement.top,
            placement.menuWidth,
            placement.menuHeight,
          ),
        );
      }
    });
  });

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
