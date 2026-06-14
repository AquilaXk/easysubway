import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easysubway_mobile/station_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('역 API 저장소는 백엔드 역 목록을 요청하고 결과를 파싱한다', () async {
    late Uri requestedUri;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    server.listen((request) {
      requestedUri = request.uri;
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'success': true,
            'data': [
              {
                'id': 'station-sangnoksu',
                'nameKo': '상록수',
                'nameEn': 'Sangnoksu',
                'region': '수도권',
                'dataQualityLevel': 'LEVEL_1',
                'lastVerifiedAt': '2026-06-12',
                'lines': [
                  {
                    'id': 'seoul-4',
                    'operatorId': 'seoul-metro',
                    'name': '수도권 4호선',
                    'color': '#00A5DE',
                    'stationCode': '448',
                    'sequence': 48,
                    'platformInfo': '당고개 방면 / 오이도 방면',
                  },
                ],
              },
            ],
          }),
        )
        ..close();
    });

    final repository = StationSearchApiRepository(
      baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
    );

    final results = await repository.searchStations('상록수');

    expect(requestedUri.path, '/api/v1/stations');
    expect(requestedUri.queryParameters['query'], '상록수');
    expect(results, hasLength(1));
    expect(results.single.id, 'station-sangnoksu');
    expect(results.single.nameKo, '상록수');
    expect(results.single.region, '수도권');
    expect(results.single.dataQualityLabel, '기본 정보만 확인됨');
    expect(results.single.lines.single.name, '수도권 4호선');
  });

  test('역 API 저장소는 역 상세와 출구와 시설 정보를 요청하고 파싱한다', () async {
    final requestedPaths = <String>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    server.listen((request) {
      requestedPaths.add(request.uri.path);
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json;

      switch (request.uri.path) {
        case '/api/v1/stations/station-sangnoksu':
          request.response.write(
            jsonEncode({
              'success': true,
              'data': {
                'id': 'station-sangnoksu',
                'nameKo': '상록수',
                'nameEn': 'Sangnoksu',
                'region': '수도권',
                'latitude': 37.302795,
                'longitude': 126.866489,
                'dataQualityLevel': 'LEVEL_1',
                'lastVerifiedAt': '2026-06-12',
                'lines': [
                  {
                    'id': 'seoul-4',
                    'operatorId': 'seoul-metro',
                    'name': '수도권 4호선',
                    'color': '#00A5DE',
                    'stationCode': '448',
                    'sequence': 48,
                    'platformInfo': '당고개 방면 / 오이도 방면',
                  },
                ],
              },
            }),
          );
          break;
        case '/api/v1/stations/station-sangnoksu/exits':
          request.response.write(
            jsonEncode({
              'success': true,
              'data': [
                {
                  'id': 'exit-sangnoksu-1',
                  'stationId': 'station-sangnoksu',
                  'exitNumber': '1',
                  'name': '1번 출구',
                  'latitude': 37.302795,
                  'longitude': 126.866489,
                  'hasElevatorConnection': true,
                  'hasStairOnlyPath': false,
                  'dataConfidence': 'HIGH',
                },
              ],
            }),
          );
          break;
        case '/api/v1/stations/station-sangnoksu/facilities':
          request.response.write(
            jsonEncode({
              'success': true,
              'data': [
                {
                  'id': 'facility-sangnoksu-elevator-1',
                  'stationId': 'station-sangnoksu',
                  'exitId': 'exit-sangnoksu-1',
                  'type': 'ELEVATOR',
                  'name': '1번 출구 엘리베이터',
                  'floorFrom': 'B1',
                  'floorTo': '1F',
                  'latitude': 37.302795,
                  'longitude': 126.866489,
                  'description': '1번 출구 앞',
                  'status': 'NORMAL',
                  'dataConfidence': 'HIGH',
                  'lastUpdatedAt': '2026-06-12',
                },
              ],
            }),
          );
          break;
        default:
          request.response
            ..statusCode = HttpStatus.notFound
            ..write(jsonEncode({'success': false}));
          break;
      }

      request.response.close();
    });

    final repository = StationSearchApiRepository(
      baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
    );

    final detail = await repository.getStationDetail('station-sangnoksu');
    final exits = await repository.listStationExits('station-sangnoksu');
    final facilities = await repository.listStationFacilities(
      'station-sangnoksu',
    );

    expect(requestedPaths, [
      '/api/v1/stations/station-sangnoksu',
      '/api/v1/stations/station-sangnoksu/exits',
      '/api/v1/stations/station-sangnoksu/facilities',
    ]);
    expect(detail.nameKo, '상록수');
    expect(detail.latitude, 37.302795);
    expect(detail.longitude, 126.866489);
    expect(detail.dataQualityLabel, '기본 정보만 확인됨');
    expect(detail.lines.single.stationCode, '448');
    expect(exits.single.name, '1번 출구');
    expect(exits.single.latitude, 37.302795);
    expect(exits.single.longitude, 126.866489);
    expect(exits.single.elevatorConnectionLabel, '엘리베이터 연결');
    expect(exits.single.stairPathLabel, '계단 없는 이동 가능');
    expect(facilities.single.typeLabel, '엘리베이터');
    expect(facilities.single.latitude, 37.302795);
    expect(facilities.single.longitude, 126.866489);
    expect(facilities.single.statusLabel, '정상');
    expect(facilities.single.confidenceLabel, '정보 신뢰도 높음');
  });

  test('즐겨찾기 역 API 저장소는 인증 헤더와 함께 목록을 요청하고 결과를 파싱한다', () async {
    late String? authorizationHeader;
    late Uri requestedUri;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    server.listen((request) {
      requestedUri = request.uri;
      authorizationHeader = request.headers.value(
        HttpHeaders.authorizationHeader,
      );
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'success': true,
            'data': [
              {
                'userId': 'anonymous-user-1',
                'stationId': 'station-sangnoksu',
                'nameKo': '상록수',
                'nameEn': 'Sangnoksu',
                'region': '수도권',
                'dataQualityLevel': 'LEVEL_1',
                'lastVerifiedAt': '2026-06-12',
                'lines': [
                  {
                    'id': 'seoul-4',
                    'name': '수도권 4호선',
                    'color': '#00A5DE',
                    'stationCode': '448',
                  },
                ],
                'addedAt': '2026-06-13T10:00:00',
              },
            ],
          }),
        )
        ..close();
    });

    final repository = FavoriteStationApiRepository(
      baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
      authProvider: const BasicFavoriteStationAuthProvider(
        username: 'anonymous-user-1',
        password: 'user-test-password',
      ),
    );

    final favorites = await repository.listFavoriteStations();

    expect(requestedUri.path, '/api/v1/me/favorites/stations');
    expect(
      authorizationHeader,
      'Basic ${base64Encode(utf8.encode('anonymous-user-1:user-test-password'))}',
    );
    expect(favorites, hasLength(1));
    expect(favorites.single.stationId, 'station-sangnoksu');
    expect(favorites.single.nameKo, '상록수');
    expect(favorites.single.lineLabel, '수도권 4호선');
    expect(favorites.single.dataQualityLabel, '기본 정보만 확인됨');
  });

  test('즐겨찾기 역 API 저장소는 인증 제공자가 없으면 인증 헤더를 보내지 않는다', () async {
    late String? authorizationHeader;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    server.listen((request) {
      authorizationHeader = request.headers.value(
        HttpHeaders.authorizationHeader,
      );
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'success': true, 'data': []}))
        ..close();
    });

    final repository = FavoriteStationApiRepository(
      baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
      authProvider: const NoFavoriteStationAuthProvider(),
    );

    final favorites = await repository.listFavoriteStations();

    expect(favorites, isEmpty);
    expect(authorizationHeader, isNull);
  });

  test('즐겨찾기 역 API 저장소는 인증 실패 시 인증을 지우고 한 번 재시도한다', () async {
    final authorizationHeaders = <String?>[];
    var requestCount = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    server.listen((request) {
      requestCount++;
      authorizationHeaders.add(
        request.headers.value(HttpHeaders.authorizationHeader),
      );
      request.response.headers.contentType = ContentType.json;

      if (requestCount == 1) {
        request.response
          ..statusCode = HttpStatus.unauthorized
          ..write(jsonEncode({'success': false}))
          ..close();
        return;
      }

      request.response
        ..statusCode = HttpStatus.ok
        ..write(
          jsonEncode({
            'success': true,
            'data': [
              {
                'userId': 'anonymous-user-1',
                'stationId': 'station-sangnoksu',
                'nameKo': '상록수',
                'nameEn': 'Sangnoksu',
                'region': '수도권',
                'dataQualityLevel': 'LEVEL_1',
                'lastVerifiedAt': '2026-06-12',
                'lines': [
                  {
                    'id': 'seoul-4',
                    'name': '수도권 4호선',
                    'color': '#00A5DE',
                    'stationCode': '448',
                  },
                ],
                'addedAt': '2026-06-13T10:00:00',
              },
            ],
          }),
        )
        ..close();
    });

    final authProvider = RetryFavoriteStationAuthProvider();
    final repository = FavoriteStationApiRepository(
      baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
      authProvider: authProvider,
    );

    final favorites = await repository.listFavoriteStations();

    expect(favorites.single.stationId, 'station-sangnoksu');
    expect(authorizationHeaders, ['Basic stale-token', 'Basic fresh-token']);
    expect(authProvider.authorizationCount, 2);
    expect(authProvider.invalidateCount, 1);
  });

  test('즐겨찾기 역 API 저장소는 역 저장과 해제를 요청한다', () async {
    final requestedMethods = <String>[];
    final requestedPaths = <String>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    server.listen((request) {
      requestedMethods.add(request.method);
      requestedPaths.add(request.uri.path);
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json;

      if (request.method == 'PUT') {
        request.response.write(
          jsonEncode({
            'success': true,
            'data': {
              'userId': 'anonymous-user-1',
              'stationId': 'station-sangnoksu',
              'nameKo': '상록수',
              'nameEn': 'Sangnoksu',
              'region': '수도권',
              'dataQualityLevel': 'LEVEL_1',
              'lastVerifiedAt': '2026-06-12',
              'lines': const [],
              'addedAt': '2026-06-13T10:00:00',
            },
          }),
        );
      } else {
        request.response.write(jsonEncode({'success': true, 'data': null}));
      }

      request.response.close();
    });

    final repository = FavoriteStationApiRepository(
      baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
      authProvider: const BasicFavoriteStationAuthProvider(
        username: 'anonymous-user-1',
        password: 'user-test-password',
      ),
    );

    final favorite = await repository.saveFavoriteStation('station-sangnoksu');
    await repository.removeFavoriteStation('station-sangnoksu');

    expect(favorite.nameKo, '상록수');
    expect(requestedMethods, ['PUT', 'DELETE']);
    expect(requestedPaths, [
      '/api/v1/me/favorites/stations/station-sangnoksu',
      '/api/v1/me/favorites/stations/station-sangnoksu',
    ]);
  });

  test('역 API 저장소는 형식이 잘못된 역 응답을 거부한다', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    server.listen((request) {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'success': true,
            'data': [
              {
                'nameKo': '상록수',
                'nameEn': 'Sangnoksu',
                'region': '수도권',
                'dataQualityLevel': 'LEVEL_1',
                'lastVerifiedAt': '2026-06-12',
                'lines': [
                  {
                    'id': 'seoul-4',
                    'name': '수도권 4호선',
                    'color': '#00A5DE',
                    'stationCode': '448',
                  },
                ],
              },
            ],
          }),
        )
        ..close();
    });

    final repository = StationSearchApiRepository(
      baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
    );

    expect(
      () => repository.searchStations('상록수'),
      throwsA(
        isA<StationSearchException>().having(
          (error) => error.message,
          'message',
          '역 정보를 불러오지 못했습니다.',
        ),
      ),
    );
  });

  test('역 검색 컨트롤러는 빈 입력을 API 호출 없이 대기 상태로 둔다', () async {
    final repository = FakeStationSearchRepository();
    final controller = StationSearchController(repository: repository);

    await controller.search('   ');

    expect(repository.requestedQueries, isEmpty);
    expect(controller.state.status, StationSearchStatus.idle);
    expect(controller.state.results, isEmpty);
  });

  test('역 검색 컨트롤러는 늦게 도착한 이전 응답을 무시한다', () async {
    final repository = ControlledStationSearchRepository();
    final controller = StationSearchController(repository: repository);

    final firstSearch = controller.search('상록수');
    final secondSearch = controller.search('강남');

    expect(repository.requestedQueries, ['상록수', '강남']);

    repository.complete('강남', [
      _stationResult(id: 'station-gangnam', name: '강남'),
    ]);
    await secondSearch;

    expect(controller.state.status, StationSearchStatus.success);
    expect(controller.state.results.single.nameKo, '강남');

    repository.complete('상록수', [
      _stationResult(id: 'station-sangnoksu', name: '상록수'),
    ]);
    await firstSearch;

    expect(controller.state.status, StationSearchStatus.success);
    expect(controller.state.results.single.nameKo, '강남');
  });

  test('역 검색 컨트롤러는 빈 결과와 실패 상태를 표시한다', () async {
    final repository = FakeStationSearchRepository();
    final controller = StationSearchController(repository: repository);

    await controller.search('없는역');

    expect(controller.state.status, StationSearchStatus.empty);
    expect(controller.state.message, '검색 결과가 없습니다.');

    repository.error = const StationSearchException('역 정보를 불러오지 못했습니다.');

    await controller.search('상록수');

    expect(controller.state.status, StationSearchStatus.failure);
    expect(controller.state.message, '역 정보를 불러오지 못했습니다.');
  });

  test('역 상세 컨트롤러는 상세와 출구와 시설 요청을 동시에 시작한다', () async {
    final repository = ControlledStationDetailRepository();
    final controller = StationDetailController(repository: repository);
    addTearDown(controller.dispose);

    final loadFuture = controller.load('station-sangnoksu');

    expect(repository.requestedDetailStationIds, ['station-sangnoksu']);
    expect(repository.requestedExitStationIds, ['station-sangnoksu']);
    expect(repository.requestedFacilityStationIds, ['station-sangnoksu']);
    expect(controller.state.status, StationDetailStatus.loading);

    repository.completeAll();
    await loadFuture;

    expect(controller.state.status, StationDetailStatus.success);
    expect(controller.state.detail?.nameKo, '상록수');
    expect(controller.state.exits.single.name, '1번 출구');
    expect(controller.state.facilities.single.name, '1번 출구 엘리베이터');
  });

  test('즐겨찾기 역 목록 컨트롤러는 목록과 빈 목록과 실패 상태를 구분한다', () async {
    final repository = FakeFavoriteStationRepository();
    final controller = FavoriteStationListController(repository: repository);

    repository.favorites = [
      _favoriteStation(id: 'station-sangnoksu', name: '상록수'),
    ];
    await controller.load();

    expect(controller.state.status, FavoriteStationListStatus.success);
    expect(controller.state.favorites.single.nameKo, '상록수');

    repository.favorites = const [];
    await controller.load();

    expect(controller.state.status, FavoriteStationListStatus.empty);
    expect(controller.state.message, '저장한 역이 없습니다.');

    repository.error = const FavoriteStationException('즐겨찾기를 불러오지 못했습니다.');
    await controller.load();

    expect(controller.state.status, FavoriteStationListStatus.failure);
    expect(controller.state.message, '즐겨찾기를 불러오지 못했습니다.');
  });

  test('역 상세 즐겨찾기 컨트롤러는 저장과 해제를 순서대로 처리한다', () async {
    final repository = FakeFavoriteStationRepository();
    final controller = StationFavoriteToggleController(
      repository: repository,
      stationId: 'station-sangnoksu',
    );

    await controller.save();

    expect(repository.savedStationIds, ['station-sangnoksu']);
    expect(controller.state.isFavorite, isTrue);
    expect(controller.state.message, '즐겨찾기에 저장했습니다.');

    await controller.remove();

    expect(repository.removedStationIds, ['station-sangnoksu']);
    expect(controller.state.isFavorite, isFalse);
    expect(controller.state.message, '즐겨찾기에서 해제했습니다.');
  });

  test('시설 정보는 백엔드 enum 값을 쉬운 라벨과 스크린리더 문구로 바꾼다', () {
    const ramp = StationFacilityInfo(
      id: 'facility-ramp-1',
      stationId: 'station-sangnoksu',
      exitId: 'exit-sangnoksu-1',
      type: 'RAMP',
      name: '1번 출구 경사로',
      floorFrom: '1F',
      floorTo: 'B1',
      description: '',
      status: 'UNDER_CONSTRUCTION',
      dataConfidence: 'NEEDS_VERIFICATION',
      lastUpdatedAt: '2026-06-13',
    );
    const customerCenter = StationFacilityInfo(
      id: 'facility-center-1',
      stationId: 'station-sangnoksu',
      exitId: '',
      type: 'CUSTOMER_CENTER',
      name: '고객센터',
      floorFrom: '대합실',
      floorTo: '대합실',
      description: '개찰구 옆',
      status: 'ADMIN_VERIFIED',
      dataConfidence: 'HIGH',
      lastUpdatedAt: '2026-06-13',
    );

    expect(ramp.typeLabel, '경사로');
    expect(ramp.statusLabel, '공사 중');
    expect(ramp.confidenceLabel, '정보 확인 필요');
    expect(
      ramp.semanticLabel,
      '1번 출구 경사로, 경사로, 공사 중, 1F-B1, 최근 확인 2026-06-13, 정보 확인 필요',
    );
    expect(customerCenter.typeLabel, '고객센터');
    expect(customerCenter.statusLabel, '검수 완료');
    expect(customerCenter.semanticLabel, contains('정보 신뢰도 높음'));
  });
}

