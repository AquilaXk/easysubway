import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'auth_headers.dart';
import 'mobile_error_reporter.dart';

const _favoriteFacilityTimeout = Duration(seconds: 8);
const _favoriteFacilityLoadErrorMessage = '즐겨찾기 시설을 불러오지 못했습니다.';

abstract class FavoriteFacilityRepository {
  Future<List<FavoriteFacility>> listFavoriteFacilities();
}

class FavoriteFacilityApiRepository implements FavoriteFacilityRepository {
  FavoriteFacilityApiRepository({
    required this.baseUri,
    required this.authProvider,
    HttpClient? httpClient,
  }) : _httpClient = httpClient ?? HttpClient();

  final Uri baseUri;
  final AuthorizationHeaderProvider authProvider;
  final HttpClient _httpClient;

  @override
  Future<List<FavoriteFacility>> listFavoriteFacilities() async {
    final data = await _requestData(
      'GET',
      baseUri.resolve('/api/v1/me/favorites/facilities'),
      errorMessage: _favoriteFacilityLoadErrorMessage,
    );
    if (data is! List) {
      throw const FavoriteFacilityException(_favoriteFacilityLoadErrorMessage);
    }

    try {
      return data
          .map((item) {
            if (item is! Map<String, Object?>) {
              throw const FormatException('Invalid favorite facility payload');
            }
            return FavoriteFacility.fromJson(item);
          })
          .toList(growable: false);
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '즐겨찾기 시설 목록 응답 처리 중 예외가 발생했습니다.',
      );
      throw const FavoriteFacilityException(_favoriteFacilityLoadErrorMessage);
    }
  }

  Future<Object?> _requestData(
    String method,
    Uri uri, {
    required String errorMessage,
  }) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final request = await _httpClient
            .openUrl(method, uri)
            .timeout(_favoriteFacilityTimeout);
        final authorizationHeader = await authProvider
            .authorizationHeader()
            .timeout(_favoriteFacilityTimeout);
        if (authorizationHeader != null) {
          request.headers.set(
            HttpHeaders.authorizationHeader,
            authorizationHeader,
          );
        }

        final response = await request.close().timeout(
          _favoriteFacilityTimeout,
        );
        final body = await utf8
            .decodeStream(response)
            .timeout(_favoriteFacilityTimeout);

        if (response.statusCode == HttpStatus.unauthorized &&
            authorizationHeader != null &&
            attempt == 0) {
          // 저장된 익명 인증이 만료된 경우 비우고 새 인증으로 한 번만 다시 시도한다.
          await authProvider.invalidateAuthorization().timeout(
            _favoriteFacilityTimeout,
          );
          continue;
        }

        if (response.statusCode < HttpStatus.ok ||
            response.statusCode >= HttpStatus.multipleChoices) {
          throw FavoriteFacilityException(errorMessage);
        }

        final decoded = jsonDecode(body);
        if (decoded is! Map<String, Object?> || decoded['success'] != true) {
          throw FavoriteFacilityException(errorMessage);
        }
        return decoded['data'];
      } on FavoriteFacilityException {
        rethrow;
      } catch (error, stackTrace) {
        reportMobileError(
          error,
          stackTrace,
          context: '즐겨찾기 시설 API 요청 처리 중 예외가 발생했습니다.',
        );
        throw FavoriteFacilityException(errorMessage);
      }
    }
    throw FavoriteFacilityException(errorMessage);
  }
}

class FavoriteFacilityException implements Exception {
  const FavoriteFacilityException(this.message);

  final String message;

  @override
  String toString() => message;
}

class FavoriteFacility {
  const FavoriteFacility({
    required this.userId,
    required this.facilityId,
    required this.stationId,
    required this.stationNameKo,
    required this.stationNameEn,
    required this.exitId,
    required this.type,
    required this.name,
    required this.floorFrom,
    required this.floorTo,
    required this.description,
    required this.status,
    required this.dataConfidence,
    this.dataSourceType = '',
    required this.lastUpdatedAt,
    required this.addedAt,
  });

  factory FavoriteFacility.fromJson(Map<String, Object?> json) {
    return FavoriteFacility(
      userId: _requiredString(json, 'userId'),
      facilityId: _requiredString(json, 'facilityId'),
      stationId: _requiredString(json, 'stationId'),
      stationNameKo: _requiredString(json, 'stationNameKo'),
      stationNameEn: _requiredString(json, 'stationNameEn'),
      exitId: _stringOrEmpty(json, 'exitId'),
      type: _requiredString(json, 'type'),
      name: _requiredString(json, 'name'),
      floorFrom: _stringOrEmpty(json, 'floorFrom'),
      floorTo: _stringOrEmpty(json, 'floorTo'),
      description: _stringOrEmpty(json, 'description'),
      status: _requiredString(json, 'status'),
      dataConfidence: _requiredString(json, 'dataConfidence'),
      dataSourceType: _stringOrEmpty(json, 'dataSourceType'),
      lastUpdatedAt: _requiredString(json, 'lastUpdatedAt'),
      addedAt: _requiredString(json, 'addedAt'),
    );
  }

