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
