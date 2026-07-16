import 'package:easysubway_mobile/features/network_map/domain/route_map_owner_labels.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseRouteMapOwnerLabelsForRegion', () {
    const sidecar = '''
    {
      "schemaVersion": 1,
      "artifactKind": "route-map-basemap-owner-labels",
      "regions": {
        "seoul": [
          {"station": "시청", "role": "transfer", "x": 1069.29, "y": 817.38, "anchor": "start", "fontSizePx": 13.0},
          {"station": "가야", "role": "ordinary", "x": 100.0, "y": 200.0, "anchor": "middle", "fontSizePx": 12.5}
        ],
        "busan": [
          {"station": "가야", "role": "terminal", "x": 300.0, "y": 400.0, "anchor": "end", "fontSizePx": 13.0}
        ]
      }
    }
    ''';

    test('region별 station명 키 맵으로 파싱한다', () {
      final seoul = parseRouteMapOwnerLabelsForRegion(sidecar, 'seoul');
      expect(seoul.length, 2);
      expect(seoul['시청']!.role, 'transfer');
      expect(seoul['시청']!.position, const Offset(1069.29, 817.38));
      expect(seoul['시청']!.anchor, RouteMapOwnerLabelAnchor.start);
      expect(seoul['가야']!.anchor, RouteMapOwnerLabelAnchor.middle);
      expect(seoul['가야']!.fontSizePx, 12.5);
    });

    test('다른 region은 섞이지 않는다', () {
      final busan = parseRouteMapOwnerLabelsForRegion(sidecar, 'busan');
      expect(busan.length, 1);
      expect(busan['가야']!.role, 'terminal');
      expect(busan['가야']!.anchor, RouteMapOwnerLabelAnchor.end);
    });

    test('없는 region·잘못된 JSON은 빈 맵(안전 폴백)', () {
      expect(parseRouteMapOwnerLabelsForRegion(sidecar, 'gwangju'), isEmpty);
      expect(parseRouteMapOwnerLabelsForRegion('not json', 'seoul'), isEmpty);
      expect(parseRouteMapOwnerLabelsForRegion('{}', 'seoul'), isEmpty);
    });

    test('중복 station명은 role 우선순위(transfer>terminal>ordinary)로 하나만 남긴다', () {
      const dup = '''
      {
        "regions": {
          "seoul": [
            {"station": "신촌", "role": "ordinary", "x": 1.0, "y": 1.0, "anchor": "start", "fontSizePx": 12.0},
            {"station": "신촌", "role": "transfer", "x": 2.0, "y": 2.0, "anchor": "start", "fontSizePx": 12.0}
          ]
        }
      }
      ''';
      final result = parseRouteMapOwnerLabelsForRegion(dup, 'seoul');
      expect(result.length, 1);
      expect(result['신촌']!.role, 'transfer');
      expect(result['신촌']!.position, const Offset(2.0, 2.0));
    });

    test('필드 누락 항목은 건너뛴다', () {
      const malformed = '''
      {
        "regions": {
          "seoul": [
            {"station": "누락역", "role": "ordinary", "anchor": "start", "fontSizePx": 12.0},
            {"station": "정상역", "role": "ordinary", "x": 5.0, "y": 5.0, "anchor": "start", "fontSizePx": 12.0}
          ]
        }
      }
      ''';
      final result = parseRouteMapOwnerLabelsForRegion(malformed, 'seoul');
      expect(result.length, 1);
      expect(result.containsKey('정상역'), isTrue);
    });

    test(
      '#2068 광주 2차: hasLineTerminalBadge 플래그를 파싱하고 미보유 시 false',
      () {
        const sidecar = '''
      {
        "regions": {
          "gwangju": [
            {"station": "평동", "role": "terminal", "x": 1.0, "y": 1.0, "anchor": "start", "fontSizePx": 78.0, "hasLineTerminalBadge": true},
            {"station": "도산", "role": "ordinary", "x": 2.0, "y": 2.0, "anchor": "start", "fontSizePx": 72.0}
          ]
        }
      }
      ''';
        final result = parseRouteMapOwnerLabelsForRegion(sidecar, 'gwangju');
        expect(result['평동']!.hasLineTerminalBadge, isTrue);
        expect(result['도산']!.hasLineTerminalBadge, isFalse);
      },
    );
  });

  group('routeMapOwnerLabelsByRegionFrom', () {
    test('전 region을 한 번에 파싱한다', () {
      const sidecar = '''
      {
        "regions": {
          "seoul": [{"station": "시청", "role": "transfer", "x": 1.0, "y": 2.0, "anchor": "start", "fontSizePx": 13.0}],
          "busan": []
        }
      }
      ''';
      final byRegion = routeMapOwnerLabelsByRegionFrom(sidecar);
      expect(byRegion.keys.toSet(), {'seoul', 'busan'});
      expect(byRegion['seoul']!['시청']!.role, 'transfer');
      expect(byRegion['busan'], isEmpty);
    });
  });
}
