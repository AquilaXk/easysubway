import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'auth_headers.dart';
import 'mobile_error_reporter.dart';
import 'mobility_profile.dart';
import 'station_search.dart';

const _routeSearchTimeout = Duration(seconds: 8);
const _routeSearchErrorMessage = '경로 정보를 불러오지 못했습니다.';
const _favoriteRouteErrorMessage = '즐겨찾기 경로를 처리하지 못했습니다.';
const _favoriteRouteLoadErrorMessage = '즐겨찾기 경로를 불러오지 못했습니다.';

String _mobilityLabelFor(String mobilityType) {
  for (final option in mobilityProfileOptions) {
    if (option.mobilityType == mobilityType) {
      return option.title;
    }
  }
  return '이동 조건 확인 필요';
}

abstract class RouteSearchRepository {
  Future<RouteSearchResult> searchRoute(RouteSearchRequest request);
}

class RouteSearchApiRepository implements RouteSearchRepository {
  RouteSearchApiRepository({required this.baseUri, HttpClient? httpClient})
    : _httpClient = httpClient ?? HttpClient();

  final Uri baseUri;
  final HttpClient _httpClient;

  @override
  Future<RouteSearchResult> searchRoute(RouteSearchRequest routeRequest) async {
    final uri = baseUri.resolve('/api/v1/routes/search');

    try {
      final request = await _httpClient
          .postUrl(uri)
          .timeout(_routeSearchTimeout);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(routeRequest.toJson()));

      final response = await request.close().timeout(_routeSearchTimeout);
      final body = await utf8
          .decodeStream(response)
          .timeout(_routeSearchTimeout);

      if (response.statusCode != HttpStatus.ok) {
        throw const RouteSearchException(_routeSearchErrorMessage);
      }

      final decoded = jsonDecode(body);
      if (decoded is! Map<String, Object?> || decoded['success'] != true) {
        throw const RouteSearchException(_routeSearchErrorMessage);
      }

      final data = decoded['data'];
      if (data is! Map<String, Object?>) {
        throw const RouteSearchException(_routeSearchErrorMessage);
      }

      return RouteSearchResult.fromJson(data);
    } on RouteSearchException {
      rethrow;
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '경로 검색 API 응답 처리 중 예외가 발생했습니다.',
      );
      throw const RouteSearchException(_routeSearchErrorMessage);
    }
  }
}

abstract class FavoriteRouteRepository {
  Future<List<FavoriteRoute>> listFavoriteRoutes();

  Future<FavoriteRoute> saveFavoriteRoute(String routeSearchId);

  Future<void> removeFavoriteRoute(String favoriteRouteId);
}

class FavoriteRouteApiRepository implements FavoriteRouteRepository {
  FavoriteRouteApiRepository({
    required this.baseUri,
    required this.authProvider,
    HttpClient? httpClient,
  }) : _httpClient = httpClient ?? HttpClient();

  final Uri baseUri;
  final AuthorizationHeaderProvider authProvider;
  final HttpClient _httpClient;

  @override
  Future<List<FavoriteRoute>> listFavoriteRoutes() async {
    final data = await _requestData(
      'GET',
      baseUri.resolve('/api/v1/me/favorites/routes'),
      errorMessage: _favoriteRouteLoadErrorMessage,
    );
    if (data is! List) {
      throw const FavoriteRouteException(_favoriteRouteLoadErrorMessage);
    }

    try {
      return data
          .map((item) {
            if (item is! Map<String, Object?>) {
              throw const FormatException('Invalid favorite route payload');
            }
            return FavoriteRoute.fromJson(item);
          })
          .toList(growable: false);
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '즐겨찾기 경로 목록 응답 처리 중 예외가 발생했습니다.',
      );
      throw const FavoriteRouteException(_favoriteRouteLoadErrorMessage);
    }
  }

  @override
  Future<FavoriteRoute> saveFavoriteRoute(String routeSearchId) async {
    final data = await _requestData(
      'POST',
      baseUri.resolve('/api/v1/me/favorites/routes'),
      body: {'routeSearchId': routeSearchId},
      errorMessage: _favoriteRouteErrorMessage,
    );
    if (data is! Map<String, Object?>) {
      throw const FavoriteRouteException(_favoriteRouteErrorMessage);
    }

    try {
      return FavoriteRoute.fromJson(data);
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '즐겨찾기 경로 저장 응답 처리 중 예외가 발생했습니다.',
      );
      throw const FavoriteRouteException(_favoriteRouteErrorMessage);
    }
  }

  @override
  Future<void> removeFavoriteRoute(String favoriteRouteId) async {
    await _requestData(
      'DELETE',
      baseUri.resolve('/api/v1/me/favorites/routes/$favoriteRouteId'),
      errorMessage: _favoriteRouteErrorMessage,
    );
  }

  Future<Object?> _requestData(
    String method,
    Uri uri, {
    Map<String, Object?>? body,
    required String errorMessage,
  }) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final request = await _httpClient
            .openUrl(method, uri)
            .timeout(_routeSearchTimeout);
        final authorizationHeader = await authProvider
            .authorizationHeader()
            .timeout(_routeSearchTimeout);
        if (authorizationHeader != null) {
          request.headers.set(
            HttpHeaders.authorizationHeader,
            authorizationHeader,
          );
        }
        if (body != null) {
          request.headers.contentType = ContentType.json;
          request.write(jsonEncode(body));
        }

        final response = await request.close().timeout(_routeSearchTimeout);
        final responseBody = await utf8
            .decodeStream(response)
            .timeout(_routeSearchTimeout);

        if (response.statusCode == HttpStatus.unauthorized &&
            authorizationHeader != null &&
            attempt == 0) {
          // 만료된 익명 인증은 비우고 새 인증으로 한 번만 다시 시도한다.
          await authProvider.invalidateAuthorization().timeout(
            _routeSearchTimeout,
          );
          continue;
        }

        if (response.statusCode < HttpStatus.ok ||
            response.statusCode >= HttpStatus.multipleChoices) {
          throw FavoriteRouteException(errorMessage);
        }

        final decoded = jsonDecode(responseBody);
        if (decoded is! Map<String, Object?> || decoded['success'] != true) {
          throw FavoriteRouteException(errorMessage);
        }
        return decoded['data'];
      } on FavoriteRouteException {
        rethrow;
      } catch (error, stackTrace) {
        reportMobileError(
          error,
          stackTrace,
          context: '즐겨찾기 경로 API 요청 처리 중 예외가 발생했습니다.',
        );
        throw FavoriteRouteException(errorMessage);
      }
    }
    throw FavoriteRouteException(errorMessage);
  }
}

