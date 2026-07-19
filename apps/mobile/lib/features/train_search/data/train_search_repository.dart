import '../../../core/network/api_client.dart';
import '../domain/train_search_models.dart';
import '../domain/train_search_scope_policy.dart';

class ApiTrainSearchRepository implements TrainSearchRepository {
  const ApiTrainSearchRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<List<TrainStation>> stations(
    String query, {
    TrainSearchTrainType? type,
  }) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.runes.length < 2) {
      throw const TrainSearchException(
        TrainSearchFailureKind.invalidArgument,
        '역 이름을 두 글자 이상 입력해 주세요.',
      );
    }
    final parameters = <String, String>{'query': normalizedQuery};
    if (type != null) parameters['trainType'] = type.apiValue;

    try {
      final response = await _apiClient.getJson(
        Uri(
          path: '/api/v1/trains/stations',
          queryParameters: parameters,
        ).toString(),
      );
      final data = _requireSuccessData(response);
      if (data is! List<Object?>) throw const FormatException();
      return List.unmodifiable(data.map(_parseStation));
    } on ApiException {
      throw const TrainSearchException(
        TrainSearchFailureKind.network,
        '인터넷 연결을 확인한 뒤 다시 시도해 주세요.',
      );
    } on TrainSearchException {
      rethrow;
    } on Object {
      throw const TrainSearchException(
        TrainSearchFailureKind.invalidResponse,
        '기차역 정보를 확인하지 못했습니다.',
      );
    }
  }

  @override
  Future<TrainSearchResult> search(TrainSearchCriteria criteria) async {
    _validateCriteria(criteria);
    final parameters = <String, String>{
      'departureStationId': criteria.departure.id,
      'arrivalStationId': criteria.arrival.id,
      'departureDate': _formatDate(criteria.departureDate),
    };
    if (criteria.returnDate case final DateTime returnDate) {
      parameters['returnDate'] = _formatDate(returnDate);
    }
    if (criteria.trainType case final TrainSearchTrainType trainType) {
      parameters['trainType'] = trainType.apiValue;
    }

    try {
      final response = await _apiClient.getJson(
        Uri(
          path: '/api/v1/trains/search',
          queryParameters: parameters,
        ).toString(),
      );
      final data = _requireSuccessData(response);
      return _parseResult(data);
    } on ApiException {
      throw const TrainSearchException(
        TrainSearchFailureKind.network,
        '인터넷 연결을 확인한 뒤 다시 시도해 주세요.',
      );
    } on TrainSearchException {
      rethrow;
    } on Object {
      throw const TrainSearchException(
        TrainSearchFailureKind.invalidResponse,
        '기차 시간표 응답을 확인하지 못했습니다.',
      );
    }
  }

  Object? _requireSuccessData(ApiResponse response) {
    if (!response.isOk) throw _responseFailure(response);
    final body = response.jsonBody;
    if (body is! Map<String, Object?> ||
        !_hasOnlyKeys(body, const {'success', 'data'}) ||
        body['success'] != true) {
      throw const FormatException();
    }
    return body['data'];
  }

  TrainSearchException _responseFailure(ApiResponse response) {
    final body = response.jsonBody;
    final data = body is Map<String, Object?> ? body['data'] : null;
    final code = data is Map<String, Object?> ? data['code'] : null;
    return switch (code) {
      'TRAIN_SEARCH_UNSUPPORTED_TRAIN_TYPE' => const TrainSearchException(
        TrainSearchFailureKind.unsupportedTrainType,
        '지원하지 않는 열차종입니다.',
      ),
      'TRAIN_SEARCH_INVALID_ARGUMENT' => const TrainSearchException(
        TrainSearchFailureKind.invalidArgument,
        '검색 조건을 확인해 주세요.',
      ),
      'TRAIN_SEARCH_RATE_LIMITED' => const TrainSearchException(
        TrainSearchFailureKind.rateLimited,
        '요청이 많습니다. 잠시 후 다시 시도해 주세요.',
      ),
      'TRAIN_SEARCH_PROVIDER_ERROR' => const TrainSearchException(
        TrainSearchFailureKind.providerError,
        '기차 정보 제공기관 응답을 처리하지 못했습니다.',
      ),
      'TRAIN_SEARCH_NO_VALID_ROWS' => const TrainSearchException(
        TrainSearchFailureKind.noValidRows,
        '유효한 열차 시간표를 확인하지 못했습니다.',
      ),
      'TRAIN_SEARCH_UNAVAILABLE' => const TrainSearchException(
        TrainSearchFailureKind.unavailable,
        '기차 검색을 일시적으로 사용할 수 없습니다.',
      ),
      _ => const TrainSearchException(
        TrainSearchFailureKind.invalidResponse,
        '기차 검색 응답을 확인하지 못했습니다.',
      ),
    };
  }

  TrainStation _parseStation(Object? value) {
    if (value is! Map<String, Object?> ||
        !_hasOnlyKeys(value, const {'id', 'name'})) {
      throw const FormatException();
    }
    return TrainStation(
      id: _requiredString(value, 'id'),
      name: _requiredString(value, 'name'),
    );
  }

  TrainSearchResult _parseResult(Object? value) {
    if (value is! Map<String, Object?> ||
        !_hasOnlyKeys(value, const {'observedAt', 'outbound', 'inbound'})) {
      throw const FormatException();
    }
    final observedAt = _parseDateTime(value['observedAt']);
    final outbound = _parseJourneys(value['outbound']);
    final inbound = _parseJourneys(value['inbound']);
    return TrainSearchResult(
      observedAt: observedAt,
      outbound: outbound,
      inbound: inbound,
    );
  }

  List<TrainJourney> _parseJourneys(Object? value) {
    if (value is! List<Object?>) throw const FormatException();
    final journeys = <TrainJourney>[];
    for (final row in value) {
      if (row is! Map<String, Object?>) throw const FormatException();
      final rawTrainType = _requiredString(row, 'trainType');
      final trainType = TrainSearchTrainType.parse(rawTrainType);
      if (trainType == null) continue;
      journeys.add(_parseJourney(row, trainType));
    }
    return List.unmodifiable(journeys);
  }

  TrainJourney _parseJourney(
    Map<String, Object?> value,
    TrainSearchTrainType trainType,
  ) {
    if (!_hasOnlyKeys(value, const {
      'trainNumber',
      'trainType',
      'departureStationId',
      'departureStationName',
      'departureAt',
      'arrivalStationId',
      'arrivalStationName',
      'arrivalAt',
      'durationMinutes',
      'adultFareWon',
    })) {
      throw const FormatException();
    }
    final departureAt = _parseDateTime(value['departureAt']);
    final arrivalAt = _parseDateTime(value['arrivalAt']);
    final durationMinutes = value['durationMinutes'];
    final adultFareWon = value['adultFareWon'];
    if (!arrivalAt.isAfter(departureAt) ||
        durationMinutes is! int ||
        durationMinutes < 1 ||
        adultFareWon is! int ||
        adultFareWon < 0) {
      throw const FormatException();
    }
    return TrainJourney(
      trainNumber: _requiredString(value, 'trainNumber'),
      trainType: trainType,
      departureStationId: _requiredString(value, 'departureStationId'),
      departureStationName: _requiredString(value, 'departureStationName'),
      departureAt: departureAt,
      arrivalStationId: _requiredString(value, 'arrivalStationId'),
      arrivalStationName: _requiredString(value, 'arrivalStationName'),
      arrivalAt: arrivalAt,
      durationMinutes: durationMinutes,
      adultFareWon: adultFareWon,
    );
  }

  String _requiredString(Map<String, Object?> value, String key) {
    final field = value[key];
    if (field is! String || field.trim().isEmpty) {
      throw const FormatException();
    }
    return field.trim();
  }

  DateTime _parseDateTime(Object? value) {
    if (value is! String || !RegExp(r'(Z|[+-]\d\d:\d\d)$').hasMatch(value)) {
      throw const FormatException();
    }
    return DateTime.parse(value);
  }

  void _validateCriteria(TrainSearchCriteria criteria) {
    final departureDate = DateTime(
      criteria.departureDate.year,
      criteria.departureDate.month,
      criteria.departureDate.day,
    );
    final returnDate = criteria.returnDate;
    if (criteria.departure.id.trim().isEmpty ||
        criteria.arrival.id.trim().isEmpty ||
        criteria.departure.id == criteria.arrival.id ||
        (returnDate != null &&
            DateTime(
              returnDate.year,
              returnDate.month,
              returnDate.day,
            ).isBefore(departureDate))) {
      throw const TrainSearchException(
        TrainSearchFailureKind.invalidArgument,
        '검색 조건을 확인해 주세요.',
      );
    }
  }

  String _formatDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  bool _hasOnlyKeys(Map<String, Object?> value, Set<String> keys) =>
      value.length == keys.length && value.keys.every(keys.contains);
}

class UnavailableTrainSearchRepository implements TrainSearchRepository {
  const UnavailableTrainSearchRepository();

  Never _unavailable() => throw const TrainSearchException(
    TrainSearchFailureKind.unavailable,
    '기차 검색을 일시적으로 사용할 수 없습니다.',
  );

  @override
  Future<TrainSearchResult> search(TrainSearchCriteria criteria) async =>
      _unavailable();

  @override
  Future<List<TrainStation>> stations(
    String query, {
    TrainSearchTrainType? type,
  }) async => _unavailable();
}
