import 'package:easysubway_mobile/features/service_notice/domain/service_notice.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, Object?> json({
    String severity = 'DISRUPTION',
    String scope = 'LINE',
    Object? scopeValue = '2',
    Object? expiresAt = '2026-07-06T18:00:00',
  }) {
    return {
      'id': 'n1',
      'scope': scope,
      'scopeValue': scopeValue,
      'title': '2호선 지연',
      'body': '우회 경로를 확인하세요.',
      'severity': severity,
      'publishedAt': '2026-07-06T09:00:00',
      'expiresAt': expiresAt,
    };
  }

  group('ServiceNotice.fromJson', () {
    test('유효한 JSON을 파싱한다', () {
      final notice = ServiceNotice.fromJson(json())!;
      expect(notice.id, 'n1');
      expect(notice.scope, NoticeScope.line);
      expect(notice.scopeValue, '2');
      expect(notice.severity, NoticeSeverity.disruption);
      expect(notice.isDisruption, isTrue);
      expect(notice.publishedAt, DateTime.utc(2026, 7, 6, 9));
      expect(notice.expiresAt, DateTime.utc(2026, 7, 6, 18));
      expect(notice.publishedAt.isUtc, isTrue);
      expect(notice.expiresAt!.isUtc, isTrue);
    });

    test('INFO 심각도·ALL 대상·만료 없음도 파싱한다', () {
      final notice = ServiceNotice.fromJson(
        json(severity: 'INFO', scope: 'ALL', scopeValue: null, expiresAt: null),
      )!;
      expect(notice.severity, NoticeSeverity.info);
      expect(notice.scope, NoticeScope.all);
      expect(notice.scopeValue, isNull);
      expect(notice.expiresAt, isNull);
      expect(notice.isDisruption, isFalse);
    });

    test('offset 없는 UTC 시각은 DST 결손 구간에서도 원문 시각을 보존한다', () {
      final payload = json()..['publishedAt'] = '2026-03-08T02:30:00';

      final notice = ServiceNotice.fromJson(payload)!;

      expect(notice.publishedAt, DateTime.utc(2026, 3, 8, 2, 30));
      expect(notice.publishedAt.isUtc, isTrue);
    });

    test('명시적 offset 시각은 같은 UTC instant로 파싱한다', () {
      final payload = json()..['publishedAt'] = '2026-07-06T09:00:00+09:00';

      final notice = ServiceNotice.fromJson(payload)!;

      expect(notice.publishedAt, DateTime.utc(2026, 7, 6));
      expect(notice.publishedAt.isUtc, isTrue);
    });

    test('date-only 시각도 숫자 offset으로 오인하지 않고 UTC로 파싱한다', () {
      final payload = json()..['publishedAt'] = '2026-07-06';

      final notice = ServiceNotice.fromJson(payload)!;

      expect(notice.publishedAt, DateTime.utc(2026, 7, 6));
      expect(notice.publishedAt.isUtc, isTrue);
    });

    test('알 수 없는 severity/scope는 null을 돌려준다(무음 실패 대신 제외)', () {
      expect(ServiceNotice.fromJson(json(severity: 'WARN')), isNull);
      expect(ServiceNotice.fromJson(json(scope: 'CITY')), isNull);
    });

    test('필수값 누락은 null을 돌려준다', () {
      final bad = json()..remove('title');
      expect(ServiceNotice.fromJson(bad), isNull);
    });
  });

  group('ServiceNotice.listFromApiData', () {
    test('배열을 파싱하고 잘못된 항목은 건너뛴다', () {
      final list = ServiceNotice.listFromApiData([
        json(),
        json(severity: 'WARN'),
        json(severity: 'INFO', scope: 'ALL', scopeValue: null),
      ]);
      expect(list, hasLength(2));
      expect(list.map((n) => n.severity), [
        NoticeSeverity.disruption,
        NoticeSeverity.info,
      ]);
    });

    test('data가 리스트가 아니면 빈 목록', () {
      expect(ServiceNotice.listFromApiData(null), isEmpty);
      expect(ServiceNotice.listFromApiData('nope'), isEmpty);
    });
  });
}