class FavoriteRouteException implements Exception {
  const FavoriteRouteException(this.message);

  final String message;

  @override
  String toString() => message;
}

class FavoriteRoute {
  const FavoriteRoute({
    required this.userId,
    required this.favoriteRouteId,
    required this.routeSearchId,
    required this.originStationId,
    required this.originStationName,
    required this.destinationStationId,
    required this.destinationStationName,
    required this.mobilityType,
    required this.status,
    required this.lineId,
    required this.lineName,
    required this.score,
    required this.routeCreatedAt,
    required this.addedAt,
  });

  factory FavoriteRoute.fromJson(Map<String, Object?> json) {
    return FavoriteRoute(
      userId: _requiredRouteString(json, 'userId'),
      favoriteRouteId: _requiredRouteString(json, 'favoriteRouteId'),
      routeSearchId: _requiredRouteString(json, 'routeSearchId'),
      originStationId: _requiredRouteString(json, 'originStationId'),
      originStationName: _requiredRouteString(json, 'originStationName'),
      destinationStationId: _requiredRouteString(json, 'destinationStationId'),
      destinationStationName: _requiredRouteString(
        json,
        'destinationStationName',
      ),
      mobilityType: _requiredRouteString(json, 'mobilityType'),
      status: _requiredRouteString(json, 'status'),
      lineId: _optionalRouteString(json, 'lineId'),
      lineName: _optionalRouteString(json, 'lineName'),
      score: _requiredRouteInt(json, 'score'),
      routeCreatedAt: _requiredRouteString(json, 'routeCreatedAt'),
      addedAt: _requiredRouteString(json, 'addedAt'),
    );
  }

  final String userId;
  final String favoriteRouteId;
  final String routeSearchId;
  final String originStationId;
  final String originStationName;
  final String destinationStationId;
  final String destinationStationName;
  final String mobilityType;
  final String status;
  final String lineId;
  final String lineName;
  final int score;
  final String routeCreatedAt;
  final String addedAt;

  String get summaryTitle => '$originStationName에서 $destinationStationName까지';

  String get lineLabel => lineName.isEmpty ? '노선 확인 필요' : lineName;

  String get scoreLabel => '이동 점수 $score점';

  String get mobilityLabel => _mobilityLabelFor(mobilityType);

  String get semanticLabel {
    return '즐겨찾기 경로, $summaryTitle, $lineLabel, $mobilityLabel, $scoreLabel';
  }
}

class RouteSearchException implements Exception {
  const RouteSearchException(this.message);

  final String message;

  @override
  String toString() => message;
}

class RouteSearchRequest {
  const RouteSearchRequest({
    required this.originStationId,
    required this.destinationStationId,
    required this.mobilityType,
  });

  final String originStationId;
  final String destinationStationId;
  final String mobilityType;

  RouteSearchRequest trimmed() {
    return RouteSearchRequest(
      originStationId: originStationId.trim(),
      destinationStationId: destinationStationId.trim(),
      mobilityType: mobilityType,
    );
  }

  Map<String, Object?> toJson() {
    final trimmedRequest = trimmed();
    return {
      'originStationId': trimmedRequest.originStationId,
      'destinationStationId': trimmedRequest.destinationStationId,
      'mobilityType': trimmedRequest.mobilityType,
    };
  }
}

class RouteSearchResult {
  const RouteSearchResult({
    required this.routeSearchId,
    required this.originStationId,
    required this.originStationName,
    required this.destinationStationId,
    required this.destinationStationName,
    required this.mobilityType,
    required this.status,
    required this.lineId,
    required this.lineName,
    required this.score,
    required this.steps,
    required this.warnings,
    required this.blockedReasons,
    required this.createdAt,
  });

  factory RouteSearchResult.fromJson(Map<String, Object?> json) {
    final rawSteps = json['steps'];
    final rawWarnings = json['warnings'];
    final rawBlockedReasons = json['blockedReasons'];
    if (rawSteps is! List ||
        rawWarnings is! List ||
        rawBlockedReasons is! List) {
      throw const FormatException('Invalid route payload');
    }

    return RouteSearchResult(
      routeSearchId: _requiredRouteString(json, 'routeSearchId'),
      originStationId: _requiredRouteString(json, 'originStationId'),
      originStationName: _requiredRouteString(json, 'originStationName'),
      destinationStationId: _requiredRouteString(json, 'destinationStationId'),
      destinationStationName: _requiredRouteString(
        json,
        'destinationStationName',
      ),
      mobilityType: _requiredRouteString(json, 'mobilityType'),
      status: _requiredRouteString(json, 'status'),
      lineId: _optionalRouteString(json, 'lineId'),
      lineName: _optionalRouteString(json, 'lineName'),
      score: _requiredRouteInt(json, 'score'),
      steps: rawSteps
          .map((item) {
            if (item is! Map<String, Object?>) {
              throw const FormatException('Invalid route step payload');
            }
            return RouteSearchStep.fromJson(item);
          })
          .toList(growable: false),
      warnings: rawWarnings
          .map((item) {
            if (item is! Map<String, Object?>) {
              throw const FormatException('Invalid route warning payload');
            }
            return RouteSearchWarning.fromJson(item);
          })
          .toList(growable: false),
      blockedReasons: rawBlockedReasons
          .map((item) {
            if (item is! String || item.trim().isEmpty) {
              throw const FormatException('Invalid blocked reason payload');
            }
            return item;
          })
          .toList(growable: false),
      createdAt: _requiredRouteString(json, 'createdAt'),
    );
  }

