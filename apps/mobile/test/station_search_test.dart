import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easysubway_mobile/mobile_error_reporter.dart';
import 'package:easysubway_mobile/station_search.dart';
import 'package:flutter/foundation.dart';
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
                'dataSourceType': 'OFFICIAL_FILE',
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
    expect(results.single.dataSourceLabel, '출처 공식 파일');
    expect(results.single.lines.single.name, '수도권 4호선');
  });

  test('역 API 저장소는 초성 검색어를 그대로 요청한다', () async {
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
                'dataSourceType': 'OFFICIAL_FILE',
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

    final results = await repository.searchStations('ㅅㄹㅅ');

    expect(requestedUri.path, '/api/v1/stations');
    expect(requestedUri.queryParameters['query'], 'ㅅㄹㅅ');
    expect(results.single.nameKo, '상록수');
  });

  test('역 API 저장소는 현재 위치 기준 가까운 역을 요청하고 거리를 파싱한다', () async {
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
                'dataSourceType': 'OFFICIAL_FILE',
                'lastVerifiedAt': '2026-06-12',
                'distanceMeters': 230,
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

    final results = await repository.searchNearbyStations(
      const CurrentLocation(latitude: 37.3028, longitude: 126.8665),
      radiusMeters: 1500,
      limit: 5,
    );

    expect(requestedUri.path, '/api/v1/stations/nearby');
    expect(requestedUri.queryParameters['lat'], '37.3028');
    expect(requestedUri.queryParameters['lng'], '126.8665');
    expect(requestedUri.queryParameters['radiusMeters'], '1500');
    expect(requestedUri.queryParameters['limit'], '5');
    expect(results.single.nameKo, '상록수');
    expect(results.single.distanceMeters, 230);
    expect(results.single.distanceLabel, '230m 거리');
  });

  test('역 API 저장소는 정수가 아닌 거리 응답을 계약 위반으로 처리한다', () async {
    final reportedErrors = _captureReportedErrors();
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
                'id': 'station-sangnoksu',
                'nameKo': '상록수',
                'nameEn': 'Sangnoksu',
                'region': '수도권',
                'dataQualityLevel': 'LEVEL_1',
                'lastVerifiedAt': '2026-06-12',
                'distanceMeters': 230.4,
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

    await runWithMobileErrorReporter(reportedErrors.add, () async {
      await expectLater(
        repository.searchNearbyStations(
          const CurrentLocation(latitude: 37.3028, longitude: 126.8665),
        ),
        throwsA(
          isA<StationSearchException>().having(
            (error) => error.message,
            'message',
            '역 정보를 불러오지 못했습니다.',
          ),
        ),
      );
    });

    expect(reportedErrors.single.exception, isA<FormatException>());
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
                'dataSourceType': 'OFFICIAL_FILE',
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
                  'dataSourceType': 'OFFICIAL_FILE',
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
                  'dataSourceType': 'OFFICIAL_FILE',
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
    expect(detail.dataSourceLabel, '출처 공식 파일');
    expect(detail.lines.single.stationCode, '448');
    expect(exits.single.name, '1번 출구');
    expect(exits.single.latitude, 37.302795);
    expect(exits.single.longitude, 126.866489);
    expect(exits.single.elevatorConnectionLabel, '엘리베이터 연결');
    expect(exits.single.stairPathLabel, '계단 없는 이동 가능');
    expect(exits.single.dataSourceLabel, '출처 공식 파일');
    expect(facilities.single.typeLabel, '엘리베이터');
    expect(facilities.single.latitude, 37.302795);
    expect(facilities.single.longitude, 126.866489);
    expect(facilities.single.statusLabel, '정상');
    expect(facilities.single.confidenceLabel, '정보 신뢰도 높음');
    expect(facilities.single.dataSourceLabel, '출처 공식 파일');
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
                'dataSourceType': 'OFFICIAL_FILE',
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
    expect(favorites.single.dataSourceLabel, '출처 공식 파일');
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
                'dataSourceType': 'OFFICIAL_FILE',
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
              'dataSourceType': 'OFFICIAL_FILE',
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
    final reportedErrors = _captureReportedErrors();
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

    await runWithMobileErrorReporter(reportedErrors.add, () async {
      await expectLater(
        repository.searchStations('상록수'),
        throwsA(
          isA<StationSearchException>().having(
            (error) => error.message,
            'message',
            '역 정보를 불러오지 못했습니다.',
          ),
        ),
      );
    });
    expect(reportedErrors, hasLength(1));
    expect(reportedErrors.single.exception, isA<FormatException>());
    expect(reportedErrors.single.stack, isNotNull);
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

  test('역 검색 컨트롤러는 현재 위치 주변 역을 거리와 함께 표시한다', () async {
    final repository = FakeStationSearchRepository()
      ..nextNearbyResults = [
        _stationResult(
          id: 'station-sangnoksu',
          name: '상록수',
          distanceMeters: 230,
        ),
      ];
    final locationProvider = FakeCurrentLocationProvider(
      location: const CurrentLocation(latitude: 37.3028, longitude: 126.8665),
    );
    final controller = StationSearchController(repository: repository);

    await controller.searchNearby(locationProvider);

    expect(locationProvider.requestCount, 1);
    expect(repository.requestedNearbyLocations.single.latitude, 37.3028);
    expect(repository.requestedNearbyLocations.single.longitude, 126.8665);
    expect(controller.state.status, StationSearchStatus.success);
    expect(controller.state.results.single.distanceLabel, '230m 거리');
  });

  test('역 검색 컨트롤러는 위치 조회 실패를 쉬운 문구로 표시한다', () async {
    final repository = FakeStationSearchRepository();
    final locationProvider = FakeCurrentLocationProvider(
      error: const CurrentLocationException('위치 권한을 확인해 주세요.'),
    );
    final controller = StationSearchController(repository: repository);

    await controller.searchNearby(locationProvider);

    expect(locationProvider.requestCount, 1);
    expect(repository.requestedNearbyLocations, isEmpty);
    expect(controller.state.status, StationSearchStatus.failure);
    expect(controller.state.message, '위치 권한을 확인해 주세요.');
  });

  test('역 검색 컨트롤러는 주변 검색 중 화면이 닫히면 늦은 응답을 알리지 않는다', () async {
    final repository = ControlledNearbyStationSearchRepository();
    final controller = StationSearchController(repository: repository);

    final searchFuture = controller.searchNearby(
      FakeCurrentLocationProvider(
        location: const CurrentLocation(latitude: 37.3028, longitude: 126.8665),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(repository.requestedNearbyLocations, hasLength(1));
    expect(controller.state.status, StationSearchStatus.loading);

    controller.dispose();
    repository.complete([_stationResult(id: 'station-sangnoksu', name: '상록수')]);
    await searchFuture;
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

  test('역 상세 컨트롤러는 처리된 역 정보 실패를 오류 경계에 다시 보고하지 않는다', () async {
    final reportedErrors = _captureReportedErrors();
    final repository = FailingStationDetailRepository();
    final controller = StationDetailController(repository: repository);
    addTearDown(controller.dispose);

    await runWithMobileErrorReporter(reportedErrors.add, () async {
      await controller.load('station-sangnoksu');
    });

    expect(reportedErrors, isEmpty);
    expect(controller.state.status, StationDetailStatus.failure);
    expect(controller.state.message, '역 상세 정보를 불러오지 못했습니다.');
  });

  test('역 상세 상태는 확인이 필요한 시설을 먼저 보여 주고 짧은 요약을 만든다', () {
    final state = StationDetailState(
      status: StationDetailStatus.success,
      detail: _stationDetail(id: 'station-sangnoksu', name: '상록수'),
      facilities: [
        _stationFacility(),
        _stationFacility(
          id: 'facility-sangnoksu-ramp-1',
          name: '1번 출구 경사로',
          status: 'UNDER_CONSTRUCTION',
        ),
        _stationFacility(
          id: 'facility-sangnoksu-call-bell-1',
          name: '비상벨',
          status: 'NEW_BACKEND_STATUS',
        ),
        _stationFacility(
          id: 'facility-sangnoksu-elevator-2',
          name: '2번 출구 엘리베이터',
          status: 'BROKEN',
        ),
      ],
    );

    expect(state.prioritizedFacilities.map((facility) => facility.name), [
      '2번 출구 엘리베이터',
      '1번 출구 경사로',
      '비상벨',
      '1번 출구 엘리베이터',
    ]);
    expect(state.facilityAttentionSummary, '확인 필요 3개');
    expect(state.facilityAttentionSemanticLabel, '확인이 필요한 시설 3개');
  });

  test('역 상세 상태는 쉬운 이동 구조 요약을 만든다', () {
    final state = StationDetailState(
      status: StationDetailStatus.success,
      detail: _stationDetail(id: 'station-sangnoksu', name: '상록수'),
      exits: [
        _stationExit(
          id: 'exit-sangnoksu-1',
          name: '1번 출구',
          hasElevatorConnection: true,
        ),
        _stationExit(
          id: 'exit-sangnoksu-2',
          name: '2번 출구',
          hasElevatorConnection: false,
          hasStairOnlyPath: true,
        ),
      ],
      facilities: [
        _stationFacility(
          id: 'facility-sangnoksu-elevator-1',
          name: '1번 출구 엘리베이터',
          type: 'ELEVATOR',
          exitId: 'exit-sangnoksu-1',
        ),
        _stationFacility(
          id: 'facility-sangnoksu-toilet-1',
          name: '장애인 화장실',
          type: 'ACCESSIBLE_TOILET',
          exitId: '',
          status: 'BROKEN',
        ),
      ],
    );

    expect(state.layoutSummaryItems.map((item) => item.text), [
      '1번 출구',
      '엘리베이터',
      '장애인 화장실',
      '승강장',
    ]);
    expect(
      state.layoutSummarySemanticLabel,
      '이동 구조, 1번 출구, 엘리베이터, 장애인 화장실, 승강장',
    );
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
      '1번 출구 경사로, 경사로, 공사 중, 1F-B1, 최근 확인 2026-06-13, 정보 확인 필요, 출처 확인 필요',
    );
    expect(customerCenter.typeLabel, '고객센터');
    expect(customerCenter.statusLabel, '검수 완료');
    expect(customerCenter.semanticLabel, contains('정보 신뢰도 높음'));
  });
}

List<FlutterErrorDetails> _captureReportedErrors() {
  return <FlutterErrorDetails>[];
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

StationSearchResult _stationResult({
  required String id,
  required String name,
  int? distanceMeters,
}) {
  return StationSearchResult(
    id: id,
    nameKo: name,
    nameEn: id,
    region: '수도권',
    dataQualityLevel: 'LEVEL_1',
    lastVerifiedAt: '2026-06-12',
    distanceMeters: distanceMeters,
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

StationExitInfo _stationExit({
  String id = 'exit-sangnoksu-1',
  String name = '1번 출구',
  bool hasElevatorConnection = true,
  bool hasStairOnlyPath = false,
}) {
  return StationExitInfo(
    id: id,
    stationId: 'station-sangnoksu',
    exitNumber: '1',
    name: name,
    hasElevatorConnection: hasElevatorConnection,
    hasStairOnlyPath: hasStairOnlyPath,
    dataConfidence: 'HIGH',
  );
}

StationFacilityInfo _stationFacility({
  String id = 'facility-sangnoksu-elevator-1',
  String name = '1번 출구 엘리베이터',
  String type = 'ELEVATOR',
  String exitId = 'exit-sangnoksu-1',
  String status = 'NORMAL',
}) {
  return StationFacilityInfo(
    id: id,
    stationId: 'station-sangnoksu',
    exitId: exitId,
    type: type,
    name: name,
    floorFrom: '지상',
    floorTo: '대합실',
    description: '1번 출구와 대합실을 연결합니다.',
    status: status,
    dataConfidence: 'HIGH',
    lastUpdatedAt: '2026-06-12',
  );
}

class FakeStationSearchRepository implements StationSearchRepository {
  final requestedQueries = <String>[];
  final requestedNearbyLocations = <CurrentLocation>[];
  Object? error;
  List<StationSearchResult> nextResults = const [];
  List<StationSearchResult> nextNearbyResults = const [];

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
  Future<List<StationSearchResult>> searchNearbyStations(
    CurrentLocation location, {
    int radiusMeters = 2000,
    int limit = 10,
  }) async {
    requestedNearbyLocations.add(location);
    final currentError = error;
    if (currentError != null) {
      throw currentError;
    }
    return nextNearbyResults;
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
  Future<List<StationSearchResult>> searchNearbyStations(
    CurrentLocation location, {
    int radiusMeters = 2000,
    int limit = 10,
  }) {
    throw UnimplementedError();
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

class ControlledNearbyStationSearchRepository
    implements StationSearchRepository {
  final requestedNearbyLocations = <CurrentLocation>[];
  final _nearbyCompleter = Completer<List<StationSearchResult>>();

  @override
  Future<List<StationSearchResult>> searchStations(String query) {
    throw UnimplementedError();
  }

  @override
  Future<List<StationSearchResult>> searchNearbyStations(
    CurrentLocation location, {
    int radiusMeters = 2000,
    int limit = 10,
  }) {
    requestedNearbyLocations.add(location);
    return _nearbyCompleter.future;
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

  void complete(List<StationSearchResult> results) {
    _nearbyCompleter.complete(results);
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
  Future<List<StationSearchResult>> searchNearbyStations(
    CurrentLocation location, {
    int radiusMeters = 2000,
    int limit = 10,
  }) {
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

class FailingStationDetailRepository implements StationSearchRepository {
  @override
  Future<List<StationSearchResult>> searchStations(String query) async {
    return const [];
  }

  @override
  Future<List<StationSearchResult>> searchNearbyStations(
    CurrentLocation location, {
    int radiusMeters = 2000,
    int limit = 10,
  }) async {
    return const [];
  }

  @override
  Future<StationDetail> getStationDetail(String stationId) async {
    throw const StationSearchException('역 정보를 불러오지 못했습니다.');
  }

  @override
  Future<List<StationExitInfo>> listStationExits(String stationId) async {
    return const [];
  }

  @override
  Future<List<StationFacilityInfo>> listStationFacilities(
    String stationId,
  ) async {
    return const [];
  }
}

class FakeCurrentLocationProvider implements CurrentLocationProvider {
  FakeCurrentLocationProvider({
    this.location,
    this.error,
    this.needsPermissionRequest = true,
  });

  final CurrentLocation? location;
  final Object? error;
  final bool needsPermissionRequest;
  int requestCount = 0;

  @override
  Future<bool> needsLocationPermissionRequest() async {
    return needsPermissionRequest;
  }

  @override
  Future<CurrentLocation> currentLocation() async {
    requestCount++;
    final currentError = error;
    if (currentError != null) {
      throw currentError;
    }
    return location ??
        const CurrentLocation(latitude: 37.3028, longitude: 126.8665);
  }

  @override
  Future<bool> openLocationSettings() async {
    return true;
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
