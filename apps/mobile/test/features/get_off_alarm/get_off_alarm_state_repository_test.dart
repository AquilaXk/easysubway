import 'dart:convert';

import 'package:easysubway_mobile/core/database/user/user_database.dart';
import 'package:easysubway_mobile/features/get_off_alarm/data/get_off_alarm_state_repository.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_schedule_mode.dart';
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
    scheduledCount: 2,
    scheduleMode: GetOffAlarmScheduleMode.inexact,
    inexactNotice: '정확 알람 권한이 없어 오차가 있을 수 있어요.',
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
    expect(loaded.scheduledCount, 2);
    expect(loaded.scheduleMode, GetOffAlarmScheduleMode.inexact);
    expect(loaded.inexactNotice, contains('오차'));
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
        scheduledCount: 1,
        scheduleMode: GetOffAlarmScheduleMode.exact,
        inexactNotice: null,
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
    expect(loaded.scheduledCount, 1);
    expect(loaded.transfers, isEmpty);
  });

  Future<void> writeRaw(Map<String, Object?> value) async {
    await db
        .into(db.appPreferences)
        .insertOnConflictUpdate(
          AppPreferencesCompanion.insert(
            key: 'get_off_alarm_active',
            value: jsonEncode(value),
            updatedAt: DateTime.utc(2026, 7, 10),
          ),
        );
  }

  test('scheduleMode와 inexactNotice를 복원한다', () async {
    await writeRaw({
      ...subscription.toJson(),
      'scheduleMode': 'inexact',
      'inexactNotice': '정확 알람 권한이 없어 오차가 있을 수 있어요.',
    });

    final loaded = await repository.loadActive();

    expect(loaded, isNotNull);
    expect(loaded!.scheduleMode, GetOffAlarmScheduleMode.inexact);
    expect(loaded.inexactNotice, '정확 알람 권한이 없어 오차가 있을 수 있어요.');
  });

  test('non-list transfers 손상값은 active subscription을 폐기한다', () async {
    await writeRaw({
      ...subscription.toJson(),
      'transferAlarmEnabled': false,
      'scheduledCount': 1,
      'transfers': <String, Object?>{},
    });

    expect(await repository.loadActive(), isNull);
  });

  test('scheduledCount 없는 current schema 구독은 최대 예약 수로 복원한다', () async {
    final currentSchema = subscription.toJson()..remove('scheduledCount');
    await writeRaw(currentSchema);

    final loaded = await repository.loadActive();

    expect(loaded, isNotNull);
    expect(loaded!.scheduledCount, 2);
  });

  test('scheduleMode 없는 실제 legacy 구독은 positive restore하지 않는다', () async {
    await writeRaw({
      'routeId': 'legacy-route',
      'transferAlarmEnabled': true,
      'destination': {
        'stationId': 'dest',
        'stationName': '사당',
        'arrivalAtEpochMs': DateTime.utc(
          2026,
          7,
          6,
          9,
          30,
        ).millisecondsSinceEpoch,
      },
      'transfers': [
        {
          'stationId': 'transfer',
          'stationName': '동작',
          'arrivalAtEpochMs': DateTime.utc(
            2026,
            7,
            6,
            9,
            15,
          ).millisecondsSinceEpoch,
        },
      ],
    });

    expect(await repository.loadActive(), isNull);
  });

  test('scheduledCount 문자열은 손상 구독으로 폐기한다', () async {
    await writeRaw({...subscription.toJson(), 'scheduledCount': '1'});

    expect(await repository.loadActive(), isNull);
  });

  test('scheduledCount null은 legacy 누락으로 보지 않고 폐기한다', () async {
    await writeRaw({...subscription.toJson(), 'scheduledCount': null});

    expect(await repository.loadActive(), isNull);
  });

  test('scheduledCount 0은 비활성 구독으로 폐기한다', () async {
    await writeRaw({...subscription.toJson(), 'scheduledCount': 0});

    expect(await repository.loadActive(), isNull);
  });

  test('scheduledCount가 구독 최대 예약 수를 넘으면 폐기한다', () async {
    await writeRaw({...subscription.toJson(), 'scheduledCount': 3});

    expect(await repository.loadActive(), isNull);
  });

  test('clearActive 후에는 활성 구독이 없다', () async {
    await repository.saveActive(subscription);
    await repository.clearActive();

    expect(await repository.loadActive(), isNull);
  });
}