FavoriteStation _favoriteStation({required String id, required String name}) {
  return FavoriteStation(
    userId: 'anonymous-user-1',
    stationId: id,
    nameKo: name,
    nameEn: id,
    region: '수도권',
    dataQualityLevel: 'LEVEL_1',
    lastVerifiedAt: '2026-06-12',
    lines: const [
      StationSearchLine(
        id: 'seoul-4',
        name: '수도권 4호선',
        color: '#00A5DE',
        stationCode: '448',
      ),
    ],
    addedAt: '2026-06-13T10:00:00',
  );
}

StationSearchResult _stationResult({required String id, required String name}) {
  return StationSearchResult(
    id: id,
    nameKo: name,
    nameEn: id,
    region: '수도권',
    dataQualityLevel: 'LEVEL_1',
    lastVerifiedAt: '2026-06-12',
    lines: const [
      StationSearchLine(
        id: 'seoul-2',
        name: '수도권 2호선',
        color: '#00A84D',
        stationCode: '222',
      ),
    ],
  );
}

StationDetail _stationDetail({required String id, required String name}) {
  return StationDetail(
    id: id,
    nameKo: name,
    nameEn: id,
    region: '수도권',
    dataQualityLevel: 'LEVEL_1',
    lastVerifiedAt: '2026-06-12',
    lines: const [
      StationSearchLine(
        id: 'seoul-4',
        name: '수도권 4호선',
        color: '#00A5DE',
        stationCode: '448',
      ),
    ],
  );
}

