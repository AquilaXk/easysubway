import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

abstract class StationSearchRepository {
  Future<List<StationSearchResult>> searchStations(String query);
}

class StationSearchApiRepository implements StationSearchRepository {
  StationSearchApiRepository({required this.baseUri, HttpClient? httpClient})
    : _httpClient = httpClient ?? HttpClient();

  final Uri baseUri;
  final HttpClient _httpClient;

  @override
  Future<List<StationSearchResult>> searchStations(String query) async {
    final uri = baseUri
        .resolve('/api/v1/stations')
        .replace(queryParameters: {'query': query});

    try {
      final request = await _httpClient.getUrl(uri);
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      final body = await utf8.decodeStream(response);

      if (response.statusCode != HttpStatus.ok) {
        throw const StationSearchException('역 정보를 불러오지 못했습니다.');
      }

      final decoded = jsonDecode(body);
      if (decoded is! Map<String, Object?> || decoded['success'] != true) {
        throw const StationSearchException('역 정보를 불러오지 못했습니다.');
      }

      final data = decoded['data'];
      if (data is! List) {
        throw const StationSearchException('역 정보를 불러오지 못했습니다.');
      }

      return data
          .whereType<Map<String, Object?>>()
          .map(StationSearchResult.fromJson)
          .toList();
    } on StationSearchException {
      rethrow;
    } catch (_) {
      throw const StationSearchException('역 정보를 불러오지 못했습니다.');
    }
  }
}

class StationSearchException implements Exception {
  const StationSearchException(this.message);

  final String message;

  @override
  String toString() => message;
}

class StationSearchResult {
  const StationSearchResult({
    required this.id,
    required this.nameKo,
    required this.nameEn,
    required this.region,
    required this.dataQualityLevel,
    required this.lastVerifiedAt,
    required this.lines,
  });

  factory StationSearchResult.fromJson(Map<String, Object?> json) {
    final lines = json['lines'];
    return StationSearchResult(
      id: json['id'] as String? ?? '',
      nameKo: json['nameKo'] as String? ?? '',
      nameEn: json['nameEn'] as String? ?? '',
      region: json['region'] as String? ?? '',
      dataQualityLevel: json['dataQualityLevel'] as String? ?? '',
      lastVerifiedAt: json['lastVerifiedAt'] as String? ?? '',
      lines: lines is List
          ? lines
                .whereType<Map<String, Object?>>()
                .map(StationSearchLine.fromJson)
                .toList()
          : const [],
    );
  }

  final String id;
  final String nameKo;
  final String nameEn;
  final String region;
  final String dataQualityLevel;
  final String lastVerifiedAt;
  final List<StationSearchLine> lines;

  String get dataQualityLabel {
    return switch (dataQualityLevel) {
      'LEVEL_1' => '기본 정보만 확인됨',
      'LEVEL_2' => '접근성 시설 확인됨',
      'LEVEL_3' => '쉬운 경로 안내 가능',
      'LEVEL_4' => '실시간 상태 반영됨',
      _ => '확인 정보 부족',
    };
  }

  String get lineLabel {
    if (lines.isEmpty) {
      return '노선 정보 없음';
    }
    return lines.map((line) => line.name).join(', ');
  }

  String get semanticLabel => '$nameKo, $lineLabel, $region, $dataQualityLabel';
}

class StationSearchLine {
  const StationSearchLine({
    required this.id,
    required this.name,
    required this.color,
    required this.stationCode,
  });

  factory StationSearchLine.fromJson(Map<String, Object?> json) {
    return StationSearchLine(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      color: json['color'] as String? ?? '',
      stationCode: json['stationCode'] as String? ?? '',
    );
  }

  final String id;
  final String name;
  final String color;
  final String stationCode;

  String get badgeText {
    final numberedLine = RegExp(r'(\d+)\s*호선').firstMatch(name);
    if (numberedLine != null) {
      return numberedLine.group(1) ?? name;
    }

    if (name.contains('경의중앙')) {
      return '경의\n중앙';
    }
    if (name.contains('수인분당')) {
      return '수인\n분당';
    }
    if (name.contains('인천') && name.contains('1')) {
      return '인천1';
    }
    if (name.contains('인천') && name.contains('2')) {
      return '인천2';
    }

    final compactName = name.replaceAll('수도권 ', '').replaceAll('선', '');
    if (compactName.length <= 4) {
      return compactName;
    }
    return compactName.substring(0, 4);
  }

  Color get badgeColor {
    final normalized = color.trim().replaceFirst('#', '');
    if (normalized.length == 6) {
      final parsed = int.tryParse(normalized, radix: 16);
      if (parsed != null) {
        return Color(0xFF000000 | parsed);
      }
    }
    return const Color(0xFF006D77);
  }
}

enum StationSearchStatus { idle, loading, success, empty, failure }

class StationSearchState {
  const StationSearchState({
    required this.status,
    required this.results,
    this.message = '',
  });

  const StationSearchState.idle()
    : status = StationSearchStatus.idle,
      results = const [],
      message = '';

  final StationSearchStatus status;
  final List<StationSearchResult> results;
  final String message;
}

class StationSearchController extends ChangeNotifier {
  StationSearchController({required this.repository});

  final StationSearchRepository repository;

  StationSearchState _state = const StationSearchState.idle();

  StationSearchState get state => _state;

