import 'package:easysubway_mobile/core/database/user/user_database.dart';
import 'package:easysubway_mobile/features/get_off_alarm/data/get_off_alarm_state_repository.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_subscription.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late UserDatabase db;
  late DriftGetOffAlarmStateRepository repository;

  setUp(() {
    db = UserDatabase.memory();
    repository = DriftGetOffAlarmStateRepository(userDatabase: db);
  });

  tearDown(() async {
    await db.close();
  });

  final subscription = GetOffAlarmSubscription(
    routeId: 'route-1',
    transferAlarmEnabled: true,
    destination: GetOffAlarmStopRef(
      stationId: 'dest',
      stationName: '사당',
      arrivalAt: DateTime.utc(2026, 7, 6, 9, 30),
    ),
    transfers: [
      GetOffAlarmStopRef(
        stationId: 'transfer',
        stationName: '동작',
        arrivalAt: DateTime.utc(2026, 7, 6, 9, 15),
      ),
    ],
  );

  test('활성 구독이 없으면 null을 돌려준다', () async {
    expect(await repository.loadActive(), isNull);
  });

  test('저장한 활성 구독을 그대로 다시 읽는다', () async {
    await repository.saveActive(subscription);

    final loaded = await repository.loadActive();
    expect(loaded, isNotNull);
    expect(loaded!.routeId, 'route-1');
    expect(loaded.transferAlarmEnabled, isTrue);
    expect(loaded.destination.stationName, '사당');
    expect(loaded.destination.arrivalAt, DateTime.utc(2026, 7, 6, 9, 30));
    expect(loaded.transfers, hasLength(1));
    expect(loaded.transfers.single.stationId, 'transfer');
  });

  test('단일 활성 구독 — 새로 저장하면 이전 것을 대체한다', () async {
    await repository.saveActive(subscription);
    await repository.saveActive(
      GetOffAlarmSubscription(
        routeId: 'route-2',
        transferAlarmEnabled: false,
        destination: GetOffAlarmStopRef(
          stationId: 'd2',
          stationName: '서울역',
          arrivalAt: DateTime.utc(2026, 7, 6, 10, 0),
        ),
        transfers: const [],
      ),
    );

    final loaded = await repository.loadActive();
    expect(loaded!.routeId, 'route-2');
    expect(loaded.transferAlarmEnabled, isFalse);
    expect(loaded.transfers, isEmpty);
  });

  test('clearActive 후에는 활성 구독이 없다', () async {
    await repository.saveActive(subscription);
    await repository.clearActive();

    expect(await repository.loadActive(), isNull);
  });
}