StationExitInfo _stationExit() {
  return const StationExitInfo(
    id: 'exit-sangnoksu-1',
    stationId: 'station-sangnoksu',
    exitNumber: '1',
    name: '1번 출구',
    hasElevatorConnection: true,
    hasStairOnlyPath: false,
    dataConfidence: 'HIGH',
  );
}

StationFacilityInfo _stationFacility() {
  return const StationFacilityInfo(
    id: 'facility-sangnoksu-elevator-1',
    stationId: 'station-sangnoksu',
    exitId: 'exit-sangnoksu-1',
    type: 'ELEVATOR',
    name: '1번 출구 엘리베이터',
    floorFrom: '지상',
    floorTo: '대합실',
    description: '1번 출구와 대합실을 연결합니다.',
    status: 'NORMAL',
    dataConfidence: 'HIGH',
    lastUpdatedAt: '2026-06-12',
  );
}

class FakeStationSearchRepository implements StationSearchRepository {
  final requestedQueries = <String>[];
  Object? error;
  List<StationSearchResult> nextResults = const [];

  @override
  Future<List<StationSearchResult>> searchStations(String query) async {
    requestedQueries.add(query);
    final currentError = error;
    if (currentError != null) {
      throw currentError;
    }
    return nextResults;
  }

  @override
  Future<StationDetail> getStationDetail(String stationId) {
    throw UnimplementedError();
  }

