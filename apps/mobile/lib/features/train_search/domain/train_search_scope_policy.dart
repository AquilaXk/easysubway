enum TrainSearchTrainType {
  ktx('KTX'),
  ktxSancheon('KTX_SANCHEON'),
  srt('SRT'),
  itxMaum('ITX_MAUM'),
  itxSaemaeul('ITX_SAEMAEUL'),
  saemaeul('SAEMAEUL'),
  mugunghwa('MUGUNGHWA'),
  nuriro('NURIRO');

  const TrainSearchTrainType(this.apiValue);

  final String apiValue;

  static TrainSearchTrainType? parse(String value) {
    final normalized = value.trim().toUpperCase();
    for (final trainType in values) {
      if (trainType.apiValue == normalized) return trainType;
    }
    return null;
  }
}

abstract final class TrainSearchScopePolicy {
  static List<T> retainSupported<T>(
    Iterable<T> rows,
    String Function(T row) trainType,
  ) => rows
      .where((row) => TrainSearchTrainType.parse(trainType(row)) != null)
      .toList(growable: false);
}

extension TrainSearchTrainTypeLabel on TrainSearchTrainType {
  String get labelKo => switch (this) {
    TrainSearchTrainType.ktx => 'KTX',
    TrainSearchTrainType.ktxSancheon => 'KTX-산천',
    TrainSearchTrainType.srt => 'SRT',
    TrainSearchTrainType.itxMaum => 'ITX-마음',
    TrainSearchTrainType.itxSaemaeul => 'ITX-새마을',
    TrainSearchTrainType.saemaeul => '새마을호',
    TrainSearchTrainType.mugunghwa => '무궁화호',
    TrainSearchTrainType.nuriro => '누리로',
  };
}
