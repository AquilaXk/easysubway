import 'dart:io';

import '../../../auth_headers.dart';
import '../../../core/network/api_client.dart';
import '../../../mobile_error_reporter.dart';
import '../../../station_search.dart';

const _stationSearchErrorMessage = '역 정보를 불러오지 못했습니다.';
const _favoriteStationTimeout = Duration(seconds: 8);
const _favoriteStationLoadErrorMessage = '즐겨찾기를 불러오지 못했습니다.';
const _favoriteStationChangeErrorMessage = '즐겨찾기를 바꾸지 못했습니다.';

class StationSearchApiRepository
    implements StationSearchRepository, StationLineFilterRepository {
  StationSearchApiRepository({
    required this.baseUri,
    ApiClient? apiClient,
    HttpClient? httpClient,
  }) : _apiClient =
           apiClient ?? ApiClient(baseUri: baseUri, httpClient: httpClient);

  final Uri baseUri;
  final ApiClient _apiClient;

  @override
  Future<List<StationSearchResult>> searchStations(String query) async {
    return _searchStations({'query': query});
  }

  @override
  Future<List<StationSearchResult>> searchStationsOnLine(
    String query,
    String lineId,
  ) {
    return _searchStations({'query': query, 'lineId': lineId});
  }

  Future<List<StationSearchResult>> _searchStations(
    Map<String, String> queryParameters,
  ) async {
    final path = Uri(
      path: '/api/v1/stations',
      queryParameters: queryParameters,
    ).toString();

    final data = await _getData(path);
    if (data is! List<Object?>) {
      throw const StationSearchException(_stationSearchErrorMessage);
    }

    try {
      return data
          .map((item) {
            if (item is! Map<String, Object?>) {
              throw const FormatException('Invalid station payload');
            }
            return StationSearchResult.fromJson(item);
          })
          .toList(growable: false);
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '역 검색 목록 응답 처리 중 예외가 발생했습니다.',
      );
      throw const StationSearchException(_stationSearchErrorMessage);
    }
  }

  @override
  Future<List<SubwayLineOption>> listLines() async {
    final data = await _getData('/api/v1/lines');
    if (data is! List<Object?>) {
      throw const StationSearchException(_stationSearchErrorMessage);
    }

    try {
      return data
          .map((item) {
            if (item is! Map<String, Object?>) {
              throw const FormatException('Invalid line payload');
            }
            return SubwayLineOption.fromJson(item);
          })
          .toList(growable: false);
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '노선 목록 응답 처리 중 예외가 발생했습니다.',
      );
      throw const StationSearchException(_stationSearchErrorMessage);
    }
  }

  @override
  Future<List<StationSearchResult>> searchNearbyStations(
    CurrentLocation location, {
    int radiusMeters = 2000,
    int limit = 10,
  }) async {
    final path = Uri(
      path: '/api/v1/stations/nearby',
      queryParameters: {
        'lat': location.latitude.toString(),
        'lng': location.longitude.toString(),
        'radiusMeters': radiusMeters.toString(),
        'limit': limit.toString(),
      },
    ).toString();

    final data = await _getData(path);
    if (data is! List<Object?>) {
      throw const StationSearchException(_stationSearchErrorMessage);
    }

    try {
      return data
          .map((item) {
            if (item is! Map<String, Object?>) {
              throw const FormatException('Invalid nearby station payload');
            }
            return StationSearchResult.fromJson(item);
          })
          .toList(growable: false);
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '주변 역 목록 응답 처리 중 예외가 발생했습니다.',
      );
      throw const StationSearchException(_stationSearchErrorMessage);
    }
  }

  @override
  Future<StationDetail> getStationDetail(String stationId) async {
    final data = await _getData(
      '/api/v1/stations/${Uri.encodeComponent(stationId)}',
    );
    if (data is! Map<String, Object?>) {
      throw const StationSearchException(_stationSearchErrorMessage);
    }
    try {
      return StationDetail.fromJson(data);
    } catch (error, stackTrace) {
      reportMobileError(error, stackTrace, context: '역 상세 응답 처리 중 예외가 발생했습니다.');
      throw const StationSearchException(_stationSearchErrorMessage);
    }
  }

  @override
  Future<List<StationExitInfo>> listStationExits(String stationId) async {
    final data = await _getData(
      '/api/v1/stations/${Uri.encodeComponent(stationId)}/exits',
    );
    if (data is! List<Object?>) {
      throw const StationSearchException(_stationSearchErrorMessage);
    }
    try {
      return data
          .map((item) {
            if (item is! Map<String, Object?>) {
              throw const FormatException('Invalid station exit payload');
            }
            return StationExitInfo.fromJson(item);
          })
          .toList(growable: false);
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '역 출구 목록 응답 처리 중 예외가 발생했습니다.',
      );
      throw const StationSearchException(_stationSearchErrorMessage);
    }
  }

  @override
  Future<List<StationFacilityInfo>> listStationFacilities(
    String stationId,
  ) async {
    final data = await _getData(
      '/api/v1/stations/${Uri.encodeComponent(stationId)}/facilities',
    );
    if (data is! List<Object?>) {
      throw const StationSearchException(_stationSearchErrorMessage);
    }
    try {
      return data
          .map((item) {
            if (item is! Map<String, Object?>) {
              throw const FormatException('Invalid station facility payload');
            }
            return StationFacilityInfo.fromJson(item);
          })
          .toList(growable: false);
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '역 시설 목록 응답 처리 중 예외가 발생했습니다.',
      );
      throw const StationSearchException(_stationSearchErrorMessage);
    }
  }

  Future<Object?> _getData(String path) async {
    try {
      final response = await _apiClient.getJson(path);
      if (response.statusCode != HttpStatus.ok) {
        throw const StationSearchException(_stationSearchErrorMessage);
      }
      final decoded = response.jsonBody;
      if (decoded is! Map<String, Object?> || decoded['success'] != true) {
        throw const StationSearchException(_stationSearchErrorMessage);
      }

      return decoded['data'];
    } on StationSearchException {
      rethrow;
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '역 정보 API 요청 처리 중 예외가 발생했습니다.',
      );
      throw const StationSearchException(_stationSearchErrorMessage);
    }
  }
}