  @override
  Future<List<StationExitInfo>> listStationExits(String stationId) {
    throw UnimplementedError();
  }

  @override
  Future<List<StationFacilityInfo>> listStationFacilities(String stationId) {
    throw UnimplementedError();
  }
}

class ControlledStationSearchRepository implements StationSearchRepository {
  final requestedQueries = <String>[];
  final _pending = <String, Completer<List<StationSearchResult>>>{};

  @override
  Future<List<StationSearchResult>> searchStations(String query) {
    requestedQueries.add(query);
    final completer = Completer<List<StationSearchResult>>();
    _pending[query] = completer;
    return completer.future;
  }

  @override
  Future<StationDetail> getStationDetail(String stationId) {
    throw UnimplementedError();
  }

  @override
  Future<List<StationExitInfo>> listStationExits(String stationId) {
    throw UnimplementedError();
  }

  @override
  Future<List<StationFacilityInfo>> listStationFacilities(String stationId) {
    throw UnimplementedError();
  }

  void complete(String query, List<StationSearchResult> results) {
    final completer = _pending.remove(query);
    if (completer == null) {
      throw StateError('Pending search not found: $query');
    }
    completer.complete(results);
  }
}

class ControlledStationDetailRepository implements StationSearchRepository {
  final requestedDetailStationIds = <String>[];
  final requestedExitStationIds = <String>[];
  final requestedFacilityStationIds = <String>[];
  final _detailCompleter = Completer<StationDetail>();
  final _exitsCompleter = Completer<List<StationExitInfo>>();
  final _facilitiesCompleter = Completer<List<StationFacilityInfo>>();