  final String userId;
  final String facilityId;
  final String stationId;
  final String stationNameKo;
  final String stationNameEn;
  final String exitId;
  final String type;
  final String name;
  final String floorFrom;
  final String floorTo;
  final String description;
  final String status;
  final String dataConfidence;
  final String dataSourceType;
  final String lastUpdatedAt;
  final String addedAt;

  String get stationLabel => '$stationNameKo역';

  String get typeLabel {
    return switch (type) {
      'ELEVATOR' => '엘리베이터',
      'ESCALATOR' => '에스컬레이터',
      'WHEELCHAIR_LIFT' => '휠체어 리프트',
      'RAMP' => '경사로',
      'ACCESSIBLE_TOILET' => '장애인 화장실',
      'TOILET' => '화장실',
      'NURSING_ROOM' => '수유실',
      'CUSTOMER_CENTER' => '고객센터',
      'STATION_OFFICE' => '역무실',
      _ => '시설',
    };
  }

  String get statusLabel {
    return switch (status) {
      'NORMAL' => '정상',
      'BROKEN' => '고장',
      'UNDER_CONSTRUCTION' => '공사 중',
      'CONSTRUCTION' => '공사 중',
      'CLOSED' => '폐쇄',
      'UNKNOWN' => '확인 필요',
      'USER_REPORTED' => '제보됨',
      'ADMIN_VERIFIED' => '검수 완료',
      'NEEDS_REPORT' => '제보 필요',
      'NEEDS_CHECK' => '확인 필요',
      _ => '상태 확인 필요',
    };
  }

  String get confidenceLabel => _dataConfidenceLabel(dataConfidence);

  String get dataSourceLabel => _dataSourceLabel(dataSourceType);

  String get locationLabel {
    if (description.trim().isNotEmpty) {
      return description;
    }
    if (floorFrom.trim().isNotEmpty && floorTo.trim().isNotEmpty) {
      return '$floorFrom-$floorTo';
    }
    return '위치 확인 필요';
  }

  String get semanticLabel {
    return '즐겨찾기 시설, $name, $stationLabel, $typeLabel, $statusLabel, $locationLabel, $confidenceLabel, $dataSourceLabel';
  }
}

enum FavoriteFacilityListStatus { loading, success, empty, failure }

class FavoriteFacilityListState {
  const FavoriteFacilityListState({
    required this.status,
    required this.favorites,
    this.message = '',
  });

  const FavoriteFacilityListState.loading()
    : status = FavoriteFacilityListStatus.loading,
      favorites = const [],
      message = '';

  final FavoriteFacilityListStatus status;
  final List<FavoriteFacility> favorites;
  final String message;
}

class FavoriteFacilityListController extends ChangeNotifier {
  FavoriteFacilityListController({required this.repository});

  final FavoriteFacilityRepository repository;

  FavoriteFacilityListState _state = const FavoriteFacilityListState.loading();
  bool _isDisposed = false;

  FavoriteFacilityListState get state => _state;

  Future<void> load() async {
    _emitState(const FavoriteFacilityListState.loading());

    try {
      final favorites = await repository.listFavoriteFacilities();
      if (favorites.isEmpty) {
        _emitState(
          const FavoriteFacilityListState(
            status: FavoriteFacilityListStatus.empty,
            favorites: [],
            message: '저장한 시설이 없습니다.',
          ),
        );
        return;
      }
      _emitState(
        FavoriteFacilityListState(
          status: FavoriteFacilityListStatus.success,
          favorites: favorites,
        ),
      );
    } on FavoriteFacilityException catch (error) {
      _emitState(
        FavoriteFacilityListState(
          status: FavoriteFacilityListStatus.failure,
          favorites: const [],
          message: error.message,
        ),
      );
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '즐겨찾기 시설 화면 처리 중 예외가 발생했습니다.',
      );
      _emitState(
        const FavoriteFacilityListState(
          status: FavoriteFacilityListStatus.failure,
          favorites: [],
          message: _favoriteFacilityLoadErrorMessage,
        ),
      );
    }
  }

  void _emitState(FavoriteFacilityListState nextState) {
    if (_isDisposed) {
      return;
    }
    _state = nextState;
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}

class FavoriteFacilityListScreen extends StatefulWidget {
  const FavoriteFacilityListScreen({required this.repository, super.key});

  final FavoriteFacilityRepository repository;