typedef FavoriteStationAuthProvider = AuthorizationHeaderProvider;

class NoFavoriteStationAuthProvider extends NoAuthorizationHeaderProvider {
  const NoFavoriteStationAuthProvider();
}

class BasicFavoriteStationAuthProvider
    extends BasicAuthorizationHeaderProvider {
  const BasicFavoriteStationAuthProvider({
    required super.username,
    required super.password,
  });
}

class FavoriteStationApiRepository implements FavoriteStationRepository {
  FavoriteStationApiRepository({
    required this.baseUri,
    required this.authProvider,
    ApiClient? apiClient,
    HttpClient? httpClient,
  }) : _apiClient =
           apiClient ?? ApiClient(baseUri: baseUri, httpClient: httpClient);

  final Uri baseUri;
  final FavoriteStationAuthProvider authProvider;
  final ApiClient _apiClient;

  @override
  Future<List<FavoriteStation>> listFavoriteStations() async {
    final data = await _requestData(
      'GET',
      '/api/v1/me/favorites/stations',
      errorMessage: _favoriteStationLoadErrorMessage,
    );
    if (data is! List<Object?>) {
      throw const FavoriteStationException(_favoriteStationLoadErrorMessage);
    }

    try {
      return data
          .map((item) {
            if (item is! Map<String, Object?>) {
              throw const FormatException('Invalid favorite station payload');
            }
            return FavoriteStation.fromJson(item);
          })
          .toList(growable: false);
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '즐겨찾기 역 목록 응답 처리 중 예외가 발생했습니다.',
      );
      throw const FavoriteStationException(_favoriteStationLoadErrorMessage);
    }
  }

  @override
  Future<FavoriteStation> saveFavoriteStation(String stationId) async {
    final path =
        '/api/v1/me/favorites/stations/${Uri.encodeComponent(stationId)}';
    final data = await _requestData(
      'PUT',
      path,
      errorMessage: _favoriteStationChangeErrorMessage,
    );
    if (data is! Map<String, Object?>) {
      throw const FavoriteStationException(_favoriteStationChangeErrorMessage);
    }

    try {
      return FavoriteStation.fromJson(data);
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '즐겨찾기 역 저장 응답 처리 중 예외가 발생했습니다.',
      );
      throw const FavoriteStationException(_favoriteStationChangeErrorMessage);
    }
  }

  @override
  Future<void> removeFavoriteStation(String stationId) async {
    final path =
        '/api/v1/me/favorites/stations/${Uri.encodeComponent(stationId)}';
    await _requestData(
      'DELETE',
      path,
      errorMessage: _favoriteStationChangeErrorMessage,
    );
  }

  Future<Object?> _requestData(
    String method,
    String path, {
    required String errorMessage,
  }) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final authorizationHeader = await authProvider
            .authorizationHeader()
            .timeout(_favoriteStationTimeout);
        final headers = authorizationHeader == null
            ? const <String, String>{}
            : {HttpHeaders.authorizationHeader: authorizationHeader};
        final response = await switch (method) {
          'GET' => _apiClient.getJson(path, headers: headers),
          'PUT' => _apiClient.putJson(path, headers: headers),
          'DELETE' => _apiClient.deleteJson(path, headers: headers),
          _ => throw FavoriteStationException(errorMessage),
        };

        if (response.statusCode == HttpStatus.unauthorized &&
            authorizationHeader != null &&
            attempt == 0) {
          // 저장된 인증이 서버에서 만료된 경우 지우고 한 번만 재시도한다.
          await authProvider.invalidateAuthorization().timeout(
            _favoriteStationTimeout,
          );
          continue;
        }

        if (response.statusCode < HttpStatus.ok ||
            response.statusCode >= HttpStatus.multipleChoices) {
          throw FavoriteStationException(errorMessage);
        }

        final decoded = response.jsonBody;
        if (decoded is! Map<String, Object?> || decoded['success'] != true) {
          throw FavoriteStationException(errorMessage);
        }
        return decoded['data'];
      } on FavoriteStationException {
        rethrow;
      } catch (error, stackTrace) {
        reportMobileError(
          error,
          stackTrace,
          context: '즐겨찾기 역 API 요청 처리 중 예외가 발생했습니다.',
        );
        throw FavoriteStationException(errorMessage);
      }
    }
    throw FavoriteStationException(errorMessage);
  }
}
