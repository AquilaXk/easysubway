import 'dart:convert';
import 'dart:io';

import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // apps/mobile/release/get-off-alarm-policy.json의 JSON 계약이 단일 진실
  // 원본이다(node 리포 계약 테스트에서도 검증). 이 테스트는 Dart 상수를 그
  // JSON에 고정해 둘이 서로 어긋나지 않게 한다.
  test('Dart policy defaults stay in sync with the release policy JSON', () {
    final json =
        jsonDecode(File('release/get-off-alarm-policy.json').readAsStringSync())
            as Map<String, dynamic>;
    final leadTime = json['leadTime'] as Map<String, dynamic>;
    final exactAlarm = json['exactAlarm'] as Map<String, dynamic>;
    final activeAlarm = json['activeAlarm'] as Map<String, dynamic>;

    expect(
      GetOffAlarmPolicyDefaults.leadSeconds,
      leadTime['defaultLeadSeconds'],
    );
    expect(
      GetOffAlarmPolicyDefaults.transferLeadSeconds,
      leadTime['transferLeadSeconds'],
    );
    expect(
      GetOffAlarmPolicyDefaults.transferAlarmEnabled,
      leadTime['transferAlarmDefaultOn'],
    );
    expect(
      GetOffAlarmPolicyDefaults.maxConcurrentRoutes,
      activeAlarm['maxConcurrentRoutes'],
    );
    expect(
      GetOffAlarmPolicyDefaults.inexactNoticeKo,
      exactAlarm['inexactNoticeKo'],
    );
  });

  test('default policy exposes the JSON lead times as Durations', () {
    expect(
      GetOffAlarmPolicyDefaults.policy.destinationLead,
      const Duration(seconds: GetOffAlarmPolicyDefaults.leadSeconds),
    );
    expect(GetOffAlarmPolicyDefaults.policy.transferAlarmEnabled, isTrue);
  });
}
