import 'package:easysubway_mobile/core/database/user/user_database.dart'
    as user_db;
import 'package:easysubway_mobile/core/datapack/data_pack_metered_consent_gate.dart';
import 'package:easysubway_mobile/core/datapack/data_pack_update_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
}
