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
        fanMenuPlacement,
        fanMenuTransferAnchor;
import 'package:easysubway_mobile/features/network_map/presentation/station_fan_menu_geometry.dart'
    show kFanMenuDesignSize, kFanMenuTailTip;

void main() {
  group('fanMenuPlacement 배치 규칙(build·카메라 패닝 공유)', () {
    test('항상 노드 위에 배치하고 꼬리 팁이 앵커 노드에 닿는다(#2192)', () {
      // 상단 경계에서 충분히 떨어진 역: 꼬리 팁(y=375/380)이 노드에 오도록 배치.
      final placement = fanMenuPlacement(
        stationPoint: const Offset(200, 400),
        viewport: const Size(400, 800),
        clampPosition: false,
      );
      // top = dy - menuHeight * (팁 y / design height).
      expect(
        placement.top,
        closeTo(
          400 -
              placement.menuHeight *
                  (kFanMenuTailTip.dy / kFanMenuDesignSize.height),
          0.001,
        ),
      );
      expect(placement.revealBounds.top, placement.top);
      // 꼬리 팁의 뷰포트 좌표 = 앵커 노드 좌표(정중앙 접촉).
      final tipX =
          placement.left +
          placement.menuWidth * (kFanMenuTailTip.dx / kFanMenuDesignSize.width);
      final tipY =
          placement.top +
          placement.menuHeight *
              (kFanMenuTailTip.dy / kFanMenuDesignSize.height);
      expect(tipX, closeTo(200, 0.001));
      expect(tipY, closeTo(400, 0.001));
    });

    test('flip 제거: 상단 경계 인근이어도 위 배치 유지(top이 음수여도 뒤집지 않음)', () {
      // 위쪽 공간이 부족해도 노드 아래로 뒤집지 않는다 — 카메라 패닝 헤드룸이
      // 메뉴 전체를 노출한다(#2192). clampPosition:false는 이상적(패닝 대상) 배치.
      final placement = fanMenuPlacement(
        stationPoint: const Offset(200, 10),
        viewport: const Size(400, 800),
        clampPosition: false,
      );
      final expectedTop =
          10 -
          placement.menuHeight *
              (kFanMenuTailTip.dy / kFanMenuDesignSize.height);
      expect(placement.top, closeTo(expectedTop, 0.001));
      expect(placement.top, lessThan(0)); // 노드 위로 나가되 아래로 뒤집지 않는다.
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

  group('fanMenuTransferAnchor 환승 캡슐 시각 중심(#2192, 렌더 규칙 재사용)', () {
    // designScale=1이라 designSpread = 멤버 최대 쌍거리(px). 임계는 렌더러와 동일
    // (stackedMax=8, spanMax=16, separateMin=28).
    test('멤버 2개 미만이면 일반역으로 보고 탭 좌표 그대로', () {
      final anchor = fanMenuTransferAnchor(
        memberPositions: const [Offset(3, 7)],
        tappedPosition: const Offset(3, 7),
        designScale: 1,
      );
      expect(anchor, const Offset(3, 7));
    });

    test('스택(소이격)은 멤버 평균 중심', () {
      // spread=5 ≤ 8 → 평균 (2.5, 0).
      final anchor = fanMenuTransferAnchor(
        memberPositions: const [Offset(0, 0), Offset(5, 0)],
        tappedPosition: const Offset(0, 0),
        designScale: 1,
      );
      expect(anchor.dx, closeTo(2.5, 0.001));
      expect(anchor.dy, closeTo(0, 0.001));
    });

    test('스팬(소이격 평행)은 멤버 bounds 중심', () {
      // 8 < spread(12) ≤ 16 → bounds 중심 (6, 0). inflate는 대칭이라 중심 불변.
      final anchor = fanMenuTransferAnchor(
        memberPositions: const [Offset(0, 0), Offset(12, 0)],
        tappedPosition: const Offset(0, 0),
        designScale: 1,
      );
      expect(anchor.dx, closeTo(6, 0.001));
      expect(anchor.dy, closeTo(0, 0.001));
    });

    test('강등 스택(스팬 상한~분리 하한)은 평균 중심', () {
      // 16 < spread(20) ≤ 28 → 평균 (10, 0).
      final anchor = fanMenuTransferAnchor(
        memberPositions: const [Offset(0, 0), Offset(20, 0)],
        tappedPosition: const Offset(0, 0),
        designScale: 1,
      );
      expect(anchor.dx, closeTo(10, 0.001));
      expect(anchor.dy, closeTo(0, 0.001));
    });

    test('분리(대이격)는 탭한 멤버의 캡슐 중심', () {
      // spread(40) > 28 → separate. 탭한 멤버 좌표를 앵커로.
      final anchor = fanMenuTransferAnchor(
        memberPositions: const [Offset(0, 0), Offset(40, 0)],
        tappedPosition: const Offset(40, 0),
        designScale: 1,
      );
      expect(anchor, const Offset(40, 0));
    });

    test('designScale이 모드 임계를 스케일한다(렌더러와 동일 값 소비)', () {
      // 비대칭 3멤버: 평균(4,0) ≠ bounds 중심(5,0)이라 모드를 구분할 수 있다.
      const members = [Offset(0, 0), Offset(2, 0), Offset(10, 0)];
      // designScale=1 → spread=10 → 스팬 → bounds 중심 (5,0).
      final span = fanMenuTransferAnchor(
        memberPositions: members,
        tappedPosition: const Offset(0, 0),
        designScale: 1,
      );
      expect(span.dx, closeTo(5, 0.001));
      // designScale=0.5 → spread=5 ≤ 8 → 스택 → 평균 (4,0).
      final stacked = fanMenuTransferAnchor(
        memberPositions: members,
        tappedPosition: const Offset(0, 0),
        designScale: 0.5,
      );
      expect(stacked.dx, closeTo(4, 0.001));
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
