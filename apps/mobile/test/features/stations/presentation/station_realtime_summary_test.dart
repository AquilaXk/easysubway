import 'package:easysubway_mobile/features/realtime/realtime_repository.dart';
import 'package:easysubway_mobile/features/stations/presentation/station_realtime_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, RealtimeSnapshot snapshot) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StationRealtimeSummary(snapshot: snapshot, onRetry: () {}),
        ),
      ),
    );
  }

  testWidgets('실시간 요약 title은 상태별로 구분된 문구를 보여준다 (#2078)', (tester) async {
    // unsupported: 미지원 노선은 사실형으로 안내하고, 준비 중 진행형을 쓰지 않는다.
    await pump(
      tester,
      const RealtimeSnapshot(status: RealtimeSnapshotStatus.unsupported),
    );
    expect(find.text('실시간 정보 미지원'), findsOneWidget);
    expect(find.text('지원 준비 중'), findsNothing);

    // loading: 실제 진행 중이라 진행형 title을 유지한다.
    await pump(
      tester,
      const RealtimeSnapshot(status: RealtimeSnapshotStatus.loading),
    );
    expect(find.text('실시간 정보 확인 중'), findsOneWidget);

    // unavailable: 조회 실패는 재시도 대상이라 별도 문구로 구분한다.
    await pump(
      tester,
      const RealtimeSnapshot(status: RealtimeSnapshotStatus.unavailable),
    );
    expect(find.text('실시간 정보 확인 불가'), findsOneWidget);

    // 세 상태 title이 서로 다른 문구로 구분된다.
    expect('실시간 정보 미지원', isNot(equals('실시간 정보 확인 중')));
    expect('실시간 정보 확인 중', isNot(equals('실시간 정보 확인 불가')));
    expect('실시간 정보 미지원', isNot(equals('실시간 정보 확인 불가')));
  });
}