  final String routeSearchId;
  final String originStationId;
  final String originStationName;
  final String destinationStationId;
  final String destinationStationName;
  final String mobilityType;
  final String status;
  final String lineId;
  final String lineName;
  final int score;
  final List<RouteSearchStep> steps;
  final List<RouteSearchWarning> warnings;
  final List<String> blockedReasons;
  final String createdAt;

  String get summaryTitle => '$originStationName에서 $destinationStationName까지';

  String get statusLabel {
    return switch (status) {
      'FOUND' => '경로를 찾았습니다',
      'BLOCKED' => '안내할 수 있는 경로가 없습니다',
      _ => '확인이 필요합니다',
    };
  }

  String get scoreLabel => '이동 점수 $score점';

  String get lineLabel => lineName.isEmpty ? '노선 확인 필요' : lineName;

  bool get isBlocked => status == 'BLOCKED' || blockedReasons.isNotEmpty;

  String get mobilityLabel => _mobilityLabelFor(mobilityType);

  String get guidanceLabel {
    if (isBlocked) {
      return '다른 경로가 필요합니다';
    }
    return status == 'FOUND' ? '이동할 수 있는 경로' : '확인이 필요합니다';
  }

  String get attentionLabel {
    if (isBlocked) {
      return '안내 불가 이유';
    }
    return warnings.isEmpty ? '주의 없음' : '주의 확인';
  }

  String get semanticLabel {
    // 결과 첫 문장은 사용자가 이동 가능 여부를 바로 판단할 수 있게 구성한다.
    final parts = <String>[
      '경로 검색 결과',
      guidanceLabel,
      mobilityLabel,
      summaryTitle,
      lineLabel,
      scoreLabel,
    ];
    if (!isBlocked && warnings.isNotEmpty) {
      parts.add(attentionLabel);
    }
    if (blockedReasons.isNotEmpty) {
      parts.add('안내 불가 이유 ${blockedReasons.join(', ')}');
    }
    if (warnings.isNotEmpty) {
      parts.add('주의 ${warnings.map((warning) => warning.message).join(', ')}');
    }
    if (steps.isNotEmpty) {
      parts.add(
        '이동 안내 ${steps.map((step) => '${step.sequence}번 ${step.title}, ${step.description}').join(', ')}',
      );
    }
    return parts.join(', ');
  }
}

class RouteSearchStep {
  const RouteSearchStep({
    required this.sequence,
    required this.title,
    required this.description,
    required this.lineId,
    required this.lineName,
    required this.fromStationId,
    required this.toStationId,
  });

  factory RouteSearchStep.fromJson(Map<String, Object?> json) {
    return RouteSearchStep(
      sequence: _requiredRouteInt(json, 'sequence'),
      title: _requiredRouteString(json, 'title'),
      description: _requiredRouteString(json, 'description'),
      lineId: _optionalRouteString(json, 'lineId'),
      lineName: _optionalRouteString(json, 'lineName'),
      fromStationId: _optionalRouteString(json, 'fromStationId'),
      toStationId: _optionalRouteString(json, 'toStationId'),
    );
  }

  final int sequence;
  final String title;
  final String description;
  final String lineId;
  final String lineName;
  final String fromStationId;
  final String toStationId;
}

class RouteSearchWarning {
  const RouteSearchWarning({required this.code, required this.message});

  factory RouteSearchWarning.fromJson(Map<String, Object?> json) {
    return RouteSearchWarning(
      code: _requiredRouteString(json, 'code'),
      message: _requiredRouteString(json, 'message'),
    );
  }

  final String code;
  final String message;
}

enum RouteSearchViewStatus { idle, loading, success, failure }

class RouteSearchState {
  const RouteSearchState({
    required this.status,
    this.result,
    this.message = '',
  });

  const RouteSearchState.idle()
    : status = RouteSearchViewStatus.idle,
      result = null,
      message = '';

  final RouteSearchViewStatus status;
  final RouteSearchResult? result;
  final String message;
}

class RouteSearchController extends ChangeNotifier {
  RouteSearchController({required this.repository});

  final RouteSearchRepository repository;

  RouteSearchState _state = const RouteSearchState.idle();
  int _searchRequestId = 0;
  bool _disposed = false;

  RouteSearchState get state => _state;