  Future<void> search(String query) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) {
      _state = const StationSearchState.idle();
      notifyListeners();
      return;
    }

    _state = const StationSearchState(
      status: StationSearchStatus.loading,
      results: [],
    );
    notifyListeners();

    try {
      final results = await repository.searchStations(trimmedQuery);
      if (results.isEmpty) {
        _state = const StationSearchState(
          status: StationSearchStatus.empty,
          results: [],
          message: '검색 결과가 없습니다.',
        );
      } else {
        _state = StationSearchState(
          status: StationSearchStatus.success,
          results: results,
        );
      }
    } on StationSearchException catch (error) {
      _state = StationSearchState(
        status: StationSearchStatus.failure,
        results: const [],
        message: error.message,
      );
    } catch (_) {
      _state = const StationSearchState(
        status: StationSearchStatus.failure,
        results: [],
        message: '역 정보를 불러오지 못했습니다.',
      );
    }
    notifyListeners();
  }
}

class StationSearchScreen extends StatefulWidget {
  const StationSearchScreen({required this.repository, super.key});

  final StationSearchRepository repository;

  @override
  State<StationSearchScreen> createState() => _StationSearchScreenState();
}

class _StationSearchScreenState extends State<StationSearchScreen> {
  late final StationSearchController _controller;
  final TextEditingController _queryController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller = StationSearchController(repository: widget.repository);
  }

  @override
  void dispose() {
    _controller.dispose();
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('역 검색')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            Semantics(
              label: '역 이름 입력',
              textField: true,
              child: TextField(
                key: const Key('stationSearchInput'),
                controller: _queryController,
                minLines: 1,
                textInputAction: TextInputAction.search,
                style: const TextStyle(fontSize: 20, height: 1.35),
                decoration: const InputDecoration(
                  labelText: '역 이름',
                  hintText: '역 이름을 입력해 주세요',
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                ),
                onSubmitted: _submit,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('stationSearchSubmitButton'),
              onPressed: () => _submit(_queryController.text),
              icon: const Icon(Icons.search),
              label: const Text('검색'),
            ),
            const SizedBox(height: 20),
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return _StationSearchBody(state: _controller.state);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _submit(String query) {
    _controller.search(query);
  }
}

class _StationSearchBody extends StatelessWidget {
  const _StationSearchBody({required this.state});

  final StationSearchState state;

  @override
  Widget build(BuildContext context) {
    return switch (state.status) {
      StationSearchStatus.idle => const SizedBox.shrink(),
      StationSearchStatus.loading => Semantics(
        label: '역 검색 중',
        liveRegion: true,
        child: const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: CircularProgressIndicator(),
          ),
        ),
      ),
      StationSearchStatus.empty || StationSearchStatus.failure =>
        _StationSearchMessage(message: state.message, liveRegion: true),
      StationSearchStatus.success => Column(
        children: [
          for (final result in state.results)
            _StationSearchResultTile(result: result),
        ],
      ),
    };
  }
}

class _StationSearchMessage extends StatelessWidget {
  const _StationSearchMessage({required this.message, this.liveRegion = false});

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

class _StationSearchResultTile extends StatelessWidget {
  const _StationSearchResultTile({required this.result});

  final StationSearchResult result;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return MergeSemantics(
      child: Semantics(
        label: result.semanticLabel,
        button: true,
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.nameKo,
                    style: textTheme.titleLarge?.copyWith(
                      color: const Color(0xFF102A2C),
                      fontWeight: FontWeight.w800,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _StationSearchLineBadges(lines: result.lines),
                  const SizedBox(height: 8),
                  Text(
                    result.lineLabel,
                    style: textTheme.bodyLarge?.copyWith(
                      color: const Color(0xFF29484B),
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    result.region,
                    style: textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF405A5D),
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
          ),
        ),
      ),
    );
  }
}

class _StationSearchLineBadges extends StatelessWidget {
  const _StationSearchLineBadges({required this.lines});

  final List<StationSearchLine> lines;

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [for (final line in lines) _StationSearchLineBadge(line: line)],
    );
  }
}

class _StationSearchLineBadge extends StatelessWidget {
  const _StationSearchLineBadge({required this.line});

  final StationSearchLine line;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = line.badgeColor;
    final foregroundColor = backgroundColor.computeLuminance() > 0.55
        ? const Color(0xFF102A2C)
        : Colors.white;
    final badgeText = line.badgeText;
    final badgeFontSize = RegExp(r'^\d+$').hasMatch(badgeText) ? 24.0 : 13.0;

    return Container(
      key: Key('stationLineBadge-${line.id}'),
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: backgroundColor, shape: BoxShape.circle),
      child: Text(
        badgeText,
        textAlign: TextAlign.center,
        maxLines: 2,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: foregroundColor,
          fontSize: badgeFontSize,
          fontWeight: FontWeight.w900,
          height: 1.05,
        ),
      ),
    );
  }
}

Uri defaultStationApiBaseUri() {
  const configuredBaseUrl = String.fromEnvironment('EASYSUBWAY_API_BASE_URL');
  if (configuredBaseUrl.isNotEmpty) {
    return Uri.parse(configuredBaseUrl);
  }
  if (Platform.isAndroid) {
    return Uri.parse('http://10.0.2.2:8080');
  }
  return Uri.parse('http://127.0.0.1:8080');
}
