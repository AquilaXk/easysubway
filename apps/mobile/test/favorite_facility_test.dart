import 'dart:convert';
import 'dart:io';

import 'package:easysubway_mobile/auth_headers.dart';
import 'package:easysubway_mobile/favorite_facility.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('즐겨찾기 시설 API 저장소는 인증 헤더와 함께 목록을 요청하고 결과를 파싱한다', () async {
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
                'facilityId': 'facility-sangnoksu-elevator-1',
                'stationId': 'station-sangnoksu',
                'stationNameKo': '상록수',
                'stationNameEn': 'Sangnoksu',
                'exitId': 'exit-sangnoksu-1',
                'type': 'ELEVATOR',
                'name': '1번 출구 엘리베이터',
                'floorFrom': '1F',
                'floorTo': 'B1',
                'description': '현장 검증 전 1번 출구 앞',
                'status': 'NORMAL',
                'dataConfidence': 'HIGH',
                'dataSourceType': 'OFFICIAL_FILE',
                'lastUpdatedAt': '2026-06-12',
                'addedAt': '2026-06-14T10:00:00',
              },
            ],
          }),
        )
        ..close();
    });

    final repository = FavoriteFacilityApiRepository(
      baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
      authProvider: const BasicAuthorizationHeaderProvider(
        username: 'anonymous-user-1',
        password: 'user-test-password',
      ),
    );

    final favorites = await repository.listFavoriteFacilities();

    expect(requestedUri.path, '/api/v1/me/favorites/facilities');
    expect(
      authorizationHeader,
      'Basic ${base64Encode(utf8.encode('anonymous-user-1:user-test-password'))}',
    );
    expect(favorites.single.facilityId, 'facility-sangnoksu-elevator-1');
    expect(favorites.single.stationNameKo, '상록수');
    expect(favorites.single.typeLabel, '엘리베이터');
    expect(favorites.single.statusLabel, '정상');
    expect(favorites.single.severityLabel, '정상');
    expect(favorites.single.nextActionLabel, '상태 제보');
    expect(favorites.single.statusTitle, '이용 가능');
    expect(favorites.single.confidenceLabel, '최근 확인된 정보예요');
    expect(favorites.single.dataSourceLabel, '공식 안내');
    expect(favorites.single.locationLabel, '1번 출구 앞');
    expect(favorites.single.verificationStatusLabel, '최신 상태를 준비 중이에요');
    expect(
      favorites.single.semanticLabel,
      '즐겨찾기 시설, 1번 출구 엘리베이터, 상록수역, 엘리베이터, 이용 가능, 1번 출구 앞, 최근 확인 2026-06-12, 최신 상태를 준비 중이에요, 상태 제보',
    );
    expect(favorites.single.semanticLabel, isNot(contains('정보 신뢰도')));
    expect(favorites.single.semanticLabel, isNot(contains('출처')));
  });

  test('즐겨찾기 시설 상태는 안내 수준과 할 일을 구분한다', () {
    final closed = _favoriteFacility(status: 'CLOSED');
    final unavailable = _favoriteFacility(status: 'OUT_OF_SERVICE');
    final reported = _favoriteFacility(status: 'USER_REPORTED');
    final unknown = _favoriteFacility(status: 'NEEDS_CHECK');
    final available = _favoriteFacility(status: 'AVAILABLE');
    final verified = _favoriteFacility(fieldValidationStatus: 'VERIFIED');
    final metadataOnlyDescription = _favoriteFacility(description: '현장 검증 전');

    expect(closed.severityLabel, '고장·폐쇄');
    expect(closed.nextActionLabel, '대체 출구 보기');
    expect(closed.needsAttention, isTrue);
    expect(unavailable.severityLabel, '고장·폐쇄');
    expect(unavailable.nextActionLabel, '대체 출구 보기');
    expect(reported.severityLabel, '가기 전 확인');
    expect(reported.nextActionLabel, '역무원 도움 요청');
    expect(unknown.severityLabel, '정보 부족');
    expect(unknown.nextActionLabel, '시설 상세 보기');
    expect(available.severityLabel, '정상');
    expect(available.needsAttention, isFalse);
    expect(available.verificationStatusLabel, '최신 상태를 준비 중이에요');
    expect(verified.verificationStatusLabel, '시설 상태가 확인됐어요');
    expect(metadataOnlyDescription.locationLabel, '1F-B1');
  });

  test('즐겨찾기 시설 API 저장소는 인증 실패 시 인증을 지우고 한 번 재시도한다', () async {
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
        ..write(jsonEncode({'success': true, 'data': <Object?>[]}))
        ..close();
    });

    final authProvider = RetryAuthorizationHeaderProvider();
    final repository = FavoriteFacilityApiRepository(
      baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
      authProvider: authProvider,
    );

    final favorites = await repository.listFavoriteFacilities();

    expect(favorites, isEmpty);
    expect(authorizationHeaders, ['Basic stale-token', 'Basic fresh-token']);
    expect(authProvider.authorizationCount, 2);
    expect(authProvider.invalidateCount, 1);
  });

  test('즐겨찾기 시설 API 저장소는 시설 저장과 해제를 요청한다', () async {
    final requestedMethods = <String>[];
    final requestedPaths = <String>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    server.listen((request) {
      requestedMethods.add(request.method);
      requestedPaths.add(request.uri.path);
      request.response.headers.contentType = ContentType.json;
      if (request.method == 'PUT') {
        request.response
          ..statusCode = HttpStatus.ok
          ..write(
            jsonEncode({
              'success': true,
              'data': {
                'userId': 'anonymous-user-1',
                'facilityId': 'facility-sangnoksu-elevator-1',
                'stationId': 'station-sangnoksu',
                'stationNameKo': '상록수',
                'stationNameEn': 'Sangnoksu',
                'exitId': 'exit-sangnoksu-1',
                'type': 'ELEVATOR',
                'name': '1번 출구 엘리베이터',
                'floorFrom': '1F',
                'floorTo': 'B1',
                'description': '1번 출구 앞',
                'status': 'NORMAL',
                'dataConfidence': 'HIGH',
                'dataSourceType': 'OFFICIAL_FILE',
                'lastUpdatedAt': '2026-06-12',
                'addedAt': '2026-06-14T10:00:00',
              },
            }),
          )
          ..close();
        return;
      }

      request.response
        ..statusCode = HttpStatus.ok
        ..write(jsonEncode({'success': true, 'data': null}))
        ..close();
    });

    final repository = FavoriteFacilityApiRepository(
      baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
      authProvider: const NoAuthorizationHeaderProvider(),
    );

    final saved = await repository.saveFavoriteFacility(
      'facility-sangnoksu-elevator-1',
    );
    await repository.removeFavoriteFacility('facility-sangnoksu-elevator-1');

    expect(saved.facilityId, 'facility-sangnoksu-elevator-1');
    expect(requestedMethods, ['PUT', 'DELETE']);
    expect(requestedPaths, [
      '/api/v1/me/favorites/facilities/facility-sangnoksu-elevator-1',
      '/api/v1/me/favorites/facilities/facility-sangnoksu-elevator-1',
    ]);
  });

  test('즐겨찾기 시설 목록 컨트롤러는 목록과 빈 목록과 실패 상태를 구분한다', () async {
    final repository = FakeFavoriteFacilityRepository();
    final controller = FavoriteFacilityListController(repository: repository);
    addTearDown(controller.dispose);

    repository.favorites = [_favoriteFacility()];
    await controller.load();

    expect(controller.state.status, FavoriteFacilityListStatus.success);
    expect(controller.state.favorites.single.name, '1번 출구 엘리베이터');

    repository.favorites = const [];
    await controller.load();

    expect(controller.state.status, FavoriteFacilityListStatus.empty);
    expect(controller.state.message, '즐겨찾기한 시설이 없습니다.');

    repository.error = const FavoriteFacilityException('즐겨찾기 시설을 불러오지 못했어요.');
    await controller.load();

    expect(controller.state.status, FavoriteFacilityListStatus.failure);
    expect(controller.state.message, '즐겨찾기 시설을 불러오지 못했어요.');
  });
}

