/// 길찾기 draft에서 채우려는 칸(출발/도착). 지도 탭·텍스트 검색 어느 경로든
/// 같은 칸을 지정해 동일한 [RouteDraft] 상태로 수렴시키기 위해 쓴다.
enum RouteDraftSlot { origin, destination, waypoint }

class RouteDraftStation {
  const RouteDraftStation({required this.id, required this.nameKo});

  final String id;
  final String nameKo;

  String get displayName {
    final trimmedName = nameKo.trim();
    if (trimmedName.endsWith('역')) {
      return trimmedName;
    }
    return '$trimmedName역';
  }
}

class RouteDraft {
  const RouteDraft({
    required this.origin,
    required this.destination,
    required this.lastModifiedAt,
    this.waypoint,
    this.invalidatedReason,
  });

  const RouteDraft.empty()
    : origin = null,
      destination = null,
      waypoint = null,
      lastModifiedAt = null,
      invalidatedReason = null;

  final RouteDraftStation? origin;
  final RouteDraftStation? destination;
  final RouteDraftStation? waypoint;
  final DateTime? lastModifiedAt;
  final String? invalidatedReason;

  bool get isEmpty =>
      origin == null && destination == null && waypoint == null;

  String get originLabel {
    final station = origin;
    return station == null ? '출발 미정' : '출발 ${station.displayName}';
  }

  String get destinationLabel {
    final station = destination;
    return station == null ? '도착 미정' : '도착 ${station.displayName}';
  }

  String get waypointLabel {
    final station = waypoint;
    return station == null ? '경유 미정' : '경유 ${station.displayName}';
  }
}

/// #1991: 슬롯 표시 라벨('출발역'/'경유역'/'도착역') 단일 출처.
/// exhaustive switch라 슬롯 추가 시 컴파일 에러로 누락을 잡는다.
extension RouteDraftSlotLabel on RouteDraftSlot {
  String get displayLabel => switch (this) {
    RouteDraftSlot.origin => '출발역',
    RouteDraftSlot.waypoint => '경유역',
    RouteDraftSlot.destination => '도착역',
  };
}