  Future<void> search(RouteSearchRequest request) async {
    if (_disposed) {
      return;
    }

    final requestId = ++_searchRequestId;
    final trimmedRequest = request.trimmed();
    if (trimmedRequest.originStationId.isEmpty ||
        trimmedRequest.destinationStationId.isEmpty) {
      _emitState(
        const RouteSearchState(
          status: RouteSearchViewStatus.failure,
          message: '출발역과 도착역을 입력해 주세요.',
        ),
      );
      return;
    }

    _emitState(const RouteSearchState(status: RouteSearchViewStatus.loading));

    try {
      final result = await repository.searchRoute(trimmedRequest);
      if (_disposed || requestId != _searchRequestId) {
        return;
      }
      _emitState(
        RouteSearchState(status: RouteSearchViewStatus.success, result: result),
      );
    } on RouteSearchException catch (error) {
      if (_disposed || requestId != _searchRequestId) {
        return;
      }
      _emitState(
        RouteSearchState(
          status: RouteSearchViewStatus.failure,
          message: error.message,
        ),
      );
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '경로 검색 화면 처리 중 예외가 발생했습니다.',
      );
      if (_disposed || requestId != _searchRequestId) {
        return;
      }
      _emitState(
        const RouteSearchState(
          status: RouteSearchViewStatus.failure,
          message: _routeSearchErrorMessage,
        ),
      );
    }
  }

  void reset() {
    if (_disposed) {
      return;
    }
    _searchRequestId += 1;
    _emitState(const RouteSearchState.idle());
  }

  void _emitState(RouteSearchState nextState) {
    if (_disposed) {
      return;
    }
    _state = nextState;
    notifyListeners();
  }

  @override
  void dispose() {
    // 화면을 떠난 뒤 도착한 네트워크 응답이 dispose된 리스너를 깨우지 않게 막는다.
    _disposed = true;
    super.dispose();
  }
}

class RouteSearchScreen extends StatefulWidget {
  RouteSearchScreen({
    required this.repository,
    required this.stationRepository,
    this.favoriteRouteRepository,
    String? initialMobilityType,
    super.key,
  }) : initialMobilityType = _resolveInitialMobilityType(initialMobilityType);

  final RouteSearchRepository repository;
  final StationSearchRepository stationRepository;
  final FavoriteRouteRepository? favoriteRouteRepository;
  final String initialMobilityType;

  @override
  State<RouteSearchScreen> createState() => _RouteSearchScreenState();
}

String _resolveInitialMobilityType(String? mobilityType) {
  if (mobilityType == null) {
    return mobilityProfileOptions.first.mobilityType;
  }

  final isKnownMobilityType = mobilityProfileOptions.any(
    (option) => option.mobilityType == mobilityType,
  );

  // 서버에 보내는 이동 조건은 화면 드롭다운에 있는 값으로만 제한한다.
  return isKnownMobilityType
      ? mobilityType
      : mobilityProfileOptions.first.mobilityType;
}

class _RouteSearchScreenState extends State<RouteSearchScreen> {
  late final RouteSearchController _controller;
  StationSearchResult? _originStation;
  StationSearchResult? _destinationStation;
  late String _selectedMobilityType;
  String _validationMessage = '';

  @override
  void initState() {
    super.initState();
    _controller = RouteSearchController(repository: widget.repository);
    _selectedMobilityType = widget.initialMobilityType;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('경로 검색')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            _RouteStationPicker(
              labelText: '출발역',
              inputKey: const Key('routeOriginStationInput'),
              searchButtonKey: const Key('routeOriginStationSearchButton'),
              optionKeyPrefix: 'routeOriginStationOption',
              selectedStation: _originStation,
              repository: widget.stationRepository,
              onSelected: _updateOriginStation,
            ),
            const SizedBox(height: 16),
            _RouteStationPicker(
              labelText: '도착역',
              inputKey: const Key('routeDestinationStationInput'),
              searchButtonKey: const Key('routeDestinationStationSearchButton'),
              optionKeyPrefix: 'routeDestinationStationOption',
              selectedStation: _destinationStation,
              repository: widget.stationRepository,
              onSelected: _updateDestinationStation,
            ),
            const SizedBox(height: 12),
            InputDecorator(
              key: const Key('routeMobilityTypeInput'),
              decoration: const InputDecoration(
                labelText: '이동 조건',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedMobilityType,
                  isExpanded: true,
                  items: [
                    for (final option in mobilityProfileOptions)
                      DropdownMenuItem<String>(
                        value: option.mobilityType,
                        child: Text(option.title),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _selectedMobilityType = value;
                    });
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final isLoading =
                    _controller.state.status == RouteSearchViewStatus.loading;
                return FilledButton.icon(
                  key: const Key('routeSearchSubmitButton'),
                  onPressed: isLoading ? null : _submit,
                  icon: const Icon(Icons.route),
                  label: const Text('경로 찾기'),
                );
              },
            ),
            const SizedBox(height: 20),
            if (_validationMessage.isNotEmpty) ...[
              _RouteSearchMessage(
                message: _validationMessage,
                liveRegion: true,
              ),
              const SizedBox(height: 16),
            ],
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => _RouteSearchBody(
                state: _controller.state,
                favoriteRouteRepository: widget.favoriteRouteRepository,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _submit() {
    if (_controller.state.status == RouteSearchViewStatus.loading) {
      return;
    }
    if (_originStation == null || _destinationStation == null) {
      _controller.reset();
      setState(() {
        _validationMessage = '출발역과 도착역을 검색 결과에서 선택해 주세요.';
      });
      return;
    }
    setState(() {
      _validationMessage = '';
    });

    // 화면에는 역 이름을 보여주지만 API에는 안정적인 station id만 전달한다.
    _controller.search(
      RouteSearchRequest(
        originStationId: _originStation!.id,
        destinationStationId: _destinationStation!.id,
        mobilityType: _selectedMobilityType,
      ),
    );
  }

  void _updateOriginStation(StationSearchResult? station) {
    setState(() {
      _originStation = station;
      _validationMessage = '';
    });
    _controller.reset();
  }

  void _updateDestinationStation(StationSearchResult? station) {
    setState(() {
      _destinationStation = station;
      _validationMessage = '';
    });
    _controller.reset();
  }
}

class _RouteStationPicker extends StatefulWidget {
  const _RouteStationPicker({
    required this.labelText,
    required this.inputKey,
    required this.searchButtonKey,
    required this.optionKeyPrefix,
    required this.selectedStation,
    required this.repository,
    required this.onSelected,
  });

  final String labelText;
  final Key inputKey;
  final Key searchButtonKey;
  final String optionKeyPrefix;
  final StationSearchResult? selectedStation;
  final StationSearchRepository repository;
  final ValueChanged<StationSearchResult?> onSelected;

  @override
  State<_RouteStationPicker> createState() => _RouteStationPickerState();
}

class _RouteStationPickerState extends State<_RouteStationPicker> {
  late final StationSearchController _controller;
  final TextEditingController _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller = StationSearchController(repository: widget.repository);
    _textController.addListener(_clearSelectedStationIfNeeded);
  }

  @override
  void dispose() {
    _controller.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: '${widget.labelText} 입력',
          textField: true,
          child: TextField(
            key: widget.inputKey,
            controller: _textController,
            minLines: 1,
            textInputAction: TextInputAction.search,
            style: const TextStyle(fontSize: 20, height: 1.35),
            decoration: InputDecoration(
              labelText: widget.labelText,
              hintText: '역 이름을 입력해 주세요',
              floatingLabelBehavior: FloatingLabelBehavior.always,
              border: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(8)),
              ),
            ),
            onSubmitted: (_) => _search(),
          ),
        ),
        const SizedBox(height: 8),
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final isLoading =
                _controller.state.status == StationSearchStatus.loading;
            return OutlinedButton.icon(
              key: widget.searchButtonKey,
              onPressed: isLoading ? null : _search,
              icon: const Icon(Icons.search),
              label: Text('${widget.labelText} 검색'),
            );
          },
        ),
        if (widget.selectedStation case final selectedStation?) ...[
          const SizedBox(height: 8),
          _RouteSelectedStationSummary(
            labelText: widget.labelText,
            station: selectedStation,
          ),
        ],
        const SizedBox(height: 8),
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return _RouteStationSearchBody(
              labelText: widget.labelText,
              optionKeyPrefix: widget.optionKeyPrefix,
              state: _controller.state,
              onSelected: _selectStation,
            );
          },
        ),
      ],
    );
  }

  void _search() {
    if (_controller.state.status == StationSearchStatus.loading) {
      return;
    }
    _controller.search(_textController.text);
  }

  void _selectStation(StationSearchResult station) {
    widget.onSelected(station);
    _textController.text = station.nameKo;
    // 선택 후 후보 목록을 접어 다음 입력을 바로 찾을 수 있게 한다.
    unawaited(_controller.search(''));
  }

  void _clearSelectedStationIfNeeded() {
    final selectedStation = widget.selectedStation;
    if (selectedStation == null) {
      return;
    }
    if (_textController.text.trim() == selectedStation.nameKo) {
      return;
    }
    widget.onSelected(null);
  }
}

