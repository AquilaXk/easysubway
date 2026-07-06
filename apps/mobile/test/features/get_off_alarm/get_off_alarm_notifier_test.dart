import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_notifier.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_schedule_mode.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('androidScheduleModeFor', () {
    test('exact 모드는 exactAllowWhileIdle로 예약', () {
      expect(
        androidScheduleModeFor(GetOffAlarmScheduleMode.exact),
        AndroidScheduleMode.exactAllowWhileIdle,
      );
    });

    test('inexact 모드는 inexactAllowWhileIdle로 강등 예약', () {
      expect(
        androidScheduleModeFor(GetOffAlarmScheduleMode.inexact),
        AndroidScheduleMode.inexactAllowWhileIdle,
      );
    });
  });
}
