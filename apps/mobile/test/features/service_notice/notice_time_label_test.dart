import 'package:easysubway_mobile/features/service_notice/presentation/notice_time_label.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 7, 6, 12, 0, 0);

  test('1분 미만이면 "방금 전 기준"', () {
    expect(
      formatNoticeAsOf(now.subtract(const Duration(seconds: 30)), now),
      '방금 전 기준',
    );
  });

  test('미래 시각(시계 오차)도 "방금 전 기준"으로 안전 처리', () {
    expect(
      formatNoticeAsOf(now.add(const Duration(minutes: 5)), now),
      '방금 전 기준',
    );
  });

  test('1시간 미만이면 분 단위', () {
    expect(
      formatNoticeAsOf(now.subtract(const Duration(minutes: 12)), now),
      '12분 전 기준',
    );
  });

  test('24시간 미만이면 시간 단위', () {
    expect(
      formatNoticeAsOf(now.subtract(const Duration(hours: 3)), now),
      '3시간 전 기준',
    );
  });

  test('24시간 이상이면 일 단위', () {
    expect(
      formatNoticeAsOf(now.subtract(const Duration(days: 2, hours: 5)), now),
      '2일 전 기준',
    );
  });
}
