import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easysubway_mobile/station_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'station API repository requests backend stations and parses results',
    () async {
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
    },
  );

  test('station API repository rejects malformed station payloads', () async {
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

  test(
    'station search controller keeps blank input idle without API calls',
    () async {
      final repository = FakeStationSearchRepository();
      final controller = StationSearchController(repository: repository);

      await controller.search('   ');

      expect(repository.requestedQueries, isEmpty);
      expect(controller.state.status, StationSearchStatus.idle);
      expect(controller.state.results, isEmpty);
    },
  );

  test('station search controller ignores stale responses', () async {
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

  test('station search controller exposes empty and failure states', () async {
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

  void complete(String query, List<StationSearchResult> results) {
    final completer = _pending.remove(query);
    if (completer == null) {
      throw StateError('Pending search not found: $query');
    }
    completer.complete(results);
  }
}