class _RouteSelectedStationSummary extends StatelessWidget {
  const _RouteSelectedStationSummary({
    required this.labelText,
    required this.station,
  });

  final String labelText;
  final StationSearchResult station;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Semantics(
        label: '$labelText 선택됨, ${station.semanticLabel}',
        liveRegion: true,
        child: ExcludeSemantics(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFFE9F5F6),
              border: Border.all(color: const Color(0xFFB9D4D8)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check_circle, color: Color(0xFF006D77)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$labelText ${station.nameKo}',
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                color: const Color(0xFF102A2C),
                                fontWeight: FontWeight.w900,
                                height: 1.3,
                              ),
                        ),
                        const SizedBox(height: 6),
                        StationLineBadges(lines: station.lines),
                        const SizedBox(height: 6),
                        Text(
                          station.lineLabel,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: const Color(0xFF29484B),
                                fontWeight: FontWeight.w700,
                                height: 1.3,
                              ),
                        ),
                      ],
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

class _RouteStationSearchBody extends StatelessWidget {
  const _RouteStationSearchBody({
    required this.labelText,
    required this.optionKeyPrefix,
    required this.state,
    required this.onSelected,
  });

  final String labelText;
  final String optionKeyPrefix;
  final StationSearchState state;
  final ValueChanged<StationSearchResult> onSelected;

  @override
  Widget build(BuildContext context) {
    return switch (state.status) {
      StationSearchStatus.idle => const SizedBox.shrink(),
      StationSearchStatus.loading => Semantics(
        label: '$labelText 검색 중',
        liveRegion: true,
        child: const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: CircularProgressIndicator(),
          ),
        ),
      ),
      StationSearchStatus.empty || StationSearchStatus.failure =>
        _RouteSearchMessage(message: state.message, liveRegion: true),
      StationSearchStatus.success => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            label: '$labelText 검색 결과 ${state.results.length}개',
            liveRegion: true,
            child: const SizedBox.shrink(),
          ),
          for (final result in state.results)
            _RouteStationOptionTile(
              key: Key('$optionKeyPrefix-${result.id}'),
              labelText: labelText,
              result: result,
              onSelected: onSelected,
            ),
        ],
      ),
    };
  }
}

class _RouteStationOptionTile extends StatelessWidget {
  const _RouteStationOptionTile({
    required this.labelText,
    required this.result,
    required this.onSelected,
    super.key,
  });

