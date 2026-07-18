enum RouteShareObjective { fastest, fewestTransfers }

enum RouteShareTransportScope { subway, subwayAndItxCheongchun }

enum RouteShareFreshness { realtime, planned, staticData }

class RouteShareFare {
  const RouteShareFare({required this.adultFareWon, required this.currency});

  final int adultFareWon;
  final String currency;
}

class RouteShareLeg {
  const RouteShareLeg({
    required this.description,
    required this.departureTime,
    required this.arrivalTime,
  });

  final String description;
  final String departureTime;
  final String arrivalTime;
}

class RouteShareSnapshot {
  const RouteShareSnapshot({
    required this.languageCode,
    required this.originName,
    required this.destinationName,
    required this.objective,
    required this.transportScope,
    required this.departureTime,
    required this.arrivalTime,
    required this.durationMinutes,
    required this.transferCount,
    required this.freshness,
    required this.legs,
    this.fare,
  });

  final String languageCode;
  final String originName;
  final String destinationName;
  final RouteShareObjective objective;
  final RouteShareTransportScope transportScope;
  final String departureTime;
  final String arrivalTime;
  final int durationMinutes;
  final int transferCount;
  final RouteShareFreshness freshness;
  final List<RouteShareLeg> legs;
  final RouteShareFare? fare;
}

String buildRouteShareSummary(
  RouteShareSnapshot snapshot, {
  int maxLength = 1200,
}) {
  _validate(snapshot, maxLength);
  final full = _compose(
    snapshot,
    List<int>.generate(snapshot.legs.length, (i) => i),
  );
  if (full.length <= maxLength) {
    return full;
  }

  final selected = <int>[];
  final priority = <int>[
    0,
    if (snapshot.legs.length > 1) snapshot.legs.length - 1,
    for (var i = 1; i < snapshot.legs.length - 1; i++) i,
  ];
  for (final index in priority) {
    final candidate = [...selected, index]..sort();
    if (_compose(snapshot, candidate).length <= maxLength) {
      selected
        ..clear()
        ..addAll(candidate);
    }
  }
  final shortened = _compose(snapshot, selected);
  if (shortened.length > maxLength) {
    throw StateError(
      'Route share length budget is too small for essential facts',
    );
  }
  return shortened;
}

void _validate(RouteShareSnapshot snapshot, int maxLength) {
  if (snapshot.languageCode != 'ko' && snapshot.languageCode != 'en') {
    throw StateError('Unsupported route share language');
  }
  if (snapshot.originName.trim().isEmpty ||
      snapshot.destinationName.trim().isEmpty ||
      snapshot.departureTime.trim().isEmpty ||
      snapshot.arrivalTime.trim().isEmpty ||
      snapshot.durationMinutes <= 0 ||
      snapshot.transferCount < 0 ||
      snapshot.legs.isEmpty ||
      maxLength <= 0) {
    throw StateError('Route share snapshot is incomplete');
  }
  if (snapshot.legs.any(
    (leg) =>
        leg.description.trim().isEmpty ||
        (leg.departureTime.isEmpty != leg.arrivalTime.isEmpty),
  )) {
    throw StateError('Route share leg is incomplete');
  }
  final fare = snapshot.fare;
  if (fare != null && (fare.adultFareWon <= 0 || fare.currency != 'KRW')) {
    throw StateError('Route share fare is invalid');
  }
}

String _compose(RouteShareSnapshot snapshot, List<int> selectedIndexes) {
  final ko = snapshot.languageCode == 'ko';
  final lines = <String>[
    '${snapshot.originName.trim()} → ${snapshot.destinationName.trim()}',
    ko
        ? '기준: ${_objective(snapshot.objective, ko)}'
        : 'Objective: ${_objective(snapshot.objective, ko)}',
    ko
        ? '교통수단: ${_scope(snapshot.transportScope, ko)}'
        : 'Transport: ${_scope(snapshot.transportScope, ko)}',
    ko
        ? '시간: ${snapshot.departureTime} → ${snapshot.arrivalTime}'
        : 'Time: ${snapshot.departureTime} → ${snapshot.arrivalTime}',
    ko
        ? '총 ${snapshot.durationMinutes}분 · 환승 ${snapshot.transferCount}회'
        : '${snapshot.durationMinutes} min · ${snapshot.transferCount} transfer${snapshot.transferCount == 1 ? '' : 's'}',
    if (snapshot.fare case final fare?)
      ko
          ? '공식 운임: 성인 ${_number(fare.adultFareWon)}원'
          : 'Official fare: Adult ${fare.currency} ${_number(fare.adultFareWon)}',
    ko
        ? '안내: ${_freshness(snapshot.freshness, ko)}'
        : 'Notice: ${_freshness(snapshot.freshness, ko)}',
  ];
  final selected = selectedIndexes.toSet();
  lines.add(ko ? '주요 경로:' : 'Main route:');
  for (var i = 0; i < snapshot.legs.length; i++) {
    if (selected.contains(i)) {
      final leg = snapshot.legs[i];
      final times = leg.departureTime.isEmpty
          ? ''
          : ' (${leg.departureTime} → ${leg.arrivalTime})';
      lines.add('- ${leg.description.trim()}$times');
    }
  }
  final omitted = snapshot.legs.length - selected.length;
  if (omitted > 0) {
    lines.add(
      ko
          ? '… 중간 경로 $omitted개 생략'
          : '… $omitted intermediate leg${omitted == 1 ? '' : 's'} omitted',
    );
  }
  return lines.join('\n');
}

String _objective(RouteShareObjective objective, bool ko) =>
    switch (objective) {
      RouteShareObjective.fastest => ko ? '최단시간' : 'Fastest',
      RouteShareObjective.fewestTransfers => ko ? '최소환승' : 'Fewest transfers',
    };

String _scope(RouteShareTransportScope scope, bool ko) => switch (scope) {
  RouteShareTransportScope.subway => ko ? '지하철' : 'Subway',
  RouteShareTransportScope.subwayAndItxCheongchun =>
    ko ? '지하철 + ITX-청춘' : 'Subway + ITX-Cheongchun',
};

String _freshness(RouteShareFreshness freshness, bool ko) =>
    switch (freshness) {
      RouteShareFreshness.realtime =>
        ko ? '실시간 정보 기준입니다.' : 'Based on realtime information.',
      RouteShareFreshness.planned =>
        ko
            ? '계획 시간 기준이며 실제 운행과 다를 수 있습니다.'
            : 'Planned schedule; actual service may differ.',
      RouteShareFreshness.staticData =>
        ko
            ? '저장된 데이터 기준이며 실제 운행과 다를 수 있습니다.'
            : 'Saved data; actual service may differ.',
    };

String _number(int value) {
  final digits = value.toString();
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) {
      out.write(',');
    }
    out.write(digits[i]);
  }
  return out.toString();
}
