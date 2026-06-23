import 'station_search.dart';

enum MapCapabilityType { offlineLineMap, nearbyGeographicMap }

class MapCapabilityContract {
  const MapCapabilityContract({
    required this.type,
    required this.title,
    required this.listEquivalentLabel,
    required this.needsCurrentLocation,
    required this.canUseExternalMapProvider,
    required this.requiresSdkKeyForTests,
    required this.requiresListEquivalent,
    required this.allowsMapOnlyCriticalGestures,
  });

  final MapCapabilityType type;
  final String title;
  final String listEquivalentLabel;
  final bool needsCurrentLocation;
  final bool canUseExternalMapProvider;
  final bool requiresSdkKeyForTests;
  final bool requiresListEquivalent;
  final bool allowsMapOnlyCriticalGestures;
}

const offlineLineMapContract = MapCapabilityContract(
  type: MapCapabilityType.offlineLineMap,
  title: '오프라인 노선도',
  listEquivalentLabel: '노선과 역 목록',
  needsCurrentLocation: false,
  canUseExternalMapProvider: false,
  requiresSdkKeyForTests: false,
  requiresListEquivalent: true,
  allowsMapOnlyCriticalGestures: false,
);

const nearbyGeographicMapContract = MapCapabilityContract(
  type: MapCapabilityType.nearbyGeographicMap,
  title: '내 주변 지도',
  listEquivalentLabel: '주변 역과 시설 목록',
  needsCurrentLocation: true,
  canUseExternalMapProvider: true,
  requiresSdkKeyForTests: false,
  requiresListEquivalent: true,
  allowsMapOnlyCriticalGestures: false,
);

const mapCapabilityContracts = [
  offlineLineMapContract,
  nearbyGeographicMapContract,
];

enum MapProviderType {
  naver,
  kakao;

  String get displayName {
    return switch (this) {
      MapProviderType.naver => '네이버 지도',
      MapProviderType.kakao => '카카오 지도',
    };
  }
}

class MapProviderConfiguration {
  const MapProviderConfiguration({
    required this.primary,
    required this.fallbacks,
  });

  const MapProviderConfiguration.defaults()
    : primary = MapProviderType.naver,
      fallbacks = const [MapProviderType.kakao];

  final MapProviderType primary;
  final List<MapProviderType> fallbacks;
}

enum MapMarkerType { station, exit, facility }

class MapCoordinate {
  const MapCoordinate({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;
}

class MapMarker {
  const MapMarker({
    required this.id,
    required this.type,
    required this.title,
    required this.coordinate,
    required this.semanticLabel,
  });

  final String id;
  final MapMarkerType type;
  final String title;
  final MapCoordinate coordinate;
  final String semanticLabel;
}

abstract interface class MapAdapter {
  MapProviderType get providerType;

  List<MapMarker> markersForStationDetail({
    required StationDetail station,
    required List<StationExitInfo> exits,
    required List<StationFacilityInfo> facilities,
  });
}

class EasySubwayMapAdapter implements MapAdapter {
  const EasySubwayMapAdapter({this.providerType = MapProviderType.naver});

  @override
  final MapProviderType providerType;

  @override
  List<MapMarker> markersForStationDetail({
    required StationDetail station,
    required List<StationExitInfo> exits,
    required List<StationFacilityInfo> facilities,
  }) {
    return [
      if (_coordinateFrom(station.latitude, station.longitude)
          case final coordinate?)
        MapMarker(
          id: station.id,
          type: MapMarkerType.station,
          title: '${station.nameKo}역',
          coordinate: coordinate,
          semanticLabel: '${station.semanticLabel}, 지도 위치',
        ),
      for (final exit in exits)
        if (_coordinateFrom(exit.latitude, exit.longitude)
            case final coordinate?)
          MapMarker(
            id: exit.id,
            type: MapMarkerType.exit,
            title: exit.name,
            coordinate: coordinate,
            // 지도 SDK marker 접근성 문구는 화면 문구보다 더 직접적으로 이동 판단 정보를 담는다.
            semanticLabel: '${exit.semanticLabel}, 지도 위치',
          ),
      for (final facility in facilities)
        if (_coordinateFrom(facility.latitude, facility.longitude)
            case final coordinate?)
          MapMarker(
            id: facility.id,
            type: MapMarkerType.facility,
            title: facility.name,
            coordinate: coordinate,
            semanticLabel: '${facility.semanticLabel}, 지도 위치',
          ),
    ];
  }

  MapCoordinate? _coordinateFrom(double? latitude, double? longitude) {
    if (latitude == null || longitude == null) {
      return null;
    }
    return MapCoordinate(latitude: latitude, longitude: longitude);
  }
}
