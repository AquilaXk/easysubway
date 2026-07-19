import 'dart:io';

import 'package:easysubway_mobile/core/network/api_client.dart';
import 'package:easysubway_mobile/features/train_search/data/train_search_repository.dart';
import 'package:easysubway_mobile/features/train_search/domain/train_search_models.dart';
import 'package:easysubway_mobile/features/train_search/domain/train_search_scope_policy.dart';
import 'package:easysubway_mobile/features/train_search/presentation/train_search_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _baseUrl = String.fromEnvironment('EASYSUBWAY_API_BASE_URL');
const _captureDelaySeconds = int.fromEnvironment(
  'EASYSUBWAY_EVIDENCE_CAPTURE_DELAY_SECONDS',
);
const _proxyPort = int.fromEnvironment('EASYSUBWAY_EVIDENCE_PROXY_PORT');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('실제 Android에서 서울-대전 KTX 왕복 시간표와 운임을 표시한다', (tester) async {
    final baseUri = Uri.parse(_baseUrl);
    expect(baseUri.scheme, 'https');
    expect(baseUri.host, isNotEmpty);
    expect(baseUri.origin, 'https://easysubway-api.aquilaxk.site');
    await tester.pumpWidget(
      MaterialApp(
        home: TrainSearchScreen(
          repository: ApiTrainSearchRepository(
            ApiClient(baseUri: baseUri, httpClient: _evidenceHttpClient()),
          ),
        ),
      ),
    );

    await _selectStation(
      tester,
      slot: 'departure',
      query: '서울',
      id: 'NAT010000',
    );
    await _selectStation(tester, slot: 'arrival', query: '대전', id: 'NAT011668');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    final trainType = find.byKey(const Key('trainSearchTrainTypeField'));
    await _scrollUntilVisible(tester, trainType);
    await tester.tap(trainType);
    await tester.pumpAndSettle();
    await tester.tap(find.text('KTX').last);
    final roundTrip = find.text('왕복');
    await _scrollUntilVisible(tester, roundTrip);
    await tester.tap(roundTrip);
    await _tapSubmit(tester);
    await _waitFor(tester, find.byKey(const Key('trainSearchResults')));

    expect(
      find.bySemanticsLabel(RegExp(r'서울 출발, 대전 도착, .+성인 1인 [0-9,]+원')),
      findsWidgets,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'대전 출발, 서울 도착, .+성인 1인 [0-9,]+원')),
      findsWidgets,
    );
    expect(find.text('가는 열차'), findsOneWidget);
    expect(find.text('오는 열차'), findsOneWidget);
    if (_captureDelaySeconds > 0) {
      debugPrint('ISSUE2094_TRAIN_RESULT_READY');
      await Future<void>.delayed(Duration(seconds: _captureDelaySeconds));
    }
  });

  testWidgets('실제 Android에서 offline network 오류는 이전 결과 없이 종료한다', (tester) async {
    final baseUri = Uri.parse(_baseUrl);
    await tester.pumpWidget(
      MaterialApp(
        home: TrainSearchScreen(
          repository: _OfflineAfterSelectionRepository(baseUri),
        ),
      ),
    );
    await _selectStation(
      tester,
      slot: 'departure',
      query: '서울',
      id: 'NAT010000',
    );
    await _selectStation(tester, slot: 'arrival', query: '대전', id: 'NAT011668');
    await _tapSubmit(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('trainSearchError')), findsOneWidget);
    expect(find.text('인터넷 연결을 확인한 뒤 다시 시도해 주세요.'), findsOneWidget);
    expect(find.byKey(const Key('trainSearchResults')), findsNothing);
  });
}

HttpClient? _evidenceHttpClient() {
  if (_proxyPort == 0) return null;
  if (_proxyPort < 1 || _proxyPort > 65535) {
    throw StateError('EASYSUBWAY_EVIDENCE_PROXY_PORT is invalid');
  }
  final client = HttpClient();
  client.findProxy = (_) => 'PROXY 127.0.0.1:$_proxyPort';
  return client;
}

Future<void> _selectStation(
  WidgetTester tester, {
  required String slot,
  required String query,
  required String id,
}) async {
  final field = slot == 'departure'
      ? find.byKey(const Key('trainSearchDepartureField'))
      : find.byKey(const Key('trainSearchArrivalField'));
  final suggestion = find.byKey(Key('trainSearchStationSuggestion-$slot-$id'));
  await tester.enterText(field, query);
  await _waitFor(tester, suggestion);
  await tester.tap(suggestion);
  await tester.pump();
}

Future<void> _tapSubmit(WidgetTester tester) async {
  final submit = find.byKey(const Key('trainSearchSubmitButton'));
  await _scrollUntilVisible(tester, submit);
  await tester.tap(submit);
}

Future<void> _scrollUntilVisible(WidgetTester tester, Finder finder) async {
  final scrollable = find
      .descendant(
        of: find.byKey(const Key('trainSearchScrollView')),
        matching: find.byType(Scrollable),
      )
      .first;
  await tester.scrollUntilVisible(finder, 240, scrollable: scrollable);
  await tester.ensureVisible(finder);
  await tester.pump();
}

Future<void> _waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) return;
  }
  final visibleText = tester
      .widgetList<Text>(find.byType(Text))
      .map((widget) => widget.data)
      .whereType<String>()
      .where((value) => value.isNotEmpty)
      .join(' | ');
  debugPrint('WAIT_FOR_TIMEOUT_VISIBLE_TEXT: $visibleText');
  expect(finder, findsOneWidget);
}

class _OfflineAfterSelectionRepository implements TrainSearchRepository {
  _OfflineAfterSelectionRepository(Uri baseUri)
    : _api = ApiTrainSearchRepository(
        ApiClient(baseUri: baseUri, httpClient: _OfflineHttpClient()),
      );

  final ApiTrainSearchRepository _api;

  @override
  Future<List<TrainStation>> stations(
    String query, {
    TrainSearchTrainType? type,
  }) async => query.contains('서울')
      ? const [TrainStation(id: 'NAT010000', name: '서울')]
      : const [TrainStation(id: 'NAT011668', name: '대전')];

  @override
  Future<TrainSearchResult> search(TrainSearchCriteria criteria) =>
      _api.search(criteria);
}

class _OfflineHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    throw const SocketException('offline evidence');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
