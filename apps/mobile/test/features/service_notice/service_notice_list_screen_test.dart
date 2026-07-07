import 'package:easysubway_mobile/features/service_notice/data/notice_repository.dart';
import 'package:easysubway_mobile/features/service_notice/domain/service_notice.dart';
import 'package:easysubway_mobile/features/service_notice/presentation/notice_controller.dart';
import 'package:easysubway_mobile/features/service_notice/presentation/service_notice_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ServiceNotice _notice(
  String id, {
  NoticeSeverity severity = NoticeSeverity.disruption,
  String? title,
}) {
  return ServiceNotice(
    id: id,
    scope: NoticeScope.all,
    title: title ?? '제목 $id',
    body: '본문 $id',
    severity: severity,
    publishedAt: DateTime(2026, 7, 6, 9, 0, 0),
  );
}

class _FakeRepository implements NoticeRepository {
  _FakeRepository(this.result);
  final ActiveNoticesResult result;
  int calls = 0;
  @override
  Future<ActiveNoticesResult> activeNotices() async {
    calls++;
    return result;
  }
}

Future<NoticeController> _seed(ActiveNoticesResult result) async {
  final controller = NoticeController(repository: _FakeRepository(result));
  await controller.refresh();
  return controller;
}

Widget _host(NoticeController controller) {
  return MaterialApp(
    home: ServiceNoticeListScreen(
      controller: controller,
      now: () => DateTime(2026, 7, 6, 12, 0, 0),
    ),
  );
}

void main() {
  testWidgets('제목·본문·심각도를 목록으로 노출한다', (tester) async {
    final controller = await _seed(
      ActiveNoticesResult(
        notices: [
          _notice('n1', title: '2호선 지연'),
          _notice('i1', severity: NoticeSeverity.info, title: '역사 안내'),
        ],
        stale: false,
      ),
    );

    await tester.pumpWidget(_host(controller));
    await tester.pumpAndSettle();

    expect(find.text('운행 공지'), findsOneWidget);
    expect(find.text('2호선 지연'), findsOneWidget);
    expect(find.text('역사 안내'), findsOneWidget);
  });

  testWidgets('공지가 없으면 빈 상태 안내를 노출한다', (tester) async {
    final controller = await _seed(
      const ActiveNoticesResult(notices: [], stale: false),
    );

    await tester.pumpWidget(_host(controller));
    await tester.pumpAndSettle();

    expect(find.text('지금은 운행 공지가 없어요'), findsOneWidget);
  });

  testWidgets('오프라인(stale)이면 "N시간 전 기준" 라벨을 노출한다', (tester) async {
    final controller = await _seed(
      ActiveNoticesResult(
        notices: [_notice('n1')],
        stale: true,
        asOf: DateTime(2026, 7, 6, 9, 0, 0),
      ),
    );

    await tester.pumpWidget(_host(controller));
    await tester.pumpAndSettle();

    expect(find.textContaining('3시간 전 기준'), findsOneWidget);
  });
}
