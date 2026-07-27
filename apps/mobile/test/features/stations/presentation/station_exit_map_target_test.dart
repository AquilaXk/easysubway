import 'package:easysubway_mobile/features/stations/domain/station_models.dart';
import 'package:easysubway_mobile/features/stations/presentation/station_exit_map_target.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('출구 좌표가 있으면 출구 위치를 사용한다', () {
    final target = stationExitMapTarget(
      station: _station(),
      exit: _exit(latitude: 37.301, longitude: 126.861),
    );

    expect(target, isNotNull);
    expect(target!.target.label, '상록수역 1번 출구');
    expect(target.target.latitude, 37.301);
    expect(target.target.longitude, 126.861);
    expect(target.usesStationFallback, isFalse);
  });

  test('출구 좌표 쌍이 없으면 역 위치를 사용한다', () {
    final target = stationExitMapTarget(
      station: _station(),
      exit: _exit(latitude: 37.301),
    );

    expect(target, isNotNull);
    expect(target!.target.label, '상록수역');
    expect(target.target.latitude, 37.302795);
    expect(target.target.longitude, 126.866489);
    expect(target.usesStationFallback, isTrue);
  });

  test('출구와 역 모두 완전한 좌표 쌍이 없으면 목적지가 없다', () {
    final target = stationExitMapTarget(
      station: _station(longitude: null),
      exit: _exit(),
    );

    expect(target, isNull);
  });
}

StationDetail _station({double? longitude = 126.866489}) {
  return StationDetail(
    id: 'station-sangnoksu',
    nameKo: '상록수',
    nameEn: 'Sangnoksu',
    region: '수도권',
    latitude: 37.302795,
    longitude: longitude,
    dataQualityLevel: 'LEVEL_2',
    lastVerifiedAt: '2026-07-28',
    lines: const [],
  );
}

StationExitInfo _exit({double? latitude, double? longitude}) {
  return StationExitInfo(
    id: 'exit-sangnoksu-1',
    stationId: 'station-sangnoksu',
    exitNumber: '1',
    name: '1번 출구',
    latitude: latitude,
    longitude: longitude,
    hasElevatorConnection: true,
    hasStairOnlyPath: false,
    dataConfidence: 'HIGH',
  );
}
