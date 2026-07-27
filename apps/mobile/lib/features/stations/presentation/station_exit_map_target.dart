import '../../../core/external/kakao_map_launcher.dart';
import '../domain/station_models.dart';

final class StationExitMapTarget {
  const StationExitMapTarget({
    required this.target,
    required this.usesStationFallback,
  });

  final KakaoMapTarget target;
  final bool usesStationFallback;
}

StationExitMapTarget? stationExitMapTarget({
  required StationDetail station,
  required StationExitInfo exit,
}) {
  final exitLatitude = exit.latitude;
  final exitLongitude = exit.longitude;
  if (exitLatitude != null && exitLongitude != null) {
    return StationExitMapTarget(
      target: KakaoMapTarget(
        label: '${station.nameKo}역 ${exit.name}',
        latitude: exitLatitude,
        longitude: exitLongitude,
      ),
      usesStationFallback: false,
    );
  }

  final stationLatitude = station.latitude;
  final stationLongitude = station.longitude;
  if (stationLatitude == null || stationLongitude == null) {
    return null;
  }
  return StationExitMapTarget(
    target: KakaoMapTarget(
      label: '${station.nameKo}역',
      latitude: stationLatitude,
      longitude: stationLongitude,
    ),
    usesStationFallback: true,
  );
}
