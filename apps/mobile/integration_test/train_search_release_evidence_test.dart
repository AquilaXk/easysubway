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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('실제 Android에서 서울-대전 KTX 왕복 시간표와 운임을 표시한다', (tester) async {
    final baseUri = Uri.parse(_baseUrl);
    expect(baseUri.scheme, 'https');
    expect(baseUri.host, isNotEmpty);
    await tester.pumpWidget(
      MaterialApp(
        home: TrainSearchScreen(
          repository: ApiTrainSearchRepository(ApiClient(baseUri: baseUri)),
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

    expect(find.textContaining('원'), findsWidgets);
    expect(find.text('가는 열차'), findsOneWidget);
    expect(find.text('오는 열차'), findsOneWidget);
    if (_captureDelaySeconds > 0) {
      debugPrint('ISSUE2094_TRAIN_RESULT_READY');
      await Future<void>.delayed(Duration(seconds: _captureDelaySeconds));
    }
  });

  testWidgets('실제 Android에서 unavailable은 이전 결과 없이 종료한다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: TrainSearchScreen(
          repository: _UnavailableAfterSelectionRepository(),
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
    expect(find.text('기차 검색을 일시적으로 사용할 수 없습니다.'), findsOneWidget);
    expect(find.byKey(const Key('trainSearchResults')), findsNothing);
  });
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
  expect(finder, findsOneWidget);
}

class _UnavailableAfterSelectionRepository implements TrainSearchRepository {
  const _UnavailableAfterSelectionRepository();

  @override
  Future<List<TrainStation>> stations(
    String query, {
    TrainSearchTrainType? type,
  }) async => query.contains('서울')
      ? const [TrainStation(id: 'NAT010000', name: '서울')]
      : const [TrainStation(id: 'NAT011668', name: '대전')];

  @override
  Future<TrainSearchResult> search(TrainSearchCriteria criteria) async {
    throw const TrainSearchException(
      TrainSearchFailureKind.unavailable,
      '기차 검색을 일시적으로 사용할 수 없습니다.',
    );
  }
}
