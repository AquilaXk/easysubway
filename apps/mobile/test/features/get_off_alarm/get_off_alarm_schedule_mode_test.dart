import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_schedule_mode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveGetOffAlarmScheduleMode', () {
    test('정확 알람 권한이 있으면 exact 모드·고지 문구 없음', () {
      final resolution = resolveGetOffAlarmScheduleMode(
        exactAlarmPermitted: true,
      );

      expect(resolution.mode, GetOffAlarmScheduleMode.exact);
      expect(resolution.inexactNotice, isNull);
    });

    test('정확 알람 권한이 없으면 inexact로 강등하고 오차 고지 문구 제공', () {
      // 강등 사다리 원칙: 무음 실패 금지 — 반드시 사용자에게 오차를 고지한다.
      final resolution = resolveGetOffAlarmScheduleMode(
        exactAlarmPermitted: false,
      );

      expect(resolution.mode, GetOffAlarmScheduleMode.inexact);
      expect(resolution.inexactNotice, isNotNull);
      expect(resolution.inexactNotice, contains('오차'));
    });
  });
}
