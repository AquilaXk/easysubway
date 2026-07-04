import 'package:easysubway_mobile/features/network_map/presentation/route_map_label_placement.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

RouteMapLabelCandidate candidate({
  required String id,
  required Offset anchor,
  required int priority,
  Size size = const Size(40, 12),
}) {
  return RouteMapLabelCandidate(
    id: id,
    anchor: anchor,
    size: size,
    priority: priority,
  );
}

void main() {
  group('routeMapLabelRect', () {
    const anchor = Offset(100, 100);
    const size = Size(40, 12);
    test('right는 점 오른쪽, 세로 중앙 정렬', () {
      final rect = routeMapLabelRect(anchor, size, RouteMapLabelAnchor.right, 4);
      expect(rect, const Rect.fromLTWH(104, 94, 40, 12));
    });
    test('left는 점 왼쪽', () {
      final rect = routeMapLabelRect(anchor, size, RouteMapLabelAnchor.left, 4);
      expect(rect, const Rect.fromLTWH(56, 94, 40, 12));
    });
    test('above는 점 위, below는 점 아래', () {
      expect(
        routeMapLabelRect(anchor, size, RouteMapLabelAnchor.above, 4),
        const Rect.fromLTWH(80, 84, 40, 12),
      );
      expect(
        routeMapLabelRect(anchor, size, RouteMapLabelAnchor.below, 4),
        const Rect.fromLTWH(80, 104, 40, 12),
      );
    });
  });

  group('placeRouteMapLabels', () {
    test('겹치지 않는 라벨은 모두 배치된다', () {
      final placed = placeRouteMapLabels([
        candidate(id: 'a', anchor: const Offset(0, 0), priority: 2),
        candidate(id: 'b', anchor: const Offset(0, 500), priority: 2),
      ]);
      expect(placed, hasLength(2));
    });

    test('우선순위 높은 라벨이 자리를 차지하고 낮은 라벨은 숨는다', () {
      // 두 후보가 같은 지점에 겹치고, anchor 후보가 하나뿐이라 둘 중 하나만 배치.
      final placed = placeRouteMapLabels(
        [
          candidate(id: 'regular', anchor: const Offset(100, 100), priority: 2),
          candidate(
            id: 'transfer',
            anchor: const Offset(100, 100),
            priority: 0,
          ),
        ],
        anchors: const [RouteMapLabelAnchor.right],
      );
      expect(placed, hasLength(1));
      expect(placed.single.candidate.id, 'transfer');
    });

    test('오른쪽이 막히면 다른 anchor로 배치한다 (variable anchor)', () {
      // a는 right에 배치. b는 같은 anchor라 right는 a와 겹치지만 left는 빈다.
      final placed = placeRouteMapLabels([
        candidate(id: 'a', anchor: const Offset(100, 100), priority: 0),
        candidate(id: 'b', anchor: const Offset(100, 100), priority: 1),
      ]);
      expect(placed, hasLength(2));
      final b = placed.firstWhere((p) => p.candidate.id == 'b');
      expect(b.anchor, isNot(RouteMapLabelAnchor.right));
    });

    test('모든 anchor가 막히면 라벨을 숨긴다', () {
      // 세 라벨이 한 점에 몰리고 anchor 후보가 right/left 둘뿐이면 3번째는 숨는다.
      final placed = placeRouteMapLabels(
        [
          candidate(id: 'a', anchor: const Offset(100, 100), priority: 0),
          candidate(id: 'b', anchor: const Offset(100, 100), priority: 1),
          candidate(id: 'c', anchor: const Offset(100, 100), priority: 2),
        ],
        anchors: const [RouteMapLabelAnchor.right, RouteMapLabelAnchor.left],
      );
      expect(placed, hasLength(2));
      expect(placed.map((p) => p.candidate.id), containsAll(['a', 'b']));
    });

    test('viewportBounds 밖 위치는 건너뛴다', () {
      final placed = placeRouteMapLabels(
        [candidate(id: 'far', anchor: const Offset(5000, 5000), priority: 0)],
        viewportBounds: const Rect.fromLTWH(0, 0, 400, 400),
      );
      expect(placed, isEmpty);
    });

    test('anchorPadding은 라벨을 anchor에서 gap보다 더 띄운다', () {
      final noPad = placeRouteMapLabels(
        [candidate(id: 'a', anchor: const Offset(100, 100), priority: 0)],
        anchors: const [RouteMapLabelAnchor.right],
        gap: 4,
      );
      final withPad = placeRouteMapLabels(
        const [
          RouteMapLabelCandidate(
            id: 'a',
            anchor: Offset(100, 100),
            size: Size(40, 12),
            priority: 0,
            anchorPadding: 20,
          ),
        ],
        anchors: const [RouteMapLabelAnchor.right],
        gap: 4,
      );
      expect(withPad.single.rect.left, greaterThan(noPad.single.rect.left));
      // right anchor: left = anchor.dx + gap + anchorPadding = 100+4+20.
      expect(withPad.single.rect.left, 124);
    });

    test('같은 우선순위는 id로 안정 정렬된다', () {
      final placed = placeRouteMapLabels(
        [
          candidate(id: 'b', anchor: const Offset(100, 100), priority: 1),
          candidate(id: 'a', anchor: const Offset(100, 100), priority: 1),
        ],
        anchors: const [RouteMapLabelAnchor.right],
      );
      expect(placed, hasLength(1));
      expect(placed.single.candidate.id, 'a');
    });
  });
}