  final String labelText;
  final StationSearchResult result;
  final ValueChanged<StationSearchResult> onSelected;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return MergeSemantics(
      child: Semantics(
        label: '$labelText 선택, ${result.semanticLabel}',
        button: true,
        onTap: () => onSelected(result),
        child: ExcludeSemantics(
          child: Card(
            margin: const EdgeInsets.only(bottom: 8),
            color: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: Color(0xFFD5E2E4)),
            ),
            child: InkWell(
              onTap: () => onSelected(result),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            result.nameKo,
                            style: textTheme.titleMedium?.copyWith(
                              color: const Color(0xFF102A2C),
                              fontWeight: FontWeight.w900,
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 8),
                          StationLineBadges(lines: result.lines),
                          const SizedBox(height: 8),
                          Text(
                            result.lineLabel,
                            style: textTheme.bodyLarge?.copyWith(
                              color: const Color(0xFF29484B),
                              fontWeight: FontWeight.w700,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            result.dataQualityLabel,
                            style: textTheme.bodyMedium?.copyWith(
                              color: const Color(0xFF405A5D),
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Icon(
                      Icons.chevron_right,
                      color: Color(0xFF006D77),
                      size: 32,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RouteSearchBody extends StatelessWidget {
  const _RouteSearchBody({
    required this.state,
    required this.favoriteRouteRepository,
  });

  final RouteSearchState state;
  final FavoriteRouteRepository? favoriteRouteRepository;

  @override
  Widget build(BuildContext context) {
    return switch (state.status) {
      RouteSearchViewStatus.idle => const SizedBox.shrink(),
      RouteSearchViewStatus.loading => Semantics(
        label: '경로 검색 중',
        liveRegion: true,
        child: const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: CircularProgressIndicator(),
          ),
        ),
      ),
      RouteSearchViewStatus.failure => _RouteSearchMessage(
        message: state.message,
        liveRegion: true,
      ),
      RouteSearchViewStatus.success => _RouteSearchResultCard(
        result: state.result!,
        favoriteRouteRepository: favoriteRouteRepository,
      ),
    };
  }
}

class _RouteSearchMessage extends StatelessWidget {
  const _RouteSearchMessage({required this.message, this.liveRegion = false});

  final String message;
  final bool liveRegion;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: liveRegion,
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: const Color(0xFF405A5D),
          fontWeight: FontWeight.w700,
          height: 1.35,
        ),
      ),
    );
  }
}

class _RouteSearchResultCard extends StatelessWidget {
  const _RouteSearchResultCard({
    required this.result,
    required this.favoriteRouteRepository,
  });

  final RouteSearchResult result;
  final FavoriteRouteRepository? favoriteRouteRepository;

  @override
  Widget build(BuildContext context) {
    final canSaveRoute = favoriteRouteRepository != null && !result.isBlocked;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RouteSearchResultSummaryCard(result: result),
        if (canSaveRoute) ...[
          const SizedBox(height: 12),
          _RouteFavoriteSaveButton(
            result: result,
            repository: favoriteRouteRepository!,
          ),
        ],
      ],
    );
  }
}

class _RouteSearchResultSummaryCard extends StatelessWidget {
  const _RouteSearchResultSummaryCard({required this.result});

  final RouteSearchResult result;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return MergeSemantics(
      child: Semantics(
        label: result.semanticLabel,
        liveRegion: true,
        child: ExcludeSemantics(
          child: Card(
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
                  _RouteResultStatusHeader(result: result),
                  const SizedBox(height: 14),
                  Text(
                    result.statusLabel,
                    style: textTheme.titleMedium?.copyWith(
                      color: const Color(0xFF102A2C),
                      fontWeight: FontWeight.w900,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    result.summaryTitle,
                    style: textTheme.titleLarge?.copyWith(
                      color: const Color(0xFF102A2C),
                      fontWeight: FontWeight.w900,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    result.lineLabel,
                    style: textTheme.bodyLarge?.copyWith(
                      color: const Color(0xFF29484B),
                      fontWeight: FontWeight.w800,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    result.scoreLabel,
                    style: textTheme.bodyLarge?.copyWith(
                      color: const Color(0xFF29484B),
                      fontWeight: FontWeight.w800,
                      height: 1.3,
                    ),
                  ),
                  if (result.blockedReasons.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    for (final reason in result.blockedReasons)
                      _RouteNotice(
                        title: '안내 불가 이유',
                        text: reason,
                        icon: Icons.block,
                      ),
                  ],
                  if (result.warnings.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    for (final warning in result.warnings)
                      _RouteNotice(
                        title: '주의 확인',
                        text: warning.message,
                        icon: Icons.warning_amber,
                      ),
                  ],
                  if (result.steps.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    _RouteStepSection(steps: result.steps),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RouteResultStatusHeader extends StatelessWidget {
  const _RouteResultStatusHeader({required this.result});

  final RouteSearchResult result;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _RouteGuidanceChip(
          key: const Key('routeGuidanceStatusChip'),
          icon: result.isBlocked ? Icons.priority_high : Icons.check_circle,
          label: result.guidanceLabel,
          emphasized: true,
        ),
        _RouteGuidanceChip(
          key: const Key('routeGuidanceMobilityChip'),
          icon: Icons.accessibility_new,
          label: result.mobilityLabel,
        ),
        if (!result.isBlocked && result.warnings.isNotEmpty)
          _RouteGuidanceChip(
            key: const Key('routeGuidanceAttentionChip'),
            icon: Icons.warning_amber,
            label: result.attentionLabel,
          ),
      ],
    );
  }
}

class _RouteGuidanceChip extends StatelessWidget {
  const _RouteGuidanceChip({
    super.key,
    required this.icon,
    required this.label,
    this.emphasized = false,
  });

  final IconData icon;
  final String label;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = emphasized
        ? const Color(0xFFE6F2F0)
        : const Color(0xFFF3F7F7);
    final foregroundColor = emphasized
        ? const Color(0xFF004A50)
        : const Color(0xFF29484B);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border.all(color: const Color(0xFFB9D4D8)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: foregroundColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: foregroundColor,
                fontWeight: FontWeight.w900,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteNotice extends StatelessWidget {
  const _RouteNotice({
    required this.title,
    required this.text,
    required this.icon,
  });

  final String title;
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7E0),
          border: Border.all(color: const Color(0xFFE6C875)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: const Color(0xFF7A4F00), size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: const Color(0xFF3C2F00),
                        fontWeight: FontWeight.w900,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      text,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: const Color(0xFF3C2F00),
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RouteStepSection extends StatelessWidget {
  const _RouteStepSection({required this.steps});

  final List<RouteSearchStep> steps;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '이동 순서',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: const Color(0xFF102A2C),
            fontWeight: FontWeight.w900,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 12),
        for (final step in steps) _RouteStepTile(step: step),
      ],
    );
  }
}

class _RouteStepTile extends StatelessWidget {
  const _RouteStepTile({required this.step});

  final RouteSearchStep step;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            key: Key('routeStepNumber-${step.sequence}'),
            radius: 22,
            backgroundColor: const Color(0xFF006D77),
            child: Text(
              '${step.sequence}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.title,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: const Color(0xFF102A2C),
                    fontWeight: FontWeight.w900,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  step.description,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: const Color(0xFF405A5D),
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteFavoriteSaveButton extends StatefulWidget {
  const _RouteFavoriteSaveButton({
    required this.result,
    required this.repository,
  });

  final RouteSearchResult result;
  final FavoriteRouteRepository repository;

  @override
  State<_RouteFavoriteSaveButton> createState() =>
      _RouteFavoriteSaveButtonState();
}

class _RouteFavoriteSaveButtonState extends State<_RouteFavoriteSaveButton> {
  bool _saving = false;
  String _message = '';

  @override
  void didUpdateWidget(_RouteFavoriteSaveButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.result.routeSearchId != widget.result.routeSearchId) {
      _saving = false;
      _message = '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          key: const Key('routeFavoriteSaveButton'),
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.bookmark_add_outlined),
          label: Text(_saving ? '저장 중' : '자주 쓰는 경로 저장'),
        ),
        if (_message.isNotEmpty) ...[
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Text(
              _message,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: const Color(0xFF29484B),
                fontWeight: FontWeight.w800,
                height: 1.35,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _message = '';
    });

    try {
      await widget.repository.saveFavoriteRoute(widget.result.routeSearchId);
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _message = '자주 쓰는 경로에 저장했습니다.';
      });
    } on FavoriteRouteException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _message = error.message;
      });
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '경로 즐겨찾기 저장 화면 처리 중 예외가 발생했습니다.',
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _message = _favoriteRouteErrorMessage;
      });
    }
  }
}

