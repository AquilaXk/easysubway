import 'get_off_alarm_scheduler.dart';

enum GetOffAlarmTimeSource { planned, realtime }

/// 경로 결과의 승차(RIDE) leg 하나를 하차 알림 관점으로 투영한 값.
///
/// route_search의 무거운 leg 모델에 결합하지 않도록, UI 어댑터가 RIDE leg를
/// 도착역·도착 시각(계획/실시간)으로만 추려서 넘긴다.
class RideLegArrival {
  const RideLegArrival({
    required this.toStationId,
    required this.plannedArrivalIso,
    this.realtimeArrivalIso,
  });

  final String toStationId;
  final String plannedArrivalIso;
  final String? realtimeArrivalIso;
}

/// 순서대로 정렬된 승차 leg들을 하차 알림 정차역으로 매핑한다.
///
/// 마지막 승차 leg의 도착역이 최종 목적지, 그 앞의 승차 leg들은 환승역이다.
/// 도착 시각은 실시간 값이 있으면 우선하고(비어 있으면 계획 값으로 강등),
/// ISO 문자열을 로컬 시각으로 파싱한다.
List<GetOffAlarmStop> getOffAlarmStopsFromRideLegs({
  required List<RideLegArrival> rideLegs,
  required String Function(String stationId) stationName,
  required GetOffAlarmTimeSource source,
}) {
  final stops = <GetOffAlarmStop>[];
  for (var index = 0; index < rideLegs.length; index++) {
    final leg = rideLegs[index];
    final isDestination = index == rideLegs.length - 1;
    final arrivalIso =
        (source == GetOffAlarmTimeSource.realtime &&
            leg.realtimeArrivalIso != null &&
            leg.realtimeArrivalIso!.isNotEmpty)
        ? leg.realtimeArrivalIso!
        : leg.plannedArrivalIso;
    stops.add(
      GetOffAlarmStop(
        stationId: leg.toStationId,
        stationName: stationName(leg.toStationId),
        arrivalAt: DateTime.parse(arrivalIso).toLocal(),
        kind: isDestination
            ? GetOffAlarmKind.destination
            : GetOffAlarmKind.transfer,
      ),
    );
  }
  return stops;
}
