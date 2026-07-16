import 'dart:async';

import 'package:easysubway_mobile/core/database/user/user_database.dart'
    as user_db;
import 'package:easysubway_mobile/core/datapack/data_pack_metered_consent_gate.dart';
import 'package:easysubway_mobile/core/datapack/data_pack_update_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/easy_subway_app_fixture.dart';

void main() {
  testWidgets('EasySubwayApp은 Navigator 아래에서 metered consent dialog를 띄운다', (
    tester,
  ) async {
    final db = user_db.UserDatabase.memory();
    addTearDown(db.close);
    final repo = DataPackUpdateStateRepository(userDatabase: db);
    await repo.savePolicyState(
      const DataPackUpdatePolicyState(pendingConsentBytes: 2 * 1024 * 1024),
    );

    await tester.pumpWidget(
      buildEasySubwayTestApp(
        dataPackUpdateStateRepository: repo,
        dataPackUpdate: Future<void>.value(),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('새 지하철 데이터'), findsOneWidget);
  });

  testWidgets('pending metered consent는 세션 1회 다이얼로그로 user consent를 실행한다', (
    tester,
  ) async {
    final db = user_db.UserDatabase.memory();
    addTearDown(db.close);
    final repo = DataPackUpdateStateRepository(userDatabase: db);
    await repo.savePolicyState(
      const DataPackUpdatePolicyState(pendingConsentBytes: 12 * 1024 * 1024),
    );
    var accepted = false;

    await tester.pumpWidget(
      MaterialApp(
        home: DataPackMeteredConsentGate(
          stateRepository: repo,
          onAccept: () async {
            accepted = true;
          },
          child: const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('새 지하철 데이터'), findsOneWidget);
    expect(find.textContaining('12MB'), findsOneWidget);

    await tester.tap(find.text('지금 받기'));
    await tester.pumpAndSettle();

    expect(accepted, isTrue);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('동의 수락 시도가 실패로 남으면 행동 안내 스낵바를 띄운다', (tester) async {
    final db = user_db.UserDatabase.memory();
    addTearDown(db.close);
    final repo = DataPackUpdateStateRepository(userDatabase: db);
    await repo.savePolicyState(
      const DataPackUpdatePolicyState(pendingConsentBytes: 3 * 1024 * 1024),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: DataPackMeteredConsentGate(
          stateRepository: repo,
          onAccept: () async {
            // 다운로드 시도 실패를 재현: updater의 _saveFailure처럼
            // 실패 사유가 남고 pendingConsent는 유지된다.
            await repo.savePolicyState(
              const DataPackUpdatePolicyState(
                pendingConsentBytes: 3 * 1024 * 1024,
                backoffAttempts: 1,
                lastFailureReason: '이동 정보를 확인하지 못했어요.',
              ),
            );
          },
          child: const Scaffold(body: SizedBox.shrink()),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('지금 받기'));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('지금 받지 못했어요. Wi-Fi 연결 시 자동으로 받아요.'), findsOneWidget);
    // 실패 상세(원인 문자열)는 노출하지 않는다.
    expect(find.textContaining('이동 정보를 확인하지 못했어요'), findsNothing);
  });

  testWidgets('동의 수락이 성공하면 스낵바를 띄우지 않는다', (tester) async {
    final db = user_db.UserDatabase.memory();
    addTearDown(db.close);
    final repo = DataPackUpdateStateRepository(userDatabase: db);
    await repo.savePolicyState(
      const DataPackUpdatePolicyState(pendingConsentBytes: 3 * 1024 * 1024),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: DataPackMeteredConsentGate(
          stateRepository: repo,
          onAccept: () async {
            // 성공 시 updater가 pendingConsent·실패 상태를 모두 지운다.
            await repo.savePolicyState(const DataPackUpdatePolicyState());
          },
          child: const Scaffold(body: SizedBox.shrink()),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('지금 받기'));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('업데이트 완료 뒤 생긴 pending metered consent도 같은 세션에서 표시한다', (
    tester,
  ) async {
    final db = user_db.UserDatabase.memory();
    addTearDown(db.close);
    final repo = DataPackUpdateStateRepository(userDatabase: db);
    final updateCompleted = Completer<void>();

    await tester.pumpWidget(
      MaterialApp(
        home: DataPackMeteredConsentGate(
          stateRepository: repo,
          recheckAfter: updateCompleted.future,
          child: const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(AlertDialog), findsNothing);

    await repo.savePolicyState(
      const DataPackUpdatePolicyState(pendingConsentBytes: 5 * 1024 * 1024),
    );
    updateCompleted.complete();
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('5MB'), findsOneWidget);
  });
}