  @override
  Future<List<StationSearchResult>> searchStations(String query) {
    throw UnimplementedError();
  }

  @override
  Future<StationDetail> getStationDetail(String stationId) {
    requestedDetailStationIds.add(stationId);
    return _detailCompleter.future;
  }

  @override
  Future<List<StationExitInfo>> listStationExits(String stationId) {
    requestedExitStationIds.add(stationId);
    return _exitsCompleter.future;
  }

  @override
  Future<List<StationFacilityInfo>> listStationFacilities(String stationId) {
    requestedFacilityStationIds.add(stationId);
    return _facilitiesCompleter.future;
  }

  void completeAll() {
    _detailCompleter.complete(
      _stationDetail(id: 'station-sangnoksu', name: '상록수'),
    );
    _exitsCompleter.complete([_stationExit()]);
    _facilitiesCompleter.complete([_stationFacility()]);
  }
}

class FakeFavoriteStationRepository implements FavoriteStationRepository {
  List<FavoriteStation> favorites = const [];
  final savedStationIds = <String>[];
  final removedStationIds = <String>[];
  Object? error;

  @override
  Future<List<FavoriteStation>> listFavoriteStations() async {
    final currentError = error;
    if (currentError != null) {
      throw currentError;
    }
    return favorites;
  }

  @override
  Future<FavoriteStation> saveFavoriteStation(String stationId) async {
    savedStationIds.add(stationId);
    final currentError = error;
    if (currentError != null) {
      throw currentError;
    }
    final favorite = _favoriteStation(id: stationId, name: '상록수');
    favorites = [favorite];
    return favorite;
  }

  @override
  Future<void> removeFavoriteStation(String stationId) async {
    removedStationIds.add(stationId);
    final currentError = error;
    if (currentError != null) {
      throw currentError;
    }
    favorites = favorites
        .where((favorite) => favorite.stationId != stationId)
        .toList(growable: false);
  }
}

class RetryFavoriteStationAuthProvider implements FavoriteStationAuthProvider {
  var authorizationCount = 0;
  var invalidateCount = 0;
  var _invalidated = false;

  @override
  Future<String?> authorizationHeader() async {
    authorizationCount++;
    return _invalidated ? 'Basic fresh-token' : 'Basic stale-token';
  }

  @override
  Future<void> invalidateAuthorization() async {
    invalidateCount++;
    _invalidated = true;
  }
}