  @override
  State<FavoriteFacilityListScreen> createState() =>
      _FavoriteFacilityListScreenState();
}

class _FavoriteFacilityListScreenState
    extends State<FavoriteFacilityListScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('즐겨찾기 시설')),
      body: FavoriteFacilityListContent(repository: widget.repository),
    );
  }
}

class FavoriteFacilityListContent extends StatefulWidget {
  const FavoriteFacilityListContent({required this.repository, super.key});

  final FavoriteFacilityRepository repository;

  @override
  State<FavoriteFacilityListContent> createState() =>
      _FavoriteFacilityListContentState();
}

class _FavoriteFacilityListContentState
    extends State<FavoriteFacilityListContent> {
  late final FavoriteFacilityListController _controller;

  @override
  void initState() {
    super.initState();
    _controller = FavoriteFacilityListController(repository: widget.repository);
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return _FavoriteFacilityListBody(
            state: _controller.state,
            onRetry: _controller.load,
          );
        },
      ),
    );
  }
}

class _FavoriteFacilityListBody extends StatelessWidget {
  const _FavoriteFacilityListBody({required this.state, required this.onRetry});

  final FavoriteFacilityListState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return switch (state.status) {
      FavoriteFacilityListStatus.loading => Semantics(
        label: '즐겨찾기 시설 불러오는 중',
        liveRegion: true,
        child: const Center(child: CircularProgressIndicator()),
      ),
      FavoriteFacilityListStatus.empty => Padding(
        padding: const EdgeInsets.all(20),
        child: _FavoriteFacilityMessage(
          message: state.message,
          liveRegion: true,
        ),
      ),
      FavoriteFacilityListStatus.failure => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _FavoriteFacilityMessage(message: state.message, liveRegion: true),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: const Key('favoriteFacilitiesRetryButton'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('다시 불러오기'),
            ),
          ],
        ),
      ),
      FavoriteFacilityListStatus.success => ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Semantics(
            label: '즐겨찾기 시설 ${state.favorites.length}개',
            liveRegion: true,
            child: const SizedBox.shrink(),
          ),
          for (final favorite in state.favorites)
            _FavoriteFacilityTile(favorite: favorite),
        ],
      ),
    };
  }
}

class _FavoriteFacilityTile extends StatelessWidget {
  const _FavoriteFacilityTile({required this.favorite});

  final FavoriteFacility favorite;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return MergeSemantics(
      child: Semantics(
        label: favorite.semanticLabel,
        child: ExcludeSemantics(
          child: Card(
            key: Key('favoriteFacilityTile-${favorite.facilityId}'),
            margin: const EdgeInsets.only(bottom: 12),
            color: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: Color(0xFFD5E2E4)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    favorite.name,
                    style: textTheme.titleLarge?.copyWith(
                      color: const Color(0xFF102A2C),
                      fontWeight: FontWeight.w900,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    favorite.stationLabel,
                    style: textTheme.bodyLarge?.copyWith(
                      color: const Color(0xFF29484B),
                      fontWeight: FontWeight.w800,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    favorite.statusLabel,
                    style: textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF405A5D),
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    favorite.locationLabel,
                    style: textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF405A5D),
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    favorite.confidenceLabel,
                    style: textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF405A5D),
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    favorite.dataSourceLabel,
                    style: textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF405A5D),
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FavoriteFacilityMessage extends StatelessWidget {
  const _FavoriteFacilityMessage({
    required this.message,
    required this.liveRegion,
  });

  final String message;
  final bool liveRegion;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: liveRegion,
      child: Text(
        message,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: const Color(0xFF102A2C),
          fontWeight: FontWeight.w800,
          height: 1.35,
        ),
      ),
    );
  }
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String && value.trim().isNotEmpty) {
    return value;
  }
  throw FormatException('Missing required favorite facility field: $key');
}

String _stringOrEmpty(Map<String, Object?> json, String key) {
  final value = json[key];
  return value is String ? value : '';
}

String _dataConfidenceLabel(String dataConfidence) {
  return switch (dataConfidence) {
    'HIGH' => '정보 신뢰도 높음',
    'MEDIUM' => '정보 신뢰도 보통',
    'LOW' => '정보 확인 필요',
    _ => '정보 확인 필요',
  };
}

String _dataSourceLabel(String dataSourceType) {
  return switch (dataSourceType) {
    'OFFICIAL_API' => '출처 공공 API',
    'OFFICIAL_FILE' => '출처 공식 파일',
    'OPERATOR_PAGE' => '출처 운영기관 페이지',
    'USER_REPORT' => '출처 사용자 제보',
    'ADMIN_VERIFIED' => '출처 관리자 검수',
    'PARTNER_FEED' => '출처 제휴 데이터',
    _ => '출처 확인 필요',
  };
}
