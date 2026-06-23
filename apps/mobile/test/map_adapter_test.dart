import 'package:easysubway_mobile/map_adapter.dart';
import 'package:easysubway_mobile/station_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('지도 기능 계약은 노선도와 주변 지도를 분리하고 목록 대체를 필수로 둔다', () {
    expect(mapCapabilityContracts.map((contract) => contract.type), [
      MapCapabilityType.offlineLineMap,
      MapCapabilityType.nearbyGeographicMap,
    ]);

    expect(offlineLineMapContract.title, '오프라인 노선도');
    expect(offlineLineMapContract.needsCurrentLocation, isFalse);
    expect(offlineLineMapContract.canUseExternalMapProvider, isFalse);
    expect(offlineLineMapContract.requiresSdkKeyForTests, isFalse);
    expect(offlineLineMapContract.requiresListEquivalent, isTrue);
    expect(offlineLineMapContract.allowsMapOnlyCriticalGestures, isFalse);
    expect(offlineLineMapContract.listEquivalentLabel, '노선과 역 목록');

    expect(nearbyGeographicMapContract.title, '내 주변 지도');
    expect(nearbyGeographicMapContract.needsCurrentLocation, isTrue);
    expect(nearbyGeographicMapContract.canUseExternalMapProvider, isTrue);
    expect(nearbyGeographicMapContract.requiresSdkKeyForTests, isFalse);
    expect(nearbyGeographicMapContract.requiresListEquivalent, isTrue);
    expect(nearbyGeographicMapContract.allowsMapOnlyCriticalGestures, isFalse);
    expect(nearbyGeographicMapContract.listEquivalentLabel, '주변 역과 시설 목록');
  });

  test('지도 제공자는 네이버를 기본값으로 두고 카카오를 대체 후보로 둔다', () {
    const configuration = MapProviderConfiguration.defaults();

    expect(configuration.primary, MapProviderType.naver);
    expect(configuration.fallbacks, [MapProviderType.kakao]);
    expect(MapProviderType.naver.displayName, '네이버 지도');
    expect(MapProviderType.kakao.displayName, '카카오 지도');
  });

  test('지도 어댑터는 좌표가 있는 역 출구 시설만 쉬운 이름의 마커로 만든다', () {
    const adapter = EasySubwayMapAdapter();
    final markers = adapter.markersForStationDetail(
      station: const StationDetail(
        id: 'station-sangnoksu',
        nameKo: '상록수',
        nameEn: 'Sangnoksu',
        region: '수도권',
        latitude: 37.302795,
        longitude: 126.866489,
        dataQualityLevel: 'LEVEL_2',
        lastVerifiedAt: '2026-06-12',
        lines: [
          StationSearchLine(
            id: 'seoul-4',
            name: '수도권 4호선',
            color: '#00A5DE',
            stationCode: '448',
          ),
        ],
      ),
      exits: const [
        StationExitInfo(
          id: 'exit-sangnoksu-1',
          stationId: 'station-sangnoksu',
          exitNumber: '1',
          name: '1번 출구',
          latitude: 37.3021,
          longitude: 126.8661,
          hasElevatorConnection: true,
          hasStairOnlyPath: false,
          dataConfidence: 'HIGH',
        ),
        StationExitInfo(
          id: 'exit-sangnoksu-2',
          stationId: 'station-sangnoksu',
          exitNumber: '2',
          name: '2번 출구',
          hasElevatorConnection: false,
          hasStairOnlyPath: true,
          dataConfidence: 'LOW',
        ),
      ],
      facilities: const [
        StationFacilityInfo(
          id: 'facility-elevator-1',
          stationId: 'station-sangnoksu',
          exitId: 'exit-sangnoksu-1',
          type: 'ELEVATOR',
          name: '1번 출구 엘리베이터',
          floorFrom: 'B1',
          floorTo: '1F',
          latitude: 37.3022,
          longitude: 126.8662,
          description: '1번 출구 앞',
          status: 'NORMAL',
          dataConfidence: 'HIGH',
          lastUpdatedAt: '2026-06-12',
        ),
      ],
    );

    expect(markers.map((marker) => marker.id), [
      'station-sangnoksu',
      'exit-sangnoksu-1',
      'facility-elevator-1',
    ]);
    expect(markers[0].title, '상록수역');
    expect(markers[0].semanticLabel, contains('상록수역 상세 정보'));
    expect(markers[0].semanticLabel, contains('마지막 확인 2026-06-12'));
    expect(markers[1].semanticLabel, contains('1번 출구'));
    expect(markers[1].semanticLabel, contains('계단 없는 이동 가능'));
    expect(markers[1].semanticLabel, contains('정보 신뢰도 높음'));
    expect(markers[2].semanticLabel, contains('엘리베이터'));
    expect(markers[2].semanticLabel, contains('정상'));
    expect(markers[2].semanticLabel, contains('최근 확인 2026-06-12'));
    expect(markers[2].semanticLabel, contains('정보 신뢰도 높음'));
  });
}
