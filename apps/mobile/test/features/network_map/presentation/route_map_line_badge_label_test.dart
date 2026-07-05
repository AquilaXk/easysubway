import 'package:easysubway_mobile/features/network_map/presentation/structured_route_map_painter.dart';
import 'package:flutter_test/flutter_test.dart';

// #1764 D: routeMapLineBadgeLabel 결정적 축약을 전 노선(렌더 대상 36개) 입력→출력
// 스냅샷으로 고정한다. 규칙이 바뀌면 이 스냅샷이 드리프트를 잡는다.
void main() {
  group('routeMapLineBadgeLabel 전 노선 스냅샷', () {
    const expected = <String, String>{
      '광주 1호선': '1',
      '대구 1호선': '1',
      '대구 2호선': '2',
      '대구 3호선': '3',
      '대구 대경선': '대경선',
      '대전 1호선': '1',
      '부산 1호선': '1',
      '부산 2호선': '2',
      '부산 3호선': '3',
      '부산 4호선': '4',
      '부산 동해': '동해',
      '부산 부산김해경전철': '부산김해',
      '수도권 1호선': '1',
      '수도권 2호선': '2',
      '수도권 3호선': '3',
      '수도권 4호선': '4',
      '수도권 5호선': '5',
      '수도권 6호선': '6',
      '수도권 7호선': '7',
      '수도권 8호선': '8',
      '수도권 9호선': '9',
      '수도권 GTX-A': 'GTX-A',
      '수도권 경강': '경강',
      '수도권 경의중앙': '경의중앙',
      '수도권 경춘': '경춘',
      '수도권 공항': '공항',
      '수도권 김포골드라인': '김포골드',
      '수도권 서해선': '서해선',
      '수도권 수인분당': '수인분당',
      '수도권 신림선': '신림선',
      '수도권 신분당': '신분당',
      '수도권 에버라인': '에버라인',
      '수도권 우이신설': '우이신설',
      '수도권 의정부': '의정부',
      '수도권 인천1호선': '인천1',
      '수도권 인천2호선': '인천2',
    };

    test('렌더 대상 36개 노선이 모두 포함된다', () {
      expect(expected, hasLength(36));
    });

    expected.forEach((nameKo, badge) {
      test('$nameKo → $badge', () {
        expect(routeMapLineBadgeLabel(nameKo), badge);
      });
    });

    test('전 뱃지는 1~5자(GTX 제외 4자 이내)', () {
      for (final entry in expected.entries) {
        final len = entry.value.length;
        expect(len, greaterThanOrEqualTo(1), reason: '${entry.key} 빈 뱃지 금지');
        if (!entry.value.startsWith('GTX')) {
          expect(len, lessThanOrEqualTo(4), reason: '${entry.key} 4자 초과');
        }
      }
    });

    test('같은 지역 안에서 뱃지가 유일하다(구분 가능)', () {
      final byRegion = <String, List<String>>{};
      expected.forEach((nameKo, badge) {
        final region = nameKo.split(' ').first;
        byRegion.putIfAbsent(region, () => []).add(badge);
      });
      for (final entry in byRegion.entries) {
        expect(
          entry.value.toSet(),
          hasLength(entry.value.length),
          reason: '${entry.key} 지역 뱃지 중복',
        );
      }
    });
  });

  group('routeMapLineBadgeLabel 경계', () {
    test('지역 접두 없는 이름도 처리', () {
      expect(routeMapLineBadgeLabel('1호선'), '1');
      expect(routeMapLineBadgeLabel('수인분당'), '수인분당');
    });

    test('GTX 다른 노선', () {
      expect(routeMapLineBadgeLabel('수도권 GTX-B'), 'GTX-B');
    });

    test('빈 문자열/공백은 원문 반환', () {
      expect(routeMapLineBadgeLabel(''), '');
      expect(routeMapLineBadgeLabel('수도권 '), '수도권');
    });

    test('5자 이상 비호선은 앞 4자로 축약', () {
      expect(routeMapLineBadgeLabel('부산 부산김해경전철'), '부산김해');
      expect(routeMapLineBadgeLabel('수도권 김포골드라인'), '김포골드');
    });
  });
}