enum FavoriteRouteListStatus { loading, success, empty, failure }

class FavoriteRouteListState {
  const FavoriteRouteListState({
    required this.status,
    required this.favorites,
    this.message = '',
    this.removingIds = const {},
  });

  const FavoriteRouteListState.loading()
    : status = FavoriteRouteListStatus.loading,
      favorites = const [],
      message = '',
      removingIds = const {};

  final FavoriteRouteListStatus status;
  final List<FavoriteRoute> favorites;
  final String message;
  final Set<String> removingIds;

  FavoriteRouteListState copyWith({
    FavoriteRouteListStatus? status,
    List<FavoriteRoute>? favorites,
    String? message,
    Set<String>? removingIds,
  }) {
    return FavoriteRouteListState(
      status: status ?? this.status,
      favorites: favorites ?? this.favorites,
      message: message ?? this.message,
      removingIds: removingIds ?? this.removingIds,
    );
  }
}

class FavoriteRouteListController extends ChangeNotifier {
  FavoriteRouteListController({required this.repository});

  final FavoriteRouteRepository repository;
  FavoriteRouteListState _state = const FavoriteRouteListState.loading();
  bool _disposed = false;

  FavoriteRouteListState get state => _state;

  Future<void> load() async {
    _emitState(const FavoriteRouteListState.loading());
    try {
      final favorites = await repository.listFavoriteRoutes();
      if (_disposed) {
        return;
      }
      _emitState(
        favorites.isEmpty
            ? const FavoriteRouteListState(
                status: FavoriteRouteListStatus.empty,
                favorites: [],
                message: '저장한 경로가 없습니다.',
              )
            : FavoriteRouteListState(
                status: FavoriteRouteListStatus.success,
                favorites: favorites,
              ),
      );
    } on FavoriteRouteException catch (error) {
      _emitFailure(error.message);
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '즐겨찾기 경로 목록 화면 처리 중 예외가 발생했습니다.',
      );
      _emitFailure(_favoriteRouteLoadErrorMessage);
    }
  }

  Future<void> remove(FavoriteRoute favorite) async {
    final favoriteRouteId = favorite.favoriteRouteId;
    if (_state.removingIds.contains(favoriteRouteId)) {
      return;
    }

    _emitState(
      _state.copyWith(removingIds: {..._state.removingIds, favoriteRouteId}),
    );

    try {
      await repository.removeFavoriteRoute(favoriteRouteId);
      if (_disposed) {
        return;
      }
      final nextFavorites = _state.favorites
          .where((item) => item.favoriteRouteId != favoriteRouteId)
          .toList(growable: false);
      final nextRemovingIds = {..._state.removingIds}..remove(favoriteRouteId);
      _emitState(
        nextFavorites.isEmpty
            ? FavoriteRouteListState(
                status: FavoriteRouteListStatus.empty,
                favorites: const [],
                message: '저장한 경로가 없습니다.',
                removingIds: nextRemovingIds,
              )
            : FavoriteRouteListState(
                status: FavoriteRouteListStatus.success,
                favorites: nextFavorites,
                removingIds: nextRemovingIds,
              ),
      );
    } on FavoriteRouteException catch (error) {
      _emitFailure(error.message, removingIdToClear: favoriteRouteId);
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '즐겨찾기 경로 삭제 처리 중 예외가 발생했습니다.',
      );
      _emitFailure(
        _favoriteRouteErrorMessage,
        removingIdToClear: favoriteRouteId,
      );
    }
  }

  void _emitFailure(String message, {String? removingIdToClear}) {
    final nextRemovingIds = {..._state.removingIds};
    if (removingIdToClear != null) {
      nextRemovingIds.remove(removingIdToClear);
    }
    _emitState(
      FavoriteRouteListState(
        status: FavoriteRouteListStatus.failure,
        favorites: _state.favorites,
        message: message,
        removingIds: nextRemovingIds,
      ),
    );
  }

  void _emitState(FavoriteRouteListState nextState) {
    if (_disposed) {
      return;
    }
    _state = nextState;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class FavoriteRouteListScreen extends StatefulWidget {
  const FavoriteRouteListScreen({required this.repository, super.key});

  final FavoriteRouteRepository repository;

  @override
  State<FavoriteRouteListScreen> createState() =>
      _FavoriteRouteListScreenState();
}

class _FavoriteRouteListScreenState extends State<FavoriteRouteListScreen> {
  late final FavoriteRouteListController _controller;

  @override
  void initState() {
    super.initState();
    _controller = FavoriteRouteListController(repository: widget.repository);
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('즐겨찾기 경로')),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => _FavoriteRouteListBody(
            state: _controller.state,
            onRetry: _controller.load,
            onRemove: _controller.remove,
          ),
        ),
      ),
    );
  }
}

