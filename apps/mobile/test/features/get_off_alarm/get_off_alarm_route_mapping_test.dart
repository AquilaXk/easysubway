import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_route_mapping.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String upper(String id) => id.toUpperCase();

  group('getOffAlarmStopsFromRideLegs', () {
    test('단일 승차 leg는 목적지 하나로 매핑되고 도착 시각을 파싱한다', () {
      final stops = getOffAlarmStopsFromRideLegs(
        rideLegs: const [
          RideLegArrival(
            toStationId: 'sadang',
            plannedArrivalIso: '2026-07-06T09:30:00',
          ),
        ],
        stationName: (id) => id == 'sadang' ? '사당' : id,
      );

      expect(stops, hasLength(1));
      expect(stops.single.kind, GetOffAlarmKind.destination);
      expect(stops.single.stationId, 'sadang');
      expect(stops.single.stationName, '사당');
      expect(stops.single.arrivalAt, DateTime.parse('2026-07-06T09:30:00'));
    });

    test('마지막 승차 leg는 목적지, 그 앞 승차 leg들은 환승', () {
      final stops = getOffAlarmStopsFromRideLegs(
        rideLegs: const [
          RideLegArrival(
            toStationId: 'dongjak',
            plannedArrivalIso: '2026-07-06T09:15:00',
          ),
          RideLegArrival(
            toStationId: 'sadang',
            plannedArrivalIso: '2026-07-06T09:30:00',
          ),
        ],
        stationName: upper,
      );

      expect(stops.map((s) => s.kind), [
        GetOffAlarmKind.transfer,
        GetOffAlarmKind.destination,
      ]);
      expect(stops.map((s) => s.stationName), ['DONGJAK', 'SADANG']);
    });

    test('실시간 도착 시각이 있으면 계획 시각보다 우선한다', () {
      final stops = getOffAlarmStopsFromRideLegs(
        rideLegs: const [
          RideLegArrival(
            toStationId: 'x',
            plannedArrivalIso: '2026-07-06T09:30:00',
            realtimeArrivalIso: '2026-07-06T09:33:00',
          ),
        ],
        stationName: (id) => id,
      );

      expect(stops.single.arrivalAt, DateTime.parse('2026-07-06T09:33:00'));
    });

    test('실시간 도착 시각이 빈 문자열이면 계획 시각으로 강등한다', () {
      final stops = getOffAlarmStopsFromRideLegs(
        rideLegs: const [
          RideLegArrival(
            toStationId: 'x',
            plannedArrivalIso: '2026-07-06T09:30:00',
            realtimeArrivalIso: '',
          ),
        ],
        stationName: (id) => id,
      );

      expect(stops.single.arrivalAt, DateTime.parse('2026-07-06T09:30:00'));
    });
  });
}
