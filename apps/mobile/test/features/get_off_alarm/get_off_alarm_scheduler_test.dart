import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const policy = GetOffAlarmPolicy(
    destinationLead: Duration(seconds: 120),
    transferLead: Duration(seconds: 120),
    transferAlarmEnabled: true,
  );

  GetOffAlarmStop stop(
    String id,
    DateTime arrival, {
    GetOffAlarmKind kind = GetOffAlarmKind.destination,
  }) {
    return GetOffAlarmStop(
      stationId: id,
      stationName: id,
      arrivalAt: arrival,
      kind: kind,
    );
  }

  group('computeGetOffAlarms', () {
    test('schedules destination alarm the lead time before arrival', () {
      final now = DateTime(2026, 7, 6, 9, 0, 0);
      final arrival = DateTime(2026, 7, 6, 9, 30, 0);

      final alarms = computeGetOffAlarms(
        stops: [stop('dest', arrival)],
        policy: policy,
        now: now,
      );

      expect(alarms, hasLength(1));
      expect(alarms.single.kind, GetOffAlarmKind.destination);
      expect(alarms.single.fireAt, DateTime(2026, 7, 6, 9, 28, 0));
      expect(alarms.single.arrivalAt, arrival);
    });

    test('includes transfer alarms when transfer alarm is enabled', () {
      final now = DateTime(2026, 7, 6, 9, 0, 0);
      final alarms = computeGetOffAlarms(
        stops: [
          stop(
            'transfer',
            DateTime(2026, 7, 6, 9, 15, 0),
            kind: GetOffAlarmKind.transfer,
          ),
          stop('dest', DateTime(2026, 7, 6, 9, 30, 0)),
        ],
        policy: policy,
        now: now,
      );

      expect(alarms.map((a) => a.kind), [
        GetOffAlarmKind.transfer,
        GetOffAlarmKind.destination,
      ]);
    });

    test('drops transfer alarms when transfer alarm is disabled', () {
      final now = DateTime(2026, 7, 6, 9, 0, 0);
      final alarms = computeGetOffAlarms(
        stops: [
          stop(
            'transfer',
            DateTime(2026, 7, 6, 9, 15, 0),
            kind: GetOffAlarmKind.transfer,
          ),
          stop('dest', DateTime(2026, 7, 6, 9, 30, 0)),
        ],
        policy: policy.copyWith(transferAlarmEnabled: false),
        now: now,
      );

      expect(alarms.map((a) => a.kind), [GetOffAlarmKind.destination]);
    });

    test('drops alarms whose fire time is already in the past', () {
      // 도착이 1분 뒤인데 리드타임은 2분 -> 발화 시각이 과거가 되어
      // 예약할 수 없으므로 제외되어야 한다.
      final now = DateTime(2026, 7, 6, 9, 0, 0);
      final alarms = computeGetOffAlarms(
        stops: [stop('dest', DateTime(2026, 7, 6, 9, 1, 0))],
        policy: policy,
        now: now,
      );

      expect(alarms, isEmpty);
    });

    test('returns alarms sorted ascending by fire time', () {
      final now = DateTime(2026, 7, 6, 9, 0, 0);
      final alarms = computeGetOffAlarms(
        stops: [
          stop('dest', DateTime(2026, 7, 6, 9, 40, 0)),
          stop(
            'transfer',
            DateTime(2026, 7, 6, 9, 20, 0),
            kind: GetOffAlarmKind.transfer,
          ),
        ],
        policy: policy,
        now: now,
      );

      final fireTimes = alarms.map((a) => a.fireAt).toList();
      expect(fireTimes, [
        DateTime(2026, 7, 6, 9, 18, 0),
        DateTime(2026, 7, 6, 9, 38, 0),
      ]);
    });

    test('handles arrival crossing the midnight boundary', () {
      final now = DateTime(2026, 7, 6, 23, 55, 0);
      final arrival = DateTime(2026, 7, 7, 0, 3, 0);

      final alarms = computeGetOffAlarms(
        stops: [stop('dest', arrival)],
        policy: policy,
        now: now,
      );

      expect(alarms.single.fireAt, DateTime(2026, 7, 7, 0, 1, 0));
    });

    test('모든 정차역이 미래면 slot은 입력 순서와 같다', () {
      final now = DateTime(2026, 7, 6, 9, 0, 0);
      final alarms = computeGetOffAlarms(
        stops: [
          stop(
            'transfer',
            DateTime(2026, 7, 6, 9, 15, 0),
            kind: GetOffAlarmKind.transfer,
          ),
          stop('dest', DateTime(2026, 7, 6, 9, 30, 0)),
        ],
        policy: policy,
        now: now,
      );

      expect(alarms.map((a) => a.slot), [0, 1]);
    });

    test('만료된 앞 정차역이 빠져도 남은 정차역 slot은 원본 위치로 고정된다', () {
      // transfer fireAt=9:13, destination fireAt=9:28. now=9:20이면 transfer만
      // 만료되어 결과에서 빠지지만, destination의 slot은 앞으로 당겨지지 않고
      // 입력 위치(1)를 유지해야 재부팅 재예약 ID가 어긋나지 않는다.
      final now = DateTime(2026, 7, 6, 9, 20, 0);
      final alarms = computeGetOffAlarms(
        stops: [
          stop(
            'transfer',
            DateTime(2026, 7, 6, 9, 15, 0),
            kind: GetOffAlarmKind.transfer,
          ),
          stop('dest', DateTime(2026, 7, 6, 9, 30, 0)),
        ],
        policy: policy,
        now: now,
      );

      expect(alarms, hasLength(1));
      expect(alarms.single.kind, GetOffAlarmKind.destination);
      expect(alarms.single.slot, 1);
    });
  });
}
