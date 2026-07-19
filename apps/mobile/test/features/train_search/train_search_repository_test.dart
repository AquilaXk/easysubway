import 'package:easysubway_mobile/core/network/api_client.dart';
import 'package:easysubway_mobile/features/train_search/data/train_search_repository.dart';
import 'package:easysubway_mobile/features/train_search/domain/train_search_models.dart';
import 'package:easysubway_mobile/features/train_search/domain/train_search_scope_policy.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeApiClient extends ApiClient {
  _FakeApiClient(this.responses, {this.error})
    : super(baseUri: Uri.parse('https://example.test'));

  final List<ApiResponse> responses;
  final Object? error;
  final paths = <String>[];

  @override
  Future<ApiResponse> getJson(
    String path, {
    Map<String, String> headers = const {},
  }) async {
    paths.add(path);
    if (error case final Object error) throw error;
    return responses.removeAt(0);
  }
}

ApiResponse _response(int statusCode, Object? data) =>
    ApiResponse(statusCode: statusCode, jsonBody: data);

Map<String, Object?> _success(Object? data) => {'success': true, 'data': data};

Map<String, Object?> _error(String code) => {
  'success': false,
  'data': {'code': code},
  'message': '검색에 실패했습니다.',
};

Map<String, Object?> _journey({
  String trainType = 'KTX',
  String trainNumber = '101',
  String departureName = '서울',
  String arrivalName = '대전',
  Object adultFareWon = 23700,
  Object departureAt = '2026-07-20T09:00:00+09:00',
  Object arrivalAt = '2026-07-20T10:02:00+09:00',
}) => {
  'trainNumber': trainNumber,
  'trainType': trainType,
  'departureStationId': 'NAT010000',
  'departureStationName': departureName,
  'departureAt': departureAt,
  'arrivalStationId': 'NAT011668',
  'arrivalStationName': arrivalName,
  'arrivalAt': arrivalAt,
  'durationMinutes': 62,
  'adultFareWon': adultFareWon,
};

TrainSearchCriteria _criteria({DateTime? returnDate}) => TrainSearchCriteria(
  departure: const TrainStation(id: 'NAT010000', name: '서울'),
  arrival: const TrainStation(id: 'NAT011668', name: '대전'),
  departureDate: DateTime(2026, 7, 20),
  returnDate: returnDate,
  trainType: TrainSearchTrainType.ktx,
);

void main() {
  test('역 검색 query와 열차종을 URI encode하고 strict station을 반환한다', () async {
    final api = _FakeApiClient([
      _response(
        200,
        _success([
          {'id': 'NAT010000', 'name': '서울'},
        ]),
      ),
    ]);

    final stations = await ApiTrainSearchRepository(
      api,
    ).stations(' 서울 ', type: TrainSearchTrainType.ktx);

    expect(stations, const [TrainStation(id: 'NAT010000', name: '서울')]);
    expect(
      api.paths.single,
      '/api/v1/trains/stations?query=%EC%84%9C%EC%9A%B8&trainType=KTX',
    );
  });

  test('ITX_CHEONGCHUN row는 버리고 대전 KTX를 유지한다', () async {
    final api = _FakeApiClient([
      _response(
        200,
        _success({
          'observedAt': '2026-07-19T12:00:00Z',
          'outbound': [
            _journey(trainType: 'ITX_CHEONGCHUN', trainNumber: '2001'),
            _journey(),
          ],
          'inbound': <Object?>[],
        }),
      ),
    ]);

    final result = await ApiTrainSearchRepository(api).search(_criteria());

    expect(result.outbound.map((journey) => journey.trainType.apiValue), [
      'KTX',
    ]);
    expect(result.outbound.single.arrivalStationName, '대전');
  });

  test('왕복 조건과 날짜를 정확히 보내고 inbound를 파싱한다', () async {
    final api = _FakeApiClient([
      _response(
        200,
        _success({
          'observedAt': '2026-07-19T12:00:00Z',
          'outbound': [_journey()],
          'inbound': [
            _journey(
              trainNumber: '102',
              departureName: '대전',
              arrivalName: '서울',
              departureAt: '2026-07-21T11:00:00+09:00',
              arrivalAt: '2026-07-21T12:02:00+09:00',
            ),
          ],
        }),
      ),
    ]);

    final result = await ApiTrainSearchRepository(
      api,
    ).search(_criteria(returnDate: DateTime(2026, 7, 21)));

    expect(result.inbound.single.trainNumber, '102');
    expect(
      api.paths.single,
      '/api/v1/trains/search?departureStationId=NAT010000&arrivalStationId=NAT011668&departureDate=2026-07-20&returnDate=2026-07-21&trainType=KTX',
    );
  });

  for (final row in <Map<String, Object?>>[
    _journey(adultFareWon: -1),
    _journey(departureAt: 'not-a-date'),
    _journey(arrivalAt: '2026-07-20T08:59:00+09:00'),
  ]) {
    test('잘못된 시간·운임 row는 응답 전체를 거부한다', () async {
      final api = _FakeApiClient([
        _response(
          200,
          _success({
            'observedAt': '2026-07-19T12:00:00Z',
            'outbound': [row],
            'inbound': <Object?>[],
          }),
        ),
      ]);

      await expectLater(
        ApiTrainSearchRepository(api).search(_criteria()),
        throwsA(
          isA<TrainSearchException>().having(
            (error) => error.kind,
            'kind',
            TrainSearchFailureKind.invalidResponse,
          ),
        ),
      );
    });
  }

  for (final entry in <(int, String, TrainSearchFailureKind)>[
    (
      400,
      'TRAIN_SEARCH_UNSUPPORTED_TRAIN_TYPE',
      TrainSearchFailureKind.unsupportedTrainType,
    ),
    (
      422,
      'TRAIN_SEARCH_INVALID_ARGUMENT',
      TrainSearchFailureKind.invalidArgument,
    ),
    (429, 'TRAIN_SEARCH_RATE_LIMITED', TrainSearchFailureKind.rateLimited),
    (502, 'TRAIN_SEARCH_PROVIDER_ERROR', TrainSearchFailureKind.providerError),
    (502, 'TRAIN_SEARCH_NO_VALID_ROWS', TrainSearchFailureKind.noValidRows),
    (503, 'TRAIN_SEARCH_UNAVAILABLE', TrainSearchFailureKind.unavailable),
  ]) {
    test('HTTP ${entry.$1} ${entry.$2}를 ${entry.$3.name}로 분류한다', () async {
      final api = _FakeApiClient([_response(entry.$1, _error(entry.$2))]);

      await expectLater(
        ApiTrainSearchRepository(api).search(_criteria()),
        throwsA(
          isA<TrainSearchException>().having(
            (error) => error.kind,
            'kind',
            entry.$3,
          ),
        ),
      );
    });
  }

  test('network 예외는 stale 결과 없이 network failure로 종료한다', () async {
    final api = _FakeApiClient(
      const [],
      error: ApiException('연결 실패', path: '/api/v1/trains/search'),
    );

    await expectLater(
      ApiTrainSearchRepository(api).search(_criteria()),
      throwsA(
        isA<TrainSearchException>().having(
          (error) => error.kind,
          'kind',
          TrainSearchFailureKind.network,
        ),
      ),
    );
  });

  test('base URI가 없으면 명시적 unavailable repository로 종료한다', () async {
    await expectLater(
      const UnavailableTrainSearchRepository().search(_criteria()),
      throwsA(
        isA<TrainSearchException>().having(
          (error) => error.kind,
          'kind',
          TrainSearchFailureKind.unavailable,
        ),
      ),
    );
  });
}
