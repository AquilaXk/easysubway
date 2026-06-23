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
    this.invalidatedReason,
  });

  const RouteDraft.empty()
    : origin = null,
      destination = null,
      lastModifiedAt = null,
      invalidatedReason = null;

  final RouteDraftStation? origin;
  final RouteDraftStation? destination;
  final DateTime? lastModifiedAt;
  final String? invalidatedReason;

  bool get isEmpty => origin == null && destination == null;

  String get originLabel {
    final station = origin;
    return station == null ? '출발 미정' : '출발 ${station.displayName}';
  }

  String get destinationLabel {
    final station = destination;
    return station == null ? '도착 미정' : '도착 ${station.displayName}';
  }
}