class RetryAuthorizationHeaderProvider implements AuthorizationHeaderProvider {
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

class FakeFavoriteFacilityRepository implements FavoriteFacilityRepository {
  List<FavoriteFacility> favorites = const [];
  Object? error;

  @override
  Future<List<FavoriteFacility>> listFavoriteFacilities() async {
    final currentError = error;
    if (currentError != null) {
      throw currentError;
    }
    return favorites;
  }

  @override
  Future<FavoriteFacility> saveFavoriteFacility(String facilityId) async {
    final currentError = error;
    if (currentError != null) {
      throw currentError;
    }
    final favorite = _favoriteFacility();
    favorites = [favorite];
    return favorite;
  }

  @override
  Future<void> removeFavoriteFacility(String facilityId) async {
    final currentError = error;
    if (currentError != null) {
      throw currentError;
    }
    favorites = favorites
        .where((favorite) => favorite.facilityId != facilityId)
        .toList(growable: false);
  }
}

FavoriteFacility _favoriteFacility({
  String status = 'NORMAL',
  String fieldValidationStatus = 'UNKNOWN',
  String description = '1번 출구 앞',
}) {
  return FavoriteFacility(
    userId: 'anonymous-user-1',
    facilityId: 'facility-sangnoksu-elevator-1',
    stationId: 'station-sangnoksu',
    stationNameKo: '상록수',
    stationNameEn: 'Sangnoksu',
    exitId: 'exit-sangnoksu-1',
    type: 'ELEVATOR',
    name: '1번 출구 엘리베이터',
    floorFrom: '1F',
    floorTo: 'B1',
    description: description,
    status: status,
    dataConfidence: 'HIGH',
    dataSourceType: 'OFFICIAL_FILE',
    fieldValidationStatus: fieldValidationStatus,
    lastUpdatedAt: '2026-06-12',
    addedAt: '2026-06-14T10:00:00',
  );
}