class _FavoriteRouteListBody extends StatelessWidget {
  const _FavoriteRouteListBody({
    required this.state,
    required this.onRetry,
    required this.onRemove,
  });

  final FavoriteRouteListState state;
  final VoidCallback onRetry;
  final ValueChanged<FavoriteRoute> onRemove;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        switch (state.status) {
          FavoriteRouteListStatus.loading => Semantics(
            label: '즐겨찾기 경로 불러오는 중',
            liveRegion: true,
            child: const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: CircularProgressIndicator(),
              ),
            ),
          ),
          FavoriteRouteListStatus.empty => _RouteSearchMessage(
            message: state.message,
            liveRegion: true,
          ),
          FavoriteRouteListStatus.failure => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _RouteSearchMessage(message: state.message, liveRegion: true),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('favoriteRoutesRetryButton'),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('다시 불러오기'),
              ),
            ],
          ),
          FavoriteRouteListStatus.success => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                label: '즐겨찾기 경로 ${state.favorites.length}개',
                liveRegion: true,
                child: const SizedBox.shrink(),
              ),
              for (final favorite in state.favorites)
                _FavoriteRouteTile(
                  favorite: favorite,
                  isRemoving: state.removingIds.contains(
                    favorite.favoriteRouteId,
                  ),
                  onRemove: onRemove,
                ),
            ],
          ),
        },
      ],
    );
  }
}

class _FavoriteRouteTile extends StatelessWidget {
  const _FavoriteRouteTile({
    required this.favorite,
    required this.isRemoving,
    required this.onRemove,
  });

  final FavoriteRoute favorite;
  final bool isRemoving;
  final ValueChanged<FavoriteRoute> onRemove;

  @override
  Widget build(BuildContext context) {
    final removeSemanticLabel =
        '${favorite.summaryTitle} ${isRemoving ? '삭제 중' : '삭제'}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FavoriteRouteSummaryCard(favorite: favorite),
        const SizedBox(height: 12),
        Semantics(
          container: true,
          label: removeSemanticLabel,
          button: true,
          enabled: !isRemoving,
          onTap: isRemoving ? null : () => onRemove(favorite),
          child: ExcludeSemantics(
            child: OutlinedButton.icon(
              key: Key('favoriteRouteRemove-${favorite.favoriteRouteId}'),
              onPressed: isRemoving ? null : () => onRemove(favorite),
              icon: isRemoving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_outline),
              label: Text(isRemoving ? '삭제 중' : '삭제'),
            ),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _FavoriteRouteSummaryCard extends StatelessWidget {
  const _FavoriteRouteSummaryCard({required this.favorite});

  final FavoriteRoute favorite;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return MergeSemantics(
      child: Semantics(
        label: favorite.semanticLabel,
        child: ExcludeSemantics(
          child: Card(
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
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    favorite.summaryTitle,
                    style: textTheme.titleLarge?.copyWith(
                      color: const Color(0xFF102A2C),
                      fontWeight: FontWeight.w900,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    favorite.lineLabel,
                    style: textTheme.bodyLarge?.copyWith(
                      color: const Color(0xFF29484B),
                      fontWeight: FontWeight.w800,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    favorite.mobilityLabel,
                    style: textTheme.bodyLarge?.copyWith(
                      color: const Color(0xFF29484B),
                      fontWeight: FontWeight.w800,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    favorite.scoreLabel,
                    style: textTheme.bodyLarge?.copyWith(
                      color: const Color(0xFF29484B),
                      fontWeight: FontWeight.w800,
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

String _requiredRouteString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String && value.trim().isNotEmpty) {
    return value;
  }
  throw FormatException('Missing required route field: $key');
}

String _optionalRouteString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String) {
    return value.trim();
  }
  return '';
}

int _requiredRouteInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int) {
    return value;
  }
  throw FormatException('Missing required route field: $key');
}
